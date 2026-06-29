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
//  Phase 4.01 (the wait action) adds a fifth case, `.stay` (zero offset) — the
//  recorded "pass a turn in place" element (D-067). It is issued ONLY via
//  `GameState.wait()`: the tap initializer never produces it, `GameState.move(_:)`
//  refuses it, and no room's hazard path uses it. Storing a wait as a `Direction`
//  case (rather than a new `Move` type) keeps a recorded run a plain `[Direction]`
//  everywhere — `currentRun`, `Echo.moves`, `stepBack`/`fold`, `Echo.position` —
//  so the verified engine and its suite need no migration (D-067).
//

/// One step on the grid. The raw value is the lowercase name used in level JSON
/// (`"up"`/`"down"`/`"left"`/`"right"`, plus `"stay"`). `.stay` is the zero-offset
/// "pass a turn in place" element issued only via `GameState.wait()` — see the
/// file header and D-067.
nonisolated enum Direction: String, CaseIterable, Codable, Sendable {
    case up, down, left, right
    /// Pass a turn in place: zero offset, so replaying it advances a run's index
    /// without moving (what lets an echo "hold" a switch across turns). Recorded
    /// only by `GameState.wait()`; never produced by `init?(from:to:)`, and refused
    /// by `move(_:)` (D-066/D-067).
    case stay

    /// Row/column offset of one step in this direction, in top-left origin
    /// coordinates (up = row − 1, down = row + 1, left = col − 1, right = col + 1).
    /// `.stay` has a zero offset — it advances the turn without moving.
    var offset: (row: Int, column: Int) {
        switch self {
        case .up:    (-1, 0)
        case .down:  ( 1, 0)
        case .left:  ( 0, -1)
        case .right: ( 0, 1)
        case .stay:  ( 0, 0)
        }
    }

    /// The direction from `origin` to `target` when `target` is exactly one
    /// orthogonal step away; `nil` for the same cell, a diagonal, or anything
    /// farther. This is the tap rule: a tap on an orthogonally-adjacent cell
    /// becomes one move, everything else is ignored. It **never** returns `.stay`
    /// — the same-cell case (a zero delta) falls through to `nil`, so a wait is
    /// only ever issued explicitly via `GameState.wait()` (D-067).
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
