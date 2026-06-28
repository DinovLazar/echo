//
//  GuidanceController.swift
//  ECHO
//
//  Phase 2.06 (Settings, persistence, the echo-trail aid & the guidance microcopy).
//  The model behind the guidance-message system (handover §6): it decides *what*
//  message is on screen and drives the seen-once persistence for the one-time hints.
//  The *look* and the fade timing live in `GuidanceOverlay` (the SwiftUI view this
//  feeds); this type stays Foundation-only so its room→hint mapping and its
//  seen-once gate are pure and unit-testable headlessly.
//
//  Five strings, two timing categories (D-042/D-052; handover §6):
//    • One-time hints (linger 2200 ms) — shown **once ever** the first time the
//      situation is relevant; a returning player is never re-taught (persisted in
//      `UserDefaults`). `swipe to move` / `fold to keep the door open` /
//      `beware — it bites`, mapped to room-01 / room-03 / room-06 (D-033 arc).
//    • Recurring feedback (linger 1600 ms) — shown **every time** it happens.
//      `you got eaten` is wired to every death dissolve. `you can't go there — your
//      ghost is` ships in the set but is **left unwired** this phase: its trigger is a
//      *refused* move into an echo, which needs the still-open block-vs-bite gameplay
//      rule (touching an echo is currently a death, not a refusal — D-016/D-018), an
//      engine decision out of this presentation-only part (D-052).
//
//  Ownership mirrors the managers (D-050): `ContentView` owns this (`@State`) and tells
//  it the active room on launch and on each `loadNextRoom`; `BoardView` reads `message`
//  through the injected reference and fires `showEaten()` from its death path.
//  `@MainActor @Observable` like the other owned services; `UserDefaults` injectable so
//  the seen-once gate is testable in isolation.
//

import Foundation
import Observation

/// The three one-time teaching hints. Each maps to the first room where its lesson is
/// relevant and is shown exactly once ever. `nonisolated`/`Sendable` like every other
/// pure value type in the project, so it stays usable from any context (D-013/D-040).
nonisolated enum GuidanceHint: String, CaseIterable, Sendable {
    case swipeToMove
    case foldToKeepDoorOpen
    case bewareItBites

    /// The verbatim on-screen string (handover §6 — final, do not reword/re-case).
    var text: String {
        switch self {
        case .swipeToMove: "swipe to move"
        case .foldToKeepDoorOpen: "fold to keep the door open"
        case .bewareItBites: "beware — it bites"
        }
    }

    /// The stable `UserDefaults` key that marks this hint as shown-once-ever.
    var seenKey: String { "guidance.seen.\(rawValue)" }

    /// The hint taught on a given room's first appearance, or `nil` if the room teaches
    /// no hint. The arc is locked by D-033: room-01 is the move room, room-03 is the
    /// first room a fold is required, room-06 is the first room with the red enemy.
    static func forRoom(_ roomID: String) -> GuidanceHint? {
        switch roomID {
        case "room-01": .swipeToMove
        case "room-03": .foldToKeepDoorOpen
        case "room-06": .bewareItBites
        default: nil
        }
    }
}

/// The recurring-feedback strings (handover §6 — verbatim).
nonisolated enum GuidanceFeedback {
    /// The only failure caption in the designed set — fired on **every** death
    /// dissolve, echo or hazard alike (D-052).
    static let eaten = "you got eaten"
    /// Ships in the string set but is **unwired** this phase: its trigger is a refused
    /// move into an echo, which depends on the unresolved block-vs-bite gameplay rule
    /// (D-052). Kept here as the fifth designed string, verbatim, so a future
    /// engine/gameplay phase can wire it (and the §8.1 deny-shake) with no new copy.
    static let blockedByGhost = "you can't go there — your ghost is"
}

/// Whether a message holds for the one-time-hint linger or the recurring-feedback
/// linger (handover §6). The concrete durations are applied by `GuidanceOverlay`.
nonisolated enum GuidanceCategory: Sendable {
    case hint
    case feedback
}

/// One message to render. `id` is a monotonic generation, so re-firing the *same*
/// text (e.g. `you got eaten` twice in a row) is a new identity and re-triggers the
/// overlay's fade. `nonisolated`/`Sendable` like the other value types (D-013).
nonisolated struct GuidanceMessage: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let category: GuidanceCategory
}

/// Drives the on-board guidance message and the one-time-hint seen-once persistence.
@MainActor
@Observable
final class GuidanceController {
    /// The message the overlay should render, or `nil` before anything has fired. Set
    /// by `enterRoom`/`showEaten`; observed by `GuidanceOverlay`.
    private(set) var message: GuidanceMessage?

    /// Backing store for the seen-once flags. Not observed (plumbing); injectable for
    /// tests.
    @ObservationIgnored private let defaults: UserDefaults
    /// Monotonic message id, so every fire is a fresh identity.
    @ObservationIgnored private var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Seen-once gate (pure-ish; the testable core)

    /// Whether this one-time hint has already been shown.
    func hasSeen(_ hint: GuidanceHint) -> Bool {
        defaults.bool(forKey: hint.seenKey)
    }

    /// The hint to teach on this room's first appearance, marking it seen as it does —
    /// or `nil` if the room teaches no hint or its hint has already been shown. This is
    /// the seen-once gate, factored out so it can be unit-tested without any UI.
    func consumeHint(forRoom roomID: String) -> GuidanceHint? {
        guard let hint = GuidanceHint.forRoom(roomID), !hasSeen(hint) else { return nil }
        defaults.set(true, forKey: hint.seenKey)
        return hint
    }

    // MARK: - Triggers (presentation events; no engine change)

    /// Notify the controller of the active room (called on launch and on each room
    /// load). Fires that room's one-time hint if it has not been shown before; a room
    /// with no hint, or an already-seen hint, shows nothing.
    func enterRoom(_ roomID: String) {
        guard let hint = consumeHint(forRoom: roomID) else { return }
        present(hint.text, category: .hint)
    }

    /// The recurring death caption — fired from `BoardView`'s death path on **every**
    /// death dissolve (D-052).
    func showEaten() {
        present(GuidanceFeedback.eaten, category: .feedback)
    }

    private func present(_ text: String, category: GuidanceCategory) {
        generation += 1
        message = GuidanceMessage(id: generation, text: text, category: category)
    }
}
