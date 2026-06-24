//
//  GridCoordinate.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move). A pure grid position: zero-based row and column,
//  origin top-left (row grows downward, column grows rightward). This is the
//  coordinate the whole game speaks in — the player now, and later echoes,
//  switches, hazards, and exits all live on these cells.
//
//  Deliberately isolation-free and Sendable (not bound to the main actor) so it
//  stays a pure value usable from any context — the view, the model, and future
//  level decoding (Phase 1.06) — even though the app builds with MainActor as the
//  default actor isolation.
//

/// A single cell on the board. Origin is top-left: `row` increases downward,
/// `column` increases rightward. Equality is exact cell identity, which becomes
/// the game's entire collision model later (same tile on the same turn = touch).
nonisolated struct GridCoordinate: Equatable, Hashable, Sendable {
    var row: Int
    var column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}
