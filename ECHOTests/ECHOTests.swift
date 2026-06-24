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
        state.move(.up)
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.position(of: echo), expected[1])
        state.move(.up)                                          // live diverges…
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

        // Advance the shared turn to 3 with any legal moves.
        state.move(.up); state.move(.up); state.move(.up)
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
        state.move(.up)                         // partial new run + advanced turn
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
}
