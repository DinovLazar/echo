//
//  ECHOTests.swift
//  ECHOTests
//
//  Phase 1.03 (Grid + Move). Covers the deterministic move model — the spine the
//  rest of the game hangs from. Every committed move and every off-grid no-op is
//  checked against the turn-counter rule. The model is pure, so these run without
//  any UI.
//
//  `GameState` is `@MainActor` (it is the SwiftUI-observed game state), so the
//  test case is marked `@MainActor` to drive it directly.
//

import XCTest
@testable import ECHO

@MainActor
final class ECHOTests: XCTestCase {

    // MARK: - Defaults

    /// The model defaults to a 7×7 board, the player on the center cell, turn 0.
    func testDefaultBoardIsSevenBySevenCenteredAtTurnZero() {
        let state = GameState()
        XCTAssertEqual(state.width, 7)
        XCTAssertEqual(state.height, 7)
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 3))
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Legal moves (one tile in each of the four directions)

    func testMoveUpStepsOneRowTowardTop() {
        let state = GameState()
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.player, GridCoordinate(row: 2, column: 3))
    }

    func testMoveDownStepsOneRowTowardBottom() {
        let state = GameState()
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.player, GridCoordinate(row: 4, column: 3))
    }

    func testMoveLeftStepsOneColumn() {
        let state = GameState()
        XCTAssertTrue(state.move(.left))
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 2))
    }

    func testMoveRightStepsOneColumn() {
        let state = GameState()
        XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 4))
    }

    // MARK: - Edge no-ops (a move that would leave the grid changes nothing)

    func testMoveOffTopEdgeIsNoOp() {
        let state = GameState(start: GridCoordinate(row: 0, column: 3))
        XCTAssertFalse(state.move(.up))
        XCTAssertEqual(state.player, GridCoordinate(row: 0, column: 3))
        XCTAssertEqual(state.turn, 0)
    }

    func testMoveOffBottomEdgeIsNoOp() {
        let state = GameState(start: GridCoordinate(row: 6, column: 3))
        XCTAssertFalse(state.move(.down))
        XCTAssertEqual(state.player, GridCoordinate(row: 6, column: 3))
        XCTAssertEqual(state.turn, 0)
    }

    func testMoveOffLeftEdgeIsNoOp() {
        let state = GameState(start: GridCoordinate(row: 3, column: 0))
        XCTAssertFalse(state.move(.left))
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 0))
        XCTAssertEqual(state.turn, 0)
    }

    func testMoveOffRightEdgeIsNoOp() {
        let state = GameState(start: GridCoordinate(row: 3, column: 6))
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 6))
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Turn counter

    func testTurnCounterIncrementsByOnePerCommittedMove() {
        let state = GameState()
        XCTAssertEqual(state.turn, 0)
        state.move(.up)
        XCTAssertEqual(state.turn, 1)
        state.move(.right)
        XCTAssertEqual(state.turn, 2)
        state.move(.down)
        XCTAssertEqual(state.turn, 3)
    }

    func testTurnCounterUnchangedOnNoOp() {
        // Start in the top-left corner so up and left are both off-grid no-ops.
        let state = GameState(start: GridCoordinate(row: 0, column: 0))
        XCTAssertFalse(state.move(.up))
        XCTAssertFalse(state.move(.left))
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.player, GridCoordinate(row: 0, column: 0))
    }

    // MARK: - Tap rule (direction between adjacent cells)

    /// The tap path: an orthogonally-adjacent cell resolves to a direction; the
    /// player's own cell, diagonals, and farther cells resolve to nil (no move).
    func testDirectionBetweenCellsMatchesTheTapRule() {
        let origin = GridCoordinate(row: 3, column: 3)
        XCTAssertEqual(Direction(from: origin, to: GridCoordinate(row: 2, column: 3)), .up)
        XCTAssertEqual(Direction(from: origin, to: GridCoordinate(row: 4, column: 3)), .down)
        XCTAssertEqual(Direction(from: origin, to: GridCoordinate(row: 3, column: 2)), .left)
        XCTAssertEqual(Direction(from: origin, to: GridCoordinate(row: 3, column: 4)), .right)

        XCTAssertNil(Direction(from: origin, to: origin))                                  // same cell
        XCTAssertNil(Direction(from: origin, to: GridCoordinate(row: 2, column: 2)))       // diagonal
        XCTAssertNil(Direction(from: origin, to: GridCoordinate(row: 1, column: 3)))       // two away
    }

    // MARK: - Fold: recording & replay (Phase 1.04)

    /// A run kept clear of the edges so every move commits (no clamping):
    /// (3,3)→(2,3)→(2,4)→(2,5)→(3,5).
    private let sampleRun: [Direction] = [.up, .right, .right, .down]

    /// Walk `run` from `start`, returning the cell after each prefix: element `t`
    /// is the cell after the first `t` moves (element 0 is `start`). This is the
    /// independent ground truth the recorded echo is checked against.
    private func walk(_ run: [Direction], from start: GridCoordinate) -> [GridCoordinate] {
        var positions = [start]
        var cell = start
        for direction in run {
            cell = GridCoordinate(row: cell.row + direction.offset.row,
                                  column: cell.column + direction.offset.column)
            positions.append(cell)
        }
        return positions
    }

    /// Every committed move is appended to the current run, in order.
    func testCommittedMovesAreRecordedInOrder() {
        let state = GameState()
        state.move(.up)
        state.move(.right)
        XCTAssertEqual(state.currentRun, [.up, .right])
    }

    /// Recording then folding yields exactly one echo whose moves equal the run.
    func testFoldBanksRunAsSingleEchoWithExactMoves() {
        let state = GameState()
        for direction in sampleRun { state.move(direction) }
        XCTAssertTrue(state.fold())
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertEqual(state.echoes[0].moves, sampleRun)
    }

    /// After a fold: player back at `start`, `turn == 0`, current run empty,
    /// echo count 1.
    func testFoldRewindsBoardToTurnZeroWithEmptyRun() {
        let state = GameState()
        for direction in sampleRun { state.move(direction) }
        state.fold()
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertEqual(state.echoes.count, 1)
    }

    /// Replay fidelity: the echo's tile at every turn `t` equals the live player's
    /// tile after the first `t` moves of its run — and it stays locked to the
    /// shared turn as the player re-walks (following its own recording, not the
    /// live path).
    ///
    /// Phase 1.05 note: the live re-walk here steps `.down` (away from the echo)
    /// rather than retracing the echo's own `.up` path, because under the new
    /// collision rule stepping onto the echo's tile would dissolve the player and
    /// rewind the turn — which would defeat this test. What the test verifies is
    /// unchanged: wherever the live player walks, the echo follows its own
    /// recording locked to the shared `turn`.
    func testReplayMatchesLivePlayerPathTurnByTurn() {
        let state = GameState()
        let expected = walk(sampleRun, from: state.start)
        for direction in sampleRun { state.move(direction) }
        state.fold()
        let echo = state.echoes[0]

        for t in 0...sampleRun.count {
            XCTAssertEqual(echo.position(start: state.start, turn: t), expected[t])
        }

        XCTAssertEqual(state.position(of: echo), expected[0])   // turn 0 → start
        state.move(.down)                                        // diverge (non-colliding)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.position(of: echo), expected[1])    // echo on its 1st tile
        state.move(.down)
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.position(of: echo), expected[2])    // …echo follows its run
    }

    /// An exhausted echo stands still on its last tile for any turn past its
    /// move count (this is what later lets it "hold" a switch).
    func testExhaustedEchoStandsStillOnLastTile() {
        let state = GameState()
        for direction in sampleRun { state.move(direction) }
        state.fold()
        let echo = state.echoes[0]
        let last = walk(sampleRun, from: state.start).last!
        XCTAssertEqual(echo.position(start: state.start, turn: sampleRun.count), last)
        XCTAssertEqual(echo.position(start: state.start, turn: sampleRun.count + 1), last)
        XCTAssertEqual(echo.position(start: state.start, turn: sampleRun.count + 50), last)
    }

    /// Folding twice yields two echoes with the correct, independent recordings;
    /// at turn 0 both sit on `start`.
    func testFoldTwiceYieldsTwoIndependentEchoesBothAtStart() {
        let state = GameState()
        let runA: [Direction] = [.up, .right, .right, .down]   // k = 4
        let runB: [Direction] = [.left, .down]                 // k = 2
        for direction in runA { state.move(direction) }
        state.fold()
        for direction in runB { state.move(direction) }
        state.fold()

        XCTAssertEqual(state.echoes.count, 2)
        XCTAssertEqual(state.echoes[0].moves, runA)
        XCTAssertEqual(state.echoes[1].moves, runB)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.position(of: state.echoes[0]), state.start)
        XCTAssertEqual(state.position(of: state.echoes[1]), state.start)
    }

    /// Two echoes of different lengths stay independently locked to the shared
    /// turn: at turn 3 the 4-move echo is on its 3rd tile while the 2-move echo
    /// already stands still on its last.
    func testTwoEchoesOfDifferentLengthsStayLockedToSharedTurn() {
        let state = GameState()
        let runA: [Direction] = [.up, .right, .right, .down]   // k = 4
        let runB: [Direction] = [.left, .down]                 // k = 2
        let pathA = walk(runA, from: state.start)
        let pathB = walk(runB, from: state.start)
        for direction in runA { state.move(direction) }
        state.fold()
        for direction in runB { state.move(direction) }
        state.fold()
        let echoA = state.echoes[0]
        let echoB = state.echoes[1]

        // Advance the shared turn to 3 with any legal, *non-colliding* moves.
        // (Stepping `.up` would retrace echoA onto its tiles and dissolve the
        // player under Phase 1.05; `.down` keeps clear of both echoes.)
        state.move(.down); state.move(.down); state.move(.down)
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.position(of: echoA), pathA[3])     // 3 of 4 moves
        XCTAssertEqual(state.position(of: echoB), pathB[2])     // exhausted (min(3,2))
    }

    /// Folding an empty run is a no-op — no zero-move echo, no rewind; and an
    /// immediate second fold (the run is empty again) does nothing either.
    func testFoldingEmptyRunIsNoOp() {
        let state = GameState()
        XCTAssertFalse(state.fold())
        XCTAssertTrue(state.echoes.isEmpty)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.player, state.start)
        XCTAssertTrue(state.currentRun.isEmpty)

        state.move(.up)
        XCTAssertTrue(state.fold())
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertFalse(state.fold())            // run empty again → no-op
        XCTAssertEqual(state.echoes.count, 1)   // unchanged
    }

    /// `clearEchoes()` returns the room to pristine: no echoes, empty run, player
    /// on `start`, turn 0 — even with a banked echo and a fresh partial run.
    func testClearEchoesReturnsRoomToPristine() {
        let state = GameState()
        for direction in sampleRun { state.move(direction) }
        state.fold()
        state.move(.down)                       // partial new run + advanced turn
                                                // (`.down` avoids retracing the echo,
                                                // which would dissolve us — Phase 1.05)
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertEqual(state.turn, 1)

        state.clearEchoes()
        XCTAssertTrue(state.echoes.isEmpty)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    /// Guard now that recording exists: a no-op move is neither recorded nor
    /// counted toward the turn; the next legal move records exactly one direction.
    func testNoOpMoveIsNeitherRecordedNorCounted() {
        let state = GameState(start: GridCoordinate(row: 0, column: 0))
        XCTAssertFalse(state.move(.up))         // off top edge
        XCTAssertFalse(state.move(.left))       // off left edge
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertEqual(state.turn, 0)

        XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.currentRun, [.right])
        XCTAssertEqual(state.turn, 1)
    }

    // MARK: - Collision & death restart (Phase 1.05)

    /// Land-on via real play: fold an echo whose first move is RIGHT, then step
    /// RIGHT. At turn 1 the player lands on the echo's first tile → dissolve and
    /// restart. The player is back on `start` at turn 0 with an empty run, and the
    /// echo persists.
    func testLandOnCollisionRestartsRunAndKeepsEcho() {
        let state = GameState()
        state.move(.right)
        state.fold()                                // echo.moves == [.right]
        XCTAssertEqual(state.echoes.count, 1)

        state.move(.right)                          // turn 1: both one cell right of start
        XCTAssertEqual(state.player, state.start)   // dissolved → restarted
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)     // fatal step discarded
        XCTAssertEqual(state.echoes.count, 1)       // echo intact, still replaying
        XCTAssertEqual(state.echoes[0].moves, [.right])
    }

    /// Turn-0 immunity, both ways. The immunity lives in `move()` — it only checks
    /// collision *after* a committed step, where `turn` is always ≥ 1 — so the
    /// turn-0 start-stack (player and every echo on `start`) is never tested. Right
    /// after a fold the player shares `start` with the echo yet is alive; and after
    /// a death the room is back at that same turn-0 stack, which must not re-trigger
    /// (a death never causes another death — no restart loop), so the next
    /// non-colliding step commits normally.
    ///
    /// (Note: the pure `playerCollides` predicate is *not* turn-0-special-cased — at
    /// turn 0 the echo is on `start`, so calling it with the player on `start` would
    /// report a land-on. That is correct: immunity is the engine's job, achieved by
    /// never calling the predicate at turn 0, which is what this test exercises.)
    func testTurnZeroIsImmunePostFoldAndPostDeath() {
        let state = GameState()
        state.move(.right)
        state.fold()                                // echo [.right]; all stacked on start, turn 0

        // Post-fold the player shares `start` with the echo at turn 0, yet is alive.
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.echoes.count, 1)

        // Force a death (land-on at turn 1), which rewinds to the same turn-0 stack.
        // It must NOT re-trigger: a clean step then commits (no restart loop).
        state.move(.right)                          // lands on the echo at turn 1 → restart
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.echoes.count, 1)

        XCTAssertTrue(state.move(.up))              // clean step (echo's turn-1 tile is (3,4))
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.player, GridCoordinate(row: 2, column: 3))
    }

    /// The fatal partial run is discarded, not folded. The player banks an echo,
    /// takes one safe step (building a partial run), then dies on the second step;
    /// afterwards the echo count is unchanged (no echo made from the fatal run) and
    /// the current run is empty.
    func testFatalPartialRunIsDiscardedNotFolded() {
        let state = GameState()
        state.move(.right); state.move(.down); state.fold()   // echo [.right, .down]
        XCTAssertEqual(state.echoes.count, 1)

        XCTAssertTrue(state.move(.down))            // turn 1: safe ((4,3) vs echo (3,4))
        XCTAssertEqual(state.currentRun, [.down])   // partial run recorded
        state.move(.right)                          // turn 2: lands on echo's (4,4) → death

        XCTAssertEqual(state.echoes.count, 1)       // no echo banked from the fatal run
        XCTAssertTrue(state.currentRun.isEmpty)     // partial run discarded
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    /// Land-on against an exhausted echo: a one-move echo stands still on tile
    /// `(3,4)` for every turn ≥ 1; the player loops around and steps onto it at
    /// turn 3 → dissolve.
    func testExhaustedEchoStandingStillCausesLandOn() {
        let state = GameState()
        state.move(.right); state.fold()            // echo [.right] → stands on (3,4)

        XCTAssertTrue(state.move(.down))            // (4,3) turn 1
        XCTAssertTrue(state.move(.right))           // (4,4) turn 2
        state.move(.up)                             // (3,4) turn 3 → lands on the standing echo

        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.echoes.count, 1)
    }

    /// Several echoes, one death. Landing on a tile held by exactly one of two
    /// echoes restarts the run once; both echoes persist.
    func testLandingOnOneOfManyEchoesIsASingleDeathOthersPersist() {
        let state = GameState()
        state.move(.right); state.fold()                  // echo A [.right] → (3,4) at turn 1
        state.move(.up); state.move(.up); state.fold()    // echo B [.up, .up]
        XCTAssertEqual(state.echoes.count, 2)

        state.move(.right)                          // turn 1: lands on echo A only
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.echoes.count, 2)       // both persist
    }

    /// No-echoes regression: with no echoes a free walk never dissolves the player,
    /// and a no-op (off-grid) move neither records, ticks, nor triggers a collision.
    func testEmptyBoardHasNoCollisionsAndNoOpIsInert() {
        let state = GameState()
        XCTAssertTrue(state.move(.up))
        XCTAssertTrue(state.move(.right))
        XCTAssertTrue(state.move(.down))
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 4))
        XCTAssertEqual(state.currentRun, [.up, .right, .down])

        // A no-op from a corner: unchanged, not recorded, no collision attempted.
        let corner = GameState(start: GridCoordinate(row: 0, column: 0))
        XCTAssertFalse(corner.move(.up))            // off the top edge
        XCTAssertEqual(corner.turn, 0)
        XCTAssertTrue(corner.currentRun.isEmpty)
        XCTAssertEqual(corner.player, GridCoordinate(row: 0, column: 0))
    }

    /// The cross-paths (swap) clause, exercised by driving the pure predicate
    /// directly. Real player-vs-echo play can never produce a swap: the player and
    /// every echo share an origin and a one-step-per-turn cadence, so at any turn
    /// they are the same checkerboard parity, while a swap requires the two to be
    /// on opposite-parity adjacent tiles. The clause exists for Phase 1.06's
    /// independently-moving hazards, which *can* cross paths; this test locks the
    /// behaviour in now. (We bank a real echo only to obtain something with the
    /// right per-turn positions; `playerCollides` reads its own `turn` argument,
    /// not the live board's.)
    func testCrossPathsClauseDetectedAtPredicateLevel() {
        let state = GameState()
        // Echo that walks right then back left: at turn 1 it is on (3,4) and at
        // turn 2 it is back on (3,3).
        state.move(.right); state.move(.left); state.fold()   // echo [.right, .left]
        let a = state.start                                   // (3,3)
        let b = GridCoordinate(row: a.row, column: a.column + 1)   // (3,4)

        // Player A→B at turn 2 while the echo goes B→A across the same step: a swap.
        // (Land-on does not fire here — the echo's turn-2 tile is A, not B — so this
        // isolates the cross-paths clause.)
        XCTAssertTrue(state.playerCollides(previousPlayerCell: a, newPlayerCell: b, turn: 2))

        // A non-swap step ending elsewhere (and not landing on the echo) is clean.
        let up = GridCoordinate(row: a.row - 1, column: a.column)  // (2,3)
        XCTAssertFalse(state.playerCollides(previousPlayerCell: a, newPlayerCell: up, turn: 2))
    }

    // MARK: - Walls (Phase 1.06)

    /// A move into a wall cell is a no-op, exactly like off-grid: no tick, no
    /// record, no collision; an open direction still commits.
    func testWallBlocksPlayerMovement() {
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 1, column: 1),
                              walls: [GridCoordinate(row: 0, column: 1)])
        XCTAssertFalse(state.move(.up))                         // into the wall above
        XCTAssertEqual(state.player, GridCoordinate(row: 1, column: 1))
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertTrue(state.move(.down))                        // open direction commits
        XCTAssertEqual(state.player, GridCoordinate(row: 2, column: 1))
        XCTAssertEqual(state.turn, 1)
    }

    // MARK: - Switches & doors (Phase 1.06)

    /// Switch held-state and door open-state are pure per-turn derivations from
    /// occupancy: with no one on the switch the door is closed and its cell blocks
    /// movement; walking the player onto the switch opens it.
    func testSwitchHeldAndDoorOpenDerivedFromOccupancy() {
        let theSwitch = Switch(id: "s1", cell: GridCoordinate(row: 0, column: 0))
        let door = Door(id: "d1", cells: [GridCoordinate(row: 0, column: 2)], heldBy: ["s1"])
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 2, column: 0),
                              switches: [theSwitch], doors: [door])
        XCTAssertFalse(state.isSwitchHeld("s1"))
        XCTAssertFalse(state.isDoorOpen(door))
        XCTAssertTrue(state.isClosedDoor(GridCoordinate(row: 0, column: 2)))

        state.move(.up)                                          // (1,0)
        state.move(.up)                                          // (0,0) == switch
        XCTAssertTrue(state.isSwitchHeld("s1"))                  // player holds it
        XCTAssertTrue(state.isDoorOpen(door))
        XCTAssertFalse(state.isClosedDoor(GridCoordinate(row: 0, column: 2)))
    }

    /// The canonical solve: fold an echo onto a switch so it holds a door open
    /// while present-you walks through it to the exit. Also proves the negative —
    /// without the echo, the closed door blocks the only path.
    func testEchoHoldsSwitchToOpenDoorCanonicalSolve() {
        let s1 = Switch(id: "s1", cell: GridCoordinate(row: 2, column: 2))
        let d1 = Door(id: "d1", cells: [GridCoordinate(row: 0, column: 1)], heldBy: ["s1"])
        func makeRoom() -> GameState {
            GameState(width: 3, height: 3,
                      start: GridCoordinate(row: 2, column: 0),
                      exit: GridCoordinate(row: 0, column: 2),
                      echoBudget: 1, switches: [s1], doors: [d1])
        }

        // Solo: the door is closed, so stepping into it is a no-op and there is no win.
        let solo = makeRoom()
        XCTAssertTrue(solo.move(.up))                            // (1,0)
        XCTAssertTrue(solo.move(.up))                            // (0,0)
        XCTAssertFalse(solo.move(.right))                        // into closed door (0,1)
        XCTAssertEqual(solo.player, GridCoordinate(row: 0, column: 0))
        XCTAssertFalse(solo.hasWon)

        // With an echo holding the switch, present-you passes the now-open door.
        let state = makeRoom()
        state.move(.right); state.move(.right)                   // onto the switch (2,2)
        XCTAssertTrue(state.fold())                              // echo stands on (2,2) for t ≥ 2
        XCTAssertTrue(state.move(.up))                           // (1,0) t1
        XCTAssertTrue(state.move(.up))                           // (0,0) t2 → switch held by echo
        XCTAssertTrue(state.isDoorOpen(d1))
        XCTAssertTrue(state.move(.right))                        // through the open door (0,1) t3
        XCTAssertTrue(state.move(.right))                        // (0,2) exit t4
        XCTAssertTrue(state.hasWon)
        XCTAssertEqual(state.player, GridCoordinate(row: 0, column: 2))
    }

    // MARK: - Hazards (Phase 1.06)

    /// Land-on: the player steps onto a hazard's current-turn cell → dissolve and
    /// restart.
    func testHazardLandOnKillsPlayer() {
        let hazard = Hazard(id: "h1", start: GridCoordinate(row: 0, column: 2),
                            path: [.left, .right], loops: true)
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 0, column: 0), hazards: [hazard])
        XCTAssertEqual(hazard.position(at: 1), GridCoordinate(row: 0, column: 1))
        state.move(.right)                                       // both on (0,1) at turn 1
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
    }

    /// Cross-paths (swap), now **live** against a hazard (D-022): the player and a
    /// hazard trade the same adjacent pair on the same turn. This isolates the swap
    /// branch — the hazard's turn-1 tile is the player's *old* cell, not its new
    /// one, so land-on does not fire.
    func testHazardCrossPathsSwapKillsPlayer() {
        let hazard = Hazard(id: "h1", start: GridCoordinate(row: 0, column: 1),
                            path: [.left, .right], loops: true)
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 0, column: 0), hazards: [hazard])
        XCTAssertEqual(hazard.position(at: 0), GridCoordinate(row: 0, column: 1))
        XCTAssertEqual(hazard.position(at: 1), GridCoordinate(row: 0, column: 0))   // not a land-on
        state.move(.right)                                       // P (0,0)→(0,1) while H (0,1)→(0,0)
        XCTAssertEqual(state.player, state.start)                // swap death → restart
        XCTAssertEqual(state.turn, 0)
    }

    /// Hazard motion model: `loops:true` repeats (indexing modulo path length);
    /// `loops:false` stands still on the last tile once exhausted; an empty path is
    /// stationary.
    func testHazardLoopsNonLoopAndStationary() {
        let loop = Hazard(id: "l", start: GridCoordinate(row: 0, column: 0),
                          path: [.right, .left], loops: true)
        XCTAssertEqual(loop.position(at: 0), GridCoordinate(row: 0, column: 0))
        XCTAssertEqual(loop.position(at: 1), GridCoordinate(row: 0, column: 1))
        XCTAssertEqual(loop.position(at: 2), GridCoordinate(row: 0, column: 0))
        XCTAssertEqual(loop.position(at: 3), GridCoordinate(row: 0, column: 1))     // repeats
        XCTAssertEqual(loop.position(at: 100), GridCoordinate(row: 0, column: 0))

        let once = Hazard(id: "o", start: GridCoordinate(row: 0, column: 0),
                          path: [.right, .right], loops: false)
        XCTAssertEqual(once.position(at: 1), GridCoordinate(row: 0, column: 1))
        XCTAssertEqual(once.position(at: 2), GridCoordinate(row: 0, column: 2))
        XCTAssertEqual(once.position(at: 3), GridCoordinate(row: 0, column: 2))     // exhausted, stands still
        XCTAssertEqual(once.position(at: 50), GridCoordinate(row: 0, column: 2))

        let still = Hazard(id: "s", start: GridCoordinate(row: 1, column: 1), path: [], loops: true)
        XCTAssertEqual(still.position(at: 0), GridCoordinate(row: 1, column: 1))
        XCTAssertEqual(still.position(at: 9), GridCoordinate(row: 1, column: 1))    // empty path
    }

    // MARK: - Win detection (Phase 1.06)

    /// Reaching the exit alive sets the win flag and locks input (move and fold).
    func testReachingExitAliveSetsWinAndLocksInput() {
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 0, column: 0),
                              exit: GridCoordinate(row: 0, column: 2))
        XCTAssertFalse(state.hasWon)
        XCTAssertTrue(state.move(.right))                       // (0,1)
        XCTAssertFalse(state.hasWon)
        XCTAssertTrue(state.move(.right))                       // (0,2) == exit
        XCTAssertTrue(state.hasWon)
        XCTAssertFalse(state.move(.down))                       // input locked
        XCTAssertEqual(state.player, GridCoordinate(row: 0, column: 2))
        XCTAssertEqual(state.turn, 2)
        XCTAssertFalse(state.fold())                           // fold locked too
    }

    /// Collision is evaluated before win on the same step: a tile that is both exit
    /// and lethal is a death, not a win. A hazard sits on the exit the turn the
    /// player arrives (a hazard, not an echo, because recording an echo onto the
    /// exit would itself win).
    func testCollisionTakesPrecedenceOverWin() {
        let hazard = Hazard(id: "h1", start: GridCoordinate(row: 2, column: 2),
                            path: [.up, .up, .down, .down], loops: true)   // (0,2) at turn 2
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 0, column: 0),
                              exit: GridCoordinate(row: 0, column: 2), hazards: [hazard])
        XCTAssertEqual(hazard.position(at: 2), GridCoordinate(row: 0, column: 2))
        state.move(.right)                                      // (0,1) t1 — hazard (1,2), safe
        XCTAssertFalse(state.hasWon)
        state.move(.right)                                      // (0,2)=exit t2 — hazard there too
        XCTAssertFalse(state.hasWon)                            // death took precedence
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - Echo budget (Phase 1.06)

    /// `fold()` is refused once `echoes.count` reaches `echoBudget`; a refused fold
    /// neither banks an echo nor rewinds the run. Budget 0 refuses the first fold.
    func testFoldRefusedAtEchoBudget() {
        let state = GameState(width: 5, height: 5,
                              start: GridCoordinate(row: 4, column: 0), echoBudget: 1)
        state.move(.up)
        XCTAssertTrue(state.fold())                            // 0 < 1 → ok
        XCTAssertEqual(state.echoes.count, 1)
        state.move(.right)
        XCTAssertFalse(state.fold())                           // 1 >= 1 → refused
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertEqual(state.currentRun, [.right])             // run kept, not consumed
        XCTAssertEqual(state.turn, 1)                          // no rewind

        let zero = GameState(width: 3, height: 3, echoBudget: 0)
        zero.move(.up)
        XCTAssertFalse(zero.fold())
        XCTAssertTrue(zero.echoes.isEmpty)
    }

    // MARK: - Level data (Phase 1.06)

    /// The locked v1 JSON format decodes into the model; absent `loops` defaults to
    /// `true` and absent element arrays default to empty.
    func testLevelJSONDecodesToModel() throws {
        let json = """
        {
          "id": "t-decode", "name": "Decode Test",
          "width": 7, "height": 7,
          "start": { "row": 6, "column": 0 },
          "exit":  { "row": 0, "column": 6 },
          "echoBudget": 2,
          "walls": [ { "row": 3, "column": 2 }, { "row": 3, "column": 4 } ],
          "switches": [ { "id": "s1", "cell": { "row": 6, "column": 6 } } ],
          "doors": [ { "id": "d1", "cells": [ { "row": 3, "column": 3 } ], "heldBy": ["s1"] } ],
          "hazards": [ { "id": "h1", "start": { "row": 0, "column": 0 },
                        "path": ["right","right","down"], "loops": true } ]
        }
        """
        let level = try JSONDecoder().decode(Level.self, from: Data(json.utf8))
        XCTAssertEqual(level.id, "t-decode")
        XCTAssertEqual(level.width, 7)
        XCTAssertEqual(level.start, GridCoordinate(row: 6, column: 0))
        XCTAssertEqual(level.exit, GridCoordinate(row: 0, column: 6))
        XCTAssertEqual(level.echoBudget, 2)
        XCTAssertEqual(level.walls.count, 2)
        XCTAssertEqual(level.switches.first?.cell, GridCoordinate(row: 6, column: 6))
        XCTAssertEqual(level.doors.first?.cells, [GridCoordinate(row: 3, column: 3)])
        XCTAssertEqual(level.doors.first?.heldBy, ["s1"])
        XCTAssertEqual(level.hazards.first?.path, [.right, .right, .down])
        XCTAssertEqual(level.hazards.first?.loops, true)

        let sparse = """
        { "id": "x", "name": "x", "width": 3, "height": 3,
          "start": {"row":0,"column":0}, "exit": {"row":2,"column":2}, "echoBudget": 0,
          "hazards": [ { "id": "h", "start": {"row":0,"column":0}, "path": ["right"] } ] }
        """
        let s2 = try JSONDecoder().decode(Level.self, from: Data(sparse.utf8))
        XCTAssertEqual(s2.hazards.first?.loops, true)           // defaulted
        XCTAssertTrue(s2.walls.isEmpty)                        // defaulted
        XCTAssertTrue(s2.switches.isEmpty)
        XCTAssertTrue(s2.doors.isEmpty)
    }

    /// Building a `GameState` from a `Level` carries every field and resets play:
    /// player→start, turn 0, empty run/echoes, win flag false.
    func testGameStateLoadsFromLevelAndResets() {
        let level = Level(id: "L", name: "L", width: 5, height: 4,
                          start: GridCoordinate(row: 3, column: 0),
                          exit: GridCoordinate(row: 0, column: 4),
                          echoBudget: 2,
                          walls: [GridCoordinate(row: 1, column: 1)],
                          switches: [Switch(id: "s", cell: GridCoordinate(row: 3, column: 4))],
                          doors: [Door(id: "d", cells: [GridCoordinate(row: 0, column: 2)], heldBy: ["s"])],
                          hazards: [Hazard(id: "h", start: GridCoordinate(row: 0, column: 0),
                                           path: [.down], loops: true)])
        let state = GameState(level: level)
        XCTAssertEqual(state.width, 5)
        XCTAssertEqual(state.height, 4)
        XCTAssertEqual(state.start, GridCoordinate(row: 3, column: 0))
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 0))
        XCTAssertEqual(state.exit, GridCoordinate(row: 0, column: 4))
        XCTAssertEqual(state.echoBudget, 2)
        XCTAssertTrue(state.isWall(GridCoordinate(row: 1, column: 1)))
        XCTAssertEqual(state.switches.count, 1)
        XCTAssertEqual(state.doors.count, 1)
        XCTAssertEqual(state.hazards.count, 1)
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertTrue(state.echoes.isEmpty)
        XCTAssertFalse(state.hasWon)
    }

    // MARK: - Step back (Phase 1.07)

    /// One `stepBack()` undoes the last committed move: the turn drops by one, the
    /// last recorded direction is popped, and the player returns to the tile it
    /// occupied at the new (lower) turn.
    func testStepBackUndoesOneMoveToPriorTurn() {
        let state = GameState()                              // bare 7×7, start (3,3)
        state.move(.up)                                      // (2,3) t1
        state.move(.right)                                   // (2,4) t2
        state.move(.right)                                   // (2,5) t3
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.currentRun, [.up, .right, .right])
        XCTAssertEqual(state.player, GridCoordinate(row: 2, column: 5))

        XCTAssertTrue(state.stepBack())
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.currentRun, [.up, .right])
        XCTAssertEqual(state.player, GridCoordinate(row: 2, column: 4))   // its turn-2 tile
    }

    /// At turn 0 (the start-stack right after a fold) `stepBack()` is a no-op: turn,
    /// run, player and echoes are all unchanged, and — crucially — no banked echo is
    /// removed. Step-back is intra-run only; it never un-folds (D-030).
    func testStepBackAtTurnZeroIsNoOpAndNeverUnfolds() {
        let state = GameState()
        state.move(.up); state.move(.right)
        XCTAssertTrue(state.fold())                          // bank an echo; back at turn 0
        XCTAssertEqual(state.echoes.count, 1)
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertEqual(state.player, state.start)

        XCTAssertFalse(state.stepBack())                     // nothing to undo
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.echoes.count, 1)                // echo NOT removed
        XCTAssertEqual(state.echoes[0].moves, [.up, .right])
    }

    /// Repeated `stepBack()` walks the current run all the way back to turn 0
    /// move-by-move; the banked echo is preserved at every step.
    func testRepeatedStepBackWalksRunToTurnZeroKeepingEchoes() {
        let state = GameState()
        state.move(.up); state.move(.up); state.fold()       // echo [.up,.up] → stands on (1,3)
        XCTAssertEqual(state.echoes.count, 1)

        // A fresh K-move run kept clear of the standing echo (down/right of start).
        let run: [Direction] = [.down, .right, .right, .down]   // K = 4
        for d in run { state.move(d) }
        XCTAssertEqual(state.turn, 4)
        XCTAssertEqual(state.currentRun, run)

        for remaining in stride(from: run.count - 1, through: 0, by: -1) {
            XCTAssertTrue(state.stepBack())
            XCTAssertEqual(state.turn, remaining)
            XCTAssertEqual(state.currentRun.count, remaining)
            XCTAssertEqual(state.echoes.count, 1)            // echo preserved throughout
        }
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.echoes.count, 1)
    }

    /// `stepBack()` is refused while `hasWon` (symmetry with `move`/`fold`); nothing
    /// changes — the won position stays put (D-031).
    func testStepBackRefusedWhileWon() {
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 0, column: 0),
                              exit: GridCoordinate(row: 0, column: 2))
        state.move(.right); state.move(.right)               // reach exit (0,2) → win at t2
        XCTAssertTrue(state.hasWon)
        XCTAssertEqual(state.turn, 2)

        XCTAssertFalse(state.stepBack())                     // refused while won
        XCTAssertTrue(state.hasWon)
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.player, GridCoordinate(row: 0, column: 2))
        XCTAssertEqual(state.currentRun, [.right, .right])
    }

    /// After a `stepBack()`, the next `move(_:)` records onto the shortened run,
    /// ticks the turn up from the rolled-back value, and lands the player on the new
    /// branch — the `turn == currentRun.count` invariant is intact across the splice.
    func testStepBackThenBranchMoveRecordsOnShortenedRun() {
        let state = GameState()
        state.move(.up); state.move(.up); state.move(.up)    // (0,3) t3
        XCTAssertEqual(state.currentRun, [.up, .up, .up])
        XCTAssertEqual(state.player, GridCoordinate(row: 0, column: 3))

        XCTAssertTrue(state.stepBack())                      // back to (1,3) t2
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.currentRun, [.up, .up])
        XCTAssertEqual(state.player, GridCoordinate(row: 1, column: 3))

        XCTAssertTrue(state.move(.right))                    // branch: (1,4) t3
        XCTAssertEqual(state.turn, 3)
        XCTAssertEqual(state.currentRun, [.up, .up, .right]) // recorded onto the shortened run
        XCTAssertEqual(state.player, GridCoordinate(row: 1, column: 4))
        XCTAssertEqual(state.currentRun.count, state.turn)   // invariant holds
    }

    /// The whole derived world rolls back with the turn. With a switch+door, a
    /// patrolling hazard, and an echo standing on the switch from turn 2, advancing
    /// to turn 2 opens the door and moves the hazard; a single `stepBack()` to turn 1
    /// restores every derived reading (switch-held, door-open, hazard tile, echo
    /// tile) to its turn-1 value — because each is a pure function of `turn`+positions.
    func testDerivedWorldRollsBackWithTheTurn() {
        let s1 = Switch(id: "s1", cell: GridCoordinate(row: 4, column: 2))
        let d1 = Door(id: "d1", cells: [GridCoordinate(row: 2, column: 2)], heldBy: ["s1"])
        let h1 = Hazard(id: "h1", start: GridCoordinate(row: 0, column: 0),
                        path: [.right, .left], loops: true)  // (0,1) at odd t, (0,0) at even t
        let state = GameState(width: 5, height: 5,
                              start: GridCoordinate(row: 4, column: 0),
                              echoBudget: 1,
                              switches: [s1], doors: [d1], hazards: [h1])

        // Bank an echo that stands on the switch from turn 2 onward.
        state.move(.right); state.move(.right)               // onto switch (4,2)
        XCTAssertTrue(state.fold())                          // echo [.right,.right]
        let echo = state.echoes[0]

        // Advance the fresh run to turn 1 and snapshot the derived world there.
        XCTAssertTrue(state.move(.up))                       // (3,0) t1
        XCTAssertEqual(state.turn, 1)
        let heldAt1   = state.isSwitchHeld("s1")             // false (echo on (4,1))
        let openAt1   = state.isDoorOpen(d1)                 // false
        let hazardAt1 = state.position(of: h1)               // (0,1)
        let echoAt1   = state.position(of: echo)             // (4,1)
        XCTAssertFalse(heldAt1)
        XCTAssertFalse(openAt1)
        XCTAssertEqual(hazardAt1, GridCoordinate(row: 0, column: 1))
        XCTAssertEqual(echoAt1, GridCoordinate(row: 4, column: 1))

        // Advance to turn 2: the derived world genuinely changes.
        XCTAssertTrue(state.move(.up))                       // (2,0) t2
        XCTAssertEqual(state.turn, 2)
        XCTAssertTrue(state.isSwitchHeld("s1"))              // echo now on the switch
        XCTAssertTrue(state.isDoorOpen(d1))
        XCTAssertEqual(state.position(of: h1), GridCoordinate(row: 0, column: 0))
        XCTAssertEqual(state.position(of: echo), GridCoordinate(row: 4, column: 2))

        // Step back to turn 1: every derived value returns to its turn-1 reading.
        XCTAssertTrue(state.stepBack())
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.player, GridCoordinate(row: 3, column: 0))
        XCTAssertEqual(state.isSwitchHeld("s1"), heldAt1)
        XCTAssertEqual(state.isDoorOpen(d1), openAt1)
        XCTAssertEqual(state.position(of: h1), hazardAt1)
        XCTAssertEqual(state.position(of: echo), echoAt1)
        XCTAssertEqual(state.echoes.count, 1)                // echo untouched by step-back
    }

    // MARK: - Reset run (Phase 1.07)

    /// Reset run is the existing `restartRun()` op exposed to a control (D-029):
    /// player→start, turn→0, current run cleared, win flag cleared, and **all banked
    /// echoes preserved** — distinct from `clearEchoes()`, which wipes them. It works
    /// mid-run and equally after a win.
    func testResetRunPreservesEchoesAndClearsRunIncludingAfterWin() {
        // Mid-run reset: keeps both echoes, returns to a clean turn-0 run.
        let state = GameState()
        state.move(.up); state.move(.up); state.fold()       // echo A [.up,.up]
        state.move(.down); state.fold()                      // echo B [.down]
        XCTAssertEqual(state.echoes.count, 2)
        state.move(.right); state.move(.right)               // partial new run, clear of echoes
        XCTAssertEqual(state.turn, 2)
        XCTAssertFalse(state.currentRun.isEmpty)

        state.restartRun()                                   // the reset-run op
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
        XCTAssertFalse(state.hasWon)
        XCTAssertEqual(state.echoes.count, 2)                // echoes preserved (unlike clearEchoes)

        // Reset after a win also works: it clears `hasWon` and still keeps echoes.
        let won = GameState(width: 3, height: 3,
                            start: GridCoordinate(row: 0, column: 0),
                            exit: GridCoordinate(row: 0, column: 2), echoBudget: 2)
        won.move(.down); won.fold()                          // bank an echo
        XCTAssertEqual(won.echoes.count, 1)
        won.move(.right); won.move(.right)                   // reach the exit → win
        XCTAssertTrue(won.hasWon)

        won.restartRun()
        XCTAssertFalse(won.hasWon)
        XCTAssertEqual(won.player, won.start)
        XCTAssertEqual(won.turn, 0)
        XCTAssertTrue(won.currentRun.isEmpty)
        XCTAssertEqual(won.echoes.count, 1)                  // echo survives the reset
    }

    // MARK: - Move outcome signal (Phase 2.05)

    /// The additive, read-only `lastMoveOutcome` is `nil` until the first committed
    /// move (the call site's "nothing has happened yet").
    func testLastMoveOutcomeIsNilBeforeAnyMove() {
        let state = GameState()
        XCTAssertNil(state.lastMoveOutcome)
    }

    /// A survived committed step sets `.stepped`.
    func testLastMoveOutcomeIsSteppedOnSurvivedStep() {
        let state = GameState()
        XCTAssertTrue(state.move(.up))
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
        XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.lastMoveOutcome, .stepped)      // still just a step
    }

    /// The committed step that reaches the exit alive sets `.won` (not `.stepped`); a
    /// non-exit step on the way stays `.stepped`.
    func testLastMoveOutcomeIsWonOnReachingExit() {
        let state = GameState(width: 3, height: 3,
                              start: GridCoordinate(row: 0, column: 0),
                              exit: GridCoordinate(row: 0, column: 2))
        XCTAssertTrue(state.move(.right))                    // (0,1) — not the exit yet
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
        XCTAssertTrue(state.move(.right))                    // (0,2) == exit
        XCTAssertTrue(state.hasWon)
        XCTAssertEqual(state.lastMoveOutcome, .won)
    }

    /// The fatal step that touches an echo sets `.died`, and the value **persists**
    /// through the rewind (the player is back on `start`, yet the last outcome still
    /// reads `.died` — what a feedback consumer needs to fire the collision tap).
    func testLastMoveOutcomeIsDiedOnCollisionAndPersistsThroughRewind() {
        let state = GameState()
        XCTAssertTrue(state.move(.right))                    // step onto (3,4)
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
        state.fold()                                         // echo [.right] stands on (3,4)
        XCTAssertEqual(state.lastMoveOutcome, .stepped)      // fold doesn't touch the signal
        state.move(.right)                                   // land on the echo at turn 1 → death
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.player, state.start)            // rewound, but the signal stands
        XCTAssertEqual(state.turn, 0)
    }

    /// A blocked / no-op move leaves `lastMoveOutcome` **unchanged** — the call site
    /// reads `move()` returning `false` as "nothing happened." Here a committed step
    /// sets `.stepped`, then an off-grid no-op leaves it `.stepped`.
    func testLastMoveOutcomeUnchangedOnNoOpMove() {
        let state = GameState(start: GridCoordinate(row: 0, column: 0))
        XCTAssertTrue(state.move(.right))                    // (0,1) committed
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
        XCTAssertFalse(state.move(.up))                      // off the top edge → no-op
        XCTAssertEqual(state.lastMoveOutcome, .stepped)      // unchanged
    }

    /// A no-op as the very first move leaves the signal at its initial `nil` (it is
    /// never spuriously set by a refused move).
    func testLastMoveOutcomeStaysNilWhenFirstMoveIsBlocked() {
        let state = GameState(start: GridCoordinate(row: 0, column: 0))
        XCTAssertFalse(state.move(.up))                      // off-grid no-op
        XCTAssertNil(state.lastMoveOutcome)
    }
}
