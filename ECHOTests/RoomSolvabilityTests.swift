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

    /// Replay one cell-path run through the state. A step is one of three kinds, derived
    /// from each consecutive pair of cells:
    ///   • **wait** — a repeated cell (Phase 4.01 — `GameState.wait()`);
    ///   • **move** — an orthogonally adjacent cell (a `Direction` step);
    ///   • **teleport** (Phase 4.03) — a non-adjacent cell reached because the step landed
    ///     on a pad and jumped to its partner; the input direction is the one whose
    ///     `resolveLanding` (with the board's `padMap`) equals the next cell.
    /// Asserts each step commits and the player lands where expected (a no-op, a wait moved
    /// off its tile, or a collision restart is a failure). Used by both `assertSolves` (the
    /// reference solutions) and the negative tests (to bank the echoes).
    private func replayRun(_ state: GameState, _ run: [GridCoordinate],
                           _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for j in 1..<run.count {
            if run[j] == run[j - 1] {
                XCTAssertTrue(state.wait(), "\(label) step \(j): wait() was refused", file: file, line: line)
                XCTAssertEqual(state.player, run[j],
                               "\(label) step \(j): a wait moved the player off \(run[j]) (a mover landed on it)",
                               file: file, line: line)
            } else {
                // An adjacent step, or — if not adjacent — a pad-jump whose input direction
                // resolves (through the board's padMap) to the next cell.
                let dir = Direction(from: run[j - 1], to: run[j])
                    ?? [Direction.up, .down, .left, .right].first {
                        resolveLanding(from: run[j - 1], step: $0, pads: state.padMap) == run[j]
                    }
                guard let dir else {
                    XCTFail("\(label) step \(j): \(run[j - 1]) -> \(run[j]) is neither adjacent nor a teleport",
                            file: file, line: line)
                    return
                }
                XCTAssertTrue(state.move(dir),
                              "\(label) step \(j): move \(run[j - 1]) -> \(run[j]) was a no-op (wall / closed door / off-grid)",
                              file: file, line: line)
                XCTAssertEqual(state.player, run[j],
                               "\(label) step \(j): expected \(run[j]) but a collision restarted the run (turn \(state.turn))",
                               file: file, line: line)
            }
        }
    }

    /// Replay a reference solution and assert a clean win within budget.
    ///
    /// `runs` is a list of coordinate-path runs (turn 0 = the room `start`); the last
    /// run is the live finish (never folded), each earlier run is folded into an echo. A
    /// **repeated cell within a run is a wait** (Phase 4.01), so a run can dwell in place —
    /// the core of the Part-4 relay rooms (21–25). Asserts: the decoded room matches the
    /// structural spec; every intended move commits and lands on its next cell (no no-op, no
    /// mid-run restart) and every wait holds the tile; each fold succeeds and banks exactly
    /// one echo; the final run reaches `exit` with `hasWon == true`; and the number of folds
    /// used is ≤ the echo budget.
    @discardableResult
    private func assertSolves(
        _ id: String, budget: Int, start: GridCoordinate, exit: GridCoordinate,
        walls: Int, switches: Int, doors: Int, hazards: Int, portals: Int = 0,
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
        XCTAssertEqual(level.portals.count, portals, "\(id): portal count")

        let state = GameState(level: level)
        var foldsUsed = 0
        for (i, run) in runs.enumerated() {
            let isFinal = (i == runs.count - 1)
            XCTAssertEqual(state.player, run[0], "\(id) run \(i): player not on start at turn 0")
            replayRun(state, run, "\(id) run \(i)")
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

    // MARK: - Room 11 — "Crossroads" (budget 2)

    func testRoom11Crossroads() {
        assertSolves("room-11", budget: 2, start: g(2, 0), exit: g(2, 6),
                     walls: 8, switches: 2, doors: 2, hazards: 0,
                     runs: [
                        [g(2, 0), g(1, 0), g(0, 0)],                                                  // echo A: holds gate 1 (s1)
                        [g(2, 0), g(3, 0), g(2, 0), g(2, 1), g(2, 2), g(2, 3), g(3, 3)],               // echo B: through gate 1 to gate 2 (s2)
                        [g(2, 0), g(2, 1), g(1, 1), g(0, 1), g(1, 1), g(2, 1), g(2, 2), g(2, 3), g(2, 4), g(2, 5), g(2, 6)], // live: wait out, cross both
                     ])
    }

    // MARK: - Room 12 — "Both at Once" (budget 2)

    func testRoom12BothAtOnce() {
        assertSolves("room-12", budget: 2, start: g(2, 0), exit: g(2, 5),
                     walls: 4, switches: 2, doors: 1, hazards: 0,
                     runs: [
                        [g(2, 0), g(1, 0), g(0, 0)],                                                  // echo A: switch A
                        [g(2, 0), g(3, 0), g(4, 0)],                                                  // echo B: switch B
                        [g(2, 0), g(2, 1), g(2, 2), g(2, 3), g(2, 4), g(2, 5)],                       // live: cross the AND-door
                     ])
    }

    /// Negative (D-034): one echo holds only s1, so the AND-door at (2,3) — which needs
    /// BOTH s1 and s2 — stays closed; the move into it is refused (a no-op, not a death).
    func testRoom12OneEchoLeavesANDDoorClosed() {
        let state = GameState(level: loadRoom("room-12"))
        XCTAssertTrue(state.move(.up))                  // (1,0)
        XCTAssertTrue(state.move(.up))                  // (0,0): onto s1
        XCTAssertTrue(state.fold())                     // echo holds s1 only
        XCTAssertTrue(state.move(.right))               // (2,1)
        XCTAssertTrue(state.move(.right))               // (2,2)
        XCTAssertFalse(state.move(.right), "AND-door needs both switches; with only s1 held it stays shut")
        XCTAssertEqual(state.player, g(2, 2))
        XCTAssertFalse(state.hasWon)
    }

    // MARK: - Room 13 — "Wide Gate" (budget 1)

    func testRoom13WideGate() {
        assertSolves("room-13", budget: 1, start: g(1, 0), exit: g(1, 6),
                     walls: 1, switches: 1, doors: 1, hazards: 1,
                     runs: [
                        [g(1, 0), g(2, 0)],                                                           // echo: holds the two-tile gate
                        [g(1, 0), g(0, 0), g(0, 1), g(0, 2), g(0, 3), g(0, 4), g(0, 5), g(1, 5), g(1, 6)], // live: cross on the gate's top tile
                     ])
    }

    /// Negative (D-034): after the fold, the low straight run reaches (1,4) on turn 4 —
    /// exactly under the patrol — so it dies. The wide gate's other tile is the way through.
    func testRoom13NaiveStraightRunHitsPatrol() {
        let state = GameState(level: loadRoom("room-13"))
        XCTAssertTrue(state.move(.down))                // (2,0): onto s1
        XCTAssertTrue(state.fold())                     // echo holds the wide gate
        state.move(.right)                              // (1,1) t1
        state.move(.right)                              // (1,2) t2
        state.move(.right)                              // (1,3) t3: through the held gate (low tile)
        state.move(.right)                              // would reach (1,4) t4, into the patrol
        XCTAssertFalse(state.hasWon, "the low straight run meets the patrol at (1,4) on turn 4")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 14 — "Twin Patrols" (budget 1)

    func testRoom14TwinPatrols() {
        assertSolves("room-14", budget: 1, start: g(1, 0), exit: g(1, 6),
                     walls: 9, switches: 1, doors: 1, hazards: 2,
                     runs: [
                        [g(1, 0), g(0, 0)],                                                           // echo: holds the entry door
                        [g(1, 0), g(1, 1), g(1, 2), g(1, 3), g(2, 3), g(2, 4), g(2, 5), g(1, 5), g(1, 6)], // live: dip to row 2, thread the patrols
                     ])
    }

    /// Negative (D-034): the two patrols sweep row 1, so the straight corridor run is
    /// caught crossing to (1,4) on turn 4; you must dip to the parallel row.
    func testRoom14NaiveStraightRunHitsTwinPatrol() {
        let state = GameState(level: loadRoom("room-14"))
        XCTAssertTrue(state.move(.up))                  // (0,0): onto s1
        XCTAssertTrue(state.fold())                     // echo holds the entry door
        state.move(.right)                              // (1,1) t1
        state.move(.right)                              // (1,2) t2: through the held door
        state.move(.right)                              // (1,3) t3
        state.move(.right)                              // would cross to (1,4) t4, into a patrol
        XCTAssertFalse(state.hasWon, "the straight row-1 run is caught by the twin patrols")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 15 — "The Long Hold" (budget 2)

    func testRoom15TheLongHold() {
        assertSolves("room-15", budget: 2, start: g(2, 0), exit: g(2, 6),
                     walls: 8, switches: 2, doors: 2, hazards: 1,
                     runs: [
                        [g(2, 0), g(1, 0), g(0, 0)],                                                  // echo A: settles early on s1, holds for the whole solve
                        [g(2, 0), g(3, 0), g(2, 0), g(2, 1), g(2, 2), g(2, 3), g(3, 3), g(4, 3)],     // echo B: through gate 1 to s2
                        [g(2, 0), g(2, 1), g(1, 1), g(0, 1), g(1, 1), g(0, 1), g(1, 1), g(2, 1), g(2, 2), g(2, 3), g(2, 4), g(2, 5), g(2, 6)], // live: wait out the long circuit
                     ])
    }

    // MARK: - Room 16 — "Three" (budget 3)

    func testRoom16Three() {
        assertSolves("room-16", budget: 3, start: g(2, 1), exit: g(2, 8),
                     walls: 12, switches: 3, doors: 3, hazards: 0,
                     runs: [
                        [g(2, 1), g(3, 1), g(4, 1), g(4, 0)],                                         // echo A: gate 1 (s1)
                        [g(2, 1), g(1, 1), g(2, 1), g(2, 2), g(2, 3), g(2, 4), g(3, 4)],              // echo B: through gate 1 to gate 2 (s2)
                        [g(2, 1), g(2, 0), g(1, 0), g(2, 0), g(2, 1), g(2, 2), g(2, 3), g(2, 4), g(2, 5), g(2, 6), g(3, 6)], // echo C: through 1+2 to gate 3 (s3)
                        [g(2, 1), g(2, 2), g(1, 2), g(0, 2), g(1, 2), g(0, 2), g(1, 2), g(2, 2), g(2, 3), g(2, 4), g(2, 5), g(2, 6), g(2, 7), g(2, 8)], // live: thread four timelines
                     ])
    }

    // MARK: - Room 17 — "Threadneedle" (budget 2)

    func testRoom17Threadneedle() {
        assertSolves("room-17", budget: 2, start: g(2, 0), exit: g(2, 7),
                     walls: 4, switches: 2, doors: 1, hazards: 2,
                     runs: [
                        [g(2, 0), g(1, 0), g(0, 0)],                                                  // echo A: switch A
                        [g(2, 0), g(3, 0), g(4, 0)],                                                  // echo B: switch B (AND-door now holdable)
                        [g(2, 0), g(2, 1), g(1, 1), g(2, 1), g(2, 2), g(2, 3), g(2, 4), g(2, 5), g(2, 6), g(2, 7)], // live: time past both patrols, cross the AND-door
                     ])
    }

    /// Negative (D-034): even with the AND-door cooperatively held, walking straight meets
    /// patrol h1 at (2,2) on turn 2 — cooperation alone is not enough, you must also time.
    func testRoom17NaiveStraightRunHitsPatrol() {
        let state = GameState(level: loadRoom("room-17"))
        XCTAssertTrue(state.move(.up))                  // (1,0)
        XCTAssertTrue(state.move(.up))                  // (0,0): onto s1
        XCTAssertTrue(state.fold())                     // echo A holds s1
        XCTAssertTrue(state.move(.down))                // (3,0)
        XCTAssertTrue(state.move(.down))                // (4,0): onto s2
        XCTAssertTrue(state.fold())                     // echo B holds s2
        state.move(.right)                              // (2,1) t1
        state.move(.right)                              // would reach (2,2) t2, into patrol h1
        XCTAssertFalse(state.hasWon, "straight run is caught by patrol h1 at (2,2) on turn 2")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 18 — "Clockwork" (budget 3)

    func testRoom18Clockwork() {
        assertSolves("room-18", budget: 3, start: g(3, 1), exit: g(3, 6),
                     walls: 12, switches: 3, doors: 2, hazards: 1,
                     runs: [
                        [g(3, 1), g(2, 1), g(1, 1), g(1, 0)],                                         // echo A: AND switch 1
                        [g(3, 1), g(4, 1), g(5, 1), g(5, 0)],                                         // echo B: AND switch 2
                        [g(3, 1), g(3, 0), g(2, 0), g(3, 0), g(2, 0), g(3, 0), g(2, 0), g(3, 0), g(3, 1), g(3, 2), g(3, 3), g(3, 4), g(2, 4), g(1, 4)], // echo C: through the AND-gate, time the clock, hold gate 2 (s3)
                        [g(3, 1), g(3, 2), g(2, 2), g(1, 2), g(0, 2), g(1, 2), g(0, 2), g(1, 2), g(0, 2), g(1, 2), g(2, 2), g(3, 2), g(3, 3), g(3, 4), g(3, 5), g(3, 6)], // live: wait, then thread the clock
                     ])
    }

    // MARK: - Room 19 — "Lattice" (budget 3)

    func testRoom19Lattice() {
        assertSolves("room-19", budget: 3, start: g(3, 1), exit: g(2, 7),
                     walls: 9, switches: 3, doors: 2, hazards: 2,
                     runs: [
                        [g(3, 1), g(2, 1), g(1, 1), g(1, 0)],                                         // echo A: AND switch 1
                        [g(3, 1), g(4, 1), g(5, 1), g(5, 0)],                                         // echo B: AND switch 2
                        [g(3, 1), g(3, 0)],                                                           // echo C: exit-door switch
                        [g(3, 1), g(3, 2), g(2, 2), g(1, 2), g(2, 2), g(2, 3), g(2, 4), g(3, 4), g(2, 4), g(2, 5), g(2, 6), g(2, 7)], // live: thread the lattice using both wide-gate tiles
                     ])
    }

    // MARK: - Room 20 — "Coda" (finale, budget 3)

    func testRoom20Coda() {
        assertSolves("room-20", budget: 3, start: g(3, 1), exit: g(3, 7),
                     walls: 12, switches: 3, doors: 2, hazards: 2,
                     runs: [
                        [g(3, 1), g(2, 1), g(1, 1), g(1, 0)],                                         // echo A: AND switch 1
                        [g(3, 1), g(4, 1), g(5, 1), g(5, 0)],                                         // echo B: AND switch 2
                        [g(3, 1), g(3, 0)],                                                           // echo C: exit-door switch
                        [g(3, 1), g(3, 2), g(2, 2), g(3, 2), g(3, 3), g(3, 4), g(3, 5), g(3, 6), g(3, 7)], // live: time the clockwork, cross both held gates
                     ])
    }

    // MARK: - Part 4 · Room 21 — "Relay" (budget 1, the new idea)

    /// One echo holds switch A, **waits** to keep door A open while present-you crosses it,
    /// then relocates to switch B for the later crossing — one self, two jobs (D-069). The
    /// wait makes the single-echo relay possible; budget 1 makes it required.
    func testRoom21Relay() {
        assertSolves("room-21", budget: 1, start: g(1, 0), exit: g(1, 4),
                     walls: 4, switches: 2, doors: 2, hazards: 0,
                     runs: [
                        [g(1,0), g(0,0), g(0,0), g(0,0), g(1,0), g(2,0)],                  // echo: up to sA, wait×2, down to sB
                        [g(1,0), g(1,0), g(1,1), g(1,2), g(1,2), g(1,2), g(1,3), g(1,4)],   // live: wait, cross dA, wait×2, cross dB, exit
                     ])
    }

    // MARK: - Room 22 — "Two Relays" (budget 2)

    /// Two relocating echoes, choreographed so the door windows line up: echo 1 relays
    /// s1→s3 (doors 1 & 3), echo 2 relays s2→s4 (doors 2 & 4); present-you threads all four.
    func testRoom22TwoRelays() {
        assertSolves("room-22", budget: 2, start: g(2, 1), exit: g(2, 9),
                     walls: 16, switches: 4, doors: 4, hazards: 0,
                     runs: [
                        [g(2,1), g(2,0), g(1,0), g(0,0), g(0,0), g(0,0), g(0,0), g(0,0), g(1,0), g(2,0), g(3,0), g(4,0)],   // echo 1: hold s1, relocate to s3
                        [g(2,1), g(1,1), g(1,1), g(1,1), g(1,1), g(1,1), g(1,1), g(1,1), g(1,1), g(1,1), g(1,1), g(2,1), g(3,1)], // echo 2: hold s2, relocate to s4
                        [g(2,1), g(2,1), g(2,1), g(2,1), g(2,2), g(2,3), g(2,4), g(2,5), g(2,5), g(2,5), g(2,5), g(2,5), g(2,6), g(2,7), g(2,8), g(2,9)], // live
                     ])
    }

    // MARK: - Room 23 — "Patrol & Relay" (budget 2, one enemy)

    /// A relay echo (sA→sC) + a static hold (sB) + a patrol bouncing column 3. The relay's
    /// generous windows mean the tension is reading the patrol across the (2,3) crossing.
    func testRoom23PatrolAndRelay() {
        assertSolves("room-23", budget: 2, start: g(2, 1), exit: g(2, 8),
                     walls: 12, switches: 3, doors: 3, hazards: 1,
                     runs: [
                        [g(2,1), g(2,0), g(1,0), g(0,0), g(0,0), g(0,0), g(0,0), g(1,0), g(2,0), g(3,0), g(4,0)],   // echo 1: hold sA, relocate to sC
                        [g(2,1), g(1,1)],                                                                            // echo 2: static hold of sB
                        [g(2,1), g(2,1), g(2,1), g(2,1), g(2,2), g(2,3), g(2,4), g(2,5), g(2,5), g(2,5), g(2,5), g(2,6), g(2,7), g(2,8)], // live: cross dA, slip past the patrol, then dC
                     ])
    }

    /// Negative (D-034): after the same folds, crossing door A one beat late walks present-you
    /// straight into the patrol on (2,3) at turn 6 — the relay alone is not enough; time it.
    func testRoom23NaiveRunHitsPatrol() {
        let state = GameState(level: loadRoom("room-23"))
        replayRun(state, [g(2,1), g(2,0), g(1,0), g(0,0), g(0,0), g(0,0), g(0,0), g(1,0), g(2,0), g(3,0), g(4,0)], "room-23 echo 1")
        XCTAssertTrue(state.fold())
        replayRun(state, [g(2,1), g(1,1)], "room-23 echo 2")
        XCTAssertTrue(state.fold())
        for _ in 0..<4 { XCTAssertTrue(state.wait()) }   // dawdle four turns, then cross dA late
        XCTAssertTrue(state.move(.right))                // turn 5: onto (2,2) through dA
        state.move(.right)                               // turn 6: onto (2,3), where the patrol is
        XCTAssertFalse(state.hasWon, "the naive run meets the patrol on (2,3) at turn 6")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 24 — "Hold & Hand-off" (budget 2, AND-door)

    /// An AND-door (both echoes on sA & sB at once) combined with a relocate: after present-you
    /// crosses it, echo 1 leaves sA and hands off to sC to hold the later door dC. Two places
    /// at once, then one self moves on.
    func testRoom24HoldAndHandoff() {
        assertSolves("room-24", budget: 2, start: g(2, 1), exit: g(2, 7),
                     walls: 8, switches: 3, doors: 2, hazards: 0,
                     runs: [
                        [g(2,1), g(2,0), g(1,0), g(0,0), g(0,0), g(0,0), g(0,0), g(0,1), g(1,1)],   // echo 1: hold sA (AND), hand off to sC
                        [g(2,1), g(3,1), g(3,0), g(4,0)],                                            // echo 2: hold sB (the other AND half)
                        [g(2,1), g(2,1), g(2,1), g(2,1), g(2,2), g(2,3), g(2,4), g(2,4), g(2,4), g(2,5), g(2,6), g(2,7)], // live: cross the AND-door, then dC
                     ])
    }

    // MARK: - Room 25 — "Clockwork" (budget 3, two enemies, the band capstone)

    /// The oversized capstone (D-069): a three-switch AND-door (be in three places at once),
    /// two of those echoes then relay to later doors (dD, dE), and two out-of-phase patrols
    /// bounce the open columns between the doors. Budget 3, every advance timed.
    func testRoom25Clockwork() {
        assertSolves("room-25", budget: 3, start: g(3, 1), exit: g(3, 10),
                     walls: 18, switches: 5, doors: 3, hazards: 2,
                     runs: [
                        [g(3,1), g(2,1), g(1,1), g(1,0), g(1,0), g(1,0), g(1,0), g(1,0), g(1,0), g(1,0), g(1,1), g(0,1)],   // echo 1: hold sA (AND), relay to sD
                        [g(3,1), g(4,1), g(5,1), g(5,0), g(5,0), g(5,0), g(5,0), g(5,0), g(5,0), g(5,0), g(5,1), g(6,1)],   // echo 2: hold sB (AND), relay to sE
                        [g(3,1), g(3,0)],                                                                                   // echo 3: hold sC (the third AND switch)
                        [g(3,1), g(3,1), g(3,1), g(3,1), g(3,2), g(3,3), g(3,4), g(3,4), g(3,4), g(3,4), g(3,4), g(3,4), g(3,5), g(3,6), g(3,7), g(3,8), g(3,9), g(3,10)], // live: cross dAND, wait out the patrols, thread dD & dE
                     ])
    }

    /// Negative (D-034): rushing the AND-door open and walking straight in steps onto patrol
    /// h1 at (3,3) on turn 9 — the relays open the doors, but the patrols still bite.
    func testRoom25NaiveRushHitsPatrol() {
        let state = GameState(level: loadRoom("room-25"))
        replayRun(state, [g(3,1), g(2,1), g(1,1), g(1,0), g(1,0), g(1,0), g(1,0), g(1,0), g(1,0), g(1,0), g(1,1), g(0,1)], "room-25 echo 1")
        XCTAssertTrue(state.fold())
        replayRun(state, [g(3,1), g(4,1), g(5,1), g(5,0), g(5,0), g(5,0), g(5,0), g(5,0), g(5,0), g(5,0), g(5,1), g(6,1)], "room-25 echo 2")
        XCTAssertTrue(state.fold())
        replayRun(state, [g(3,1), g(3,0)], "room-25 echo 3")
        XCTAssertTrue(state.fold())
        for _ in 0..<7 { XCTAssertTrue(state.wait()) }   // dawdle, then cross the AND-door at turn 8
        XCTAssertTrue(state.move(.right))                // turn 8: onto (3,2) through dAND
        state.move(.right)                               // turn 9: onto (3,3), where patrol h1 is
        XCTAssertFalse(state.hasWon, "the naive rush meets patrol h1 on (3,3) at turn 9")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Part 4 · Room 26 — "Threshold" (budget 1, the portal — clean)

    /// One pad pair joins two walled regions. An echo holds switch A in region A; present-you
    /// **portals** to region B and exits through the door A holds (D-070/D-073). Unsolvable
    /// without the portal (region B is walled off) and without folding (door B stays shut).
    func testRoom26Threshold() {
        assertSolves("room-26", budget: 1, start: g(1, 0), exit: g(1, 6),
                     walls: 9, switches: 1, doors: 1, hazards: 0, portals: 1,
                     runs: [
                        [g(1,0), g(0,0)],                              // echo: hold switch A
                        [g(1,0), g(1,1), g(1,4), g(1,5), g(1,6)],      // live: portal A->B, cross dB, exit
                     ])
    }

    // MARK: - Room 27 — "Two Rooms" (budget 2, echoes traverse portals)

    /// An echo **teleports** to the far region to hold s2 while another echo holds s1 in the
    /// near region — two door-pairs. Teaches that echoes teleport too: present-you crosses d1
    /// (near), portals to B, crosses d2 (far) to the exit (D-073).
    func testRoom27TwoRooms() {
        assertSolves("room-27", budget: 2, start: g(1, 0), exit: g(1, 8),
                     walls: 17, switches: 2, doors: 2, hazards: 0, portals: 1,
                     runs: [
                        [g(1,0), g(0,0)],                                          // echo1: hold s1 (near)
                        [g(1,0), g(1,1), g(1,2), g(1,5), g(0,5)],                  // echo2: cross d1, TELEPORT, hold s2 (far)
                        [g(1,0), g(1,0), g(1,1), g(1,2), g(1,5), g(1,6), g(1,7), g(1,8)], // live
                     ])
    }

    // MARK: - Room 28 — "Portal & Patrol" (budget 2, one enemy)

    /// A patrol bounces the partner-pad column in region B, so the teleport **landing** is
    /// timed — danger is checked where you land (D-070). echo1 holds s1 (near); echo2 teleports
    /// to B to hold s2 (far); present-you times the hop and the crossing.
    func testRoom28PortalAndPatrol() {
        assertSolves("room-28", budget: 2, start: g(2, 0), exit: g(2, 8),
                     walls: 32, switches: 2, doors: 2, hazards: 1, portals: 1,
                     runs: [
                        [g(2,0), g(1,0)],                                          // echo1: hold s1 (near)
                        [g(2,0), g(2,1), g(2,2), g(2,5), g(1,5), g(0,5)],          // echo2: cross d1, TELEPORT, hold s2 (far)
                        [g(2,0), g(2,0), g(2,1), g(2,2), g(2,5), g(2,6), g(2,7), g(2,8)], // live: hop when the pad is clear
                     ])
    }

    /// Negative (D-034): dawdling, then teleporting LATE, lands present-you on the partner pad
    /// (2,5) at turn 6 — exactly when the patrol sweeps onto it — a mistimed hop, so it dies.
    func testRoom28NaiveHopLandsOnPatrol() {
        let state = GameState(level: loadRoom("room-28"))
        replayRun(state, [g(2,0), g(1,0)], "room-28 echo1");                  XCTAssertTrue(state.fold())
        replayRun(state, [g(2,0), g(2,1), g(2,2), g(2,5), g(1,5), g(0,5)], "room-28 echo2"); XCTAssertTrue(state.fold())
        for _ in 0..<3 { XCTAssertTrue(state.wait()) }   // dawdle three turns
        XCTAssertTrue(state.move(.right))                // turn 4: (2,1)
        XCTAssertTrue(state.move(.right))                // turn 5: cross d1 onto (2,2)
        state.move(.right)                               // turn 6: hop onto padB (2,5) — the patrol is there
        XCTAssertFalse(state.hasWon, "a mistimed hop lands on the patrol at the partner pad")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Room 29 — "Relay Across" (budget 2, wait + teleport combined)

    /// The wait threaded through a portal (D-073): ONE echo holds switch A in region A (opening
    /// an early door dB1 in region B), **waits**, then relocates **through the portal** to switch
    /// B in region B (opening the late door dB2). A second echo statically holds sC so present-you
    /// can reach the portal. The hard pre-capstone.
    func testRoom29RelayAcross() {
        assertSolves("room-29", budget: 2, start: g(1, 0), exit: g(1, 10),
                     walls: 20, switches: 3, doors: 3, hazards: 0, portals: 1,
                     runs: [
                        [g(1,0), g(2,0)],                                                                       // echo2: static hold sC (opens dA)
                        [g(1,0), g(0,0), g(0,0), g(0,0), g(0,0), g(0,0), g(1,0), g(1,1), g(1,2), g(1,3), g(1,6), g(0,6)], // relay: hold sA, wait, TELEPORT, hold sB
                        [g(1,0), g(1,0), g(1,1), g(1,2), g(1,3), g(1,6), g(1,7), g(1,8), g(1,8), g(1,8), g(1,8), g(1,8), g(1,9), g(1,10)], // live
                     ])
    }

    // MARK: - Room 30 — "Junction" (budget 3, two enemies, the band capstone)

    /// The oversized capstone (D-073): a hub corridor with **three** pad pairs to three isolated
    /// switch-spokes; three echoes each **teleport** out to hold one switch of an **AND-door
    /// across three regions** (dEXIT = sA & sB & sC); two out-of-phase patrols sweep the corridor.
    /// Budget 3, every advance timed; the switches are reachable only by portal.
    func testRoom30Junction() {
        assertSolves("room-30", budget: 3, start: g(4, 1), exit: g(4, 7),
                     walls: 33, switches: 3, doors: 1, hazards: 2, portals: 3,
                     runs: [
                        [g(4,1), g(3,1), g(2,1), g(0,0)],     // echo1: TELEPORT to spoke A, hold sA
                        [g(4,1), g(0,2)],                     // echo2: TELEPORT to spoke B, hold sB
                        [g(4,1), g(5,1), g(6,1), g(0,4)],     // echo3: TELEPORT to spoke C, hold sC
                        [g(4,1), g(4,2), g(4,2), g(4,3), g(4,4), g(4,4), g(4,5), g(4,6), g(4,7)], // live: thread both patrols, cross the AND-door
                     ])
    }

    /// Negative (D-034): once the AND-door is held open, rushing straight along the corridor
    /// steps onto patrol h1 at (4,3) on turn 2 — the portals open the door, but the patrols still bite.
    func testRoom30NaiveRushHitsPatrol() {
        let state = GameState(level: loadRoom("room-30"))
        replayRun(state, [g(4,1), g(3,1), g(2,1), g(0,0)], "room-30 echo1");   XCTAssertTrue(state.fold())
        replayRun(state, [g(4,1), g(0,2)], "room-30 echo2");                   XCTAssertTrue(state.fold())
        replayRun(state, [g(4,1), g(5,1), g(6,1), g(0,4)], "room-30 echo3");   XCTAssertTrue(state.fold())
        XCTAssertTrue(state.move(.right))                // turn 1: (4,2)
        state.move(.right)                               // turn 2: onto (4,3), where patrol h1 is
        XCTAssertFalse(state.hasWon, "the naive rush meets patrol h1 on (4,3) at turn 2")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Hazard traces (one period, vs the documented patrol)

    /// Each hazard's computed one-period trace matches the trace documented for its
    /// room (and wraps correctly), so the timing the rooms are authored against is real.
    func testHazardTracesMatchDocumentedPaths() {
        func traceAt(_ id: String, _ index: Int, _ expected: [GridCoordinate]) {
            let h = loadRoom(id).hazards[index]
            for t in expected.indices {
                XCTAssertEqual(h.position(at: t), expected[t], "\(id) hazard \(index) at turn \(t)")
            }
            XCTAssertEqual(h.position(at: expected.count), expected[0], "\(id) hazard \(index) period wrap")
        }
        func trace(_ id: String, _ expected: [GridCoordinate]) { traceAt(id, 0, expected) }
        trace("room-06", [g(0, 1), g(0, 2), g(0, 3), g(0, 4), g(1, 4), g(1, 3), g(1, 2), g(1, 1)])
        trace("room-07", [g(2, 1), g(2, 2), g(1, 2), g(1, 1)])
        trace("room-08", [g(1, 5), g(0, 5), g(0, 6), g(1, 6), g(2, 6), g(2, 5)])
        trace("room-09", [g(3, 0), g(3, 1), g(3, 2), g(3, 3), g(3, 4), g(4, 4), g(4, 3), g(4, 2), g(4, 1), g(4, 0)])
        trace("room-10", [g(1, 6), g(0, 6), g(0, 7), g(1, 7), g(2, 7), g(2, 6)])
        // Part 3 campaign hazards (room-11 … room-20); multi-hazard rooms check each.
        traceAt("room-13", 0, [g(1, 4), g(2, 4), g(1, 4), g(0, 4)])
        traceAt("room-14", 0, [g(1, 3), g(1, 4), g(1, 5), g(1, 4)])
        traceAt("room-14", 1, [g(1, 5), g(1, 4), g(1, 3), g(1, 4)])
        traceAt("room-15", 0, [g(1, 5), g(0, 5), g(0, 6), g(1, 6), g(2, 6), g(3, 6), g(4, 6), g(4, 5), g(3, 5), g(2, 5)])
        traceAt("room-17", 0, [g(0, 2), g(1, 2), g(2, 2), g(1, 2)])
        traceAt("room-17", 1, [g(4, 3), g(3, 3), g(2, 3), g(3, 3)])
        traceAt("room-18", 0, [g(6, 4), g(5, 4), g(4, 4), g(3, 4), g(2, 4), g(1, 4), g(0, 4), g(1, 4), g(2, 4), g(3, 4), g(4, 4), g(5, 4)])
        traceAt("room-19", 0, [g(2, 3), g(2, 4), g(2, 5), g(2, 4)])
        traceAt("room-19", 1, [g(3, 4), g(3, 5), g(3, 4), g(3, 3)])
        traceAt("room-20", 0, [g(1, 3), g(2, 3), g(3, 3), g(2, 3)])
        traceAt("room-20", 1, [g(2, 5), g(3, 5), g(4, 5), g(3, 5)])
        // Part 4 band patrols (rooms 23 & 25).
        traceAt("room-23", 0, [g(0, 3), g(1, 3), g(2, 3), g(3, 3), g(4, 3), g(3, 3), g(2, 3), g(1, 3)])
        traceAt("room-25", 0, [g(0, 3), g(1, 3), g(2, 3), g(3, 3), g(4, 3), g(5, 3), g(6, 3), g(5, 3), g(4, 3), g(3, 3), g(2, 3), g(1, 3)])
        traceAt("room-25", 1, [g(6, 6), g(5, 6), g(4, 6), g(3, 6), g(2, 6), g(1, 6), g(0, 6), g(1, 6), g(2, 6), g(3, 6), g(4, 6), g(5, 6)])
        // Part 4 teleport band patrols (rooms 28 & 30).
        traceAt("room-28", 0, [g(0, 5), g(1, 5), g(2, 5), g(3, 5), g(4, 5), g(3, 5), g(2, 5), g(1, 5)])
        traceAt("room-30", 0, [g(2, 3), g(3, 3), g(4, 3), g(5, 3), g(4, 3), g(3, 3)])
        traceAt("room-30", 1, [g(5, 5), g(4, 5), g(3, 5), g(2, 5), g(3, 5), g(4, 5)])
    }
}
