//
//  Echo.swift
//  ECHO
//
//  Phase 1.04 (Fold — record & replay). A grey "echo": one folded run, stored as
//  the exact sequence of moves the live player walked. The keystone of the whole
//  game — an echo's position at any turn is a pure function of (start tile, its
//  recorded moves, the shared turn counter), so replays are exact and repeatable
//  with no per-step bookkeeping to get wrong (Plan §14, points 1–2).
//
//  Deliberately isolation-free and Sendable (a `UUID` and `[Direction]`, both
//  Sendable), matching `GridCoordinate`/`Direction` (D-013). The `id` gives each
//  echo a stable identity so SwiftUI can animate every grey square independently.
//
//  No collision here — that an echo can share a tile with the player (or with
//  another echo) is intended in 1.04; touching an echo only dissolves you from
//  Phase 1.05 onward.
//

import Foundation

/// A recorded run, replayed as a grey echo locked to the shared turn counter.
nonisolated struct Echo: Identifiable, Equatable, Sendable {
    /// Stable identity for independent SwiftUI animation; never reused.
    let id: UUID
    /// The exact moves walked during the run, in order. Empty echoes are never
    /// created (folding an empty run is a no-op — see `GameState.fold()`).
    let moves: [Direction]

    init(id: UUID = UUID(), moves: [Direction]) {
        self.id = id
        self.moves = moves
    }

    /// The cell this echo occupies at `turn`, starting from `start`.
    ///
    /// Applies the first `min(turn, moves.count)` recorded moves in order: at
    /// `turn == 0` the echo sits on `start`; at `turn == moves.count` it has
    /// walked its whole path; for any `turn` beyond that it **stands still** on
    /// its last tile (what later lets an echo "hold" a switch). Pure: same inputs
    /// always yield the same tile, which is the replay-fidelity guarantee.
    func position(start: GridCoordinate, turn: Int) -> GridCoordinate {
        let steps = max(0, min(turn, moves.count))
        var cell = start
        for index in 0..<steps {
            let step = moves[index].offset
            cell = GridCoordinate(row: cell.row + step.row,
                                  column: cell.column + step.column)
        }
        return cell
    }

    /// The cells this echo is **about to enter** from `turn` onward — the data the
    /// optional echo-trail aid draws its dotted preview through (Phase 2.06; handover
    /// §8/§6f). It is the tiles at turns `turn + 1, turn + 2, …` up to the last
    /// recorded move (`moves.count`).
    ///
    /// Empty once the echo has run out of recorded moves at `turn` (`turn >=
    /// moves.count`): a stationary echo has no upcoming path, so it shows no dots.
    /// Because the list stops at `moves.count` it never includes the standing-still
    /// repeats of an exhausted echo, so there are no trailing duplicate cells. Pure —
    /// a read of recorded intent only; it changes no gameplay.
    func upcomingCells(start: GridCoordinate, turn: Int) -> [GridCoordinate] {
        guard turn < moves.count else { return [] }
        return ((turn + 1)...moves.count).map { position(start: start, turn: $0) }
    }
}
