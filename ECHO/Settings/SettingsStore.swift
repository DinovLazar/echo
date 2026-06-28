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
}
