//
//  Motion.swift
//  ECHO
//
//  Phase 2.02 (The board's real look + motion). The five named easing curves from
//  the Phase 2.01 handover (§6a), as reusable SwiftUI `Animation`s with the exact
//  control points / spring parameters given, plus the handover's motion *tokens*
//  (§1c) built from those curves at their specified durations.
//
//  A bezier `timingCurve` bakes in a duration, so the four cubic curves are exposed
//  as duration-parameterised factories (`Curve.standard(_:)`, …) — the *shape* is
//  fixed by the control points, the *duration* is chosen per use. `decayShake` is a
//  decaying back-and-forth, so per the handover it is a spring, not a bezier. The
//  `Motion` tokens are the ready-to-use values the board actually animates with.
//
//  Only the values this phase uses (step / enemy step / soft-snap settle) are wired
//  into `BoardView`; the rest (fold, death, deny-shake, guidance, trail) are defined
//  here so the later phases that own those beats (2.03+) can use them without
//  re-deriving the numbers. Marked `nonisolated` to match the rest of the token
//  layer (D-013/D-040).
//

import SwiftUI

/// The five named easing curves (handover §6a). The four cubic curves take a
/// duration; `decayShake` is a spring.
nonisolated enum Curve {
    /// Symmetric ease-in-out — the default board move. Control points `(0.42, 0, 0.58, 1)`.
    static func standard(_ duration: Double) -> Animation {
        .timingCurve(0.42, 0.0, 0.58, 1.0, duration: duration)
    }

    /// Decelerate-in — reveals, ripples, fizz. Control points `(0, 0, 0.2, 1)`.
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.0, 0.0, 0.2, 1.0, duration: duration)
    }

    /// Accelerate-out — fade-outs. Control points `(0.4, 0, 1, 1)`.
    static func easeIn(_ duration: Double) -> Animation {
        .timingCurve(0.4, 0.0, 1.0, 1.0, duration: duration)
    }

    /// Tiny overshoot (control point y > 1) for the arrival settle. Control points
    /// `(0.2, 0.9, 0.3, 1.06)`.
    static func softSnap(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.9, 0.3, 1.06, duration: duration)
    }

    /// Damped oscillation for the deny-shake (handover §6a note: prefer an
    /// interpolating spring over a bezier — it is a decaying back-and-forth, not a
    /// monotonic ease). `stiffness: 320, damping: 14`.
    static let decayShake: Animation = .interpolatingSpring(stiffness: 320, damping: 14)
}

/// The handover's motion tokens (§1c) as concrete `Animation` values, built from the
/// named curves at their specified durations. Durations are in seconds (the handover
/// states them in ms).
nonisolated enum Motion {
    /// `motion.step` — the player/echo slide between cells. `120 ms`, `curve.standard`.
    static let step = Curve.standard(0.120)

    /// `motion.stepSnap` — the player's arrival settle. `40 ms`, `curve.softSnap`.
    static let stepSnap = Curve.softSnap(0.040)

    /// `motion.enemyStep` — the enemy/hazard slide, deliberately heavier than the
    /// player. `140 ms`, `curve.standard`.
    static let enemyStep = Curve.standard(0.140)

    // --- Defined for later phases (2.03+); not wired into the board this phase. ---

    /// `motion.foldRipple` — `220 ms`, `curve.easeOut`.
    static let foldRipple = Curve.easeOut(0.220)
    /// `motion.foldPeel` — `180 ms`, `curve.easeOut`.
    static let foldPeel = Curve.easeOut(0.180)
    /// `motion.deathFizz` — `320 ms`, `curve.easeOut`.
    static let deathFizz = Curve.easeOut(0.320)
    /// `motion.trailReveal` — `200 ms`, `curve.easeOut` (per-dot stagger handled at the call site).
    static let trailReveal = Curve.easeOut(0.200)
    /// `motion.denyShake` — `260 ms`, `curve.decayShake`.
    static let denyShake = Curve.decayShake
    /// `motion.guidanceIn` — `200 ms`, `curve.easeOut`.
    static let guidanceIn = Curve.easeOut(0.200)
    /// `motion.guidanceOut` — `350 ms`, `curve.easeIn`.
    static let guidanceOut = Curve.easeIn(0.350)
}
