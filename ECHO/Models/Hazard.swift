//
//  Hazard.swift
//  ECHO
//
//  Phase 1.06 (Room contents, level data & win). A moving hazard: an
//  independently-patrolling cell that is **lethal to present-you on contact** but
//  is not solid (you can step onto its tile — and die) and does not hold switches.
//  Like an echo, its position is a pure function of (start, its authored path, the
//  shared turn) so its replay is exact and repeatable; unlike an echo, its path is
//  authored in the level rather than recorded from play, and it **loops** by
//  default instead of standing still when exhausted (D-019..D-021).
//
//  Hazards are the first thing that can move *opposite* the player and trade tiles
//  with it, so this is what finally makes the collision predicate's cross-paths
//  (swap) branch reachable in real play (D-018, dormant against echoes since 1.05).
//
//  Deliberately isolation-free and Sendable, matching the other pure value types
//  (D-013). Decodes from the locked v1 level schema:
//      { "id": "h1", "start": { "row": 0, "column": 0 },
//        "path": ["right","right","down"], "loops": true }
//

import Foundation

/// One authored patrol. `path` is a list of one-tile steps applied from `start`,
/// one per turn; `loops` repeats the path (default), otherwise the hazard stands
/// still on its last tile once the path is walked. An empty `path` is a
/// stationary hazard.
nonisolated struct Hazard: Identifiable, Equatable, Sendable, Decodable {
    /// Unique within a level (authoring/debug identity).
    let id: String
    /// The cell the hazard occupies at turn 0.
    let start: GridCoordinate
    /// The ordered patrol: one `Direction` applied per turn from `start`.
    let path: [Direction]
    /// Whether the patrol repeats forever (`true`, default) or the hazard stands
    /// still on its last tile once `path` is exhausted (`false`, like an echo —
    /// D-014).
    let loops: Bool

    /// Direct initializer (used by tests and any in-code level construction).
    /// `loops` defaults to `true`, matching the JSON default.
    init(id: String, start: GridCoordinate, path: [Direction], loops: Bool = true) {
        self.id = id
        self.start = start
        self.path = path
        self.loops = loops
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, path, loops
    }

    /// Custom decode so absent optional fields take their documented defaults: a
    /// missing `path` is the empty (stationary) patrol, and a missing `loops` is
    /// `true`. (Synthesized `Decodable` would instead require both keys.)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        start = try container.decode(GridCoordinate.self, forKey: .start)
        path = try container.decodeIfPresent([Direction].self, forKey: .path) ?? []
        loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? true
    }

    /// The cell this hazard occupies at `turn`, starting from `start`.
    ///
    /// Applies one step of `path` per turn. With an empty path (or turn 0) the
    /// hazard sits on `start`. With `loops == false` it walks the first
    /// `min(turn, path.count)` steps and then **stands still** on its last tile
    /// for every later turn (exactly like an exhausted echo, D-014). With
    /// `loops == true` it keeps going, indexing the path modulo its length, so the
    /// patrol repeats. Pure: same inputs always yield the same tile — the
    /// replay-fidelity guarantee echoes and hazards share.
    func position(at turn: Int) -> GridCoordinate {
        guard turn > 0, !path.isEmpty else { return start }
        let steps = loops ? turn : min(turn, path.count)
        var cell = start
        for index in 0..<steps {
            let step = path[index % path.count].offset
            cell = GridCoordinate(row: cell.row + step.row,
                                  column: cell.column + step.column)
        }
        return cell
    }
}
