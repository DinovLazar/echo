//
//  SettingsStore.swift
//  ECHO
//
//  Phase 2.06 (Settings, persistence, the echo-trail aid & the guidance microcopy).
//  The single, persisted source of truth for the four user preferences this phase
//  gives a real home: **Invert** (palette), **Sound**, **Haptics**, and the **Echo
//  trail** aid. It is `UserDefaults`-backed so a relaunch restores the last state.
//
//  The three switch points already existed before this phase — the `\.theme`
//  environment seam (Theme.swift), `AudioManager.isEnabled`, and
//  `HapticsManager.isEnabled` — but had no UI, no persistence, and no single owner.
//  This store is that owner (D-050): `ContentView` holds it (`@State`, exactly like it
//  holds `audio`/`haptics`) and drives the three seams from it, while `SettingsView`
//  edits it. The fourth preference, the echo trail, is new this phase (D-051).
//
//  Defaults (D-050/D-051): invert **off** (Light is the resting palette), sound **on**,
//  haptics **on**, echo-trail **off** (a clean board is the resting look — the trail is
//  an opt-in clarity aid).
//
//  Phase 3.02 adds the **Echo Run high score** — the designated second `UserDefaults`
//  value (Plan §6). It rides this same wrapper rather than a second persistence system
//  (D-058): a stored `Int` (default 0) plus `recordEchoRunScore(_:)`, the keep-the-best
//  comparison the arcade mode calls on death. The `Bool` preference shape is unchanged.
//
//  Phase 3.03 adds the **solved-rooms set** — the campaign save data Level Select reads
//  to mark solved rooms and write on a win (D-061). It rides this same wrapper too (one
//  persistence system, exactly as the high score did — not a second store): the solved
//  subset of `Campaign.roomIDs` (the existing `String` room identifier) persisted as a
//  `[String]` under one key, exposed as `markSolved(_:)` / `isSolved(_:)` and the
//  `solvedRooms` read accessor. The four `Bool` preferences and the high score are
//  unchanged.
//
//  Persistence shape: each preference is a stored `Bool` loaded from its key in `init`
//  (with the documented default when the key is absent) and written back through a
//  `didSet`, so there is one in-memory source of truth that is mirrored to
//  `UserDefaults` on every change. `@Observable` so SwiftUI re-renders the moment a
//  toggle flips (the board flips palette live, the managers re-gate live). `@MainActor`
//  to match the manager/owner pattern (D-013); `UserDefaults` is injectable so the
//  persistence round-trip and the defaults are unit-testable headlessly.
//

import Foundation
import Observation

/// The four persisted user preferences. The single source of truth `ContentView` owns
/// and `SettingsView` edits; every property reads its key at launch and writes it on
/// change, so the last state survives a relaunch.
@MainActor
@Observable
final class SettingsStore {
    /// Stable `UserDefaults` keys. Namespaced so they never collide with a future
    /// save-data key (Part 3).
    private enum Key {
        static let invert = "settings.invertEnabled"
        static let sound = "settings.soundEnabled"
        static let haptics = "settings.hapticsEnabled"
        static let echoTrail = "settings.echoTrailEnabled"
        static let echoRunHighScore = "echoRun.highScore"
        static let solvedRooms = "campaign.solvedRooms"
    }

    /// Invert palette. Default **false** — Light is the default palette (D-050).
    var invertEnabled: Bool { didSet { defaults.set(invertEnabled, forKey: Key.invert) } }
    /// Generative audio. Default **true**; mirrors `AudioManager.isEnabled` (D-050).
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    /// Haptic feedback. Default **true**; mirrors `HapticsManager.isEnabled` (D-050).
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    /// The echo-trail aid. Default **false** — an opt-in clarity aid; a clean board is
    /// the resting look (D-051).
    var echoTrailEnabled: Bool { didSet { defaults.set(echoTrailEnabled, forKey: Key.echoTrail) } }

    /// The best Echo Run score so far (turns survived). Default **0** — the designated
    /// second `UserDefaults` value (Plan §6 / Phase 3.02), persisted through this same
    /// wrapper rather than a separate store (D-058). Written through on change like the
    /// preferences above; updated via `recordEchoRunScore(_:)`.
    var echoRunHighScore: Int { didSet { defaults.set(echoRunHighScore, forKey: Key.echoRunHighScore) } }

    /// The campaign rooms the player has solved (the solved subset of `Campaign.roomIDs`).
    /// Default **empty** — a fresh save has nothing solved (Phase 3.03 / D-061). Persisted
    /// as a `[String]` through this same wrapper rather than a separate save file (one
    /// persistence system, like the high score — D-058). Read by Level Select; written
    /// only through `markSolved(_:)` so a redundant write is avoided (`private(set)`).
    private(set) var solvedRooms: Set<String> { didSet { defaults.set(Array(solvedRooms), forKey: Key.solvedRooms) } }

    /// The backing store. Not observed (it is plumbing, not state); injectable so tests
    /// can use an isolated suite.
    @ObservationIgnored private let defaults: UserDefaults

    /// Load each preference from its key, falling back to the documented default when
    /// the key has never been written (a `nil` `object(forKey:)`). Assigning in `init`
    /// does **not** fire the `didSet`s, so the load never redundantly writes back.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.invertEnabled = defaults.object(forKey: Key.invert) as? Bool ?? false
        self.soundEnabled = defaults.object(forKey: Key.sound) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        self.echoTrailEnabled = defaults.object(forKey: Key.echoTrail) as? Bool ?? false
        self.echoRunHighScore = defaults.object(forKey: Key.echoRunHighScore) as? Int ?? 0
        self.solvedRooms = Set(defaults.stringArray(forKey: Key.solvedRooms) ?? [])
    }

    /// Record an Echo Run score, keeping it only if it beats the stored best. Returns
    /// whether it was a new high score (so the game-over screen can mark it). The single
    /// persistence point for the arcade high score — the arcade engine stays pure and
    /// the view calls this on death (D-058).
    @discardableResult
    func recordEchoRunScore(_ score: Int) -> Bool {
        guard score > echoRunHighScore else { return false }
        echoRunHighScore = score
        return true
    }

    // MARK: - Campaign solved-rooms (Phase 3.03 / D-061)

    /// Whether `roomID` has been solved.
    func isSolved(_ roomID: String) -> Bool {
        solvedRooms.contains(roomID)
    }

    /// Record `roomID` as solved (called when the player reaches a room's exit).
    /// Idempotent: marking an already-solved room is a no-op and never writes again, so
    /// re-solving a room costs nothing and never re-fires observers.
    func markSolved(_ roomID: String) {
        guard !solvedRooms.contains(roomID) else { return }
        solvedRooms.insert(roomID)
    }
}
