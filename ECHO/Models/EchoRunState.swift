//
//  EchoRunState.swift
//  ECHO
//
//  Phase 3.02 (Echo Run — the arcade survival mode). The game's second mode, built
//  entirely on the move/replay idea the campaign already proved (Plan §4, §14 "Two
//  modes from one verb"). It is a SEPARATE, additive engine (D-058): the campaign's
//  `GameState`/`Echo`/`Hazard`/`Level`/`LevelLoader` are left byte-for-byte unchanged;
//  Echo Run only reuses the shared pure value types (`GridCoordinate`, `Direction`)
//  and the pure replay function `Echo.position(start:turn:)` (D-014).
//
//  The mechanic (D-057):
//    • Board — an open 9×9 grid, no interior walls; the grid edge is the boundary. The
//      player starts at the centre tile (4, 4).
//    • Recording — one continuous, never-folded recording of the player's *real* moves
//      (a growing `[Direction]`) from the run's start. The player's position is always
//      the tip of that path (`player == walk(recording, recording.count)`).
//    • Stall — a swipe that would leave the grid is a stall: the player stays put, the
//      turn still advances, and every echo still steps. A stall is the only "wait" and
//      adds no recorded move (the trail does not grow), so it is self-limiting — the
//      trailing shadows keep advancing along the existing trail and close on the head.
//    • Delayed shadows — every `spawnPeriod` turns (8, 16, 24, … by default — D-057) a
//      new echo spawns at the start tile and replays the recorded path one step per
//      turn. An echo that spawned at turn `s` is, at the shared turn `t`, exactly
//      `t − s` recorded steps along the path — so it trails the live player by its
//      spawn-turn offset and snakes along the exact path walked. Its tile is a pure
//      function of (start, the current recording, turn) via `Echo.position` (D-014).
//    • Death — touching any echo ends the run, by land-on OR cross-paths/swap (the same
//      strict predicate spirit as the campaign, D-018/D-022). Unlike the campaign the
//      swap branch is *live* against echoes here, because a stall breaks the
//      shared-parity lock that makes it dormant in `GameState`.
//    • Score — turns survived: the turn count reached when the run ends (stalls
//      included). The fatal turn ticked the counter, so it is counted.
//
//  Kept pure and view-independent so it is fully unit-testable headlessly, exactly like
//  `GameState`. `@MainActor @Observable` to match the campaign engine and the manager
//  pattern (D-013); the new pure value types are `nonisolated`/`Sendable`.
//
//  The high score is NOT held here — it is persisted through `SettingsStore`
//  (`recordEchoRunScore`), and the view bridges the two on death. Keeping the engine
//  free of persistence keeps it pure (D-058).
//

import Foundation
import Observation

/// One delayed-shadow echo in an Echo Run: a stable identity plus the turn it spawned
/// on. It carries no moves of its own — every shadow replays the *same* growing
/// `EchoRunState.recording`, just offset by its `spawnTurn`, so its tile is derived
/// from the engine's current recording at offset `turn − spawnTurn`. A pure value type
/// (`nonisolated`/`Sendable`) like `GridCoordinate`/`Direction` (D-058).
nonisolated struct RunEcho: Identifiable, Equatable, Sendable {
    /// Stable identity so SwiftUI can animate each shadow independently (and so the
    /// death overlay can name exactly which shadows it is dissolving). Never reused.
    let id: UUID
    /// The shared turn this shadow first appeared on (at the start tile, offset 0).
    let spawnTurn: Int

    init(id: UUID = UUID(), spawnTurn: Int) {
        self.id = id
        self.spawnTurn = spawnTurn
    }
}

/// The outcome of one committed Echo Run turn, surfaced so the view can pair feedback
/// (audio/haptics) with what actually happened — the arcade analogue of the campaign's
/// `MoveOutcome` (D-049). Additive, read-only; `nonisolated`/`Sendable`.
nonisolated enum RunOutcome: Equatable, Sendable {
    case stepped   // a real move committed (the player advanced one tile)
    case stalled   // an edge swipe: the player held, but the turn advanced and echoes stepped
    case died      // the committed turn touched an echo — the run is over
    case ignored   // input was locked (the run was already over) — nothing happened
}

/// Observable model of an Echo Run. Turn-based and deterministic like the campaign: the
/// world advances by exactly one turn each time the player commits a move OR stalls, and
/// every shadow takes its next recorded step in lockstep. Pure (no view, no persistence,
/// no level data) so it is fully unit-testable.
@MainActor
@Observable
final class EchoRunState {

    /// The board is `size × size` (default 9). The grid edge is the only boundary —
    /// there are no interior walls, doors, switches, hazards, or exit in Echo Run.
    let size: Int

    /// The start tile — the board centre. The player begins here, every shadow is born
    /// here, and `reset()` returns the player here.
    let start: GridCoordinate

    /// Turns between shadow spawns (D-057 fixes this at 8 for the real game). Injectable
    /// so tests can construct collisions in a few turns without driving the full cadence;
    /// the production default is always 8.
    let spawnPeriod: Int

    /// The player's current cell. Read-only from outside; only `move(_:)` changes it.
    private(set) var player: GridCoordinate

    /// The shared turn counter. Starts at 0 and increases by exactly one on every
    /// committed turn — a real move and a stall alike. Shadows step in lockstep with it.
    private(set) var turn: Int = 0

    /// The one continuous, never-folded recording of the player's *real* moves, in
    /// order, from the run's start. A stall appends nothing (the trail does not grow);
    /// `player` is always the tip of this path.
    private(set) var recording: [Direction] = []

    /// The live shadows, oldest first. Each replays `recording` offset by its
    /// `spawnTurn`; its current tile is `position(of:)`.
    private(set) var echoes: [RunEcho] = []

    /// Set the instant the player touches a shadow. While `true`, input is locked
    /// (`move` is a no-op) until `reset()`. The run is over; the view shows game-over.
    private(set) var isOver: Bool = false

    /// The outcome of the most recent committed turn — an additive, read-only feedback
    /// signal (mirrors the campaign's `lastMoveOutcome`, D-049) so the view can voice
    /// the right tick/tap. `nil` until the first committed turn.
    private(set) var lastOutcome: RunOutcome?

    /// Score = turns survived: the turn count reached. Read live for the on-screen score
    /// and, at the end, as the run's final score (the fatal turn is included — it ticked
    /// the counter, D-057).
    var score: Int { turn }

    /// - Parameters:
    ///   - size: board width/height (default 9). The player starts at its centre.
    ///   - spawnPeriod: turns between shadow spawns (default 8 — D-057).
    init(size: Int = 9, spawnPeriod: Int = 8) {
        self.size = size
        self.spawnPeriod = max(1, spawnPeriod)
        let centre = GridCoordinate(row: size / 2, column: size / 2)
        self.start = centre
        self.player = centre
    }

    // MARK: - Board queries

    /// Whether `cell` lies inside the board. A target outside it is the edge — a stall.
    func contains(_ cell: GridCoordinate) -> Bool {
        cell.row >= 0 && cell.row < size && cell.column >= 0 && cell.column < size
    }

    /// The tile `echo` occupies right now — a pure function of (`start`, the current
    /// `recording`, the shared `turn`) at offset `turn − spawnTurn`. Reuses the
    /// campaign's pure replay function (D-014): a fresh, just-spawned shadow (offset 0)
    /// sits on `start`; a shadow that has caught up to the path tip stands on it.
    func position(of echo: RunEcho) -> GridCoordinate {
        Echo(moves: recording).position(start: start, turn: turn - echo.spawnTurn)
    }

    /// The direction each currently-active shadow takes stepping into the *next* turn —
    /// the player's tick plus one per stepping shadow is how the per-move audio chord is
    /// built (matching the campaign's one-tick-per-mover idea, Phase 2.04). A pure read
    /// of the recording at the current turn; an exhausted or not-yet-walking shadow
    /// contributes nothing. Called by the view *before* it commits the move.
    var echoMovesNextTurn: [Direction] {
        echoes.compactMap { echo in
            let index = turn - echo.spawnTurn   // the recorded move it replays into turn+1
            guard index >= 0, index < recording.count else { return nil }
            return recording[index]
        }
    }

    // MARK: - The turn engine

    /// Advance the run by one turn in `direction`.
    ///
    /// If the target tile is off the board the move is a **stall**: the player holds, but
    /// the turn still advances and every shadow still steps. Otherwise the player moves
    /// one tile and the direction is appended to the recording. Either way the turn ticks
    /// by one, a shadow spawns if the new turn is a multiple of `spawnPeriod`, and the
    /// new position is checked against every shadow (land-on OR cross-paths). A touch
    /// ends the run (`isOver`); the turn is not rewound, so `score` reads the turn the
    /// run reached. Input is locked once the run is over.
    ///
    /// Returns the outcome of the turn.
    @discardableResult
    func move(_ direction: Direction) -> RunOutcome {
        guard !isOver else { return .ignored }   // input locked after the run ends

        let previous = player
        let target = GridCoordinate(row: player.row + direction.offset.row,
                                    column: player.column + direction.offset.column)
        let stalled = !contains(target)
        if !stalled {
            player = target
            recording.append(direction)
        }
        turn += 1

        // A delayed shadow spawns at the start tile on every `spawnPeriod`-th turn.
        if turn % spawnPeriod == 0 {
            echoes.append(RunEcho(spawnTurn: turn))
        }

        // Death: touching any shadow (land-on or cross-paths) ends the run.
        if collides(previous: previous, new: player, turn: turn,
                    recording: recording, echoes: echoes) {
            isOver = true
            lastOutcome = .died
            return .died
        }

        lastOutcome = stalled ? .stalled : .stepped
        return lastOutcome!
    }

    /// Capture everything the death dissolve needs for the move that is *about to* end
    /// the run — without mutating the model — or `nil` if the move would not be fatal.
    /// This lets the view defer the commit and play `BoardEffects`' freeze + fizz first,
    /// exactly as the campaign's `playerCollides` lets the board defer a fatal step.
    ///
    /// It builds the same future snapshot `move(_:)` would (the same stall rule, the same
    /// appended move, the same spawn at a period boundary) and runs the same `collides`
    /// core, so the prediction and the later commit are guaranteed to agree (verified by
    /// `testPendingDeathAgreesWithCommit`). The returned `echoes` are the shadows the
    /// move touches — the view maps them to their current tiles (`position(of:)`) for the
    /// glide and hides exactly them in the steady layer.
    func pendingDeath(for direction: Direction) -> PendingDeath? {
        guard !isOver else { return nil }

        let previous = player
        let target = GridCoordinate(row: player.row + direction.offset.row,
                                    column: player.column + direction.offset.column)
        let stalled = !contains(target)
        let newPlayer = stalled ? previous : target
        let t = turn + 1
        let futureRecording = stalled ? recording : recording + [direction]
        var futureEchoes = echoes
        if t % spawnPeriod == 0 { futureEchoes.append(RunEcho(spawnTurn: t)) }

        let snake = Echo(moves: futureRecording)
        let hit = futureEchoes.filter { echo in
            let now = snake.position(start: start, turn: t - echo.spawnTurn)
            if now == newPlayer { return true }                                  // land-on
            let before = snake.position(start: start, turn: (t - 1) - echo.spawnTurn)
            return before == newPlayer && now == previous                        // cross-paths
        }
        guard !hit.isEmpty else { return nil }
        return PendingDeath(previous: previous, contact: newPlayer, echoes: hit)
    }

    /// Reset to a fresh run — the Retry op. Player back to the centre, turn 0, the
    /// recording and shadows emptied, the run un-ended. The high score (held by
    /// `SettingsStore`) is untouched.
    func reset() {
        player = start
        turn = 0
        recording = []
        echoes = []
        isOver = false
        lastOutcome = nil
    }

    // MARK: - Collision core (shared by `move` and `pendingDeath`)

    /// Whether the player, having stepped from `previous` to `new` on `turn` `t`, has
    /// touched any shadow in `echoes`, evaluated against `recording`. Pure: a touch is
    /// land-on (a shadow on the new tile this turn) OR cross-paths (a shadow traded the
    /// adjacent pair — onto the player's old tile while the player took its old tile).
    /// `move` and `pendingDeath` both call this on the same future snapshot, so they
    /// always agree.
    private func collides(previous: GridCoordinate, new: GridCoordinate, turn t: Int,
                          recording: [Direction], echoes: [RunEcho]) -> Bool {
        let snake = Echo(moves: recording)
        for echo in echoes {
            let now = snake.position(start: start, turn: t - echo.spawnTurn)
            if now == new { return true }                                        // land-on
            let before = snake.position(start: start, turn: (t - 1) - echo.spawnTurn)
            if before == new && now == previous { return true }                  // cross-paths
        }
        return false
    }
}

/// The read-only capture of a move that is about to end the run, for the death dissolve
/// (see `EchoRunState.pendingDeath`). `nonisolated`/`Sendable` like the other value types.
nonisolated struct PendingDeath: Sendable {
    /// The player's tile before the fatal turn — where its glide onto `contact` begins
    /// (equal to `contact` when the fatal turn is a stall — the player held in place).
    let previous: GridCoordinate
    /// The tile the player dies on and the fizz emits from.
    let contact: GridCoordinate
    /// The shadows the move touches — the ones the overlay dissolves and the steady
    /// layer hides.
    let echoes: [RunEcho]
}
