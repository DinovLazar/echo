//
//  RoomSolvabilityTests.swift
//  ECHOTests
//
//  Phase 1.08 (The first teaching rooms). One test per bundled teaching room: load
//  its JSON through the app's loader, replay a verified reference solution through
//  the **real** `GameState`, and assert it wins within the room's echo budget.
//  Rooms 04 / 06 / 07 also pin their "naive run that must fail" so the lesson is
//  locked in (D-034).
//
//  These join the deterministic-logic suite in `ECHOTests.swift`. They exercise the
//  real engine (move / fold / collision / closed-door / win), not a re-implementation:
//  each room test encodes ONE known-good solution as a list of coordinate-path runs,
//  derives every `Direction` from consecutive cells via `Direction(from:to:)`, and
//  asserts every intended move actually lands (a silent no-op or a mid-run collision
//  restart is a failure).
//
//  `GameState` is `@MainActor`, so the case is `@MainActor` to drive it directly,
//  matching `ECHOTests`.
//

import XCTest
@testable import ECHO

@MainActor
final class RoomSolvabilityTests: XCTestCase {

    // MARK: - Helpers

    /// Shorthand for a cell.
    private func g(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    /// Load a room by id through the app's `LevelLoader`, falling back to reading the
    /// JSON straight from the repo-root `Levels/` folder (resolved from this test
    /// file's path) and decoding it via the same real `Level` Decodable the loader
    /// uses. The fallback keeps the suite green whether or not the room JSON is copied
    /// into the *test* target's bundle — the rooms are bundled into the *app* target
    /// (D-025), and a hosted unit test's `Bundle.main` is that app bundle, so the
    /// loader path is exercised when available.
    private func loadRoom(_ id: String, file: StaticString = #filePath) -> Level {
        if let level = LevelLoader.load(id, in: Bundle(for: type(of: self))) ?? LevelLoader.load(id) {
            return level
        }
        let testFile = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("Levels").appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url),
              let level = try? JSONDecoder().decode(Level.self, from: data) else {
            fatalError("room \(id) could not be loaded via LevelLoader or from \(url.path)")
        }
        return level
    }

    /// Replay a reference solution and assert a clean win within budget.
    ///
    /// `runs` is a list of coordinate-path runs (turn 0 = the room `start`); the last
    /// run is the live finish (never folded), each earlier run is folded into an echo.
    /// Asserts: the decoded room matches the structural spec; every intended move
    /// commits and lands on its next cell (no no-op, no mid-run restart); each fold
    /// succeeds and banks exactly one echo; the final run reaches `exit` with
    /// `hasWon == true`; and the number of folds used is ≤ the echo budget.
    @discardableResult
    private func assertSolves(
        _ id: String, budget: Int, start: GridCoordinate, exit: GridCoordinate,
        walls: Int, switches: Int, doors: Int, hazards: Int,
        runs: [[GridCoordinate]]
    ) -> GameState {
        let level = loadRoom(id)
        XCTAssertEqual(level.id, id, "\(id): id")
        XCTAssertEqual(level.start, start, "\(id): start")
        XCTAssertEqual(level.exit, exit, "\(id): exit")
        XCTAssertEqual(level.echoBudget, budget, "\(id): echoBudget")
        XCTAssertEqual(level.walls.count, walls, "\(id): wall count")
        XCTAssertEqual(level.switches.count, switches, "\(id): switch count")
        XCTAssertEqual(level.doors.count, doors, "\(id): door count")
        XCTAssertEqual(level.hazards.count, hazards, "\(id): hazard count")

        let state = GameState(level: level)
        var foldsUsed = 0
        for (i, run) in runs.enumerated() {
            let isFinal = (i == runs.count - 1)
            XCTAssertEqual(state.player, run[0], "\(id) run \(i): player not on start at turn 0")
            for j in 1..<run.count {
                guard let dir = Direction(from: run[j - 1], to: run[j]) else {
                    XCTFail("\(id) run \(i) step \(j): \(run[j - 1]) -> \(run[j]) is not orthogonally adjacent")
                    return state
                }
                XCTAssertTrue(state.move(dir),
                              "\(id) run \(i) step \(j): move \(run[j - 1]) -> \(run[j]) was a no-op (wall / closed door / off-grid)")
                XCTAssertEqual(state.player, run[j],
                               "\(id) run \(i) step \(j): expected \(run[j]) but a collision restarted the run (turn \(state.turn))")
            }
            if !isFinal {
                let before = state.echoes.count
                XCTAssertTrue(state.fold(), "\(id) run \(i): fold() was refused")
                XCTAssertEqual(state.echoes.count, before + 1, "\(id) run \(i): fold did not bank exactly one echo")
                foldsUsed += 1
            }
        }
        XCTAssertTrue(state.hasWon, "\(id): final run did not reach the exit alive")
        XCTAssertEqual(state.player, exit, "\(id): player not on exit at win")
        XCTAssertLessThanOrEqual(foldsUsed, budget, "\(id): used \(foldsUsed) folds, over budget \(budget)")
        return state
    }

    // MARK: - Room 01 — "Straight Line" (budget 0)

    func testRoom01StraightLine() {
        assertSolves("room-01", budget: 0, start: g(1, 0), exit: g(1, 4),
                     walls: 0, switches: 0, doors: 0, hazards: 0,
                     runs: [[g(1, 0), g(1, 1), g(1, 2), g(1, 3), g(1, 4)]])
    }

    // MARK: - Room 02 — "The Turn" (budget 0)

    func testRoom02TheTurn() {
        assertSolves("room-02", budget: 0, start: g(4, 0), exit: g(0, 4),
                     walls: 16, switches: 0, doors: 0, hazards: 0,
                     runs: [[g(4, 0), g(4, 1), g(4, 2), g(4, 3), g(4, 4), g(3, 4), g(2, 4), g(1, 4), g(0, 4)]])
    }

    // MARK: - Room 03 — "First Fold" (budget 1)

    func testRoom03FirstFold() {
        assertSolves("room-03", budget: 1, start: g(1, 0), exit: g(1, 4),
                     walls: 8, switches: 1, doors: 1, hazards: 0,
                     runs: [
                        [g(1, 0), g(0, 0)],                                 // echo: holds the switch
                        [g(1, 0), g(1, 1), g(1, 2), g(1, 3), g(1, 4)],      // live: through the held door
                     ])
    }

    // MARK: - Room 04 — "Mind the Past" (budget 1)

    func testRoom04MindThePast() {
        assertSolves("room-04", budget: 1, start: g(1, 0), exit: g(1, 4),
                     walls: 7, switches: 1, doors: 1, hazards: 0,
                     runs: [
                        [g(1, 0), g(1, 1)],                                          // echo: parks ON the switch, in the path
                        [g(1, 0), g(0, 0), g(0, 1), g(0, 2), g(1, 2), g(1, 3), g(1, 4)], // live: detours over the top
                     ])
    }

    /// Negative (D-034): with the echo parked on the switch at (1,1), walking straight
    /// collides with it on turn 1 and restarts — the room is not won.
    func testRoom04NaiveStraightRunHitsEchoAndDoesNotWin() {
        let state = GameState(level: loadRoom("room-04"))
        XCTAssertTrue(state.move(.right))               // (1,1): onto the switch
        XCTAssertEqual(state.player, g(1, 1))
        XCTAssertTrue(state.fold())                     // echo stands on (1,1)
        XCTAssertTrue(state.move(.right))               // fatal step: lands on the echo at (1,1), turn 1
        XCTAssertEqual(state.player, state.start, "naive straight run should dissolve on the parked echo")
        XCTAssertEqual(state.turn, 0)
        XCTAssertFalse(state.hasWon)
    }

    // MARK: - Room 05 — "Two Selves" (budget 2)

    func testRoom05TwoSelves() {
        assertSolves("room-05", budget: 2, start: g(1, 2), exit: g(4, 2),
                     walls: 10, switches: 2, doors: 2, hazards: 0,
                     runs: [
                        [g(1, 2), g(1, 1), g(1, 0), g(0, 0)],                               // echo A: switch A
                        [g(1, 2), g(1, 3), g(1, 4), g(0, 4)],                               // echo B: switch B
                        [g(1, 2), g(0, 2), g(1, 2), g(0, 2), g(1, 2), g(2, 2), g(3, 2), g(4, 2)], // live: stall, then centre
                     ])
    }

    // MARK: - Room 06 — "The Patrol" (budget 0)

    func testRoom06ThePatrol() {
        assertSolves("room-06", budget: 0, start: g(1, 0), exit: g(1, 4),
                     walls: 0, switches: 0, doors: 0, hazards: 1,
                     runs: [[g(1, 0), g(0, 0), g(0, 1), g(0, 2), g(0, 3), g(0, 4), g(1, 4)]])
    }

    /// Negative (D-034): walking straight along row 1 reaches the exit (1,4) on turn 4
    /// — exactly when the patrol occupies it — so it dies instead of winning.
    func testRoom06NaiveStraightRunHitsPatrolOnExit() {
        let state = GameState(level: loadRoom("room-06"))
        state.move(.right)                              // (1,1) t1
        state.move(.right)                              // (1,2) t2
        state.move(.right)                              // (1,3) t3
        XCTAssertEqual(state.player, g(1, 3))
        state.move(.right)                              // would reach (1,4)=exit at t4, patrol is there
        XCTAssertFalse(state.hasWon, "straight run reaches the exit exactly under the patrol")
        XCTAssertEqual(state.player, state.start)       // dissolved -> restart
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 07 — "Hold, Then Time" (budget 1)

    func testRoom07HoldThenTime() {
        assertSolves("room-07", budget: 1, start: g(1, 0), exit: g(1, 4),
                     walls: 5, switches: 1, doors: 1, hazards: 1,
                     runs: [
                        [g(1, 0), g(0, 0)],                                                  // echo: holds the switch
                        [g(1, 0), g(1, 1), g(0, 1), g(0, 2), g(1, 2), g(1, 3), g(1, 4)],     // live: dodge up, then door
                     ])
    }

    /// Negative (D-034): after the fold, walking straight collides with the patrol at
    /// (1,2) on turn 2 — the held door alone is not enough; you must time the patrol.
    func testRoom07NaiveStraightRunAfterFoldHitsPatrol() {
        let state = GameState(level: loadRoom("room-07"))
        XCTAssertTrue(state.move(.up))                  // (0,0): onto the switch
        XCTAssertEqual(state.player, g(0, 0))
        XCTAssertTrue(state.fold())                     // echo holds the door open
        state.move(.right)                              // (1,1) t1
        state.move(.right)                              // (1,2) t2 -> patrol there
        XCTAssertFalse(state.hasWon, "straight run after the fold should die to the patrol")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 08 — "Two Jobs" (budget 2)

    func testRoom08TwoJobs() {
        assertSolves("room-08", budget: 2, start: g(1, 0), exit: g(1, 6),
                     walls: 4, switches: 2, doors: 2, hazards: 1,
                     runs: [
                        [g(1, 0), g(0, 0)],                                                          // echo A: switch A
                        [g(1, 0), g(1, 1), g(1, 2), g(1, 3), g(0, 3)],                               // echo B: through door A to switch B
                        [g(1, 0), g(2, 0), g(1, 0), g(1, 1), g(1, 2), g(1, 3), g(1, 4), g(1, 5), g(1, 6)], // live: stall, then across
                     ])
    }

    // MARK: - Room 09 — "Contested" (budget 2)

    func testRoom09Contested() {
        assertSolves("room-09", budget: 2, start: g(1, 2), exit: g(6, 2),
                     walls: 18, switches: 2, doors: 2, hazards: 1,
                     runs: [
                        [g(1, 2), g(1, 1)],                                                          // echo: entry-neck switch
                        [g(1, 2), g(1, 3)],                                                          // echo: exit-neck switch
                        [g(1, 2), g(0, 2), g(1, 2), g(2, 2), g(3, 2), g(4, 2), g(5, 2), g(6, 2)],    // live: stall, then centre
                     ])
    }

    // MARK: - Room 10 — "Capstone" (budget 2)

    func testRoom10Capstone() {
        assertSolves("room-10", budget: 2, start: g(1, 0), exit: g(1, 7),
                     walls: 4, switches: 2, doors: 2, hazards: 1,
                     runs: [
                        [g(1, 0), g(0, 0)],                                                          // echo A: switch A
                        [g(1, 0), g(1, 1), g(1, 2), g(1, 3), g(0, 3), g(0, 4)],                      // echo B: through door A to deep switch B
                        [g(1, 0), g(2, 0), g(1, 0), g(2, 0), g(1, 0),
                         g(1, 1), g(1, 2), g(1, 3), g(1, 4), g(1, 5), g(1, 6), g(1, 7)],             // live: two stalls, then across
                     ])
    }

    // MARK: - Hazard traces (one period, vs the documented patrol)

    /// Each hazard's computed one-period trace matches the trace documented for its
    /// room (and wraps correctly), so the timing the rooms are authored against is real.
    func testHazardTracesMatchDocumentedPaths() {
        func trace(_ id: String, _ expected: [GridCoordinate]) {
            let h = loadRoom(id).hazards[0]
            for t in expected.indices {
                XCTAssertEqual(h.position(at: t), expected[t], "\(id) hazard at turn \(t)")
            }
            XCTAssertEqual(h.position(at: expected.count), expected[0], "\(id) hazard period wrap")
        }
        trace("room-06", [g(0, 1), g(0, 2), g(0, 3), g(0, 4), g(1, 4), g(1, 3), g(1, 2), g(1, 1)])
        trace("room-07", [g(2, 1), g(2, 2), g(1, 2), g(1, 1)])
        trace("room-08", [g(1, 5), g(0, 5), g(0, 6), g(1, 6), g(2, 6), g(2, 5)])
        trace("room-09", [g(3, 0), g(3, 1), g(3, 2), g(3, 3), g(3, 4), g(4, 4), g(4, 3), g(4, 2), g(4, 1), g(4, 0)])
        trace("room-10", [g(1, 6), g(0, 6), g(0, 7), g(1, 7), g(2, 7), g(2, 6)])
    }
}
