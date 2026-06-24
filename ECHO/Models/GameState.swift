//
//  GameState.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move) → 1.04 (Fold — record & replay). The board's
//  observable state and the rule that advances the world: a single committed move
//  per legal step, against one shared turn counter. Phase 1.04 adds the keystone
//  on top: every committed move is also recorded into the current run, and
//  **folding** that run banks it as a grey echo, then rewinds the whole board to
//  turn 0. Because each echo's position is a pure function of (start, its moves,
//  the turn), all echoes step in lockstep automatically — no imperative per-echo
//  stepping to get wrong (Plan §14, points 1–2).
//
//  Kept pure and view-independent so it can be unit-tested directly. Dimensions
//  and the start cell are parameters (default 7×7, centered) so Phase 1.06 can
//  build a board from level data without touching this type. No level loading,
//  collision, or win logic here — those are later phases. In particular there is
//  **no collision** in 1.04: the player and any echoes may share a tile and the
//  player walks straight through echoes (touching one only dissolves you from
//  Phase 1.05 onward).
//

import Observation

/// Observable model of the board: its size, the player's cell, and the shared
/// turn counter. The world is turn-based and deterministic — it advances *only*
/// when the player commits a legal move, and by exactly one turn each time.
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
    /// counter does not advance, and the move is **not recorded**. A legal move
    /// updates the player's cell, advances the turn counter by exactly one, and
    /// appends its direction to the current run. Returns whether the move was
    /// committed, so callers can pair feedback to a real step.
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        let target = GridCoordinate(
            row: player.row + direction.offset.row,
            column: player.column + direction.offset.column
        )
        guard contains(target) else { return false }
        player = target
        turn += 1
        currentRun.append(direction)
        return true
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
