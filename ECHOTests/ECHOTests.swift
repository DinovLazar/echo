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
}
