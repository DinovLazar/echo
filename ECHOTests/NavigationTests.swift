//
//  NavigationTests.swift
//  ECHOTests
//
//  Phase 3.03 (Navigation shell). Deterministic coverage for the parts of the new shell
//  that are testable without a screen — the pure room-order/identity helpers (`Campaign`)
//  and the additive solved-state persistence (`SettingsStore`, D-061). These join the
//  deterministic-logic suite and touch no engine rule.
//
//  Pinned here (brief §Tasks 12):
//    • the solved-state round-trip through `SettingsStore` (mark → persists → reads back),
//      including that marking an already-solved room is idempotent;
//    • next-room computation over `Campaign.roomIDs`, including the final-room boundary
//      (the last room has no next);
//    • the no-gating invariant (D-060) — every room is selectable irrespective of
//      solved-state; solved-state only drives the Level-Select "next to play" accent.
//
//  `SettingsStore` is `@MainActor`, so the case is `@MainActor` to drive it directly
//  (matching the other suites; `Campaign` is `nonisolated` and callable from here).
//  Each persistence test uses its own isolated, pre-cleared `UserDefaults` suite.
//

import XCTest
@testable import ECHO

@MainActor
final class NavigationTests: XCTestCase {

    /// A fresh, emptied `UserDefaults` suite for one test.
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Campaign catalog & ordering

    /// The catalog is the thirty `room-01 … room-30` ids, in zero-padded order.
    func testCampaignCatalogIsThirtyRoomsInOrder() {
        XCTAssertEqual(Campaign.roomIDs.count, 30)
        XCTAssertEqual(Campaign.roomIDs.first, "room-01")
        XCTAssertEqual(Campaign.roomIDs.last, "room-30")
        for (i, id) in Campaign.roomIDs.enumerated() {
            XCTAssertEqual(id, String(format: "room-%02d", i + 1))
        }
        XCTAssertEqual(Set(Campaign.roomIDs).count, 30)   // no duplicates
    }

    /// The 1-based display number maps room-01 → 1 … room-30 → 30; unknown → nil.
    func testRoomNumberMapping() {
        XCTAssertEqual(Campaign.number(of: "room-01"), 1)
        XCTAssertEqual(Campaign.number(of: "room-10"), 10)
        XCTAssertEqual(Campaign.number(of: "room-20"), 20)
        XCTAssertEqual(Campaign.number(of: "room-25"), 25)
        XCTAssertEqual(Campaign.number(of: "room-30"), 30)
        XCTAssertNil(Campaign.number(of: "not-a-room"))
    }

    /// `contains` recognises real rooms (now through room-30) and rejects everything else.
    func testContainsKnownAndUnknownRooms() {
        XCTAssertTrue(Campaign.contains("room-01"))
        XCTAssertTrue(Campaign.contains("room-20"))
        XCTAssertTrue(Campaign.contains("room-25"))
        XCTAssertTrue(Campaign.contains("room-26"))
        XCTAssertTrue(Campaign.contains("room-30"))
        XCTAssertFalse(Campaign.contains("room-31"))
        XCTAssertFalse(Campaign.contains(""))
    }

    // MARK: - Next-room computation (incl. the final-room boundary)

    /// `next(after:)` follows play order — including across the Part-4 band boundaries.
    func testNextRoomFollowsOrder() {
        XCTAssertEqual(Campaign.next(after: "room-01"), "room-02")
        XCTAssertEqual(Campaign.next(after: "room-10"), "room-11")
        XCTAssertEqual(Campaign.next(after: "room-19"), "room-20")
        XCTAssertEqual(Campaign.next(after: "room-20"), "room-21")
        XCTAssertEqual(Campaign.next(after: "room-25"), "room-26")
        XCTAssertEqual(Campaign.next(after: "room-29"), "room-30")
    }

    /// The final room (now room-30) has no next — the win overlay's "Campaign complete" branch.
    func testNextRoomFinalBoundaryIsNil() {
        XCTAssertNil(Campaign.next(after: "room-30"))
    }

    /// An unknown id has no next (never crashes, never wraps).
    func testNextRoomUnknownIsNil() {
        XCTAssertNil(Campaign.next(after: "not-a-room"))
    }

    /// Walking `next(after:)` from room-01 visits the whole campaign exactly once, in
    /// order, then stops — no wrap, no skip, no repeat.
    func testNextRoomWalksTheWholeCampaignThenStops() {
        var id: String? = "room-01"
        var visited: [String] = []
        while let current = id {
            visited.append(current)
            id = Campaign.next(after: current)
        }
        XCTAssertEqual(visited, Campaign.roomIDs)
    }

    // MARK: - First-unsolved (the Level-Select "next to play" accent — D-060)

    /// With nothing solved, the next to play is the first room.
    func testFirstUnsolvedIsRoomOneWhenNothingSolved() {
        XCTAssertEqual(Campaign.firstUnsolved(solved: []), "room-01")
    }

    /// A solved prefix is skipped to the first unsolved room.
    func testFirstUnsolvedSkipsSolvedPrefix() {
        XCTAssertEqual(Campaign.firstUnsolved(solved: ["room-01", "room-02", "room-03"]), "room-04")
    }

    /// "First unsolved" is by play **order**, not insertion order — solving a later room
    /// first does not move the accent off the earliest unsolved room.
    func testFirstUnsolvedRespectsOrderNotInsertion() {
        XCTAssertEqual(Campaign.firstUnsolved(solved: ["room-03", "room-05"]), "room-01")
        XCTAssertEqual(Campaign.firstUnsolved(solved: ["room-01", "room-03"]), "room-02")
    }

    /// With every room solved there is no next to play, so no tile is accented.
    func testFirstUnsolvedIsNilWhenAllSolved() {
        XCTAssertNil(Campaign.firstUnsolved(solved: Set(Campaign.roomIDs)))
    }

    // MARK: - Solved-state persistence (SettingsStore — D-061)

    /// A fresh save has nothing solved.
    func testSolvedDefaultsToEmpty() {
        let store = SettingsStore(defaults: freshDefaults("test.nav.solved.empty"))
        XCTAssertTrue(store.solvedRooms.isEmpty)
        for id in Campaign.roomIDs { XCTAssertFalse(store.isSolved(id)) }
    }

    /// `markSolved` records exactly the marked room; others stay unsolved.
    func testMarkSolvedSetsAndReads() {
        let store = SettingsStore(defaults: freshDefaults("test.nav.solved.mark"))
        XCTAssertFalse(store.isSolved("room-05"))
        store.markSolved("room-05")
        XCTAssertTrue(store.isSolved("room-05"))
        XCTAssertFalse(store.isSolved("room-06"))
        XCTAssertEqual(store.solvedRooms, ["room-05"])
    }

    /// Marking an already-solved room is idempotent — the set is unchanged.
    func testMarkSolvedIsIdempotent() {
        let store = SettingsStore(defaults: freshDefaults("test.nav.solved.idempotent"))
        store.markSolved("room-07")
        store.markSolved("room-07")
        XCTAssertTrue(store.isSolved("room-07"))
        XCTAssertEqual(store.solvedRooms, ["room-07"])
        XCTAssertEqual(store.solvedRooms.count, 1)
    }

    /// Solved rooms round-trip across store instances (a relaunch restores them).
    func testSolvedRoundTripsAcrossStoreInstances() {
        let name = "test.nav.solved.roundtrip"
        let defaults = freshDefaults(name)

        let writer = SettingsStore(defaults: defaults)
        writer.markSolved("room-02")
        writer.markSolved("room-09")
        writer.markSolved("room-20")

        let reader = SettingsStore(defaults: defaults)
        XCTAssertEqual(reader.solvedRooms, ["room-02", "room-09", "room-20"])
        XCTAssertTrue(reader.isSolved("room-02"))
        XCTAssertTrue(reader.isSolved("room-09"))
        XCTAssertTrue(reader.isSolved("room-20"))
        XCTAssertFalse(reader.isSolved("room-01"))
    }

    /// `markSolved` writes through to its `UserDefaults` key immediately.
    func testMarkSolvedWritesThroughToDefaultsKey() {
        let name = "test.nav.solved.writethrough"
        let defaults = freshDefaults(name)
        let store = SettingsStore(defaults: defaults)
        store.markSolved("room-11")
        XCTAssertEqual(Set(defaults.stringArray(forKey: "campaign.solvedRooms") ?? []), ["room-11"])
    }

    /// The solved set does not disturb the four `Bool` preferences or the high score —
    /// it rides the same wrapper additively (D-061).
    func testSolvedStateIsIndependentOfOtherPreferences() {
        let store = SettingsStore(defaults: freshDefaults("test.nav.solved.independent"))
        store.markSolved("room-04")
        XCTAssertFalse(store.invertEnabled)
        XCTAssertTrue(store.soundEnabled)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertFalse(store.echoTrailEnabled)
        XCTAssertEqual(store.echoRunHighScore, 0)
    }

    // MARK: - No gating (D-060): every room selectable regardless of solved-state

    /// A solved room is still a real, openable room — it can be replayed (no gating).
    func testSolvedRoomsRemainSelectable() {
        let store = SettingsStore(defaults: freshDefaults("test.nav.replayable"))
        store.markSolved("room-03")
        XCTAssertTrue(store.isSolved("room-03"))
        XCTAssertTrue(Campaign.contains("room-03"))   // still openable
    }

    /// The selectable set is constant across solved-state — always all thirty rooms. The
    /// only solved-dependent value is the `firstUnsolved` accent hint, which is always
    /// either nil (all solved) or a real catalog room — never a gate.
    func testSelectableSetIsConstantAcrossSolvedState() {
        let none = SettingsStore(defaults: freshDefaults("test.nav.const.none"))
        let some = SettingsStore(defaults: freshDefaults("test.nav.const.some"))
        some.markSolved("room-05"); some.markSolved("room-12"); some.markSolved("room-20")
        let all = SettingsStore(defaults: freshDefaults("test.nav.const.all"))
        for id in Campaign.roomIDs { all.markSolved(id) }

        XCTAssertEqual(Campaign.roomIDs.count, 30)   // the selectable set never shrinks
        for store in [none, some, all] {
            if let next = Campaign.firstUnsolved(solved: store.solvedRooms) {
                XCTAssertTrue(Campaign.contains(next))
            }
        }
        XCTAssertEqual(Campaign.firstUnsolved(solved: none.solvedRooms), "room-01")
        XCTAssertEqual(Campaign.firstUnsolved(solved: some.solvedRooms), "room-01")
        XCTAssertNil(Campaign.firstUnsolved(solved: all.solvedRooms))
    }
}
