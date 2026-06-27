//
//  BoardEffects.swift
//  ECHO
//
//  Phase 2.03 (The fold choreography & the death dissolve). The transient effect
//  layer that rides on top of the steady `BoardView`, giving folding and dying their
//  weight. Presentation only — it reads nothing it can mutate and changes no turn /
//  collision / win / replay outcome; it is handed pre-computed *descriptors* of an
//  event that has already been decided by the engine (or, for a death, that the view
//  is about to ask the engine to perform) and draws the handover's choreography for it.
//
//  Built on **SwiftUI Canvas** (the locked-stack default — no SpriteKit, no new
//  dependency) inside a `TimelineView(.animation)` so it redraws every frame at the
//  display's cadence. The overlay is mounted by `BoardView` only while an effect is
//  in flight (≤ ~0.5 s bursts), so the per-frame clock costs nothing at rest.
//
//  Two events, both from the Phase 2.01 handover:
//    • Fold (§6c): a 50 ms hit-pause, a grid ripple radiating across the hairlines
//      (`motion.foldRipple`), and the new grey echo peeling off the player — born
//      looking like you (ink) and settling to echo grey (`motion.foldPeel`).
//    • Death (§6d): the fatal step glides onto the contact tile (a step is still a
//      step — §6b), a calm freeze (`motion.deathFreeze`), the player and the echo(es)
//      it touched fizzing into ~14 soft particles each (`motion.deathFizz`), and a
//      faint red vignette + one enemy-glow pulse rising and falling over it.
//
//  Every colour comes from the active `Theme` (both palettes), never a literal; the
//  danger red is the D-041 accent and stays red in Light and Invert. Timings/curves
//  come from `Motion.Span` / `Ease` (the §1c / §6a token layer). `nonisolated` on the
//  descriptors matches the model value types (D-013); `Diamond`-style custom `Shape`s
//  are deliberately avoided (D-040) — the canvas draws paths directly.
//

import SwiftUI

// MARK: - Effect descriptors

/// One in-flight **fold** event. Captured at the instant `BoardView` detects a fold
/// (the echo count went up); the board has already rewound to `start`.
nonisolated struct FoldEffect: Identifiable, Sendable {
    /// A monotonic generation, so `BoardView` can key a cleanup `task` on it.
    let id: Int
    /// Where the ripple radiates from and where the peel settles — `GameState.start`
    /// (where the whole board, the player, and every echo sit after a fold).
    let origin: GridCoordinate
    /// The new echo's run-end cell — where present-you stood when you folded. The
    /// peel starts here (ink, player-sized) and slides back to `origin`, so you see
    /// the just-walked run shed itself and rewind into the start stack.
    let peelFrom: GridCoordinate
    /// Identity of the freshly-banked echo, so the steady echo layer hides it while
    /// the overlay owns its peel-in (no double-draw, and the crossfade reads against
    /// the paper instead of being swallowed by the co-located steady echo/player).
    let newEchoID: UUID
    /// Wall-clock moment the effect began; the canvas derives every phase from
    /// `now − start`.
    let start: Date
}

/// One in-flight **death** event. Captured the instant `BoardView` predicts a fatal
/// step, *before* it mutates the model — so the canvas can show the kill at the
/// contact tile and `BoardView` performs the (instant) restart only once the dissolve
/// has played.
nonisolated struct DeathEffect: Identifiable, Sendable {
    /// Monotonic generation (keys the cleanup `task`).
    let id: Int
    /// The player's tile *before* the fatal step — where its glide onto the contact
    /// tile begins.
    let previous: GridCoordinate
    /// The collision tile: where the player dies and the fizz emits.
    let contact: GridCoordinate
    /// Each colliding echo's tile *before* the fatal step. They glide from here onto
    /// `contact` (so you see what you touched) and then fizz with the player.
    let echoOrigins: [GridCoordinate]
    /// Identities of those colliding echoes, so the steady echo layer hides them while
    /// the canvas owns their dissolve (no double-draw).
    let collidingEchoIDs: Set<UUID>
    /// If a hazard was the killer, its tile at the contact turn — the one enemy whose
    /// glow pulses once (§6d). `nil` for an echo death (no enemy involved).
    let killerHazard: GridCoordinate?
    /// Wall-clock moment the effect began.
    let start: Date
}

// MARK: - The Canvas overlay

/// The transient effects, drawn over the board. Mounted by `BoardView` only while
/// `fold` or `death` is non-nil; it draws whichever is active for the current frame.
struct BoardEffectsOverlay: View {
    let fold: FoldEffect?
    let death: DeathEffect?
    /// The runtime cell size (points) — the canvas maps grid cells to points exactly
    /// as `BoardView` does, and scales handover §1b metrics from the reference cell.
    let cell: CGFloat
    /// The active palette; every effect colour reads from it (both modes).
    let theme: Theme

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                let now = timeline.date
                if let fold { drawFold(fold, now: now, into: &context, size: size) }
                if let death { drawDeath(death, now: now, into: &context, size: size) }
            }
        }
        // Purely decorative; never intercept input (the lattice underneath is the
        // tap layer).
        .allowsHitTesting(false)
    }

    // MARK: Fold choreography (§6c)

    private func drawFold(_ effect: FoldEffect, now: Date, into ctx: inout GraphicsContext, size: CGSize) {
        let elapsed = now.timeIntervalSince(effect.start)
        let origin = center(effect.origin)

        // (2) Grid ripple — one expanding hairline ring (plus a fainter trailing
        // ring), fading as it grows. No colour: it uses the tile-hairline ink, so it
        // reads as the grid itself pulsing. Begins after the hit-pause.
        let rippleT = (elapsed - Motion.Span.foldHitPause) / Motion.Span.foldRipple
        if rippleT > 0, rippleT < 1 {
            let e = Ease.easeOut(rippleT)
            let radius = scaled(8) + CGFloat(e) * (cell * 2.6)
            let alpha = (1 - e) * 0.7
            ctx.stroke(ringPath(center: origin, radius: radius),
                       with: .color(theme.tileHairline.opacity(alpha)),
                       lineWidth: max(0.5, scaled(1.0)))
            let inner = radius * 0.72
            ctx.stroke(ringPath(center: origin, radius: inner),
                       with: .color(theme.tileHairline.opacity(alpha * 0.5)),
                       lineWidth: max(0.5, scaled(0.75)))
        }

        // (3) Echo peel-off — the new echo peels off the just-walked path. It starts
        // at the run's end (where present-you stood at the fold, ink, player-sized)
        // and slides back to `start`, crossfading ink → echo grey and shrinking
        // 32 → 28 pt, so you *see* the present shed a past self that rewinds into the
        // start stack (handover §6c step 3). Travelling across the board (rather than
        // crossfading in place) keeps the grey legible against the paper instead of
        // being swallowed by the co-located opaque player. During the hit-pause it
        // holds as the solid ink square at the run-end (q = 0), so the moment lands
        // before it peels. The steady echo layer hides this echo for the whole fold,
        // so the overlay is its sole source until it settles.
        let peelEnd = Motion.Span.foldHitPause + Motion.Span.foldPeel
        if elapsed < peelEnd {
            let raw = (elapsed - Motion.Span.foldHitPause) / Motion.Span.foldPeel
            let q = raw <= 0 ? 0 : Ease.easeOut(min(raw, 1))
            let pos = lerp(center(effect.peelFrom), origin, q)
            let side = scaled(BoardMetrics.playerSize)
                + CGFloat(q) * (scaled(BoardMetrics.echoSize) - scaled(BoardMetrics.playerSize))
            let shape = squarePath(center: pos, side: side,
                                   radius: scaled(BoardMetrics.radiusPlayer))
            // Ink (the present) fading out…
            ctx.fill(shape, with: .color(theme.ink.opacity(1 - q)))
            // …crossfading into the resting echo (fill + stroke fading in).
            ctx.fill(shape, with: .color(theme.echoBase.opacity(theme.echoFillOpacity * q)))
            ctx.stroke(shape, with: .color(theme.echoBase.opacity(theme.echoStrokeOpacity * q)),
                       lineWidth: scaled(BoardMetrics.strokeEcho))
        } else {
            // Peel has landed: hold the resting echo at `start` until the overlay
            // unmounts and the (un-hidden) steady echo layer takes over, so the new
            // echo never blinks out in the gap between the peel finishing and the
            // fold effect clearing.
            drawEcho(center: origin, into: &ctx)
        }
    }

    // MARK: Death dissolve (§6d)

    private func drawDeath(_ effect: DeathEffect, now: Date, into ctx: inout GraphicsContext, size: CGSize) {
        let elapsed = now.timeIntervalSince(effect.start)
        let slideEnd = Motion.Span.step                          // glide onto contact
        let freezeEnd = slideEnd + Motion.Span.deathFreeze       // + calm freeze
        let fizzEnd = freezeEnd + Motion.Span.deathFizz          // + soft fizz
        let contact = center(effect.contact)

        // Red note — vignette flash + one enemy-glow pulse — rising and falling from
        // the instant of contact (the freeze), beneath nothing else here.
        drawRedNote(effect, elapsed: elapsed, since: slideEnd, into: &ctx, size: size)

        if elapsed < freezeEnd {
            // Glide (player + colliding echoes converge on the contact tile, easing
            // like a normal step) then hold solid through the freeze.
            let slideT = min(max(elapsed / slideEnd, 0), 1)
            let e = Ease.standard(slideT)
            let playerPos = lerp(center(effect.previous), contact, e)
            fillSquare(center: playerPos,
                       side: scaled(BoardMetrics.playerSize),
                       radius: scaled(BoardMetrics.radiusPlayer),
                       color: theme.ink, into: &ctx)
            for from in effect.echoOrigins {
                drawEcho(center: lerp(center(from), contact, e), into: &ctx)
            }
        } else if elapsed < fizzEnd {
            // Soft fizz — the player into ~14 ink particles, each colliding echo into
            // ~10 grey ones, all dispersing outward from the contact tile and fading.
            let p = (elapsed - freezeEnd) / Motion.Span.deathFizz
            emitFizz(at: contact, color: theme.ink, count: 14, progress: p, seed: 1, into: &ctx)
            for (index, _) in effect.echoOrigins.enumerated() {
                emitFizz(at: contact, color: theme.echoBase, count: 10, progress: p,
                         seed: 7 + index, startOpacity: max(0.5, theme.echoStrokeOpacity), into: &ctx)
            }
        }
    }

    /// The faint full-board red vignette (D-041 danger red @ 0.08 peak), plus the one
    /// enemy-glow pulse for a hazard death — both a smooth rise-and-fall over
    /// `deathVignette`, starting at the contact instant.
    private func drawRedNote(_ effect: DeathEffect, elapsed: TimeInterval, since: TimeInterval,
                             into ctx: inout GraphicsContext, size: CGSize) {
        let vt = (elapsed - since) / Motion.Span.deathVignette
        guard vt > 0, vt < 1 else { return }
        let bump = sin(Double.pi * vt)                 // 0 → 1 → 0

        let rect = CGRect(origin: .zero, size: size)
        let vignette = GraphicsContext.Shading.radialGradient(
            Gradient(stops: [
                .init(color: theme.dangerRed.opacity(0), location: 0.45),
                .init(color: theme.dangerRed.opacity(0.08 * bump), location: 1.0),
            ]),
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.72)
        ctx.fill(Path(rect), with: vignette)

        if let hazard = effect.killerHazard {
            let c = center(hazard)
            let r = scaled(BoardMetrics.enemySize) * CGFloat(0.55 + bump * 0.55)
            let glow = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [theme.dangerGlow.opacity(bump), theme.dangerGlow.opacity(0)]),
                center: c, startRadius: 0, endRadius: r)
            ctx.fill(ringPath(center: c, radius: r), with: glow)
        }
    }

    // MARK: Particles

    /// Emit one bounded, deterministic burst from `center`. Particle count is fixed
    /// (no open-ended emitter); angles/sizes come from a deterministic hash of the
    /// index, so a given death always fizzes identically (matching the engine's
    /// no-randomness character — though this is pure presentation).
    private func emitFizz(at center: CGPoint, color: Color, count: Int, progress p: Double,
                          seed: Int, startOpacity: Double = 1.0, into ctx: inout GraphicsContext) {
        let pe = Ease.easeOut(min(max(p, 0), 1))
        let base = scaled(4.5)
        for i in 0..<count {
            let h1 = hashFraction(i &* 2 &+ seed &* 131)
            let h2 = hashFraction(i &* 7 &+ seed &* 977 &+ 1)
            let angle = (Double(i) + 0.5) / Double(count) * 2 * .pi + (h1 - 0.5) * 0.7
            let drift = cell * CGFloat(0.40 + h2 * 0.35)
            let dist = CGFloat(pe) * drift
            let pos = CGPoint(x: center.x + CGFloat(cos(angle)) * dist,
                              y: center.y + CGFloat(sin(angle)) * dist)
            let dotSize = base * CGFloat(1.0 - 0.45 * p) * CGFloat(0.7 + h1 * 0.6)
            let dot = Path(ellipseIn: CGRect(x: pos.x - dotSize / 2, y: pos.y - dotSize / 2,
                                             width: dotSize, height: dotSize))
            ctx.fill(dot, with: .color(color.opacity(startOpacity * (1 - p))))
        }
    }

    // MARK: Primitives

    /// A resting echo square (fill + stroke) — matches the steady `BoardView` echo so
    /// the dissolving echo reads as itself before it fizzes.
    private func drawEcho(center: CGPoint, into ctx: inout GraphicsContext) {
        let shape = squarePath(center: center, side: scaled(BoardMetrics.echoSize),
                               radius: scaled(BoardMetrics.radiusEcho))
        ctx.fill(shape, with: .color(theme.echoBase.opacity(theme.echoFillOpacity)))
        ctx.stroke(shape, with: .color(theme.echoBase.opacity(theme.echoStrokeOpacity)),
                   lineWidth: scaled(BoardMetrics.strokeEcho))
    }

    private func fillSquare(center: CGPoint, side: CGFloat, radius: CGFloat,
                            color: Color, into ctx: inout GraphicsContext) {
        ctx.fill(squarePath(center: center, side: side, radius: radius), with: .color(color))
    }

    private func squarePath(center: CGPoint, side: CGFloat, radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: center.x - side / 2, y: center.y - side / 2,
                                 width: side, height: side),
             cornerRadius: radius, style: .continuous)
    }

    /// A centred circle path — used both as the ripple ring (stroked) and the
    /// enemy-glow disc (filled with a radial gradient).
    private func ringPath(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2))
    }

    // MARK: Geometry helpers (mirror BoardView's)

    private func center(_ c: GridCoordinate) -> CGPoint {
        CGPoint(x: (CGFloat(c.column) + 0.5) * cell, y: (CGFloat(c.row) + 0.5) * cell)
    }

    private func scaled(_ points: CGFloat) -> CGFloat {
        points / BoardMetrics.referenceCell * cell
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }

    /// A deterministic fraction in `[0, 1)` from an integer — the classic hashed-sine
    /// trick. Pure (no RNG), so the fizz is identical every time, like the engine.
    private func hashFraction(_ n: Int) -> Double {
        let s = sin(Double(n) * 12.9898) * 43758.5453
        return s - floor(s)
    }
}
