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
    /// The echo-trail's toggle-off fade — `150 ms`, `curve.easeIn` (handover §6f). Used
    /// when the aid is switched off, before the dots stop rendering (Phase 2.06).
    static let trailFadeOut = Curve.easeIn(0.150)
    /// `motion.denyShake` — `260 ms`, `curve.decayShake`.
    static let denyShake = Curve.decayShake
    /// `motion.guidanceIn` — `200 ms`, `curve.easeOut`.
    static let guidanceIn = Curve.easeOut(0.200)
    /// `motion.guidanceOut` — `350 ms`, `curve.easeIn`.
    static let guidanceOut = Curve.easeIn(0.350)
}

// MARK: - Phase durations (seconds) for the Canvas-driven effect layer (2.03)

extension Motion {
    /// The handover §1c durations as raw seconds. The fold/death choreography
    /// (Phase 2.03) is advanced by *elapsed time* inside a `TimelineView`/`Canvas`
    /// rather than by a baked SwiftUI `Animation`, so it needs the numbers, not the
    /// curve values above. These are the *same* §1c values — kept here, beside the
    /// `Animation` tokens, so no magic timing number is scattered through the view.
    nonisolated enum Span {
        /// `motion.foldHitPause` — the board-still beat at the instant of a fold
        /// (§6c, 3 frames @60fps).
        static let foldHitPause: TimeInterval = 0.050
        /// `motion.foldRipple` — the grid ripple radiating from the fold cell (§6c).
        static let foldRipple: TimeInterval = 0.220
        /// `motion.foldPeel` — the new echo peeling off the player (§6c).
        static let foldPeel: TimeInterval = 0.180

        /// `motion.deathFreeze` — the calm hold at the instant of contact (§6d,
        /// 4 frames @60fps).
        static let deathFreeze: TimeInterval = 0.066
        /// `motion.deathFizz` — the soft particle dissolve (§6d).
        static let deathFizz: TimeInterval = 0.320
        /// The red-vignette flash that rises and falls alongside the fizz (§6d,
        /// "~200 ms").
        static let deathVignette: TimeInterval = 0.200

        /// The fatal step's glide onto the contact tile. A fatal move is still a
        /// move, so it slides like any other step (`motion.step`, §6b) before the
        /// death beats begin — the project never teleports a piece (Plan §5). The
        /// death-specific beats above keep their own §6d numbers.
        static let step: TimeInterval = 0.120

        // --- Phase 2.06: echo-trail fade + guidance microcopy (§6f / §6) ---

        /// `motion.trailReveal`/off as raw seconds. The toggle-off fade length the
        /// echo-trail layer holds for before it stops rendering (§6f, 150 ms easeIn).
        static let trailFade: TimeInterval = 0.150

        /// The guidance microcopy fade-in / fade-out lengths as raw seconds, so the
        /// overlay (which times its linger with `Task.sleep`, not a baked `Animation`)
        /// reads the same §6 numbers the `Motion.guidanceIn`/`guidanceOut` curves use.
        static let guidanceIn: TimeInterval = 0.200
        static let guidanceOut: TimeInterval = 0.350
        /// `motion.guidanceLingerHint` — one-time hints hold for 2200 ms (§6).
        static let guidanceLingerHint: TimeInterval = 2.2
        /// `motion.guidanceLingerFeedback` — recurring feedback holds for 1600 ms (§6).
        static let guidanceLingerFeedback: TimeInterval = 1.6
    }
}

// MARK: - Scalar easing for the Canvas effect layer

/// The named §6a curves as **scalar** easings (input/output both in `0…1`), for the
/// Canvas effect layer that advances by elapsed time. Each evaluates the exact same
/// cubic Bézier the matching `Curve` `Animation` uses, so a canvas-driven effect and
/// a `withAnimation` one share the handover's curve shape. `nonisolated` to match the
/// rest of the token layer (D-013/D-040).
nonisolated enum Ease {
    /// Symmetric ease-in-out — `curve.standard` `(0.42, 0, 0.58, 1)`.
    static func standard(_ t: Double) -> Double { bezier(0.42, 0.0, 0.58, 1.0, t) }
    /// Decelerate-in — `curve.easeOut` `(0, 0, 0.2, 1)`.
    static func easeOut(_ t: Double) -> Double { bezier(0.0, 0.0, 0.2, 1.0, t) }
    /// Accelerate-out — `curve.easeIn` `(0.4, 0, 1, 1)`.
    static func easeIn(_ t: Double) -> Double { bezier(0.4, 0.0, 1.0, 1.0, t) }

    /// Evaluate a cubic-Bézier easing with implicit endpoints `P0 = (0,0)`,
    /// `P3 = (1,1)` at time fraction `t`: solve `x(u) = t` for the Bézier parameter
    /// `u` (binary search — monotone in `x` for these control points), then return
    /// `y(u)`. Cheap and deterministic.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        // One axis of the Bézier at parameter `u` (P0 and P3 components are 0 and 1).
        func axis(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let mu = 1 - u
            return 3 * mu * mu * u * a + 3 * mu * u * u * b + u * u * u
        }
        var lo = 0.0, hi = 1.0, u = x
        for _ in 0..<24 {
            let cx = axis(x1, x2, u)
            if abs(cx - x) < 1e-5 { break }
            if cx < x { lo = u } else { hi = u }
            u = (lo + hi) * 0.5
        }
        return axis(y1, y2, u)
    }
}
