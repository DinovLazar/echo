//
//  HapticsManager.swift
//  ECHO
//
//  Phase 2.05 (Haptics). The touch-feedback layer for ECHO: a light tick on every
//  committed step, a weightier tap when you fold, a soft error buzz when an echo or
//  hazard catches you, and a success tap when you solve a room. It maps the four game
//  events that already exist in the engine (committed step, committed fold,
//  collision/restart, win) to the four system `UIFeedbackGenerator` signals.
//
//  Architecture (D-049): a self-contained `@MainActor` service owning the three
//  system feedback generators — `UISelectionFeedbackGenerator` (the step tick),
//  `UIImpactFeedbackGenerator(style: .medium)` (the fold), and one
//  `UINotificationFeedbackGenerator` (`.error` for a collision, `.success` for a win).
//  These are the right tool for discrete, semantic feedback that the system itself
//  matches to the device's Taptic Engine and to the user's system haptics setting.
//
//  Deliberately NOT a `CHHapticEngine` (out of scope, D-049): custom, audio-synced
//  `CHHapticPattern`s — taps shaped to the generative audio (2.04) and the fold/death
//  choreography (2.03) — are a later tuning pass. There is nothing to gain from
//  standing up a haptic engine to play system-equivalent taps now, and `CoreHaptics`
//  is not even imported here. `UIFeedbackGenerator` already degrades to a safe no-op
//  on hardware without a Taptic Engine (and in the Simulator), so no capability query
//  is needed — the four methods can never crash, they simply do nothing where haptics
//  are unavailable.
//
//  Graceful degradation also covers the toolchain: `UIKit` does not exist on macOS, so
//  the whole UIKit surface is behind `#if canImport(UIKit)`. Off-iOS (the no-Xcode dev
//  env's macOS type-check, or any non-UIKit platform) the type compiles to a pure
//  no-op skeleton — the public API is identical, the bodies do nothing — which keeps
//  the rest of the app type-checking against the macOS SDK exactly as `AudioManager`'s
//  iOS-only `AVAudioSession` config does.
//
//  `var isEnabled` gates ALL output, pre-warming included. Default `true`. This is the
//  single Settings hook (Phase 2.06 binds a real, persisted toggle to it); flipping it
//  off makes every method an immediate no-op. No toggle UI or persistence is built here.
//
//  Pairing & ownership: `ContentView` owns this (an `@State`, exactly like the
//  `AudioManager`) and pre-warms it at launch; `BoardView` fires it from the same
//  `commitMove`/`triggerFold` paths that already fire the audio and the motion, so each
//  tap lands with its visible state change. The step and fold taps also coincide with
//  their sounds; the collision and win taps fire at the moment of contact/commit, a
//  beat before their (deliberately delayed) sounds — a system tap can't be host-time
//  scheduled the way an audio buffer can, and firing at contact is the better feel.
//

#if canImport(UIKit)
import UIKit
#endif

/// Owns the system feedback generators and exposes four semantic taps — `step()`,
/// `fold()`, `collision()`, `win()`. Created and pre-warmed at app launch
/// (`ContentView`) and kept for the session so the first tap has no Taptic-Engine
/// spin-up latency. Every method is a safe no-op when `isEnabled` is false or when the
/// hardware has no haptics.
@MainActor
final class HapticsManager {
    /// Gates **all** output, pre-warming included. Default `true`. The only Settings
    /// hook — Phase 2.06 binds a real, persisted toggle to it; nothing else changes
    /// here. When `false`, every method returns immediately.
    var isEnabled: Bool = true

    #if canImport(UIKit)
    /// The committed-step tick (`selectionChanged()`): the lightest, most neutral tap,
    /// matching a single quiet grid step.
    private let selection = UISelectionFeedbackGenerator()
    /// The fold tap (`impactOccurred()`): a weightier medium impact for the meta-verb,
    /// landing with the §6c fold choreography (hit-pause → ripple → echo peel).
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    /// Collision (`.error`) and win (`.success`) both ride this one notification
    /// generator — the system gives each its own distinct, recognisable pattern.
    private let notification = UINotificationFeedbackGenerator()
    #endif

    init() {}

    /// Pre-warm all three generators so the first real tap has no Taptic-Engine
    /// spin-up latency. Called when the board appears; safe to call repeatedly. A
    /// no-op when `isEnabled` is false or haptics are unsupported (UIKit absent).
    func prepare() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        selection.prepare()
        impact.prepare()
        notification.prepare()
        #endif
    }

    /// A committed **step** — a light selection tick. Re-`prepare()`s right after
    /// firing, since the system lets the Taptic Engine idle between events, so a rapid
    /// next step stays latency-free.
    func step() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        selection.selectionChanged()
        selection.prepare()
        #endif
    }

    /// A committed **fold** — a medium impact. Re-`prepare()`s for the next fold.
    func fold() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        impact.impactOccurred()
        impact.prepare()
        #endif
    }

    /// A **collision / restart** (you touched an echo or hazard) — a soft error
    /// notification. Re-`prepare()`s for the next event.
    func collision() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.error)
        notification.prepare()
        #endif
    }

    /// A **win** (you reached the exit alive) — a success notification.
    /// Re-`prepare()`s for the next event.
    func win() {
        guard isEnabled else { return }
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        notification.prepare()
        #endif
    }
}
