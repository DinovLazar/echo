//
//  MirrorTests.swift
//  ECHOTests
//
//  Phase 4.05 (the mirror engine). Deterministic coverage for `MirrorGameState` —
//  the separate two-body engine (D-074/D-075) — driven directly, the way `ECHOTests`
//  drives `GameState`. Every rule in the mirror spec is pinned: reflected controls,
//  partial movement (desync + the both-blocked no-op), centerline confinement, the
//  reused wait, the two-body fold and its verbatim replay (a blocked turn's `.stay`
//  is reproduced), cross-half switch holds and AND-doors, per-half death (echo-body
//  and hazard, either half, both bodies dissolve), the both-home win, step-back over
//  both streams, and the format's additive `mirror` block (D-076).
//
//  The headline proof is an asymmetric room where the solve *requires* the mechanic:
//  desync the bodies past a one-sided wall, fold a mirror echo that holds a
//  cross-half AND-door open, then land both bodies on their exits the same turn.
//
//  `MirrorGameState` is `@MainActor`, so the case is `@MainActor`, matching the
//  other engine suites.
//

import XCTest
@testable import ECHO

@MainActor
final class MirrorTests: XCTestCase {

    // MARK: - Helpers

    /// Shorthand for a cell.
    private func g(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    /// A bare 8×4 mirror board (mid-column 4): left body starts at (2,1), right at
    /// (2,6); exits parked on the top corners' neighbours so ordinary stepping never
    /// accidentally wins. Contents are injectable per test.
    private func makeBoard(startLeft: GridCoordinate? = nil,
                           startRight: GridCoordinate? = nil,
                           exitLeft: GridCoordinate? = nil,
                           exitRight: GridCoordinate? = nil,
                           echoBudget: Int = .max,
                           walls: [GridCoordinate] = [],
                           switches: [Switch] = [],
                           doors: [Door] = [],
                           hazards: [Hazard] = []) -> MirrorGameState {
        MirrorGameState(width: 8, height: 4,
                        startLeft: startLeft ?? g(2, 1),
                        startRight: startRight ?? g(2, 6),
                        exitLeft: exitLeft ?? g(0, 1),
                        exitRight: exitRight ?? g(0, 6),
                        echoBudget: echoBudget,
                        walls: walls, switches: switches,
                        doors: doors, hazards: hazards)
    }

    // MARK: - Reflected controls (D-074)

    /// UP and DOWN move both bodies the same way; the shared turn ticks once per input.
    func testUpDownMoveBothBodiesTheSameWay() {
        let state = makeBoard()
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.leftBody, g(1, 1))
        XCTAssertEqual(state.rightBody, g(1, 6))
        XCTAssertEqual(state.turn, 1)
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.currentLeftRun, [.up, .down])
        XCTAssertEqual(state.currentRightRun, [.up, .down])
    }

    /// LEFT moves the left body left and the right body RIGHT (and vice versa) —
    /// the bodies mirror across the centerline, and each stream records its own step.
    func testLeftRightMoveBodiesOppositely() {
        let state = makeBoard()
        XCTAssertTrue(state.move(.left))
        XCTAssertEqual(state.leftBody, g(2, 0), "left body moved left")
        XCTAssertEqual(state.rightBody, g(2, 7), "right body moved right (mirrored)")
        XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.currentLeftRun, [.left, .right])
        XCTAssertEqual(state.currentRightRun, [.right, .left], "the right stream records the reflected steps")
    }

    /// `.stay` is refused by `move(_:)` — a wait is only ever `wait()` (D-067 reused).
    func testMoveRefusesStay() {
        let state = makeBoard()
        XCTAssertFalse(state.move(.stay))
        XCTAssertEqual(state.turn, 0)
        XCTAssertNil(state.lastMoveOutcome)
    }

    // MARK: - Partial movement (the crux)

    /// An asymmetric wall blocks one body while the other moves — they desync, and
    /// the blocked body records a `.stay` for the turn (the verbatim record D-020
    /// replay rests on).
    func testAsymmetricWallDesyncsTheBodies() {
        let state = makeBoard(walls: [g(2, 0)])   // left half only
        XCTAssertTrue(state.move(.left))
        XCTAssertEqual(state.leftBody, g(2, 1), "left body blocked by the one-sided wall")
        XCTAssertEqual(state.rightBody, g(2, 7), "right body moved — the bodies desync")
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.currentLeftRun, [.stay], "the blocked body recorded a .stay")
        XCTAssertEqual(state.currentRightRun, [.right])
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
    }

    /// If neither body can move the input is a no-op: the turn does not advance,
    /// nothing is recorded, and `lastMoveOutcome` is untouched.
    func testBothBodiesBlockedIsANoOp() {
        let state = makeBoard(startLeft: g(0, 1), startRight: g(0, 6),
                              exitLeft: g(3, 1), exitRight: g(3, 6))
        XCTAssertTrue(state.move(.down))              // establish a .stepped outcome first
        XCTAssertTrue(state.move(.up))                // back to row 0
        XCTAssertEqual(state.leftBody, g(0, 1))
        XCTAssertEqual(state.rightBody, g(0, 6))
        let turnBefore = state.turn
        XCTAssertFalse(state.move(.up), "both bodies off-grid: the input is refused")
        XCTAssertEqual(state.turn, turnBefore, "a no-op never advances the turn")
        XCTAssertEqual(state.currentLeftRun.count, turnBefore, "nothing recorded")
        XCTAssertEqual(state.lastMoveOutcome, .stepped, "a no-op leaves the outcome unchanged")
    }

    // MARK: - Confinement (the centerline blocks)

    /// Neither body ever crosses the centerline: stepping "inward" from the two
    /// innermost columns blocks both bodies (a no-op), while stepping outward works.
    func testNeitherBodyCrossesTheCenterline() {
        let state = makeBoard(startLeft: g(1, 3), startRight: g(1, 4))
        XCTAssertFalse(state.move(.right), "left→(1,4) and right→(1,3) both cross the line: no-op")
        XCTAssertEqual(state.leftBody, g(1, 3))
        XCTAssertEqual(state.rightBody, g(1, 4))
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.move(.left), "outward is fine")
        XCTAssertEqual(state.leftBody, g(1, 2))
        XCTAssertEqual(state.rightBody, g(1, 5))
    }

    // MARK: - The wait (reused — D-066)

    /// A `.stay` input holds both bodies and advances the shared turn, appending a
    /// `.stay` to both streams.
    func testWaitHoldsBothBodiesAndAdvancesTheTurn() {
        let state = makeBoard()
        XCTAssertTrue(state.wait())
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.currentLeftRun, [.stay])
        XCTAssertEqual(state.currentRightRun, [.stay])
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
    }

    // MARK: - Fold: the two-body echo

    /// `fold()` banks exactly one mirror echo (a pair of per-half `Echo`s carrying the
    /// two recorded streams), rewinds both bodies to their starts and the turn to 0,
    /// and is refused at the budget / on an empty run.
    func testFoldBanksATwoBodyEchoWithinBudget() {
        let state = makeBoard(echoBudget: 1)
        XCTAssertFalse(state.fold(), "an empty run never folds")
        XCTAssertTrue(state.move(.up))
        XCTAssertTrue(state.move(.left))
        XCTAssertTrue(state.fold())
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertEqual(state.echoes[0].left.moves, [.up, .left])
        XCTAssertEqual(state.echoes[0].right.moves, [.up, .right])
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentLeftRun.isEmpty)
        XCTAssertTrue(state.currentRightRun.isEmpty)
        // At the budget: a second fold is refused; the run and echo count are unchanged.
        XCTAssertTrue(state.move(.down))
        XCTAssertFalse(state.fold(), "the budget caps folding (D-027)")
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertEqual(state.currentLeftRun, [.down])
    }

    /// A mirror echo replays both bodies verbatim — a `.stay` recorded on a blocked
    /// turn is reproduced as a hold, then the walk continues; an exhausted echo
    /// stands still on its last tiles (D-020 per half).
    func testMirrorEchoReplaysBothBodiesVerbatimIncludingTheBlockedStay() {
        let state = makeBoard(walls: [g(1, 1)])       // one-sided: blocks the LEFT body's .up
        XCTAssertTrue(state.move(.up))                 // left blocked (.stay), right → (1,6)
        XCTAssertTrue(state.move(.down))               // left → (3,1), right → (2,6)
        XCTAssertEqual(state.currentLeftRun, [.stay, .down])
        XCTAssertEqual(state.currentRightRun, [.up, .down])
        XCTAssertTrue(state.fold())
        let echo = state.echoes[0]

        // Live bodies step aside so the replaying echo never touches them.
        XCTAssertTrue(state.move(.right))              // live: left (2,2) / right (2,5); turn 1
        XCTAssertEqual(state.leftPosition(of: echo), g(2, 1),
                       "turn 1: the left echo-body reproduces its recorded .stay (the blocked turn)")
        XCTAssertEqual(state.rightPosition(of: echo), g(1, 6))
        XCTAssertTrue(state.wait())                    // turn 2
        XCTAssertEqual(state.leftPosition(of: echo), g(3, 1),
                       "turn 2: after the held turn, the left echo-body walks on")
        XCTAssertEqual(state.rightPosition(of: echo), g(2, 6))
        XCTAssertTrue(state.wait())                    // turn 3: both streams exhausted
        XCTAssertEqual(state.leftPosition(of: echo), g(3, 1), "an exhausted echo-body stands still")
        XCTAssertEqual(state.rightPosition(of: echo), g(2, 6))
    }

    // MARK: - Cross-half switches & doors (D-074/D-019)

    /// A body in one half holds a switch that opens a door in the *other* half — and
    /// the door pass is read at the pre-step turn (D-038): the same input that puts a
    /// body on the switch cannot also carry the other body through the door.
    func testCrossHalfHoldOpensADoorInTheOtherHalf() {
        let state = makeBoard(exitLeft: g(0, 0), exitRight: g(0, 7),
                              switches: [Switch(id: "sL", cell: g(1, 1))],
                              doors: [Door(id: "dR", cells: [g(1, 6)], heldBy: ["sL"])])
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.leftBody, g(1, 1), "left body on the switch")
        XCTAssertEqual(state.rightBody, g(2, 6),
                       "right body blocked: at the pre-step turn the cross-half door was still closed")
        XCTAssertTrue(state.isSwitchHeld("sL"))
        XCTAssertTrue(state.isDoorOpen(state.doors[0]), "held from this turn on")
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.leftBody, g(0, 1), "left body walked on")
        XCTAssertEqual(state.rightBody, g(1, 6),
                       "right body crossed the cross-half door held open at the pre-step turn")
    }

    /// An AND-door spanning halves opens iff BOTH its switches (one per half) are
    /// held — by any combination of live bodies and echo-bodies (D-074).
    func testANDDoorSpanningHalvesNeedsBothSwitches() {
        let state = makeBoard(switches: [Switch(id: "sL", cell: g(1, 1)),
                                         Switch(id: "sR", cell: g(1, 6))],
                              doors: [Door(id: "dX", cells: [g(3, 1), g(3, 6)],
                                           heldBy: ["sL", "sR"])])
        XCTAssertFalse(state.isDoorOpen(state.doors[0]))
        XCTAssertTrue(state.move(.up))                 // both bodies onto their switches
        XCTAssertEqual(state.leftBody, g(1, 1))
        XCTAssertEqual(state.rightBody, g(1, 6))
        XCTAssertTrue(state.isSwitchHeld("sL"))
        XCTAssertTrue(state.isSwitchHeld("sR"))
        XCTAssertTrue(state.isDoorOpen(state.doors[0]), "both halves held → the AND-door opens")
        // One mirror echo can hold both at once: fold here, walk the live bodies off,
        // and the pair keeps the AND-door open from its resting tiles.
        XCTAssertTrue(state.fold())
        XCTAssertTrue(state.move(.left))               // live bodies step aside (echo goes up)
        XCTAssertTrue(state.wait())                    // echo now resting on both switches
        XCTAssertTrue(state.isDoorOpen(state.doors[0]),
                      "a single folded mirror echo holds a switch in each half at once")
    }

    // MARK: - Death (per half; both bodies dissolve)

    /// ONLY the LEFT body touches an echo-body — and both bodies dissolve: the run
    /// restarts (both to their starts, turn 0, streams empty), echoes persist,
    /// outcome `.died`. The right body was nowhere near anything.
    func testLeftBodyOntoEchoBodyDissolvesBoth() {
        // The one-sided wall at (2,5) blocks the RIGHT body's outward step, so the
        // banked echo desyncs: its left body rests at (2,2), its right at (2,6).
        let state = makeBoard(walls: [g(2, 5)])
        XCTAssertTrue(state.move(.right))              // left → (2,2); right blocked (.stay)
        XCTAssertTrue(state.fold())
        // Live: skirt below, then step up — the LEFT body alone lands on the echo's
        // resting left body at (2,2); the right body's target (2,5) is the wall, and
        // the echo's right body is at (2,6), untouched.
        XCTAssertTrue(state.move(.down))               // t1: left (3,1) / right (3,6)
        XCTAssertTrue(state.move(.right))              // t2: left (3,2) / right (3,5)
        XCTAssertTrue(state.move(.up))                 // t3: left → (2,2) = echo-body → death
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.leftBody, g(2, 1), "both bodies back at their starts")
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentLeftRun.isEmpty)
        XCTAssertEqual(state.echoes.count, 1, "echoes persist through a death")
        XCTAssertFalse(state.hasWon)
    }

    /// ONLY the RIGHT body touches an echo-body — the rule is per body, per half,
    /// and either body's touch dissolves both.
    func testRightBodyOntoEchoBodyDissolvesBoth() {
        // The one-sided wall at (2,2) blocks the LEFT body's outward step, so the
        // banked echo desyncs: its left body rests at (2,1), its right at (2,5).
        let state = makeBoard(walls: [g(2, 2)])
        XCTAssertTrue(state.move(.right))              // left blocked (.stay); right → (2,5)
        XCTAssertTrue(state.fold())
        // Live: skirt below, then step up — the RIGHT body alone lands on the echo's
        // resting right body at (2,5); the left body's target (2,2) is the wall, and
        // the echo's left body is at (2,1), untouched.
        XCTAssertTrue(state.move(.down))               // t1: left (3,1) / right (3,6)
        XCTAssertTrue(state.move(.right))              // t2: left (3,2) / right (3,5)
        XCTAssertTrue(state.move(.up))                 // t3: right → (2,5) = echo-body → death
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.echoes.count, 1)
    }

    /// A hazard in a body's half kills on land-on — here the right half's patrol
    /// sweeps onto the right body's target tile at the same turn.
    func testHazardLandOnKillsInTheRightHalf() {
        let state = makeBoard(hazards: [Hazard(id: "h1", start: g(0, 6),
                                               path: [.down, .up], loops: true)])
        XCTAssertTrue(state.move(.up))                 // right → (1,6); hazard t1 → (1,6): land-on
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 0)
    }

    /// The cross-paths (swap) branch is live per body: the right body and a hazard
    /// trading adjacent tiles on the same turn is a death (D-018/D-022).
    func testHazardCrossPathsKillsPerBody() {
        let state = makeBoard(hazards: [Hazard(id: "h1", start: g(1, 6),
                                               path: [.down, .up], loops: true)])
        XCTAssertTrue(state.move(.up))   // right (2,6)→(1,6) while hazard (1,6)→(2,6): swap
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 0)
    }

    /// A fatal wait: a mover landing on a held body's tile kills — holding position
    /// is risky for two bodies exactly as for one (D-066).
    func testFatalWaitWhenAMoverLandsOnAHeldBody() {
        let state = makeBoard(hazards: [Hazard(id: "h1", start: g(2, 5),
                                               path: [.right, .left], loops: true)])
        XCTAssertTrue(state.wait())      // hazard t1 → (2,6): lands on the held right body
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Win (both bodies home the same turn)

    /// Exactly one body on its exit is NOT a win; the win lands on the committed
    /// turn that has BOTH bodies on their own-half exits — and a wall-held body
    /// counts as "sitting" there (partial movement can complete a win).
    func testWinNeedsBothBodiesOnTheirExitsTheSameTurn() {
        let state = makeBoard(startLeft: g(1, 1), startRight: g(1, 6),
                              exitLeft: g(0, 0), exitRight: g(0, 6),
                              walls: [g(0, 7)])
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.rightBody, g(0, 6), "right body is home")
        XCTAssertFalse(state.hasWon, "one body home is not a win")
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
        XCTAssertTrue(state.move(.left))   // left → (0,0) = exit; right blocked by (0,7): holds its exit
        XCTAssertTrue(state.hasWon, "both bodies on their exits the same turn")
        XCTAssertEqual(state.lastMoveOutcome, .won)
        // Input locks after the win (symmetry with GameState — D-031).
        XCTAssertFalse(state.move(.down))
        XCTAssertFalse(state.wait())
        XCTAssertFalse(state.stepBack())
        XCTAssertFalse(state.fold())
    }

    // MARK: - Step back (both streams)

    /// `stepBack()` pops the last step from BOTH streams, decrements the shared turn,
    /// and rewinds both bodies — including across a desynced (partial-movement) turn.
    /// Refused at turn 0.
    func testStepBackRewindsBothBodiesAcrossADesyncedTurn() {
        let state = makeBoard(walls: [g(2, 0)])        // blocks the left body's .left
        XCTAssertTrue(state.move(.left))               // desync: left stays, right → (2,7)
        XCTAssertTrue(state.move(.up))                 // left → (1,1), right → (1,7)
        XCTAssertEqual(state.turn, 2)
        XCTAssertTrue(state.stepBack())
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 7))
        XCTAssertEqual(state.currentLeftRun, [.stay])
        XCTAssertEqual(state.currentRightRun, [.right])
        XCTAssertTrue(state.stepBack())
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.leftBody, g(2, 1))
        XCTAssertEqual(state.rightBody, g(2, 6))
        XCTAssertFalse(state.stepBack(), "turn 0: nothing to undo (D-030)")
    }

    // MARK: - The format: the additive `mirror` block (D-076)

    /// A level with a `mirror` block decodes it; `MirrorGameState(level:)` wires the
    /// left body to the top-level start/exit and the right body to the block's.
    func testLevelWithMirrorBlockDecodesAndWiresTheEngine() throws {
        let json = """
        { "id": "m", "name": "Mirror", "width": 8, "height": 4,
          "start": { "row": 2, "column": 1 }, "exit": { "row": 0, "column": 1 },
          "echoBudget": 1,
          "mirror": { "axis": "vertical",
                      "startRight": { "row": 2, "column": 6 },
                      "exitRight":  { "row": 0, "column": 6 } } }
        """
        let level = try JSONDecoder().decode(Level.self, from: Data(json.utf8))
        XCTAssertEqual(level.mirror?.axis, "vertical")
        XCTAssertEqual(level.mirror?.startRight, g(2, 6))
        XCTAssertEqual(level.mirror?.exitRight, g(0, 6))
        let state = MirrorGameState(level: level)
        XCTAssertEqual(state.startLeft, g(2, 1))
        XCTAssertEqual(state.startRight, g(2, 6))
        XCTAssertEqual(state.exitLeft, g(0, 1))
        XCTAssertEqual(state.exitRight, g(0, 6))
        XCTAssertEqual(state.midColumn, 4)
        XCTAssertEqual(state.echoBudget, 1)
    }

    /// A level WITHOUT the block decodes exactly as before — `mirror` is `nil`, so
    /// every existing room JSON (rooms 01–30) is byte-for-byte valid and unchanged.
    func testLevelWithoutMirrorBlockDecodesAsBefore() throws {
        let json = """
        { "id": "n", "name": "Normal", "width": 5, "height": 3,
          "start": { "row": 1, "column": 0 }, "exit": { "row": 1, "column": 4 },
          "echoBudget": 0 }
        """
        let level = try JSONDecoder().decode(Level.self, from: Data(json.utf8))
        XCTAssertNil(level.mirror, "an absent mirror block ⇒ a normal single-body room")
        XCTAssertEqual(level.id, "n")
        XCTAssertEqual(level.walls, [])
        XCTAssertEqual(level.portals, [])
    }

    // MARK: - The headline proof (desync + cross-half AND-door + both-home win)

    /// The composite the whole band is built on, in one asymmetric room:
    ///   (a) **desync** — a one-sided wall at (3,6) forces the bodies out of lockstep
    ///       so the echo run can end on two non-mirrored switches;
    ///   (b) **cross-half AND-door** — one folded mirror echo rests on sL (3,1) and
    ///       sR (3,5) at once, holding open the AND-door spanning (1,1)+(1,6);
    ///   (c) **both-home win** — the live bodies thread the held door and land on
    ///       their exits the same turn.
    func testHeadlineProofDesyncFoldCrossHalfANDDoorThenBothHome() {
        let state = MirrorGameState(
            width: 8, height: 4,
            startLeft: g(2, 1), startRight: g(2, 6),
            exitLeft: g(0, 1), exitRight: g(0, 6),
            echoBudget: 1,
            walls: [g(3, 6),                              // the one-sided desync wall
                    g(0, 0), g(0, 7),                     // seal the top corners
                    g(1, 0), g(1, 2), g(1, 3), g(1, 4), g(1, 5), g(1, 7)],  // row 1 = walls except the door
            switches: [Switch(id: "sL", cell: g(3, 1)),
                       Switch(id: "sR", cell: g(3, 5))],
            doors: [Door(id: "dX", cells: [g(1, 1), g(1, 6)], heldBy: ["sL", "sR"])])

        // The echo run: desync past the one-sided wall to end on BOTH switches.
        XCTAssertTrue(state.move(.down))               // left → sL (3,1); right blocked by (3,6)
        XCTAssertEqual(state.leftBody, g(3, 1))
        XCTAssertEqual(state.rightBody, g(2, 6), "desynced")
        XCTAssertTrue(state.move(.right))              // left → (3,2); right → (2,5)
        XCTAssertTrue(state.move(.down))               // left blocked (edge); right → sR (3,5)
        XCTAssertTrue(state.move(.left))               // left → back onto sL; right blocked by (3,6)
        XCTAssertEqual(state.leftBody, g(3, 1))
        XCTAssertEqual(state.rightBody, g(3, 5))
        XCTAssertEqual(state.currentLeftRun, [.down, .right, .stay, .left])
        XCTAssertEqual(state.currentRightRun, [.stay, .left, .down, .stay])
        XCTAssertTrue(state.fold())

        // The AND-door is held only once the echo pair rests on both switches (turn 4+).
        XCTAssertFalse(state.isDoorOpen(state.doors[0]), "at turn 0 the echo is on the start stack")

        // The live run: step aside (the echo's right body lingers on the right start
        // at turn 1 — waiting there would be a death), wait out the echo's walk, then
        // thread the held AND-door and land both bodies home the same turn.
        XCTAssertTrue(state.move(.left))               // t1: left (2,0) / right (2,7)
        XCTAssertTrue(state.wait())                    // t2
        XCTAssertTrue(state.wait())                    // t3
        XCTAssertTrue(state.wait())                    // t4: echo now rests on sL + sR
        XCTAssertTrue(state.isDoorOpen(state.doors[0]),
                      "one folded mirror echo holds the cross-half AND-door open")
        XCTAssertTrue(state.move(.right))              // t5: back to (2,1) / (2,6)
        XCTAssertTrue(state.move(.up))                 // t6: through the held door (1,1) / (1,6)
        XCTAssertEqual(state.leftBody, g(1, 1))
        XCTAssertEqual(state.rightBody, g(1, 6))
        XCTAssertTrue(state.move(.up))                 // t7: both exits, same turn
        XCTAssertTrue(state.hasWon, "the mirror mechanic completes: desync → cross-half hold → both home")
        XCTAssertEqual(state.lastMoveOutcome, .won)
        XCTAssertEqual(state.echoes.count, 1, "solved within the budget of one fold")
    }
}
