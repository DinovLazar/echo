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
//  stays a pure value usable from any context — the view, the model, and the
//  level decoding (Phase 1.06) — even though the app builds with MainActor as the
//  default actor isolation.
//
//  Phase 1.06 adds `Codable`: a cell in a level JSON file is written exactly as
//  `{ "row": R, "column": C }`, which maps one-to-one onto these two stored
//  properties, so the synthesized coding keys decode the room format with no
//  custom logic. (Encodable is along for the ride for the Part 3 save data.)
//

/// A single cell on the board. Origin is top-left: `row` increases downward,
/// `column` increases rightward. Equality is exact cell identity, which is the
/// game's entire collision model (same tile on the same turn = touch).
nonisolated struct GridCoordinate: Equatable, Hashable, Sendable, Codable {
    var row: Int
    var column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}
