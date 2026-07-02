//
//  MirrorGameState.swift
//  ECHO
//
//  Phase 4.05 (the mirror engine — D-074/D-075). The separate, additive engine for
//  **mirror rooms**: one grid split down a vertical centerline into two halves, and
//  present-you as **two bodies on one reflected input** — one body confined to each
//  half. Built beside the verified campaign `GameState` (the D-058 Echo Run
//  precedent), never inside it: with no mirror rooms instantiated, nothing existing
//  changes.
//
//  The rules (D-074), exactly:
//    • Split — left half is columns `0 … width/2−1`, right half `width/2 … width−1`.
//      Width must be even (debug-asserted).
//    • Reflected controls — one input drives both bodies: UP/DOWN move both the same
//      way; LEFT/RIGHT move them oppositely (they mirror across the centerline).
//    • Partial movement (the crux) — each body moves iff its target cell is inside
//      its own half, on the board, not a wall, and not a closed door; otherwise that
//      body **stays while the other moves** (it records a `.stay` for the turn).
//      Using asymmetric walls/doors to knock the bodies out of lockstep is how mirror
//      rooms are solved. If neither body can move the input is a no-op — the turn
//      does not advance and nothing is recorded, exactly like walking into a wall.
//    • Blocking vs. death — walls, closed doors, the board edge, and the centerline
//      *block* (partial movement); contact with an echo-body or a hazard is *death*:
//      if either live body lands on — or crosses paths with — one, **both bodies
//      dissolve** and the run restarts (the usual rule, applied per body per half).
//      The two live bodies are always in different halves, so they never collide
//      with each other.
//    • Switches & doors across halves — a switch is held at a turn iff any live body
//      or any echo-body (left or right) occupies its cell that turn; a door is open
//      iff every switch in its `heldBy` is held (AND) — so an AND-door can span
//      halves, and one folded mirror echo can hold a switch in each half at once.
//    • Echoes — folding banks a two-body echo: a pair of plain `Echo`s (one per
//      half), each replaying its half's recorded per-turn steps **verbatim** (D-020).
//      A body that was blocked on a turn recorded a `.stay`, so its echo reproduces
//      that stay and never re-checks doors at replay. Recorded runs stay plain
//      turn-aligned `[Direction]` streams, one per body (D-075).
//    • Win — two exits (left = the level's `exit`, right = `mirror.exitRight`). You
//      win the instant BOTH live bodies sit on their own-half exits on the same
//      turn; one body home but not the other is not a win. Collision is evaluated
//      before win (D-023), and a wait never checks the exits.
//
//  Teleport is deliberately **not** in this engine — mirror × teleport is room 36's
//  interaction, defined in Phase 4.07. Every position walk here uses the pure
//  `Echo.position` with its default-empty `pads`, i.e. the plain offset walk.
//
//  Like `GameState`, the whole world is a pure derivation of (starts, recorded
//  streams, authored hazards, the shared `turn`), so replays are exact, step-back is
//  a positional rollback, and the engine is directly unit-testable (D-014).
//

import Foundation
import Observation

extension Direction {
    /// The horizontally-reflected step — what the RIGHT body does when the input
    /// drives the LEFT body in `self` (D-074): up/down (and `.stay`) are unchanged,
    /// left ↔ right swap, so the two bodies mirror across the vertical centerline.
    nonisolated var horizontallyMirrored: Direction {
        switch self {
        case .left:  .right
        case .right: .left
        case .up, .down, .stay: self
        }
    }
}

/// One folded **mirror echo**: a pair of plain `Echo`s, one per half, banked by a
/// single fold and replaying in lockstep against the shared turn (D-075). The two
/// streams are turn-aligned (a blocked body recorded `.stay`), so the pair is one
/// past-self that exists in both halves at once. `Echo` is reused, not duplicated —
/// each half's body is an ordinary verbatim replay from its half's start.
nonisolated struct MirrorEcho: Identifiable, Equatable, Sendable {
    /// Stable identity for the pair (SwiftUI animates the two grey bodies via the
    /// member echoes' own ids; this id keys the pair itself).
    let id: UUID
    /// The left half's replay (starts at the level `start`).
    let left: Echo
    /// The right half's replay (starts at `mirror.startRight`).
    let right: Echo

    init(id: UUID = UUID(), left: Echo, right: Echo) {
        self.id = id
        self.left = left
        self.right = right
    }
}

/// What one input would do to the two bodies — the single prediction both
/// `MirrorGameState.move(_:)` **and** the mirror board's presentation read, so there
/// is one movement rule, not an engine copy and a view copy (the Phase 4.03 lesson:
/// a view-side re-implementation silently diverged; this surface prevents that).
nonisolated struct MirrorStepPlan: Equatable, Sendable {
    /// The step each body actually takes — the reflected input, or `.stay` if that
    /// body is blocked (this is what a committed move appends to each stream).
    let leftStep: Direction
    let rightStep: Direction
    /// Where each body ends the turn (its current cell when its step is `.stay`).
    let leftTarget: GridCoordinate
    let rightTarget: GridCoordinate
    /// Whether the input commits a turn at all — `false` means both bodies are
    /// blocked (the no-op), `true` for any partial or full movement and for a wait.
    let commits: Bool
}

/// Observable model of one mirror room: the split board, the two live bodies, the
/// shared turn counter, the two recorded streams, and the folded mirror echoes.
/// Parallel to `GameState` (same op names, same input-lock/`lastMoveOutcome`
/// surface) so the room screen can drive either engine the same way — but a
/// separate type, leaving the verified single-body engine untouched (D-075).
@MainActor
@Observable
final class MirrorGameState {
    /// Board size. `width` must be even — the centerline is between columns
    /// `midColumn − 1` and `midColumn`.
    let width: Int
    let height: Int

    /// First column of the RIGHT half (`width / 2`). The left half is
    /// `0 ..< midColumn`; a body never crosses this line (partial-movement rule).
    let midColumn: Int

    /// The two bodies' start tiles — left = the level's `start`, right =
    /// `mirror.startRight`. Fold / reset / a death return both bodies here.
    let startLeft: GridCoordinate
    let startRight: GridCoordinate

    /// The two exits — left = the level's `exit`, right = `mirror.exitRight`.
    /// Winning needs BOTH bodies on their own exits on the same turn.
    let exitLeft: GridCoordinate
    let exitRight: GridCoordinate

    /// Maximum number of folds (mirror echoes) this room allows (D-027, reused).
    let echoBudget: Int

    /// The room contents, authored on the full grid exactly as in a normal room.
    let walls: Set<GridCoordinate>
    let switches: [Switch]
    let doors: [Door]
    let hazards: [Hazard]

    /// The two live bodies. Read-only from outside; only `move(_:)` (and the
    /// rewinds) change them. `leftBody` is always in the left half, `rightBody`
    /// always in the right — the confinement invariant.
    private(set) var leftBody: GridCoordinate
    private(set) var rightBody: GridCoordinate

    /// The shared turn counter — one world, one clock, exactly as in `GameState`.
    private(set) var turn: Int = 0

    /// The live run since the last fold, one turn-aligned stream per body. Equal
    /// length always (== `turn`); a blocked body's turn is a recorded `.stay`.
    private(set) var currentLeftRun: [Direction] = []
    private(set) var currentRightRun: [Direction] = []

    /// The banked mirror echoes, oldest first. Each replays both its bodies locked
    /// to `turn`.
    private(set) var echoes: [MirrorEcho] = []

    /// Set the instant both bodies reach their exits alive. While `true`, input is
    /// locked (`move`/`wait`/`fold`/`stepBack` are no-ops) until reset/reload.
    private(set) var hasWon: Bool = false

    /// The outcome of the most recent **committed** input — the same additive,
    /// read-only feedback signal `GameState.lastMoveOutcome` is (Phase 2.05): a
    /// survived turn → `.stepped`, the both-home turn → `.won`, the collision
    /// branch → `.died` (set before the restart, so it survives the rewind). A
    /// blocked no-op leaves it unchanged; `nil` until the first committed input.
    private(set) var lastMoveOutcome: MoveOutcome?

    /// Designated initializer (used by tests and in-code construction). Debug-asserts
    /// the mirror invariants: an even width, and each body's start/exit inside its
    /// own half — all authoring bugs if violated (D-074/D-076).
    init(width: Int, height: Int,
         startLeft: GridCoordinate, startRight: GridCoordinate,
         exitLeft: GridCoordinate, exitRight: GridCoordinate,
         echoBudget: Int = .max,
         walls: [GridCoordinate] = [], switches: [Switch] = [],
         doors: [Door] = [], hazards: [Hazard] = []) {
        assert(width % 2 == 0, "a mirror room's width must be even, got \(width)")
        let mid = width / 2
        assert(startLeft.column < mid && exitLeft.column < mid,
               "the left body's start/exit must lie in the left half")
        assert(startRight.column >= mid && exitRight.column >= mid,
               "the right body's start/exit must lie in the right half")
        self.width = width
        self.height = height
        self.midColumn = mid
        self.startLeft = startLeft
        self.startRight = startRight
        self.exitLeft = exitLeft
        self.exitRight = exitRight
        self.echoBudget = echoBudget
        self.walls = Set(walls)
        self.switches = switches
        self.doors = doors
        self.hazards = hazards
        self.leftBody = startLeft
        self.rightBody = startRight
    }

    /// Build a mirror board from a decoded `Level`. The level must carry a `mirror`
    /// block (the screen only routes here when it does — debug-asserted); in release
    /// a missing block falls back to the horizontal mirror of `start`/`exit` rather
    /// than crashing. A fresh instance per room inherently resets play.
    convenience init(level: Level) {
        assert(level.mirror != nil, "MirrorGameState requires a level with a mirror block")
        let mirrored = { (cell: GridCoordinate) in
            GridCoordinate(row: cell.row, column: level.width - 1 - cell.column)
        }
        self.init(width: level.width, height: level.height,
                  startLeft: level.start,
                  startRight: level.mirror?.startRight ?? mirrored(level.start),
                  exitLeft: level.exit,
                  exitRight: level.mirror?.exitRight ?? mirrored(level.exit),
                  echoBudget: level.echoBudget,
                  walls: level.walls, switches: level.switches,
                  doors: level.doors, hazards: level.hazards)
    }

    // MARK: - Board queries (the same per-turn derivations GameState makes — D-019)

    /// Whether `cell` lies inside the board.
    func contains(_ cell: GridCoordinate) -> Bool {
        cell.row >= 0 && cell.row < height
            && cell.column >= 0 && cell.column < width
    }

    /// Whether `cell` is an impassable wall.
    func isWall(_ cell: GridCoordinate) -> Bool {
        walls.contains(cell)
    }

    /// Whether `cell` lies in the left half (`column < midColumn`).
    func isInLeftHalf(_ cell: GridCoordinate) -> Bool {
        cell.column < midColumn
    }

    /// The cell a mirror echo's LEFT body occupies at the current turn — the pure
    /// `Echo.position` walk from the left start (empty pads; no teleport in mirror).
    func leftPosition(of echo: MirrorEcho) -> GridCoordinate {
        echo.left.position(start: startLeft, turn: turn)
    }

    /// The cell a mirror echo's RIGHT body occupies at the current turn.
    func rightPosition(of echo: MirrorEcho) -> GridCoordinate {
        echo.right.position(start: startRight, turn: turn)
    }

    /// The cells the echo's LEFT body is about to enter (the echo-trail aid's read).
    func leftUpcomingCells(of echo: MirrorEcho) -> [GridCoordinate] {
        echo.left.upcomingCells(start: startLeft, turn: turn)
    }

    /// The cells the echo's RIGHT body is about to enter.
    func rightUpcomingCells(of echo: MirrorEcho) -> [GridCoordinate] {
        echo.right.upcomingCells(start: startRight, turn: turn)
    }

    /// The cell `hazard` occupies right now (verbatim authored patrol, D-036).
    func position(of hazard: Hazard) -> GridCoordinate {
        hazard.position(at: turn)
    }

    /// Whether `cell` is occupied by **either live body or any echo-body (left or
    /// right)** at the current turn — the cross-half occupancy that holds switches
    /// (hazards never hold switches — D-019). This is what lets one folded mirror
    /// echo hold a switch in each half at once (D-074).
    func isCellHeld(_ cell: GridCoordinate) -> Bool {
        if leftBody == cell || rightBody == cell { return true }
        return echoes.contains {
            leftPosition(of: $0) == cell || rightPosition(of: $0) == cell
        }
    }

    /// Whether the switch with `id` is held at the current turn.
    func isSwitchHeld(_ id: String) -> Bool {
        guard let theSwitch = switches.first(where: { $0.id == id }) else { return false }
        return isCellHeld(theSwitch.cell)
    }

    /// Whether `door` is open at the current turn: every switch in its `heldBy` must
    /// be held (AND) — the switches may sit in different halves (D-074).
    func isDoorOpen(_ door: Door) -> Bool {
        door.heldBy.allSatisfy { isSwitchHeld($0) }
    }

    /// Whether `cell` is blocked by a closed door at the current turn.
    func isClosedDoor(_ cell: GridCoordinate) -> Bool {
        doors.contains { $0.cells.contains(cell) && !isDoorOpen($0) }
    }

    // MARK: - The step plan (one movement rule, shared with the presentation)

    /// What `direction` would do to the two bodies right now (D-074): reflect the
    /// input per body, apply the partial-movement rule per body against the current
    /// (pre-step, D-038) door state, and report each body's actual step + landing
    /// and whether anything commits. `move(_:)` executes exactly this plan, and the
    /// mirror board reads the same plan to choose its presentation — one rule.
    /// A `.stay` input (the wait) trivially commits with both bodies holding.
    func plan(for direction: Direction) -> MirrorStepPlan {
        let leftIntent = direction
        let rightIntent = direction.horizontallyMirrored

        /// Whether `body` may take one step to `target` — inside its own half (the
        /// centerline blocks), on the board, not a wall, and not a closed door read
        /// at the current turn. A zero-offset "step" (the wait) is always allowed.
        func allows(_ body: GridCoordinate, _ target: GridCoordinate) -> Bool {
            guard target != body else { return true }
            guard isInLeftHalf(target) == isInLeftHalf(body) else { return false }
            guard contains(target) else { return false }
            guard !isWall(target) else { return false }
            guard !isClosedDoor(target) else { return false }
            return true
        }

        let leftRaw = GridCoordinate(row: leftBody.row + leftIntent.offset.row,
                                     column: leftBody.column + leftIntent.offset.column)
        let rightRaw = GridCoordinate(row: rightBody.row + rightIntent.offset.row,
                                      column: rightBody.column + rightIntent.offset.column)
        let leftMoves = allows(leftBody, leftRaw) && leftIntent != .stay
        let rightMoves = allows(rightBody, rightRaw) && rightIntent != .stay

        return MirrorStepPlan(
            leftStep: leftMoves ? leftIntent : .stay,
            rightStep: rightMoves ? rightIntent : .stay,
            leftTarget: leftMoves ? leftRaw : leftBody,
            rightTarget: rightMoves ? rightRaw : rightBody,
            // A wait always commits; a directional input commits iff a body moves.
            commits: direction == .stay || leftMoves || rightMoves)
    }

    /// Whether a body, having just stepped from `previousBodyCell` (its tile at turn
    /// `t − 1`) to `newBodyCell` (its tile at turn `t`), has **touched** any
    /// echo-body or hazard on this step — the same land-on OR cross-paths predicate
    /// as `GameState.playerCollides` (D-018/D-022), evaluated per body. Pure and
    /// view-independent; the mirror board reads it for its death prediction too.
    ///
    /// Every echo-body (left and right of every pair) and every hazard is checked:
    /// confinement makes this exactly the "in its own half" rule — a mover can only
    /// ever land on / cross a body that is in the same half at that moment. Unlike
    /// the single-body engine, the echo **cross-paths branch is live** here: partial
    /// movement records a `.stay` for a blocked body, which breaks the shared-parity
    /// argument that made it dormant, so a live body and an echo-body genuinely can
    /// trade adjacent tiles.
    func bodyCollides(previousBodyCell: GridCoordinate,
                      newBodyCell: GridCoordinate,
                      turn t: Int) -> Bool {
        for echo in echoes {
            for (start, body) in [(startLeft, echo.left), (startRight, echo.right)] {
                let bodyNow = body.position(start: start, turn: t)
                if bodyNow == newBodyCell { return true }                  // land-on
                let bodyBefore = body.position(start: start, turn: t - 1)
                if bodyBefore == newBodyCell && bodyNow == previousBodyCell {
                    return true                                            // cross-paths (live)
                }
            }
        }
        for hazard in hazards {
            let hazardNow = hazard.position(at: t)
            if hazardNow == newBodyCell { return true }                    // land-on
            let hazardBefore = hazard.position(at: t - 1)
            if hazardBefore == newBodyCell && hazardNow == previousBodyCell {
                return true                                                // cross-paths (live)
            }
        }
        return false
    }

    // MARK: - The turn engine

    /// Move both bodies one reflected step in `direction` (D-074).
    ///
    /// Executes `plan(for:)`: each body takes its reflected step iff its target is
    /// legal, else it stays (partial movement); if **neither** can move the input is
    /// a no-op — nothing changes, nothing is recorded, `false` is returned — exactly
    /// like walking into a wall today. `.stay` is refused (the wait is `wait()`), as
    /// is any input after a win.
    ///
    /// A committed input advances the shared turn by one and appends each body's
    /// **actual** step (`.stay` for a blocked body) to its stream — the verbatim
    /// record its echo will replay (D-020). Then the per-body death check runs
    /// (land-on OR cross-paths against every echo-body and hazard): either body
    /// touching one dissolves **both** — `lastMoveOutcome = .died` and the run
    /// restarts, echoes intact. Only a survived step checks the win: both bodies on
    /// their own exits the same turn sets `hasWon` (collision before win, D-023);
    /// a blocked no-op can never win because it never commits.
    ///
    /// Returns whether a turn was committed (including the fatal one, which did
    /// happen before it was discarded).
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        guard direction != .stay else { return false }   // `.stay` is issued only via wait()
        guard !hasWon else { return false }              // input locked after a win
        let plan = plan(for: direction)
        guard plan.commits else { return false }         // both bodies blocked: the no-op

        let previousLeft = leftBody
        let previousRight = rightBody
        leftBody = plan.leftTarget
        rightBody = plan.rightTarget
        turn += 1
        currentLeftRun.append(plan.leftStep)
        currentRightRun.append(plan.rightStep)

        // Per-body death check — either body touching an echo-body or hazard in its
        // half dissolves both (D-074). Turn 0 is never tested (a committed input makes
        // turn ≥ 1), so the post-fold start stack is immune and there is no restart loop.
        if bodyCollides(previousBodyCell: previousLeft, newBodyCell: leftBody, turn: turn)
            || bodyCollides(previousBodyCell: previousRight, newBodyCell: rightBody, turn: turn) {
            lastMoveOutcome = .died   // set before the rewind, which never touches it
            restartRun()
            return true
        }

        // Then win: BOTH bodies on their own-half exits on the same turn (D-074).
        if leftBody == exitLeft && rightBody == exitRight {
            hasWon = true
            lastMoveOutcome = .won
        } else {
            lastMoveOutcome = .stepped
        }
        return true
    }

    /// **Wait** — both bodies hold position while the world advances one shared turn
    /// (the reused Phase 4.01 action — D-066, applied to two bodies). Appends a
    /// `.stay` to **both** streams, then runs the same per-body death check a move
    /// does (each held tile as both previous and new cell), so a mover landing on
    /// either held body this turn kills both. Never checks the exits (you can't win
    /// standing still); refused only while won. Returns whether a turn passed.
    @discardableResult
    func wait() -> Bool {
        guard !hasWon else { return false }   // input locked after a win
        let heldLeft = leftBody
        let heldRight = rightBody
        turn += 1
        currentLeftRun.append(.stay)
        currentRightRun.append(.stay)

        if bodyCollides(previousBodyCell: heldLeft, newBodyCell: heldLeft, turn: turn)
            || bodyCollides(previousBodyCell: heldRight, newBodyCell: heldRight, turn: turn) {
            lastMoveOutcome = .died
            restartRun()
            return true
        }

        lastMoveOutcome = .stepped
        return true
    }

    /// Restart the current run — both bodies dissolving on contact, and the op the
    /// reset-run control is wired to (D-029, reused). Both bodies return to their
    /// starts, the turn to 0, both streams empty, any win flag cleared — while every
    /// folded mirror echo stays intact and keeps replaying.
    func restartRun() {
        leftBody = startLeft
        rightBody = startRight
        turn = 0
        currentLeftRun = []
        currentRightRun = []
        hasWon = false
    }

    /// **Step back** — undo one committed turn of the current run (D-028/D-030/D-031,
    /// reused): pop the last step from **both** streams, decrement the shared turn,
    /// and replay both bodies from their starts through the same pure `Echo.position`
    /// walk their echoes use (the streams stay the single source of truth, so the
    /// bodies can never drift from them). No collision/win check — it rolls back to
    /// a turn both bodies already occupied alive. Refused while won or at turn 0
    /// (intra-run only; it never crosses the fold boundary).
    @discardableResult
    func stepBack() -> Bool {
        guard !hasWon else { return false }
        guard !currentLeftRun.isEmpty else { return false }

        currentLeftRun.removeLast()
        currentRightRun.removeLast()
        turn -= 1
        leftBody = Echo(moves: currentLeftRun).position(start: startLeft, turn: currentLeftRun.count)
        rightBody = Echo(moves: currentRightRun).position(start: startRight, turn: currentRightRun.count)
        return true
    }

    /// **Fold** the current two-stream run into one permanent mirror echo, then
    /// rewind the board to its start (the Plan §14 fold, applied to two bodies).
    /// Banks `(Echo(currentLeftRun), Echo(currentRightRun))` as a pair, returns both
    /// bodies to their starts, resets the turn to 0, and empties both streams —
    /// every existing mirror echo then sits on the start stack again by consequence.
    /// Refused after a win, on an empty run, or at the echo budget (D-027).
    @discardableResult
    func fold() -> Bool {
        guard !hasWon else { return false }
        guard !currentLeftRun.isEmpty else { return false }
        guard echoes.count < echoBudget else { return false }
        echoes.append(MirrorEcho(left: Echo(moves: currentLeftRun),
                                 right: Echo(moves: currentRightRun)))
        leftBody = startLeft
        rightBody = startRight
        turn = 0
        currentLeftRun = []
        currentRightRun = []
        return true
    }
}
