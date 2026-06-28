//
//  EchoRunTests.swift
//  ECHOTests
//
//  Phase 3.02 (Echo Run — the arcade survival mode). Deterministic coverage of the new,
//  separate arcade engine `EchoRunState` (D-058), driven through its real public API
//  exactly as `ECHOTests`/`RoomSolvabilityTests` drive the campaign engine — no
//  re-implementation. These join the deterministic-logic suite and touch no campaign
//  rule.
//
//  What is pinned here (the mechanic, D-057):
//    • the 9×9 board with a centre start;
//    • the delayed-shadow spawn cadence (turns 8 / 16 / 24);
//    • that each shadow retraces the player's exact path, lagging by its spawn-turn
//      offset (asserted at specific turns);
//    • the edge-swipe stall (player holds, turn advances, shadows step);
//    • death on touching a shadow — both a land-on (a trailing shadow catches a stalled
//      head) and a cross-paths/swap — at the right turn, with the right score;
//    • score = turns survived (stalls included);
//    • input locked after death and a clean `reset()`;
//    • that `pendingDeath` (the view's deferred-death predictor) agrees with the commit;
//    • the Echo Run high score round-trips through `SettingsStore` and keeps the best.
//
//  `EchoRunState` and `SettingsStore` are `@MainActor`, so the case is `@MainActor` to
//  drive them directly (matching the existing suites). Some tests inject a small
//  `spawnPeriod` so a collision can be set up in a few turns; the production default is
//  always 8 (D-057), exercised by `testSpawnCadenceFiresEveryEighthTurn`.
//

import XCTest
@testable import ECHO

@MainActor
final class EchoRunTests: XCTestCase {

    /// Shorthand for a cell.
    private func g(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    /// A 24-move non-self-intersecting snake from the centre that survives the full
    /// default cadence: up the centre column to the top edge, right along it to the
    /// corner, down the right edge, then left along the bottom edge (up×4, right×4,
    /// down×8, left×8). Because every tile is fresh and the shadows trail strictly
    /// behind on the path, nothing is ever caught — so the player survives all 24 turns.
    private let snake: [Direction] =
        Array(repeating: .up, count: 4)
        + Array(repeating: .right, count: 4)
        + Array(repeating: .down, count: 8)
        + Array(repeating: .left, count: 8)

    // MARK: - Board

    func testStartsAtCentreOfNineByNine() {
        let s = EchoRunState()
        XCTAssertEqual(s.size, 9)
        XCTAssertEqual(s.start, g(4, 4))
        XCTAssertEqual(s.player, g(4, 4))
        XCTAssertEqual(s.turn, 0)
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(s.echoes.count, 0)
        XCTAssertFalse(s.isOver)
    }

    func testEveryMoveFromCentreIsARealStepNotAStall() {
        // The centre has four on-board neighbours, so no first move can stall.
        for direction in Direction.allCases {
            let s = EchoRunState()
            XCTAssertEqual(s.move(direction), .stepped)
            XCTAssertEqual(s.recording, [direction])
            XCTAssertEqual(s.turn, 1)
        }
    }

    // MARK: - Spawn cadence (turns 8 / 16 / 24)

    func testSpawnCadenceFiresEveryEighthTurn() {
        let s = EchoRunState()   // default spawnPeriod 8
        for (index, direction) in snake.enumerated() {
            let turnAfter = index + 1
            XCTAssertNotEqual(s.move(direction), .died, "snake move \(turnAfter) unexpectedly died")
            XCTAssertEqual(s.turn, turnAfter)
            // A shadow per completed period: 0 until turn 8, 1 until 16, 2 until 24, 3 at 24.
            XCTAssertEqual(s.echoes.count, turnAfter / 8, "echo count after turn \(turnAfter)")
        }
        XCTAssertEqual(s.echoes.map(\.spawnTurn), [8, 16, 24])
        XCTAssertFalse(s.isOver)
        XCTAssertEqual(s.score, 24)
    }

    func testEchoBeginsAtStartTileOnSpawn() {
        let s = EchoRunState()
        for direction in snake.prefix(8) { s.move(direction) }   // turn 8: E8 just spawned
        XCTAssertEqual(s.echoes.count, 1)
        XCTAssertEqual(s.echoes[0].spawnTurn, 8)
        XCTAssertEqual(s.position(of: s.echoes[0]), g(4, 4))     // born at start, offset 0
    }

    // MARK: - Shadows retrace the exact path, lagging by the spawn-turn offset

    func testEchoRetracesPlayerPathTilesAtGivenTurns() {
        let s = EchoRunState()
        for direction in snake.prefix(12) { s.move(direction) }  // turn 12; only E8 exists
        XCTAssertEqual(s.echoes.count, 1)
        // E8 (spawnTurn 8) at turn 12 is offset 4 along the path → P4 = (0,4).
        XCTAssertEqual(s.position(of: s.echoes[0]), g(0, 4))

        for direction in snake[12..<16] { s.move(direction) }    // turn 16; E8 and E16
        XCTAssertEqual(s.echoes.count, 2)
        // E8 offset 8 → P8 = (0,8); E16 offset 0 → the start tile.
        XCTAssertEqual(s.position(of: s.echoes[0]), g(0, 8))
        XCTAssertEqual(s.position(of: s.echoes[1]), g(4, 4))
        XCTAssertFalse(s.isOver)
    }

    // MARK: - Stall (edge swipe)

    func testStallHoldsPlayerAdvancesTurnLeavesRecordingUnchanged() {
        let s = EchoRunState()
        for _ in 0..<4 { s.move(.up) }   // (4,4) → (0,4): four real moves
        XCTAssertEqual(s.player, g(0, 4))
        XCTAssertEqual(s.turn, 4)
        XCTAssertEqual(s.recording.count, 4)

        // A fifth up at the top edge is a stall: the player holds, the turn advances, and
        // the trail does not grow.
        XCTAssertEqual(s.move(.up), .stalled)
        XCTAssertEqual(s.player, g(0, 4))
        XCTAssertEqual(s.turn, 5)
        XCTAssertEqual(s.recording.count, 4)
    }

    func testStallStepsEchoesAlongTheTrail() {
        let s = EchoRunState()
        for _ in 0..<4 { s.move(.up) }   // turns 1-4 real; player (0,4)
        for _ in 0..<4 { s.move(.up) }   // turns 5-8 stalls; turn 8 spawns E8 at the centre
        XCTAssertEqual(s.turn, 8)
        XCTAssertEqual(s.player, g(0, 4))
        XCTAssertEqual(s.recording.count, 4)
        XCTAssertEqual(s.echoes.count, 1)
        XCTAssertEqual(s.position(of: s.echoes[0]), g(4, 4))     // E8 at start (offset 0)

        // One more stall: the turn advances and E8 steps along the laid-down trail.
        XCTAssertEqual(s.move(.up), .stalled)
        XCTAssertEqual(s.turn, 9)
        XCTAssertEqual(s.player, g(0, 4))
        XCTAssertEqual(s.position(of: s.echoes[0]), g(3, 4))     // offset 1 → P1
    }

    // MARK: - Death: land-on (a trailing shadow catches a stalled head)

    func testLandOnDeathWhenAShadowCatchesTheStalledHead() {
        let s = EchoRunState()
        for _ in 0..<4 { s.move(.up) }   // turns 1-4: player walks to (0,4)
        // Stall at the top edge. E8 spawns at the centre on turn 8 and walks up the trail
        // (P1 at turn 9, P2 at 10, P3 at 11), reaching P4 = (0,4) — the held head — at 12.
        for turn in 5...11 {
            XCTAssertEqual(s.move(.up), .stalled, "turn \(turn) should be a non-fatal stall")
            XCTAssertFalse(s.isOver)
        }
        XCTAssertEqual(s.turn, 11)
        XCTAssertEqual(s.echoes.count, 1)

        // The eighth stall (turn 12): E8 lands on the stalled head → land-on death.
        XCTAssertEqual(s.move(.up), .died)
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.turn, 12)
        XCTAssertEqual(s.score, 12)
    }

    // MARK: - Death: cross-paths / swap (parity broken so the swap branch is live)

    func testCrossPathsDeathWhenAShadowSwapsTilesWithThePlayer() {
        // spawnPeriod 1: a shadow spawns every turn, so E1 trails the player by one tile.
        let s = EchoRunState(spawnPeriod: 1)
        XCTAssertEqual(s.move(.up), .stepped)    // turn 1: (4,4) → (3,4); E1 spawns at centre
        XCTAssertEqual(s.move(.up), .stepped)    // turn 2: (3,4) → (2,4); E1 now at (3,4)
        XCTAssertFalse(s.isOver)

        // E1 sits one step behind at (3,4). Stepping DOWN trades tiles with it — the player
        // (2,4) → (3,4) while E1 (3,4) → (2,4): a cross-paths/swap death.
        XCTAssertEqual(s.move(.down), .died)
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.turn, 3)
        XCTAssertEqual(s.score, 3)
    }

    // MARK: - Score, input lock, reset

    func testScoreEqualsTurnsSurvivedIncludingStalls() {
        let s = EchoRunState()
        for _ in 0..<4 { s.move(.up) }
        XCTAssertEqual(s.score, 4)
        XCTAssertEqual(s.score, s.turn)
        XCTAssertEqual(s.move(.up), .stalled)    // a stall still counts toward the score
        XCTAssertEqual(s.score, 5)
        XCTAssertEqual(s.move(.up), .stalled)
        XCTAssertEqual(s.score, 6)
    }

    func testInputLockedAfterDeath() {
        let s = EchoRunState(spawnPeriod: 1)
        s.move(.up); s.move(.up); s.move(.down)   // swap death at turn 3
        XCTAssertTrue(s.isOver)
        let turnAtDeath = s.turn

        XCTAssertEqual(s.move(.up), .ignored)     // input locked
        XCTAssertEqual(s.turn, turnAtDeath)       // no further advance
        XCTAssertEqual(s.score, turnAtDeath)
    }

    func testResetReturnsToFreshStartState() {
        let s = EchoRunState()
        for direction in snake.prefix(10) { s.move(direction) }
        XCTAssertEqual(s.turn, 10)
        XCTAssertEqual(s.echoes.count, 1)

        s.reset()
        XCTAssertEqual(s.player, g(4, 4))
        XCTAssertEqual(s.turn, 0)
        XCTAssertEqual(s.score, 0)
        XCTAssertTrue(s.recording.isEmpty)
        XCTAssertTrue(s.echoes.isEmpty)
        XCTAssertFalse(s.isOver)
    }

    // MARK: - The view's deferred-death predictor matches the commit

    func testPendingDeathAgreesWithCommit() {
        // Safe: continuing up after up,up does not end the run, and the commit agrees.
        let safe = EchoRunState(spawnPeriod: 1)
        safe.move(.up); safe.move(.up)
        XCTAssertNil(safe.pendingDeath(for: .up))
        XCTAssertEqual(safe.move(.up), .stepped)

        // Fatal: down after up,up swaps and dies, and the commit agrees.
        let fatal = EchoRunState(spawnPeriod: 1)
        fatal.move(.up); fatal.move(.up)
        XCTAssertNotNil(fatal.pendingDeath(for: .down))
        XCTAssertEqual(fatal.move(.down), .died)
    }

    // MARK: - The per-move audio chord (stepping shadows)

    func testEchoMovesNextTurnListsSteppingShadows() {
        let s = EchoRunState(spawnPeriod: 1)
        s.move(.up); s.move(.up)
        // Next turn, E1 (offset feeds recording[1]) and E2 (recording[0]) both step up.
        XCTAssertEqual(s.echoMovesNextTurn, [.up, .up])
    }

    // MARK: - Echo Run high score persists through SettingsStore (round-trip + keep-best)

    func testHighScoreRoundTripsThroughSettingsAndKeepsBest() {
        let name = "test.echorun.highscore"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.echoRunHighScore, 0)            // default
        XCTAssertTrue(store.recordEchoRunScore(10))          // first score is a new best
        XCTAssertEqual(store.echoRunHighScore, 10)

        // Round-trip: a fresh store over the same suite reads the saved best.
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.echoRunHighScore, 10)

        XCTAssertFalse(reloaded.recordEchoRunScore(5))       // not a new best — unchanged
        XCTAssertEqual(reloaded.echoRunHighScore, 10)
        XCTAssertTrue(reloaded.recordEchoRunScore(12))       // a new best
        XCTAssertEqual(reloaded.echoRunHighScore, 12)
    }
}
