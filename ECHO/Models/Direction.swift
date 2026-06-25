//
//  Direction.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move). The four orthogonal moves — the game's single verb.
//  A pure value type with no UI dependency: it knows its row/column offset and
//  how to read itself off two adjacent cells (used to turn a tap on an adjacent
//  cell into a move). Diagonals and multi-step moves are deliberately
//  unrepresentable — the game has exactly one verb, and these are its directions.
//
//  Phase 1.06 gives it a `String` raw value and `Codable`: a hazard's authored
//  patrol in a level JSON file is a list of these names (e.g. `["right","down"]`),
//  and the raw values match the case names exactly, so a `[Direction]` decodes
//  straight from that array with no custom logic.
//

/// One orthogonal step on the grid. The raw value is the lowercase name used in
/// level JSON (`"up"`/`"down"`/`"left"`/`"right"`).
nonisolated enum Direction: String, CaseIterable, Codable, Sendable {
    case up, down, left, right

    /// Row/column offset of one step in this direction, in top-left origin
    /// coordinates (up = row − 1, down = row + 1, left = col − 1, right = col + 1).
    var offset: (row: Int, column: Int) {
        switch self {
        case .up:    (-1, 0)
        case .down:  ( 1, 0)
        case .left:  ( 0, -1)
        case .right: ( 0, 1)
        }
    }

    /// The direction from `origin` to `target` when `target` is exactly one
    /// orthogonal step away; `nil` for the same cell, a diagonal, or anything
    /// farther. This is the tap rule: a tap on an orthogonally-adjacent cell
    /// becomes one move, everything else is ignored.
    init?(from origin: GridCoordinate, to target: GridCoordinate) {
        switch (target.row - origin.row, target.column - origin.column) {
        case (-1, 0): self = .up
        case ( 1, 0): self = .down
        case ( 0, -1): self = .left
        case ( 0, 1): self = .right
        default: return nil
        }
    }
}
