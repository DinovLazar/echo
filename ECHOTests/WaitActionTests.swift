//
//  WaitActionTests.swift
//  ECHOTests
//
//  Phase 4.01 (The wait action). Drives the **real** `GameState`/`Echo`/`Direction`
//  to pin the new pass-a-turn-in-place primitive (D-066/D-067): `Direction.stay`,
//  `GameState.wait()` (incl. that a wait can be fatal), the interaction of waits with
//  `stepBack`/`fold`/`Echo.position`, that `move(.stay)` is a no-op, and the headline
//  payoff — the **dwell-then-relocate** proof: one folded echo holds switch A, waits,
//  then relocates to switch B, so present-you crosses door A early and door B later and
//  reaches the exit. No re-implementation of the engine — every assertion runs the real
//  turn/collision/door rules.
//
//  `GameState` is `@MainActor`, so the case is `@MainActor` to drive it directly, matching
//  the other engine suites. The existing suite needs **no** migration — storing a wait as
//  a fifth `Direction` case keeps a run a plain `[Direction]` everywhere (D-067).
//

import XCTest
@testable import ECHO

@MainActor
final class WaitActionTests: XCTestCase {

    /// Shorthand for a cell.
    private func g(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    // MARK: - Direction.stay (D-067)

    /// `.stay` has a zero offset, joins `allCases` as the fifth case, carries the raw
    /// value `"stay"`, and `init?(from:to:)` never produces it (the same-cell case is nil).
    func testStayIsAZeroOffsetFifthDirectionTheTapRuleNeverProduces() {
        XCTAssertEqual(Direction.stay.offset.row, 0)
        XCTAssertEqual(Direction.stay.offset.column, 0)
        XCTAssertEqual(Direction.stay.rawValue, "stay")

        XCTAssertEqual(Direction.allCases.count, 5)
        XCTAssertTrue(Direction.allCases.contains(.stay))
        for movement in [Direction.up, .down, .left, .right] {
            XCTAssertTrue(Direction.allCases.contains(movement))
        }

        // The tap/adjacency rule must never return `.stay` — a zero delta is `nil`.
        XCTAssertNil(Direction(from: g(2, 2), to: g(2, 2)))
        XCTAssertNotEqual(Direction(from: g(2, 2), to: g(2, 3)), .stay)
    }

    /// `move(.stay)` is a no-op — `wait()` is the single way to pass a turn (D-067).
    func testMoveStayIsANoOp() {
        let state = GameState()
        XCTAssertFalse(state.move(.stay))
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.player, state.start)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertNil(state.lastMoveOutcome)
    }

    // MARK: - wait() core (D-066)

    /// A survived wait advances the turn by exactly one, appends exactly one `.stay`,
    /// leaves the player put, and reports `.stepped`.
    func testWaitAdvancesTurnAppendsOneStayLeavesPlayerPut() {
        let state = GameState()
        XCTAssertTrue(state.wait())
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.currentRun, [.stay])
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.lastMoveOutcome, .stepped)

        // A second wait stacks another `.stay`; the player still has not moved.
        XCTAssertTrue(state.wait())
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.currentRun, [.stay, .stay])
        XCTAssertEqual(state.player, state.start)
    }

    /// A wait is refused (a no-op) once the room is won — symmetry with `move`/`stepBack`
    /// — and leaves the won state and the `.won` outcome untouched.
    func testWaitRefusedWhileWon() {
        let state = GameState(width: 3, height: 1, start: g(0, 0), exit: g(0, 1))
        XCTAssertTrue(state.move(.right))            // step onto the exit
        XCTAssertTrue(state.hasWon)
        XCTAssertEqual(state.lastMoveOutcome, .won)
        let wonTurn = state.turn
        let wonRun = state.currentRun

        XCTAssertFalse(state.wait())                 // refused while won
        XCTAssertEqual(state.turn, wonTurn)          // turn untouched
        XCTAssertEqual(state.currentRun, wonRun)     // no `.stay` appended
        XCTAssertEqual(state.lastMoveOutcome, .won)  // outcome untouched
        XCTAssertTrue(state.hasWon)
    }

    /// A wait can be **fatal**: a mover (here a hazard) stepping onto the held tile this
    /// turn kills you — `.died` + the current run restarts to `start`/turn 0 (D-066).
    func testWaitIsFatalWhenAMoverLandsOnTheHeldTile() {
        // The hazard walks right and stands on the player's tile at turn 2.
        let state = GameState(
            width: 5, height: 1, start: g(0, 2), exit: g(0, 4),
            hazards: [Hazard(id: "h", start: g(0, 0), path: [.right, .right], loops: false)]
        )

        // First wait survives — the hazard is one tile away (0,1) at turn 1.
        XCTAssertTrue(state.wait())
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.player, g(0, 2))
        XCTAssertEqual(state.lastMoveOutcome, .stepped)

        // Second wait is fatal — the hazard lands on (0,2), the held tile, at turn 2.
        XCTAssertTrue(state.wait())                       // the fatal turn did happen…
        XCTAssertEqual(state.lastMoveOutcome, .died)      // …and is reported as a death
        XCTAssertEqual(state.player, state.start)         // …then the run restarted
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertFalse(state.hasWon)
    }

    // MARK: - waits inside stepBack / fold / replay

    /// `stepBack()` pops a `.stay` as cleanly as a move; repeated step-back over a mixed
    /// run (moves + waits) walks all the way back to turn 0 with the player on `start` and
    /// every banked echo intact (step-back is intra-run only — D-030).
    func testStepBackPopsStayAndUnwindsAMixedRunToTurnZeroWithEchoesIntact() {
        let state = GameState()
        // Bank an unrelated echo first, to prove step-back never disturbs it.
        XCTAssertTrue(state.move(.up))
        XCTAssertTrue(state.fold())
        XCTAssertEqual(state.echoes.count, 1)

        // A mixed live run: move, wait, move, wait.
        XCTAssertTrue(state.move(.right))
        XCTAssertTrue(state.wait())
        XCTAssertTrue(state.move(.right))
        XCTAssertTrue(state.wait())
        XCTAssertEqual(state.currentRun, [.right, .stay, .right, .stay])
        XCTAssertEqual(state.turn, 4)
        XCTAssertEqual(state.player, g(3, 5))   // (3,3) + right + right

        XCTAssertTrue(state.stepBack())         // pop the trailing `.stay`
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.currentRun, [.right, .stay, .right])
        XCTAssertEqual(state.player, g(3, 5))   // still on the post-second-move tile

        XCTAssertTrue(state.stepBack())         // pop the second `.right`
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.player, g(3, 4))

        XCTAssertTrue(state.stepBack())         // pop the first `.stay`
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.player, g(3, 4))

        XCTAssertTrue(state.stepBack())         // pop the first `.right`
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.player, state.start)
        XCTAssertTrue(state.currentRun.isEmpty)

        XCTAssertFalse(state.stepBack())        // nothing left to undo (intra-run only)
        XCTAssertEqual(state.echoes.count, 1)   // the banked echo is untouched throughout
    }

    /// `fold()` banks a run containing a `.stay`, and the resulting echo **replays the
    /// wait** — it stands on its tile for the held turn before walking on (`Echo.position`).
    func testFoldBanksARunWithStayAndTheEchoReplaysTheWait() {
        let state = GameState()
        XCTAssertTrue(state.move(.right))   // (3,4) at turn 1
        XCTAssertTrue(state.wait())         // hold (3,4) at turn 2
        XCTAssertTrue(state.move(.right))   // (3,5) at turn 3
        XCTAssertEqual(state.currentRun, [.right, .stay, .right])

        XCTAssertTrue(state.fold())
        let echo = try! XCTUnwrap(state.echoes.last)
        XCTAssertEqual(echo.moves, [.right, .stay, .right])

        // The echo holds (3,4) across turns 1 AND 2 (the recorded wait), then moves on.
        XCTAssertEqual(echo.position(start: state.start, turn: 0), g(3, 3))
        XCTAssertEqual(echo.position(start: state.start, turn: 1), g(3, 4))
        XCTAssertEqual(echo.position(start: state.start, turn: 2), g(3, 4))  // dwell
        XCTAssertEqual(echo.position(start: state.start, turn: 3), g(3, 5))
        XCTAssertEqual(echo.position(start: state.start, turn: 4), g(3, 5))  // exhausted, stands
    }

    // MARK: - The dwell-then-relocate proof (the headline of D-066)

    /// One echo does two jobs in sequence — the thing the wait makes possible for the
    /// first time. The echo walks to switch A, **waits** there to hold door A open while
    /// present-you crosses it early, then relocates to switch B to hold door B open for
    /// present-you's later crossing. Proven on a small in-code board with two switch→door
    /// pairs: the relay is genuinely required (door A is shut with no echo), and replaying
    /// the relay echo + the timed live run reaches the exit with `hasWon`.
    func testDwellThenRelocateOneEchoHoldsThenRelocatesAcrossTwoDoors() {
        // A 7×3 board: a row-1 corridor S=(1,0) → door A (1,1) → door B (1,5) → exit (1,6),
        // with switch A=(0,1) and switch B=(0,5) on the row above, off the corridor.
        func makeState() -> GameState {
            GameState(
                width: 7, height: 3,
                start: g(1, 0), exit: g(1, 6), echoBudget: 1,
                switches: [Switch(id: "sA", cell: g(0, 1)),
                           Switch(id: "sB", cell: g(0, 5))],
                doors: [Door(id: "dA", cells: [g(1, 1)], heldBy: ["sA"]),
                        Door(id: "dB", cells: [g(1, 5)], heldBy: ["sB"])]
            )
        }

        // Without any echo, door A is closed: an immediate cross is refused (relay needed).
        let bare = makeState()
        XCTAssertFalse(bare.move(.right), "door A must be shut with no echo holding switch A")
        XCTAssertEqual(bare.player, bare.start)
        XCTAssertFalse(bare.hasWon)

        // The real solve. Record the relay echo: up, right onto sA, WAIT, WAIT, then walk
        // the top row to sB.
        let state = makeState()
        XCTAssertTrue(state.move(.up))      // (0,0)
        XCTAssertTrue(state.move(.right))   // (0,1) = sA
        XCTAssertTrue(state.wait())         // hold sA
        XCTAssertTrue(state.wait())         // hold sA
        XCTAssertTrue(state.move(.right))   // (0,2)
        XCTAssertTrue(state.move(.right))   // (0,3)
        XCTAssertTrue(state.move(.right))   // (0,4)
        XCTAssertTrue(state.move(.right))   // (0,5) = sB
        XCTAssertEqual(state.currentRun, [.up, .right, .stay, .stay, .right, .right, .right, .right])
        XCTAssertTrue(state.fold())
        XCTAssertEqual(state.echoes.count, 1)

        // The echo holds sA early (turns 2–4) and sB late (turn 8 on) — the relay window.
        let echo = try! XCTUnwrap(state.echoes.first)
        XCTAssertEqual(echo.position(start: state.start, turn: 2), g(0, 1))   // on sA
        XCTAssertEqual(echo.position(start: state.start, turn: 4), g(0, 1))   // still on sA (waited)
        XCTAssertEqual(echo.position(start: state.start, turn: 8), g(0, 5))   // relocated to sB
        XCTAssertEqual(echo.position(start: state.start, turn: 12), g(0, 5))  // holds sB (exhausted)

        // The live run: wait for the echo to reach sA, cross door A early, walk to (1,4),
        // wait for the echo to reach sB, cross door B late, step onto the exit.
        XCTAssertTrue(state.wait())                                   // t1
        XCTAssertTrue(state.wait())                                   // t2 — echo now holds sA
        XCTAssertTrue(state.move(.right), "door A should be open")    // t3 cross dA → (1,1)
        XCTAssertEqual(state.player, g(1, 1))
        XCTAssertTrue(state.move(.right))                             // t4 → (1,2)
        XCTAssertTrue(state.move(.right))                             // t5 → (1,3)
        XCTAssertTrue(state.move(.right))                             // t6 → (1,4)
        XCTAssertEqual(state.player, g(1, 4))
        XCTAssertTrue(state.wait())                                   // t7
        XCTAssertTrue(state.wait())                                   // t8 — echo now holds sB
        XCTAssertTrue(state.move(.right), "door B should be open")    // t9 cross dB → (1,5)
        XCTAssertEqual(state.player, g(1, 5))
        XCTAssertTrue(state.move(.right))                             // t10 → exit (1,6)

        XCTAssertTrue(state.hasWon, "the relay (hold A, wait, relocate to B) should win")
        XCTAssertEqual(state.player, g(1, 6))
        XCTAssertEqual(state.echoes.count, 1)   // one self did both jobs (budget 1)
    }
}
