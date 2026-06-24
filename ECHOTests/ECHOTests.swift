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
}
