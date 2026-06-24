//
//  GameState.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move). The board's observable state and the one rule that
//  advances the world: a single committed move per legal step. This is the spine
//  the rest of the game hangs from — Phase 1.04 records and replays sequences of
//  exactly these moves against this same shared turn counter.
//
//  Kept pure and view-independent so it can be unit-tested directly. Dimensions
//  and the start cell are parameters (default 7×7, centered) so Phase 1.06 can
//  build a board from level data without touching this type. No level loading,
//  fold/replay, collision, or win logic here — those are later phases.
//

import Observation

/// Observable model of the board: its size, the player's cell, and the shared
/// turn counter. The world is turn-based and deterministic — it advances *only*
/// when the player commits a legal move, and by exactly one turn each time.
@MainActor
@Observable
final class GameState {
    /// Number of columns. A parameter, not a magic number — set from level data later.
    let width: Int
    /// Number of rows.
    let height: Int

    /// The player's current cell. Read-only from outside; only `move(_:)` changes it.
    private(set) var player: GridCoordinate

    /// The shared turn counter. Starts at 0 and increases by exactly one on each
    /// committed move. Echoes (Phase 1.04) will step in lockstep with this.
    private(set) var turn: Int = 0

    /// - Parameters:
    ///   - width: number of columns (default 7).
    ///   - height: number of rows (default 7).
    ///   - start: the player's starting cell; defaults to the center cell.
    init(width: Int = 7, height: Int = 7, start: GridCoordinate? = nil) {
        self.width = width
        self.height = height
        self.player = start ?? GridCoordinate(row: height / 2, column: width / 2)
    }

    /// Whether `cell` lies inside the board.
    func contains(_ cell: GridCoordinate) -> Bool {
        cell.row >= 0 && cell.row < height
            && cell.column >= 0 && cell.column < width
    }

    /// Move the player one tile in `direction`.
    ///
    /// A move that would leave the grid is a **no-op**: nothing changes and the
    /// turn counter does not advance. A legal move updates the player's cell and
    /// advances the turn counter by exactly one. Returns whether the move was
    /// committed, so callers can pair feedback to a real step.
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        let target = GridCoordinate(
            row: player.row + direction.offset.row,
            column: player.column + direction.offset.column
        )
        guard contains(target) else { return false }
        player = target
        turn += 1
        return true
    }
}
