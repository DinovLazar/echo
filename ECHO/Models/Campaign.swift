//
//  Campaign.swift
//  ECHO
//
//  Phase 3.03 (Navigation shell). The single source of truth for the campaign's room
//  order and identity — the ordered list of the twenty hand-authored rooms
//  (`room-01 … room-20`) and the pure helpers the navigation layer reads: the next room
//  in order (for the win overlay's "Next room"), the 1-based display number (for the
//  in-room HUD and the Level-Select tiles), and the "next to play" room (the first
//  unsolved room, which Level Select marks with the single muted accent — D-060).
//
//  This list lived as a `private static` inside `ContentView` through 3.02 (the interim
//  debug `Next` cycle). Phase 3.03 lifts it here so room order/identity is one shared,
//  unit-testable value — Level Select, the Room screen, the win overlay, and the tests
//  all read it, rather than each carrying a parallel numbering (brief §Context).
//
//  Pure data + pure functions: the room id is a plain `String` (the existing identifier
//  type — also the `Levels/<id>.json` base name and the `Echo`/`Level` id), so this adds
//  no new identity type. `nonisolated` like every other value type in the project, so it
//  stays usable from any context and from the headless test harness even though the app
//  builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (D-013).
//

/// The campaign's rooms and the pure order/identity helpers over them. There is
/// **no unlock gating** (D-060): every room is always selectable; `firstUnsolved` only
/// drives the Level-Select accent hint, never a lock.
nonisolated enum Campaign {
    /// The full campaign in play order: the ten teaching rooms (Phase 1.08), the ten
    /// Part-3 campaign rooms (Phase 3.01), and the Part-4 "strategic / relocating echo"
    /// band (rooms 21–25, Phase 4.02 — the wait action's payoff; D-069). Index `i` ⇒
    /// display number `i + 1`. This is the one ordering; everything else derives from it.
    static let roomIDs: [String] = [
        "room-01", "room-02", "room-03", "room-04", "room-05",
        "room-06", "room-07", "room-08", "room-09", "room-10",
        "room-11", "room-12", "room-13", "room-14", "room-15",
        "room-16", "room-17", "room-18", "room-19", "room-20",
        "room-21", "room-22", "room-23", "room-24", "room-25",
    ]

    /// Whether `id` is a real campaign room.
    static func contains(_ id: String) -> Bool {
        roomIDs.contains(id)
    }

    /// The position of `id` in play order, or `nil` if it is not a campaign room.
    static func index(of id: String) -> Int? {
        roomIDs.firstIndex(of: id)
    }

    /// The 1-based display number of `id` (room-01 → 1 … room-20 → 20), or `nil` if it
    /// is not a campaign room. The in-room HUD and the Level-Select tiles show this.
    static func number(of id: String) -> Int? {
        index(of: id).map { $0 + 1 }
    }

    /// The room after `id` in play order, or `nil` when `id` is the **last** room (or is
    /// not a campaign room). The win overlay's "Next room" uses this; a `nil` is the
    /// final-room "Campaign complete" case (brief §Overlay spec).
    static func next(after id: String) -> String? {
        guard let i = index(of: id), i + 1 < roomIDs.count else { return nil }
        return roomIDs[i + 1]
    }

    /// The first room in play order not in `solved` — the single "next to play" room
    /// Level Select tints with the muted accent — or `nil` if every room is solved (then
    /// no tile is accented). Pure over a plain set so it is trivially unit-testable
    /// (D-060/D-061).
    static func firstUnsolved(solved: Set<String>) -> String? {
        roomIDs.first { !solved.contains($0) }
    }
}
