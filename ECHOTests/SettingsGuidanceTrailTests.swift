//
//  SettingsGuidanceTrailTests.swift
//  ECHOTests
//
//  Phase 2.06 (Settings, persistence, the echo-trail aid & the guidance microcopy).
//  Additive coverage for the phase's pure / persisted helpers — the parts that can be
//  verified without a screen:
//    • `SettingsStore` — the documented defaults and the `UserDefaults` round-trip.
//    • `GuidanceController` — the room→hint mapping and the seen-once gate (a one-time
//      hint fires once ever, persisted across instances), plus the recurring caption.
//    • `Echo.upcomingCells(start:turn:)` — the echo-trail aid's upcoming-path cell list.
//
//  These join the deterministic-logic suite; they touch no engine rule. `SettingsStore`
//  and `GuidanceController` are `@MainActor`, so the case is `@MainActor` to drive them
//  directly (matching `ECHOTests`). Each test uses its own isolated `UserDefaults`
//  suite, cleared up front, so nothing leaks between tests or from the real app domain.
//

import XCTest
@testable import ECHO

@MainActor
final class SettingsGuidanceTrailTests: XCTestCase {

    /// A fresh, emptied `UserDefaults` suite for one test.
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - SettingsStore: defaults

    /// A store over a never-written suite reports the documented defaults: invert off,
    /// sound on, haptics on, echo-trail off (D-050/D-051).
    func testSettingsDefaultsWhenNothingPersisted() {
        let store = SettingsStore(defaults: freshDefaults("test.settings.defaults"))
        XCTAssertFalse(store.invertEnabled)
        XCTAssertTrue(store.soundEnabled)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertFalse(store.echoTrailEnabled)
    }

    // MARK: - SettingsStore: persistence round-trip

    /// Writing each preference persists it: a second store over the *same* suite reads
    /// back the changed values (a relaunch restores the last state).
    func testSettingsPersistAcrossStoreInstances() {
        let name = "test.settings.roundtrip"
        let defaults = freshDefaults(name)

        let writer = SettingsStore(defaults: defaults)
        writer.invertEnabled = true       // flip every preference off its default
        writer.soundEnabled = false
        writer.hapticsEnabled = false
        writer.echoTrailEnabled = true

        let reader = SettingsStore(defaults: defaults)
        XCTAssertTrue(reader.invertEnabled)
        XCTAssertFalse(reader.soundEnabled)
        XCTAssertFalse(reader.hapticsEnabled)
        XCTAssertTrue(reader.echoTrailEnabled)
    }

    /// Each setter writes through to its `UserDefaults` key immediately (not only on a
    /// later read), so the persisted domain reflects the live preference.
    func testSettingsWriteThroughToDefaultsKeys() {
        let name = "test.settings.writethrough"
        let defaults = freshDefaults(name)
        let store = SettingsStore(defaults: defaults)

        store.echoTrailEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "settings.echoTrailEnabled"))
        store.soundEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "settings.soundEnabled"))
    }

    // MARK: - GuidanceController: room → hint mapping

    /// The locked arc (D-033): room-01 teaches the move, room-03 the first required
    /// fold, room-06 the first enemy; every other room teaches nothing.
    func testHintMappingMatchesTheTeachingArc() {
        XCTAssertEqual(GuidanceHint.forRoom("room-01"), .swipeToMove)
        XCTAssertEqual(GuidanceHint.forRoom("room-03"), .foldToKeepDoorOpen)
        XCTAssertEqual(GuidanceHint.forRoom("room-06"), .bewareItBites)
        XCTAssertNil(GuidanceHint.forRoom("room-02"))
        XCTAssertNil(GuidanceHint.forRoom("room-10"))
        XCTAssertNil(GuidanceHint.forRoom("not-a-room"))
    }

    /// The four designed strings are reproduced verbatim (exact casing/punctuation). The
    /// fifth, unwired `blockedByGhost` string was removed in Phase 3.03 (D-056
    /// follow-through), so it is no longer asserted.
    func testGuidanceStringsAreVerbatim() {
        XCTAssertEqual(GuidanceHint.swipeToMove.text, "swipe to move")
        XCTAssertEqual(GuidanceHint.foldToKeepDoorOpen.text, "fold to keep the door open")
        XCTAssertEqual(GuidanceHint.bewareItBites.text, "beware — it bites")
        XCTAssertEqual(GuidanceFeedback.eaten, "you got eaten")
    }

    // MARK: - GuidanceController: seen-once gate

    /// A one-time hint is consumed exactly once: the first `consumeHint` for its room
    /// returns it (and marks it seen); a second returns `nil`.
    func testConsumeHintFiresOnceEver() {
        let controller = GuidanceController(defaults: freshDefaults("test.guidance.once"))
        XCTAssertFalse(controller.hasSeen(.swipeToMove))
        XCTAssertEqual(controller.consumeHint(forRoom: "room-01"), .swipeToMove)
        XCTAssertTrue(controller.hasSeen(.swipeToMove))
        XCTAssertNil(controller.consumeHint(forRoom: "room-01"))   // already shown
    }

    /// A room with no hint never marks anything seen and returns `nil`.
    func testConsumeHintNilForRoomWithoutHint() {
        let controller = GuidanceController(defaults: freshDefaults("test.guidance.nohint"))
        XCTAssertNil(controller.consumeHint(forRoom: "room-02"))
    }

    /// "Seen" persists across controller instances over the same suite — a returning
    /// player is never re-taught.
    func testSeenPersistsAcrossControllers() {
        let name = "test.guidance.persist"
        let defaults = freshDefaults(name)

        let first = GuidanceController(defaults: defaults)
        XCTAssertEqual(first.consumeHint(forRoom: "room-06"), .bewareItBites)

        let second = GuidanceController(defaults: defaults)
        XCTAssertTrue(second.hasSeen(.bewareItBites))
        XCTAssertNil(second.consumeHint(forRoom: "room-06"))
    }

    // MARK: - GuidanceController: message triggers

    /// `enterRoom` sets a one-time-hint message the first time, then nothing on a
    /// re-enter of the same room.
    func testEnterRoomPresentsHintOnceThenStaysSilent() {
        let name = "test.guidance.enter"
        let defaults = freshDefaults(name)

        let controller = GuidanceController(defaults: defaults)
        XCTAssertNil(controller.message)
        controller.enterRoom("room-01")
        XCTAssertEqual(controller.message?.text, "swipe to move")
        XCTAssertEqual(controller.message?.category, .hint)

        // A new session (same suite, hint already seen) shows nothing for that room.
        let returning = GuidanceController(defaults: defaults)
        returning.enterRoom("room-01")
        XCTAssertNil(returning.message)
    }

    /// `showEaten` sets the recurring feedback caption, and re-firing it is a fresh
    /// message identity (so the overlay re-animates).
    func testShowEatenPresentsFeedbackAndReFiresWithNewIdentity() {
        let controller = GuidanceController(defaults: freshDefaults("test.guidance.eaten"))
        controller.showEaten()
        XCTAssertEqual(controller.message?.text, "you got eaten")
        XCTAssertEqual(controller.message?.category, .feedback)
        let firstID = controller.message?.id

        controller.showEaten()
        XCTAssertEqual(controller.message?.text, "you got eaten")
        XCTAssertNotEqual(controller.message?.id, firstID)   // new identity each fire
    }

    // MARK: - Echo upcoming-path (the echo-trail aid's cell list)

    private let run: [Direction] = [.up, .right, .right, .down]

    /// From turn 0 the upcoming cells are the whole recorded path (turns 1…count);
    /// from a mid-turn they are the remaining tail; once exhausted they are empty.
    func testUpcomingCellsListsRemainingRecordedPath() {
        let start = GridCoordinate(row: 3, column: 3)
        let echo = Echo(moves: run)   // (3,3)→(2,3)→(2,4)→(2,5)→(3,5)

        XCTAssertEqual(echo.upcomingCells(start: start, turn: 0),
                       [GridCoordinate(row: 2, column: 3),
                        GridCoordinate(row: 2, column: 4),
                        GridCoordinate(row: 2, column: 5),
                        GridCoordinate(row: 3, column: 5)])

        XCTAssertEqual(echo.upcomingCells(start: start, turn: 2),
                       [GridCoordinate(row: 2, column: 5),
                        GridCoordinate(row: 3, column: 5)])

        XCTAssertEqual(echo.upcomingCells(start: start, turn: 3),
                       [GridCoordinate(row: 3, column: 5)])
    }

    /// An exhausted echo (at or past its last move) and a zero-length echo have no
    /// upcoming path — so the aid draws no dots and never repeats a standing-still tile.
    func testUpcomingCellsEmptyWhenExhaustedOrStationary() {
        let start = GridCoordinate(row: 3, column: 3)
        let echo = Echo(moves: run)
        XCTAssertTrue(echo.upcomingCells(start: start, turn: run.count).isEmpty)      // exactly exhausted
        XCTAssertTrue(echo.upcomingCells(start: start, turn: run.count + 5).isEmpty)  // long past
    }

    /// Every cell in the upcoming list is a distinct step from the one before it (a
    /// `Direction` always moves to an adjacent tile, and the list stops at `moves.count`
    /// before any standing-still repeat), so the trail never carries trailing duplicates.
    func testUpcomingCellsHaveNoConsecutiveDuplicates() {
        let start = GridCoordinate(row: 4, column: 0)
        let echo = Echo(moves: [.up, .up, .right, .down, .down, .left])
        let cells = echo.upcomingCells(start: start, turn: 0)
        for i in 1..<cells.count {
            XCTAssertNotEqual(cells[i], cells[i - 1])
        }
    }
}
