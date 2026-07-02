//
//  Level.swift
//  ECHO
//
//  Phase 1.06 (Room contents, level data & win). The decoded shape of one room
//  and the loader that reads it from a bundled JSON file. A `Level` is plain,
//  view-independent data; `GameState(level:)` turns it into a playable board
//  (D-025). The v1 JSON format is locked (D-024); Phase 4.03 adds the **v2**
//  extension — an optional top-level `portals` array (D-072) — and Phase 4.05 adds
//  the **`mirror` extension** — an optional top-level `mirror` block (D-076) — both
//  additively, so an absent key means "no portals" / "a normal single-body room" and
//  every earlier room JSON (rooms 01–30) is byte-for-byte valid and unchanged:
//
//      {
//        "id": "example", "name": "Schema Example",
//        "width": 8, "height": 7,
//        "start": { "row": 6, "column": 0 },
//        "exit":  { "row": 0, "column": 3 },
//        "echoBudget": 1,
//        "walls":    [ { "row": 3, "column": 0 } ],
//        "switches": [ { "id": "s1", "cell": { "row": 6, "column": 1 } } ],
//        "doors":    [ { "id": "d1", "cells": [ { "row": 3, "column": 3 } ],
//                        "heldBy": ["s1"] } ],
//        "hazards":  [ { "id": "h1", "start": { "row": 0, "column": 0 },
//                        "path": ["right","down"], "loops": true } ],
//        "portals":  [ { "id": "p1", "cells": [ { "row": 1, "column": 0 },
//                        { "row": 1, "column": 6 } ] } ],     // v2 (D-072), optional
//        "mirror":   { "axis": "vertical",                    // mirror ext (D-076), optional
//                      "startRight": { "row": 6, "column": 7 },
//                      "exitRight":  { "row": 0, "column": 4 } }
//      }
//
//  Coordinates are `{ row, column }`, origin top-left, 0-indexed — the same
//  `GridCoordinate` the engine speaks (Codable since 1.06). `doors.heldBy` is an
//  AND-array (a door is open iff every listed switch is held); `doors.cells` is an
//  array; `hazards.path` is a `Direction` list with a `loops` flag. v1 rooms use
//  single-cell, single-switch doors, but the arrays exist so multi-tile and
//  multi-switch doors need no format change later. A `portals` entry is a linked
//  **pad pair**: its `cells` are exactly two, each the other's bidirectional partner
//  — stepping onto one lands you on the other (D-070/D-072). A `mirror` block makes
//  the room **two-body** (Phase 4.05 / D-074): the board splits down a vertical
//  centerline (width must be even), the top-level `start`/`exit` become the LEFT
//  body's, and `startRight`/`exitRight` are the RIGHT body's — see `MirrorGameState`.
//
//  Deliberately isolation-free and Sendable, matching the other pure value types
//  (D-013).
//

import Foundation

/// A switch: held at a turn iff the player or any echo occupies its `cell` that
/// turn (hazards do not hold switches — D-019).
nonisolated struct Switch: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    let cell: GridCoordinate
}

/// A door: open at a turn iff **every** switch in `heldBy` is held that turn
/// (AND). Spans one or more `cells`. A closed door blocks the player's movement
/// like a wall; doors never kill (D-019).
nonisolated struct Door: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    let cells: [GridCoordinate]
    let heldBy: [String]
}

/// A teleport pad pair (level format v2 — D-070/D-072). `cells` are exactly **two**,
/// each the other's **bidirectional** partner: stepping onto one pad lands you instantly
/// on the other as part of that move. A pad is a plain board property, so echoes teleport
/// through it too (an echo replaying a step onto a pad jumps deterministically); hazards
/// ignore pads (patrols stay predictable — D-036). The single teleport rule lives in
/// `resolveLanding(from:step:pads:)` (Echo.swift); `GameState` derives a bidirectional
/// `padMap` from these portals and asserts well-formedness (exactly two distinct cells per
/// portal, no cell shared across portals) in debug.
nonisolated struct Portal: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    let cells: [GridCoordinate]   // exactly two — each other's partner (bidirectional)
}

/// The **mirror** block (level-format `mirror` extension — Phase 4.05 / D-074/D-076).
/// Its presence makes the room two-body: the board splits down a vertical centerline
/// into a left half (columns `0 … width/2−1`) and a right half (`width/2 … width−1`),
/// and present-you is **two bodies on one reflected input**, one confined to each half.
/// The top-level `start`/`exit` are the LEFT body's; `startRight`/`exitRight` are the
/// RIGHT body's (authored — the intended design mirrors `start`, but an asymmetric half
/// may place it elsewhere). Width must be even (debug-asserted by `MirrorGameState`).
/// Walls/switches/doors/hazards stay authored on the full grid as normal; the halves
/// may be asymmetric — that asymmetry is the puzzle. Absent block ⇒ a normal
/// single-body room, so rooms 01–30 decode byte-for-byte unchanged.
nonisolated struct MirrorSpec: Equatable, Sendable, Decodable {
    /// The split axis — `"vertical"` is the only value in this version.
    let axis: String
    /// The right body's starting cell (must lie in the right half).
    let startRight: GridCoordinate
    /// The right body's exit cell (must lie in the right half). You win the instant
    /// BOTH bodies sit on their own-half exits on the same turn.
    let exitRight: GridCoordinate
}

/// One decoded room. Pure data — `GameState(level:)` configures a board from it.
nonisolated struct Level: Identifiable, Equatable, Sendable, Decodable {
    /// Unique room id (also the JSON file's base name in `Levels/`).
    let id: String
    /// Human-readable name, for debugging.
    let name: String
    /// Board size for this room (rooms are no longer hardcoded 7×7).
    let width: Int
    let height: Int
    /// Where the player begins.
    let start: GridCoordinate
    /// The single exit cell (singular by design; multi-exit would be a v2 bump).
    let exit: GridCoordinate
    /// Maximum number of folds (max echoes) allowed in this room.
    let echoBudget: Int
    /// Impassable cells.
    let walls: [GridCoordinate]
    /// Switches by id + cell.
    let switches: [Switch]
    /// Doors by id + spanned cells + holding switches.
    let doors: [Door]
    /// Independently-moving lethal hazards.
    let hazards: [Hazard]
    /// Linked teleport pad pairs (level format v2 — D-072). Empty (the default) on
    /// every v1 room, so rooms 01–25 are unchanged.
    let portals: [Portal]
    /// The optional two-body mirror block (the `mirror` extension — D-076). `nil`
    /// (the default) ⇒ a normal single-body room, so rooms 01–30 are unchanged;
    /// present ⇒ `RoomView`'s screen path runs `MirrorGameState` instead of `GameState`.
    let mirror: MirrorSpec?

    /// Direct initializer (used by tests and any in-code level construction). The
    /// element collections default to empty so a sparse room is cheap to build.
    init(id: String, name: String, width: Int, height: Int,
         start: GridCoordinate, exit: GridCoordinate, echoBudget: Int,
         walls: [GridCoordinate] = [], switches: [Switch] = [],
         doors: [Door] = [], hazards: [Hazard] = [], portals: [Portal] = [],
         mirror: MirrorSpec? = nil) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.start = start
        self.exit = exit
        self.echoBudget = echoBudget
        self.walls = walls
        self.switches = switches
        self.doors = doors
        self.hazards = hazards
        self.portals = portals
        self.mirror = mirror
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, width, height, start, exit, echoBudget
        case walls, switches, doors, hazards, portals, mirror
    }

    /// Custom decode so the element arrays may be omitted from a room's JSON (an
    /// absent `walls`/`switches`/`doors`/`hazards`/`portals` simply means "none"); the
    /// core fields stay required so a malformed room fails loudly rather than loading a
    /// silently-broken board. `portals` is the v2 extension (D-072) and `mirror` the
    /// mirror extension (D-076): an absent key ⇒ no portals / a normal single-body
    /// room, so every earlier room JSON decodes byte-for-byte as before.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        start = try container.decode(GridCoordinate.self, forKey: .start)
        exit = try container.decode(GridCoordinate.self, forKey: .exit)
        echoBudget = try container.decode(Int.self, forKey: .echoBudget)
        walls = try container.decodeIfPresent([GridCoordinate].self, forKey: .walls) ?? []
        switches = try container.decodeIfPresent([Switch].self, forKey: .switches) ?? []
        doors = try container.decodeIfPresent([Door].self, forKey: .doors) ?? []
        hazards = try container.decodeIfPresent([Hazard].self, forKey: .hazards) ?? []
        portals = try container.decodeIfPresent([Portal].self, forKey: .portals) ?? []
        mirror = try container.decodeIfPresent(MirrorSpec.self, forKey: .mirror)
    }
}

/// Reads a `Level` from a bundled JSON file. The proof rooms live in the repo-root
/// `Levels/` folder (Plan §7) and are added to the app target as bundled resources
/// (D-023).
enum LevelLoader {
    /// Decode the level whose `id` matches the JSON file's base name. Returns `nil`
    /// (rather than crashing) if the resource is missing or unreadable, so a
    /// caller can fall back gracefully. `bundle` is injectable for testing.
    static func load(_ id: String, in bundle: Bundle = .main) -> Level? {
        guard let url = url(forLevel: id, in: bundle),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Level.self, from: data)
    }

    /// Locate a level's JSON in the bundle. A file-system synchronized group (the
    /// mechanism this project uses) flattens resources to the bundle root, while a
    /// folder reference would nest them under `Levels/`; we try the flat name
    /// first and the `Levels` subdirectory second, so the loader works whichever
    /// Xcode bundling mechanism is used.
    private static func url(forLevel id: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: id, withExtension: "json")
            ?? bundle.url(forResource: id, withExtension: "json", subdirectory: "Levels")
    }
}
