//
//  GameState.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move) → 1.04 (Fold — record & replay) → 1.05 (Collision +
//  restart) → 1.06 (Room contents, level data & win) → 1.07 (Reset run & step
//  back). The board's observable state and the rule that advances the world: a
//  single committed move per legal step, against one shared turn counter. Folding
//  the current run banks it as a grey echo and rewinds the board to turn 0; because
//  each echo's position is a pure function of (start, its moves, the turn), all
//  echoes step in lockstep automatically (Plan §14, points 1–2).
//
//  Kept pure and view-independent so it can be unit-tested directly. Phase 1.06
//  fills the empty board in with the contents that make it a puzzle, all driven
//  from per-room level data:
//    • Walls block the player (a move into a wall is a no-op, like off-grid).
//    • Switches + doors: a switch is held at a turn iff the player or any echo is
//      on its cell; a door is open iff all its switches are held; a closed door
//      blocks the player (never kills). These are pure per-turn derivations from
//      positions, not stored mutable state (D-019).
//    • Hazards: independently-moving lethal cells. Collision now evaluates echoes
//      AND hazards (land-on OR cross-paths), so the swap branch goes live for the
//      first time (D-018, D-022).
//    • Win: reaching the exit alive sets a win flag and locks input. Collision is
//      evaluated before win on the same committed step, so a tile that is both
//      exit and lethal is a death (D-023).
//    • Echo budget: fold is refused at the cap (D-027).
//
//  Phase 1.07 adds the two everyday supporting controls (Plan §14), both of which
//  fall straight out of the turn model and need no new stored state:
//    • Reset run scraps the current attempt but keeps banked echoes — exactly the
//      existing `restartRun()` op (the death restart), now also exposed to a
//      control (D-029).
//    • Step back undoes one committed move: pop the last recorded move, decrement
//      the shared turn, and replay `player` from `start`. The whole derived world
//      (echoes, hazards, switches, doors) rolls back for free because all of it is
//      a function of `turn` + positions. It is a pure positional rollback — no
//      collision/win check, never touches echoes, intra-run only (D-028, D-030,
//      D-031). There is no redo this phase (D-032).
//
//  Echoes and hazards replay verbatim — neither re-checks walls/doors each turn
//  (walls are static so never bite; door nuance is handled by level design). The
//  verbatim-replay promise is the keystone and is not special-cased (D-020).
//
//  Phase 4.03 (teleport) adds linked **pad pairs**: stepping onto one pad lands you
//  instantly on its partner as part of that move (one turn ticks; you end on the
//  partner). It is the one place position stops being "start + the sum of the offsets"
//  and becomes a step-by-step walk that jumps at pads — through the single shared
//  `resolveLanding` resolver (Echo.swift). `move`/`stepBack`, `Echo.position`/
//  `upcomingCells`, `isCellHeld`, and the echo branch of `playerCollides` are all
//  pad-aware via the board's `padMap`; **hazards ignore pads** (patrols stay predictable
//  — D-036). With no portals the engine behaves byte-for-byte as before (D-070/D-071).
//

import Observation

/// The outcome of the most recent **committed** move, surfaced so a call site can
/// pair feedback (sound, haptic) with what actually happened. A pure, additive,
/// read-only signal (Phase 2.05) — it changes no rule. `nonisolated`/`Sendable` like
/// the other model value types so it can be read from any context.
nonisolated enum MoveOutcome: Equatable, Sendable {
    case stepped   // a survived committed step (the turn ticked, the player lived)
    case died      // a fatal step: touched an echo/hazard, the run restarted
    case won       // a survived committed step that reached the exit
}

/// Observable model of the board: its size and contents, the player's cell, the
/// shared turn counter, the live run, and the folded echoes. The world is
/// turn-based and deterministic — it advances *only* when the player commits a
/// legal move, by exactly one turn each time, and that step then dissolves
/// present-you if it touched an echo or a hazard (collision is a rule of this
/// model, not of the view).
@MainActor
@Observable
final class GameState {
    /// Number of columns. Set from level data (default 7).
    let width: Int
    /// Number of rows. Set from level data (default 7).
    let height: Int

    /// The level's start tile — where the player begins, and where fold/clear/a
    /// death return present-you to. Defaults to the centre cell.
    let start: GridCoordinate

    /// The single exit cell; reaching it alive wins. `nil` on the bare default
    /// board (no level loaded), which therefore can never be won.
    let exit: GridCoordinate?

    /// Maximum number of folds (echoes) this room allows. `fold()` is refused once
    /// `echoes.count` reaches it. The bare default board uses `.max` (effectively
    /// unlimited) so non-level play and the existing fold tests are uncapped.
    let echoBudget: Int

    /// Impassable cells. A move into one is a no-op, exactly like off-grid.
    let walls: Set<GridCoordinate>

    /// The room's switches (held-state is derived per turn, not stored).
    let switches: [Switch]

    /// The room's doors (open-state is derived per turn, not stored).
    let doors: [Door]

    /// The room's moving hazards. Each is lethal on contact and replays verbatim.
    let hazards: [Hazard]

    /// The room's teleport pad pairs (Phase 4.03 / D-070). Stored for rendering; the
    /// engine reads `padMap`, the derived bidirectional jump table.
    let portals: [Portal]

    /// The bidirectional pad-jump table derived from `portals`: for each portal `[a, b]`,
    /// `a → b` and `b → a`. The single source the shared `resolveLanding` resolver reads,
    /// so `move`/`stepBack`/echo position all jump by the same rule. Empty when the room
    /// has no portals (then every position walk equals the old offset sum — D-071). Built
    /// once at init, where malformed portals (not exactly two distinct cells, or a cell
    /// shared across portals) trip a debug assertion — a malformed map is an authoring bug
    /// (D-070).
    let padMap: [GridCoordinate: GridCoordinate]

    /// The player's current cell. Read-only from outside; only `move(_:)` changes it.
    private(set) var player: GridCoordinate

    /// The shared turn counter. Starts at 0 and increases by exactly one on each
    /// committed move. Every echo and hazard steps in lockstep with this.
    private(set) var turn: Int = 0

    /// The live run since the last fold: the directions of every committed move,
    /// in order. A fold banks this as an echo; a no-op move never appends here.
    /// May contain `.stay` elements — one per `wait()` (Phase 4.01) — so a folded
    /// echo can hold position across turns (D-066/D-067).
    private(set) var currentRun: [Direction] = []

    /// The banked echoes, oldest first. Each replays its recorded moves locked to
    /// `turn`; its current cell is `position(of:)`.
    private(set) var echoes: [Echo] = []

    /// Set the instant present-you reaches the exit alive. While `true`, input is
    /// locked (`move`/`fold` are no-ops) until the room is reset or reloaded.
    private(set) var hasWon: Bool = false

    /// The outcome of the most recent **committed** move — an additive, read-only
    /// signal (Phase 2.05) so a call site can pair feedback with what happened. Set
    /// **only** inside `move(_:)`: a survived step → `.stepped`, the exit step →
    /// `.won`, the collision branch → `.died` (set before `restartRun()`, so it
    /// survives the rewind and a consumer can still read "you just died"). A blocked /
    /// no-op move leaves it **unchanged** — the call site treats `move()` returning
    /// `false` as "nothing happened." `nil` until the first committed move. It changes
    /// no rule: `restartRun`/`fold`/`stepBack`/`clearEchoes` never touch it.
    private(set) var lastMoveOutcome: MoveOutcome?

    /// Designated initializer. Every room property has a default so the bare
    /// `GameState()` is still a plain centered 7×7 board with no contents, no exit,
    /// and an uncapped echo budget (used by previews and the move/fold tests).
    /// - Parameters:
    ///   - width: number of columns (default 7).
    ///   - height: number of rows (default 7).
    ///   - start: the player's starting cell; defaults to the center cell.
    ///   - exit: the exit cell, or `nil` for a board that can't be won.
    ///   - echoBudget: max folds allowed; defaults to effectively unlimited.
    ///   - walls/switches/doors/hazards: the room contents; default to none.
    ///   - portals: the room's teleport pad pairs (default none — D-070).
    init(width: Int = 7,
         height: Int = 7,
         start: GridCoordinate? = nil,
         exit: GridCoordinate? = nil,
         echoBudget: Int = .max,
         walls: [GridCoordinate] = [],
         switches: [Switch] = [],
         doors: [Door] = [],
         hazards: [Hazard] = [],
         portals: [Portal] = []) {
        self.width = width
        self.height = height
        let origin = start ?? GridCoordinate(row: height / 2, column: width / 2)
        self.start = origin
        self.player = origin
        self.exit = exit
        self.echoBudget = echoBudget
        self.walls = Set(walls)
        self.switches = switches
        self.doors = doors
        self.hazards = hazards
        self.portals = portals
        self.padMap = Self.buildPadMap(portals)
    }

    /// Derive the bidirectional `padMap` from the room's `portals`. Each portal `[a, b]`
    /// contributes `a → b` and `b → a`. A well-formed portal has exactly two distinct
    /// cells and shares no cell with another portal; in debug those invariants are
    /// asserted (a malformed map is an authoring bug — D-070), while in release the
    /// builder skips anything malformed rather than crashing the game.
    private static func buildPadMap(_ portals: [Portal]) -> [GridCoordinate: GridCoordinate] {
        var map: [GridCoordinate: GridCoordinate] = [:]
        for portal in portals {
            assert(portal.cells.count == 2,
                   "portal \(portal.id) must have exactly two cells, has \(portal.cells.count)")
            guard portal.cells.count == 2 else { continue }
            let a = portal.cells[0], b = portal.cells[1]
            assert(a != b, "portal \(portal.id) cells must be distinct")
            assert(map[a] == nil && map[b] == nil,
                   "portal \(portal.id) shares a cell with another portal")
            guard a != b else { continue }
            map[a] = b
            map[b] = a
        }
        return map
    }

    /// Build a board from a decoded `Level`. A fresh instance per room means
    /// loading inherently resets play: player → `start`, `turn` → 0, the run and
    /// echoes empty, the win flag false (all the initial-state defaults above).
    convenience init(level: Level) {
        self.init(width: level.width,
                  height: level.height,
                  start: level.start,
                  exit: level.exit,
                  echoBudget: level.echoBudget,
                  walls: level.walls,
                  switches: level.switches,
                  doors: level.doors,
                  hazards: level.hazards,
                  portals: level.portals)
    }

    // MARK: - Board queries

    /// Whether `cell` lies inside the board.
    func contains(_ cell: GridCoordinate) -> Bool {
        cell.row >= 0 && cell.row < height
            && cell.column >= 0 && cell.column < width
    }

    /// Whether `cell` is an impassable wall.
    func isWall(_ cell: GridCoordinate) -> Bool {
        walls.contains(cell)
    }

    /// Whether `cell` is occupied by the player or any echo **at the current
    /// turn** — the occupancy that holds switches (hazards do not count, D-019).
    /// Evaluated at `turn`/`player` because that is the only state any live
    /// derivation (the door-block check and rendering) ever asks about.
    func isCellHeld(_ cell: GridCoordinate) -> Bool {
        if player == cell { return true }
        // Pad-aware (Phase 4.03): an echo that teleported holds a switch in the *far*
        // region, so its switch occupancy is read at its pad-resolved cell (D-070).
        return echoes.contains { $0.position(start: start, turn: turn, pads: padMap) == cell }
    }

    /// Whether the switch with `id` is held at the current turn (its cell is
    /// occupied by the player or an echo). Unknown ids are never held.
    func isSwitchHeld(_ id: String) -> Bool {
        guard let theSwitch = switches.first(where: { $0.id == id }) else { return false }
        return isCellHeld(theSwitch.cell)
    }

    /// Whether `door` is open at the current turn: every switch in its `heldBy`
    /// must be held (AND). A door with no holders is always open (degenerate, not
    /// used by v1 rooms).
    func isDoorOpen(_ door: Door) -> Bool {
        door.heldBy.allSatisfy { isSwitchHeld($0) }
    }

    /// Whether `cell` is blocked by a closed door at the current turn — i.e. some
    /// door covers `cell` and is not open. (A cell covered only by open doors, or
    /// by no door, is not blocked.)
    func isClosedDoor(_ cell: GridCoordinate) -> Bool {
        doors.contains { $0.cells.contains(cell) && !isDoorOpen($0) }
    }

    /// The cell `echo` occupies right now — a pure function of (`start`, the echo's
    /// recorded moves, the shared `turn`, and the board's `padMap`). The board reads this
    /// to draw; pad-aware so a teleported echo draws (and is queried) in the far region
    /// (Phase 4.03 / D-070).
    func position(of echo: Echo) -> GridCoordinate {
        echo.position(start: start, turn: turn, pads: padMap)
    }

    /// The cells `echo` is about to enter from the current `turn` onward — the pad-aware
    /// read the optional echo-trail aid draws through (Phase 4.03 wraps `Echo.upcomingCells`
    /// with the board's `padMap`, so the trail shows a teleport as the jump it is). The
    /// board calls this rather than `Echo.upcomingCells` directly so `padMap` stays
    /// encapsulated.
    func upcomingCells(of echo: Echo) -> [GridCoordinate] {
        echo.upcomingCells(start: start, turn: turn, pads: padMap)
    }

    /// The cell `hazard` occupies right now — a pure function of (its `start`,
    /// authored path, and the shared `turn`). The board reads this to draw.
    func position(of hazard: Hazard) -> GridCoordinate {
        hazard.position(at: turn)
    }

    // MARK: - The turn engine

    /// Move the player one tile in `direction`.
    ///
    /// A move is a **no-op** — nothing changes, the turn does not advance, the move
    /// is not recorded, no collision is checked — if it would leave the grid, enter
    /// a wall, or enter a closed door (a door's open-state is read at the current
    /// turn, the visible state *before* the step). Input is also locked after a win.
    ///
    /// Phase 4.03 (teleport): the destination is the **resolved landing** — if the step
    /// lands on a pad, you end the turn on its partner (one turn ticks). The guards run on
    /// that landing, so you cannot teleport into a blocked cell. Collision/switch/door/win
    /// all evaluate at the landing; a teleporting move is land-on-only at the partner
    /// (cross-paths can't fire across a non-adjacent jump), which is correct — danger is
    /// checked where you land (D-070).
    ///
    /// A committed move updates the player's cell, advances the turn by one, and
    /// appends its direction to the current run. Then the new position is checked
    /// against every echo and hazard: if present-you touched one, the **current run
    /// restarts** (`restartRun()`) — the fatal step happened (it ticked the turn and
    /// was appended) and the restart then discards it, returning present-you to
    /// `start` and the turn to 0 while every folded echo stays put. Only if the step
    /// was survived is the exit checked: landing on the exit alive sets `hasWon`
    /// (collision is therefore evaluated **before** win — a tile that is both exit
    /// and lethal is a death, D-023).
    ///
    /// The collision check only ever runs *after* a committed step, so `turn` is
    /// always ≥ 1 there — turn 0 (the start-stack right after a fold or a restart)
    /// is never tested and so never counts as a touch, which also means a death can
    /// never trigger another death (no restart loop).
    ///
    /// Returns whether a step was **committed** (a real tile move happened),
    /// including the fatal step, which did happen before it was discarded. A no-op
    /// returns `false`.
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        guard direction != .stay else { return false }   // `.stay` is passed only via wait() (D-067)
        guard !hasWon else { return false }   // input locked after a win
        // Pad-aware (Phase 4.03): resolve where the step lands — a step onto a pad jumps
        // to its partner — then run the same off-grid / wall / closed-door guards on the
        // **resolved landing**. You cannot teleport into a blocked cell, so that is a
        // no-op exactly like walking into a wall (turn doesn't advance, nothing recorded).
        let target = resolveLanding(from: player, step: direction, pads: padMap)
        guard contains(target) else { return false }       // off-grid
        guard !isWall(target) else { return false }         // into a wall
        guard !isClosedDoor(target) else { return false }   // into a closed door

        let previousPlayerCell = player
        player = target
        turn += 1
        // Record the **input direction**, not the destination — a replay re-derives the
        // jump through `resolveLanding`, so an echo teleports deterministically (D-070).
        currentRun.append(direction)

        // Collision first (echoes + hazards): a fatal step restarts the run. The
        // start-stack at turn 0 is never reached here, so it is immune and there is
        // no restart loop.
        if playerCollides(previousPlayerCell: previousPlayerCell,
                          newPlayerCell: player,
                          turn: turn) {
            lastMoveOutcome = .died   // additive signal (Phase 2.05): set before the
            restartRun()              // rewind, which never touches it, so it persists
            return true
        }

        // Then win: reaching the exit alive locks input.
        if let exit, player == exit {
            hasWon = true
            lastMoveOutcome = .won
        } else {
            lastMoveOutcome = .stepped
        }
        return true
    }

    /// **Wait** — pass a turn in place (Phase 4.01 / D-066). The fifth player action:
    /// the world advances by one shared turn — every echo and hazard takes its next
    /// step — while present-you holds position and records a `.stay`.
    ///
    /// Holding position is **risky**: a wait runs the **same** collision check a move
    /// does (`playerCollides`), with the held cell as both the previous and the new
    /// cell, so a mover (echo or hazard) stepping onto that tile this turn is a
    /// **death** — `lastMoveOutcome = .died` and the current run restarts (the fatal
    /// wait ticked the turn and appended its `.stay`, which the restart then discards,
    /// returning present-you to `start` and the turn to 0 while every folded echo stays
    /// put). Otherwise the wait survives → `lastMoveOutcome = .stepped`.
    ///
    /// A wait **never checks the exit** (you can't win by standing still) and is the
    /// **single** way to record a `.stay`. Refused (a no-op returning `false`) only
    /// when input is locked by a win — symmetry with `move(_:)`/`stepBack()`. Returns
    /// whether a turn was passed (always `true` unless already won, including the fatal
    /// wait, which did pass its turn before the run was discarded).
    @discardableResult
    func wait() -> Bool {
        guard !hasWon else { return false }   // input locked after a win
        let held = player
        turn += 1
        currentRun.append(.stay)

        // Same collision rule as a move (echoes + hazards), with the held tile as both
        // the previous and the new cell: a mover that lands on it this turn kills you.
        if playerCollides(previousPlayerCell: held, newPlayerCell: held, turn: turn) {
            lastMoveOutcome = .died   // set before the rewind, which never touches it
            restartRun()
            return true
        }

        lastMoveOutcome = .stepped
        return true
    }

    /// Whether present-you, having just stepped from `previousPlayerCell` (the
    /// player's tile at turn `t − 1`) to `newPlayerCell` (its tile at turn `t`),
    /// has **touched** any echo or hazard on this step. Pure and view-independent:
    /// it reads only `start`, the recorded echoes, and the authored hazards,
    /// deriving each mover's tiles from the same pure position functions the board
    /// draws from.
    ///
    /// A touch (against either an echo or a hazard) is either of (per D-018):
    /// - **Land-on (occupation):** the mover is on the player's new tile this turn.
    /// - **Cross-paths (swap):** the player and the mover traded the same pair of
    ///   adjacent tiles — the mover moved onto the player's old tile while the
    ///   player moved onto the mover's old tile.
    ///
    /// The swap branch is dormant against echoes (player and echoes share an origin
    /// and a one-step cadence, so they are always the same checkerboard parity at a
    /// given turn, while a swap needs opposite-parity adjacent tiles) but **live
    /// against hazards**, which move independently and can trade tiles with the
    /// player (D-022).
    func playerCollides(previousPlayerCell: GridCoordinate,
                        newPlayerCell: GridCoordinate,
                        turn t: Int) -> Bool {
        for echo in echoes {
            // Pad-aware (Phase 4.03): an echo's tiles are read through the board's
            // `padMap`, so a teleported echo is detected in the far region it landed in.
            // Hazards (below) stay pad-blind by design (D-036).
            let echoNow = echo.position(start: start, turn: t, pads: padMap)
            if echoNow == newPlayerCell { return true }                 // land-on
            let echoBefore = echo.position(start: start, turn: t - 1, pads: padMap)
            if echoBefore == newPlayerCell && echoNow == previousPlayerCell {
                return true                                             // cross-paths (dormant)
            }
        }
        for hazard in hazards {
            let hazardNow = hazard.position(at: t)
            if hazardNow == newPlayerCell { return true }               // land-on
            let hazardBefore = hazard.position(at: t - 1)
            if hazardBefore == newPlayerCell && hazardNow == previousPlayerCell {
                return true                                             // cross-paths (live)
            }
        }
        return false
    }

    /// Restart the current run — present-you dissolving on contact (Phase 1.05),
    /// and the single op the player-facing **reset run** control is wired to as of
    /// Phase 1.07 (so the control reuses this; it is not duplicated — D-029).
    /// Returns present-you to `start`, the turn to 0, empties the current run, and
    /// clears any win flag, while **leaving every folded echo intact** so they keep
    /// replaying. Allowed at any time (it is a full restart, so it is fine after a
    /// win — clearing `hasWon` is what unlocks the room, D-031). Deliberately
    /// distinct from `clearEchoes()`, which also wipes the echoes; a reset keeps them.
    func restartRun() {
        player = start
        turn = 0
        currentRun = []
        hasWon = false
    }

    /// **Step back** — undo a single committed move of the current run (Plan §14,
    /// one of the two supporting controls). A pure, deterministic positional
    /// rollback to the tile present-you occupied one turn earlier; the whole derived
    /// world (echoes, hazards, switches, doors) recomputes for free because each is
    /// a function of `turn` + positions, so rolling the turn back recomputes the
    /// board (D-028).
    ///
    /// Refused (a no-op, returning `false`) when input is locked by a win (symmetry
    /// with `move(_:)` — D-031) or when the current run is **empty** (i.e. `turn == 0`,
    /// the start-stack right after a fold/restart): there is nothing to undo, and
    /// step-back is **intra-run only** — it never crosses the fold boundary and never
    /// removes a banked echo (D-030).
    ///
    /// Otherwise it pops the last recorded move, decrements the shared `turn` by one,
    /// and restores `player` by replaying the now-shorter run from `start`. It runs
    /// **no collision check and no win check** — it rolls back to a turn the player
    /// already occupied alive — and never mutates `echoes`. Replaying from `start`
    /// (rather than subtracting the popped offset) keeps `currentRun` the single
    /// source of truth, so `player` can never drift from it (D-028). Returns whether
    /// a move was undone.
    @discardableResult
    func stepBack() -> Bool {
        guard !hasWon else { return false }              // input locked after a win (D-031)
        guard !currentRun.isEmpty else { return false }  // turn 0: nothing to undo (D-030)

        currentRun.removeLast()
        turn -= 1
        // Replay the now-shorter run from `start` through the shared `resolveLanding`
        // walk (Phase 4.03), so undoing a teleporting move returns the player to the
        // correct pre-teleport cell. With no portals this equals the old offset sum (D-071).
        var cell = start
        for direction in currentRun {
            cell = resolveLanding(from: cell, step: direction, pads: padMap)
        }
        player = cell
        return true
    }

    /// **Fold** the current run into a permanent grey echo, then rewind the whole
    /// board to its start (Plan §14, point 4).
    ///
    /// Banks the current run as a new echo, returns the player to `start`, resets
    /// `turn` to 0, and empties the current run. Every existing echo then sits on
    /// `start` again by consequence. Refused (a no-op) when input is locked by a
    /// win, when the current run is **empty** (no zero-move echo is ever created),
    /// or when the **echo budget is already reached** (D-027). Returns whether a
    /// fold occurred.
    @discardableResult
    func fold() -> Bool {
        guard !hasWon else { return false }
        guard !currentRun.isEmpty else { return false }
        guard echoes.count < echoBudget else { return false }
        echoes.append(Echo(moves: currentRun))
        player = start
        turn = 0
        currentRun = []
        return true
    }

    /// Debug only (Phase 1.07 ships the real reset-run). Wipe all echoes, empty the
    /// current run, return the player to `start`, reset `turn` to 0, and clear the
    /// win flag — the room exactly as if freshly opened (Plan §14, point 6).
    func clearEchoes() {
        echoes = []
        currentRun = []
        player = start
        turn = 0
        hasWon = false
    }
}
