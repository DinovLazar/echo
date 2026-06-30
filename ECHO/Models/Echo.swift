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

/// **The single teleport rule** (Phase 4.03 / D-070/D-071). Resolve where one step in
/// `step` from `cell` lands, given the board's bidirectional pad map `pads` (a portal's
/// two cells each map to the other):
///   • apply `step.offset`;
///   • if the step **displaced** you (a non-zero offset) and the stepped-to cell is a
///     pad, return its partner — you teleport, ending the step on the partner;
///   • otherwise return the stepped-to cell.
///
/// The partner **never re-fires**: arriving on a pad is terminal for that step (you rest
/// on the partner; it does not bounce). A `.stay` (zero offset) never teleports even while
/// you rest on a pad — only a displacing step onto a pad jumps. With an **empty** `pads`
/// the result is exactly `cell + step.offset`, so a no-portal walk equals the old offset
/// sum and rooms 01–25 / the verified suite behave byte-for-byte as before.
///
/// Pure and shared: `Echo.position`/`upcomingCells` and `GameState.move`/`stepBack` all
/// walk through *this* one function, so there is exactly one teleport rule (D-070).
/// `nonisolated` so it is callable from `Echo` (a nonisolated value type) and from the
/// `@MainActor` `GameState` alike.
nonisolated func resolveLanding(from cell: GridCoordinate,
                                step: Direction,
                                pads: [GridCoordinate: GridCoordinate]) -> GridCoordinate {
    let stepped = GridCoordinate(row: cell.row + step.offset.row,
                                 column: cell.column + step.offset.column)
    // A zero-offset step (`.stay`) rests in place and never teleports; a displacing step
    // onto a pad lands on its partner (and the partner is terminal — no re-fire).
    if stepped != cell, let partner = pads[stepped] { return partner }
    return stepped
}

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
    ///
    /// A recorded run may contain mid-path `.stay` elements (Phase 4.01 — one
    /// per `GameState.wait()`); each has a zero offset, so it advances the index
    /// without moving and the echo **holds its tile** for that turn before walking
    /// on (D-066/D-067). This needs no special-casing here — `.stay.offset` is
    /// `(0, 0)`.
    ///
    /// Phase 4.03 (teleport) makes the replay a **step-by-step walk through the shared
    /// `resolveLanding` resolver** instead of a closed-form offset sum, so an echo that
    /// recorded a step onto a pad teleports deterministically and can relay across
    /// regions (D-070/D-071). `pads` defaults to empty: with no portals the walk equals
    /// the old offset sum, so existing call sites and the verified suite need no
    /// migration. An echo replays a teleport **verbatim** and does not re-check doors
    /// (D-020) — a pad is a board property, not a gate.
    func position(start: GridCoordinate, turn: Int,
                  pads: [GridCoordinate: GridCoordinate] = [:]) -> GridCoordinate {
        let steps = max(0, min(turn, moves.count))
        var cell = start
        for index in 0..<steps {
            cell = resolveLanding(from: cell, step: moves[index], pads: pads)
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
    /// repeats of an *exhausted* echo, so there are no trailing duplicate cells. A
    /// mid-path `.stay` (Phase 4.01), however, repeats the *same* cell on consecutive
    /// turns within the path, so the list can contain an interior duplicate — harmless
    /// for the dotted trail (the resampler skips a zero-length segment), so dedupe is
    /// left as-is (D-067). A teleport likewise produces a non-adjacent jump between two
    /// consecutive entries (Phase 4.03), which the trail draws truthfully as the jump it
    /// is. Pure — a read of recorded intent only; it changes no gameplay. `pads` defaults
    /// to empty (a no-portal preview is identical to before — D-071).
    func upcomingCells(start: GridCoordinate, turn: Int,
                       pads: [GridCoordinate: GridCoordinate] = [:]) -> [GridCoordinate] {
        guard turn < moves.count else { return [] }
        return ((turn + 1)...moves.count).map { position(start: start, turn: $0, pads: pads) }
    }
}
