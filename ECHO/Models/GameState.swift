//
//  GameState.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move) → 1.04 (Fold — record & replay) → 1.05 (Collision +
//  restart). The board's observable state and the rule that advances the world: a
//  single committed move per legal step, against one shared turn counter. Phase
//  1.04 added the keystone: every committed move is recorded into the current run,
//  and **folding** that run banks it as a grey echo, then rewinds the whole board
//  to turn 0. Because each echo's position is a pure function of (start, its
//  moves, the turn), all echoes step in lockstep automatically — no imperative
//  per-echo stepping to get wrong (Plan §14, points 1–2).
//
//  Kept pure and view-independent so it can be unit-tested directly. Dimensions
//  and the start cell are parameters (default 7×7, centered) so Phase 1.06 can
//  build a board from level data without touching this type. No level loading or
//  win logic here, and no walls/switches/hazards yet — those are later phases.
//  Phase 1.05 adds the one hard rule on top: after a committed step the player is
//  checked against every echo, and **touching** one — landing on its tile, or
//  trading the same pair of adjacent tiles with it — dissolves present-you and
//  **restarts the current run** (player back to `start`, turn to 0, the run
//  emptied) while every folded echo stays put and keeps replaying (Plan §14,
//  point 4).
//

import Observation

/// Observable model of the board: its size, the player's cell, the shared turn
/// counter, the live run, and the folded echoes. The world is turn-based and
/// deterministic — it advances *only* when the player commits a legal move, by
/// exactly one turn each time, and that step then dissolves present-you if it
/// touched an echo (collision is a rule of this model, not of the view).
@MainActor
@Observable
final class GameState {
    /// Number of columns. A parameter, not a magic number — set from level data later.
    let width: Int
    /// Number of rows.
    let height: Int

    /// The level's start tile — where the player begins, and where fold/clear
    /// return everyone to. The centre cell for now; set from level data later.
    let start: GridCoordinate

    /// The player's current cell. Read-only from outside; only `move(_:)` changes it.
    private(set) var player: GridCoordinate

    /// The shared turn counter. Starts at 0 and increases by exactly one on each
    /// committed move. Every echo steps in lockstep with this.
    private(set) var turn: Int = 0

    /// The live run since the last fold: the directions of every committed move,
    /// in order. A fold banks this as an echo; a no-op move never appends here.
    private(set) var currentRun: [Direction] = []

    /// The banked echoes, oldest first. Each replays its recorded moves locked to
    /// `turn`; its current cell is `position(of:)`.
    private(set) var echoes: [Echo] = []

    /// - Parameters:
    ///   - width: number of columns (default 7).
    ///   - height: number of rows (default 7).
    ///   - start: the player's starting cell; defaults to the center cell.
    init(width: Int = 7, height: Int = 7, start: GridCoordinate? = nil) {
        self.width = width
        self.height = height
        let origin = start ?? GridCoordinate(row: height / 2, column: width / 2)
        self.start = origin
        self.player = origin
    }

    /// Whether `cell` lies inside the board.
    func contains(_ cell: GridCoordinate) -> Bool {
        cell.row >= 0 && cell.row < height
            && cell.column >= 0 && cell.column < width
    }

    /// Move the player one tile in `direction`.
    ///
    /// A move that would leave the grid is a **no-op**: nothing changes, the turn
    /// counter does not advance, the move is **not recorded**, and no collision is
    /// checked (nothing moved, so nothing new can be touched). A legal move updates
    /// the player's cell, advances the turn counter by exactly one, and appends its
    /// direction to the current run — then the new position is checked against every
    /// echo (Phase 1.05). If present-you has touched an echo, the **current run
    /// restarts** (`restartRun()`): the fatal step is taken first (it resolves,
    /// ticks the turn, and is appended) and the restart then discards it, returning
    /// the player to `start` and the turn to 0 while every folded echo stays put.
    ///
    /// The collision check only ever runs *after* a committed step, so `turn` is
    /// always ≥ 1 there — turn 0 (the start-stack right after a fold or a restart)
    /// is never tested and so never counts as a touch, which also means a death can
    /// never trigger another death (no restart loop).
    ///
    /// Returns whether a step was **committed** (a real tile move happened), so
    /// callers can pair feedback to a step — including the fatal step, which did
    /// happen before it was discarded. A no-op returns `false`.
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        let target = GridCoordinate(
            row: player.row + direction.offset.row,
            column: player.column + direction.offset.column
        )
        guard contains(target) else { return false }
        let previousPlayerCell = player
        player = target
        turn += 1
        currentRun.append(direction)
        // After the committed step (turn ≥ 1), dissolving on contact with an echo
        // restarts the current run; turn 0 is never reached here, so the
        // start-stack is immune and there is no restart loop.
        if playerCollides(previousPlayerCell: previousPlayerCell,
                          newPlayerCell: player,
                          turn: turn) {
            restartRun()
        }
        return true
    }

    /// Whether present-you, having just stepped from `previousPlayerCell` (the
    /// player's tile at turn `t − 1`) to `newPlayerCell` (its tile at turn `t`),
    /// has **touched** any echo on this step. Pure and view-independent: it reads
    /// only `start` and the recorded echoes, deriving each echo's tiles from the
    /// same `Echo.position(start:turn:)` the board draws from.
    ///
    /// A touch is either of (per D-018):
    /// - **Land-on (occupation):** some echo is on the player's new tile this turn —
    ///   `echo.position(turn: t) == newPlayerCell`.
    /// - **Cross-paths (swap):** the player and some echo traded the same pair of
    ///   adjacent tiles — the echo moved onto the player's old tile while the
    ///   player moved onto the echo's old tile:
    ///   `echo.position(turn: t − 1) == newPlayerCell` **and**
    ///   `echo.position(turn: t) == previousPlayerCell`.
    ///
    /// Both clauses are written because this is the general, correct "did
    /// present-you touch a thing that moved this step" test. The swap clause cannot
    /// currently fire against an echo — player and echoes share an origin and a
    /// one-step-per-turn cadence, so at any given turn they are always the same
    /// checkerboard parity, while a swap needs opposite-parity adjacent tiles — but
    /// Phase 1.06's independently-moving hazards *can* cross paths and reuse this
    /// predicate unchanged.
    func playerCollides(previousPlayerCell: GridCoordinate,
                        newPlayerCell: GridCoordinate,
                        turn t: Int) -> Bool {
        for echo in echoes {
            let echoNow = echo.position(start: start, turn: t)
            // Land-on (occupation): an echo is on the player's new tile this turn.
            if echoNow == newPlayerCell { return true }
            // Cross-paths (swap): the player and this echo traded the same adjacent
            // pair across this step. (Dormant against echoes; live for 1.06 hazards.)
            let echoBefore = echo.position(start: start, turn: t - 1)
            if echoBefore == newPlayerCell && echoNow == previousPlayerCell { return true }
        }
        return false
    }

    /// Restart the current run — present-you dissolving on contact with an echo
    /// (Phase 1.05), and the very operation Phase 1.07 will attach the real "reset
    /// run" control to (so wire that control here, don't duplicate this). Returns
    /// the player to `start`, the turn to 0, and empties the current run, while
    /// **leaving every folded echo intact** so they keep replaying. Deliberately
    /// distinct from `clearEchoes()`, which also wipes the echoes; a death keeps
    /// them.
    func restartRun() {
        player = start
        turn = 0
        currentRun = []
    }

    /// The cell `echo` occupies right now — a pure function of (`start`, the
    /// echo's recorded moves, the shared `turn`). The board reads this to draw
    /// and animate each grey square.
    func position(of echo: Echo) -> GridCoordinate {
        echo.position(start: start, turn: turn)
    }

    /// **Fold** the current run into a permanent grey echo, then rewind the whole
    /// board to its start (Plan §14, point 4).
    ///
    /// Banks the current run as a new echo, returns the player to `start`, resets
    /// `turn` to 0, and empties the current run. Every existing echo then sits on
    /// `start` again by consequence (their position at turn 0 is `start`).
    /// Folding an **empty** run does nothing — no zero-move echo is ever created
    /// and no rewind happens when nothing was walked. Returns whether a fold
    /// occurred.
    @discardableResult
    func fold() -> Bool {
        guard !currentRun.isEmpty else { return false }
        echoes.append(Echo(moves: currentRun))
        player = start
        turn = 0
        currentRun = []
        return true
    }

    /// Debug only (Phase 1.07 ships the real reset-run). Wipe all echoes, empty
    /// the current run, return the player to `start`, and reset `turn` to 0 — the
    /// room exactly as if freshly opened (Plan §14, point 6).
    func clearEchoes() {
        echoes = []
        currentRun = []
        player = start
        turn = 0
    }
}
