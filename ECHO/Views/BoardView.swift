//
//  BoardView.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move) → 1.04 (Fold) → 1.06 (Room contents) → 2.02 (The
//  board's real look + motion) → 2.03 (The fold choreography & the death dissolve).
//  The state-driven board, rendered to the locked Phase 2.01 visual design: real
//  colours/geometry from the `Theme` token layer, in both Light and Invert palettes,
//  with pieces that glide between cells instead of snapping.
//
//  Presentation only — the engine is untouched. `GameState` still owns every rule
//  (turn order, collision, win, replay); this view animates how those state changes
//  are *displayed*. Each committed step:
//    • Player — a 120 ms `curve.standard` slide + a departure squash-and-stretch
//      (94% along / 106% across) + a 40 ms soft-snap settle, and the board's only
//      drop shadow (it must always read as the clearest, "most now" thing — §3).
//    • Echoes — the same 120 ms `curve.standard` slide in lockstep, but flat: no
//      squash, no shadow, smaller and translucent so they recede (§2.2 / §3).
//    • Enemy/hazard — a heavier 140 ms `curve.standard` slide with a ~30 ms
//      anticipation lean-in toward travel, no overshoot (§6e).
//  A no-op move animates nothing; a survived step slides/squashes; a reset/step-back/
//  room-load snaps (not wrapped in an animation — handover §6d restart = 0 ms).
//
//  Phase 2.03 wires the two big *events* (presentation still only). Detecting a fold
//  (the echo count rose) plays the §6c choreography — hit-pause → grid ripple → the
//  new grey echo peeling off the player — over the rewound board. Predicting a fatal
//  step hands the §6d death dissolve a read-only descriptor and **defers** the model
//  mutation: the effects overlay (`BoardEffectsOverlay`, SwiftUI Canvas) plays the
//  glide → calm freeze → soft particle fizz → red vignette, and `finishDeath()`
//  performs the instant restart once it has played. The engine still decides every
//  outcome; the overlay only reads predicates to know *when*/*where* to draw.
//
//  Glows and the player shadow render *outside* the cell and are never clipped (no
//  `.clipped`/`.clipShape` anywhere here). Every drawn piece has hit testing off so
//  a tap falls through to the lattice cell beneath it, which is the input layer.
//  Grayscale identity is preserved: every element stays uniquely readable by shape +
//  size + opacity with colour removed (§3); red/gold are a bonus layer only (D-041).
//

import SwiftUI

struct BoardView: View {
    /// The board's state, owned by `ContentView` and passed in (Observation
    /// re-renders this view when the state it reads changes).
    let state: GameState

    /// The generative-audio manager, owned and started by `ContentView` (Phase 2.04).
    /// Presentation-only, like the motion: `commitMove`/`triggerFold`/`triggerDeath`
    /// fire its sounds on the same paths the animation already uses, gated by its own
    /// `isEnabled` switch. Passed in (not in the environment) for symmetry with `state`.
    let audio: AudioManager

    /// The haptic-feedback manager, owned and pre-warmed by `ContentView` (Phase 2.05).
    /// Fired from the same `commitMove`/`triggerFold` paths as the audio, so each tap
    /// lands with its visible state change: step → slide, fold → §6c choreography,
    /// collision → §6d dissolve, win → solve. The **step and fold** taps also coincide
    /// with their sounds (both fired at commit); the **collision and win** taps fire at
    /// the instant of contact/commit, a beat *before* their sounds — those sounds are
    /// deliberately offset by the audio layer (to the §6d fizz / to arrival), and a
    /// system `UIFeedbackGenerator` tap can't be host-time scheduled, so the tap leads.
    /// Presentation-only; gated by its own `isEnabled` switch; passed in for symmetry.
    let haptics: HapticsManager

    /// Whether the optional echo-trail aid is on (Phase 2.06). Passed in by
    /// `ContentView` as `settings.echoTrailEnabled` — an additive parameter exactly like
    /// `audio`/`haptics` were. When on, a faint dotted preview of each echo's upcoming
    /// path is drawn beneath the player; the aid reads existing echo intent only and
    /// changes no gameplay (D-051; handover §8/§6f).
    let showEchoTrail: Bool

    /// The guidance microcopy controller (Phase 2.06), owned by `ContentView` and
    /// injected like `audio`/`haptics`. `BoardView` mounts `GuidanceOverlay` to render
    /// its current `message`, and fires `showEaten()` from its death path. Presentation
    /// only — it adds no engine state (D-052; handover §6).
    let guidance: GuidanceController

    /// Optional outward report of this view's input lock (Phase 3.03 / D-059). The board
    /// already refuses input while a fold or death choreography plays (`commitMove`'s
    /// `fold == nil, death == nil` guard); this reports that same lock to a parent so the
    /// **out-of-board** campaign controls (Fold / Step back / Reset run, owned by
    /// `RoomView`) can honor it too instead of mutating `state` directly mid-effect — the
    /// correctness cleanup the interim HUD deferred (D-017/D-054). Additive and presentation
    /// only, in the same vein as `audio`/`haptics`/`guidance` were added in earlier phases;
    /// it changes nothing the board draws. Left `nil` (the default) by call sites that
    /// don't need it (e.g. previews), so the board's behaviour is unchanged when unused.
    var inputLock: Binding<Bool>? = nil

    /// A monotonically-rising "wait requested" counter from `RoomView`'s Wait control
    /// (Phase 4.01 / D-068). Each increment runs one wait through `commitWait()` — the
    /// **same** input-lock-guarded path a tap/swipe uses — so the wait gets the in-place
    /// pulse, the calm `.stay` tick, the step haptic, and (on a fatal wait) the deferred
    /// death dissolve, instead of `RoomView` mutating `state` directly. Defaults to `0`
    /// (never changes for call sites that don't pass it, e.g. previews), so an unused
    /// board never waits — `.onChange` fires only on a real change.
    var waitSignal: Int = 0

    /// The active palette (Light by default; `ContentView` injects it). The single
    /// switch point a later Settings phase (2.06) will bind to a user toggle.
    @Environment(\.theme) private var theme

    /// Bumped once per **survived** committed step. Drives the player's
    /// squash-and-stretch and each hazard's anticipation lean-in (keyframe triggers),
    /// so those transient effects fire only on a real step — never on a fold, a death
    /// restart, a step-back to start, or a room load.
    @State private var stepTick = 0
    /// Whether the last survived step was horizontal — chooses the squash axis.
    @State private var lastStepHorizontal = true
    /// Bumped once per **survived wait** (Phase 4.01). Drives the player's gentle in-place
    /// "breath" pulse (a small symmetric scale) — distinct from the directional step
    /// squash and from a blocked move's nothing — so a held turn reads as its own beat.
    @State private var waitPulseTick = 0

    /// The in-flight fold choreography (hit-pause → ripple → echo peel), or `nil` at
    /// rest. Set when a fold is detected (the echo count rose); cleared by a `task`
    /// once the choreography has played (Phase 2.03).
    @State private var fold: FoldEffect? = nil
    /// The in-flight death dissolve (glide → freeze → fizz + red note), or `nil` at
    /// rest. Set the instant a fatal step is predicted — **before** the model is
    /// mutated — so the canvas can show the kill at the contact tile; the (instant)
    /// restart is performed by `finishDeath()` once the dissolve has played.
    @State private var death: DeathEffect? = nil
    /// Monotonic generations so each fold/death keys its own cleanup `task`.
    @State private var foldGeneration = 0
    @State private var deathGeneration = 0

    /// Whether the echo-trail layer is in the view tree. It mounts the instant the aid
    /// is switched on and stays mounted for the 150 ms fade after it is switched off
    /// (so the dots can fade rather than vanish), then unmounts — so when the aid is off
    /// at rest nothing is rendered (handover §6f). Driven by the `.task(id: showEchoTrail)`.
    @State private var trailMounted = false

    /// Board occupies this fraction of the smaller available dimension, leaving a
    /// margin from the safe-area edges.
    private static let fillFraction: CGFloat = 0.82
    /// Minimum drag distance that counts as a swipe rather than a tap.
    private static let swipeThreshold: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            // Square cells sized so the whole board fits within `fillFraction` of the
            // smaller dimension. `max(width, height)` keeps cells square for a
            // non-square board.
            let available = min(proxy.size.width, proxy.size.height) * Self.fillFraction
            let cell = available / CGFloat(max(state.width, state.height))
            let boardSize = CGSize(width: cell * CGFloat(state.width),
                                   height: cell * CGFloat(state.height))

            ZStack(alignment: .topLeading) {
                lattice(cell: cell)
                walls(cell: cell)
                pads(cell: cell)
                exitRing(cell: cell)
                doorBars(cell: cell)
                switchMarks(cell: cell)
                echoes(cell: cell)
                // The optional echo-trail aid (Phase 2.06): a faint dotted preview of
                // each echo's upcoming path, beneath the player and hit-testing off.
                // Mounted only while on (or fading off), so off = nothing rendered.
                if trailMounted {
                    echoTrail(cell: cell)
                }
                hazardMarks(cell: cell)
                playerSquare(cell: cell)
                // The transient fold/death choreography, on top of the steady board.
                // Mounted only while an effect is in flight, so its per-frame
                // `TimelineView` clock costs nothing at rest (Phase 2.03).
                if fold != nil || death != nil {
                    BoardEffectsOverlay(fold: fold, death: death, cell: cell, theme: theme)
                        .frame(width: boardSize.width, height: boardSize.height)
                        .allowsHitTesting(false)
                }
                // The guidance microcopy (Phase 2.06), anchored to the board above the
                // pieces (hit-testing off). Renders the controller's current message;
                // self-times its own fade.
                GuidanceOverlay(message: guidance.message,
                                boardSize: boardSize,
                                placeUpper: state.player.row >= state.height * 2 / 3,
                                color: theme.textGuidance)
                    .frame(width: boardSize.width, height: boardSize.height)
                    .allowsHitTesting(false)
            }
            .frame(width: boardSize.width, height: boardSize.height)
            // Centre the board within the available (safe-area) space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(swipeGesture)
            // A fold is the only thing that grows the echo count, so an increment is
            // an unambiguous "a fold just happened" — play its choreography. (Clear
            // and room-load drop the count to 0; reset/step-back/death never touch
            // it; so none of those false-trigger.)
            .onChange(of: state.echoes.count) { old, new in
                if new > old { triggerFold() }
            }
            // Report the fold/death input lock outward (Phase 3.03 / D-059) so the
            // out-of-board campaign controls can gate on the same lock `commitMove` uses.
            // A pure side report — it never feeds back into the board's own state.
            .onChange(of: fold != nil || death != nil) { _, locked in
                inputLock?.wrappedValue = locked
            }
            // A wait requested by the HUD's Wait control (Phase 4.01 / D-068): run it
            // through `commitWait`, the same input-lock-guarded path a tap/swipe uses, so
            // it lands with its pulse/tick/haptic and deferred-death handling. Fires only
            // on a real change, so the default `waitSignal == 0` never waits.
            .onChange(of: waitSignal) { _, _ in commitWait() }
            // Clear each effect once it has fully played. Keyed on the generation so a
            // new event cancels the previous timer; the model restart a death needs is
            // performed here, at the end of the dissolve (handover §6d restart = 0 ms).
            .task(id: foldGeneration) {
                guard fold != nil else { return }
                let total = Motion.Span.foldHitPause + max(Motion.Span.foldRipple, Motion.Span.foldPeel)
                try? await Task.sleep(for: .seconds(total))
                if !Task.isCancelled { fold = nil }
            }
            .task(id: deathGeneration) {
                guard death != nil else { return }
                let total = Motion.Span.step + Motion.Span.deathFreeze + Motion.Span.deathFizz
                try? await Task.sleep(for: .seconds(total))
                if !Task.isCancelled { finishDeath() }
            }
            // Echo-trail mount/unmount. On → mount immediately (the layer fades its dots
            // in with the per-dot reveal stagger). Off → keep the layer mounted for the
            // 150 ms fade, then unmount so nothing renders at rest (handover §6f).
            .task(id: showEchoTrail) {
                if showEchoTrail {
                    trailMounted = true
                } else if trailMounted {
                    try? await Task.sleep(for: .seconds(Motion.Span.trailFade))
                    if !Task.isCancelled { trailMounted = false }
                }
            }
        }
    }

    // MARK: - Pieces

    /// The grid lattice: quiet `tile.hairline` borders (handover §1b — the quietest
    /// marks on screen). Each cell is independently tappable so a tap on a cell
    /// orthogonally adjacent to the player can become a move. This is the input
    /// layer; every other layer has hit testing off so taps reach it.
    private func lattice(cell: CGFloat) -> some View {
        let hairline = scaled(BoardMetrics.strokeHairline, cell: cell)
        return VStack(spacing: 0) {
            ForEach(0..<state.height, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<state.width, id: \.self) { column in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: cell, height: cell)
                            .border(theme.tileHairline, width: hairline)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tap(GridCoordinate(row: row, column: column))
                            }
                    }
                }
            }
        }
    }

    /// Walls: a full-cell rounded tile (1 pt inset so adjacent walls read separately)
    /// filled with one flat solid tone — a calm, even block that reads as solid matter
    /// rather than a drawn outline (Phase 2.07 / D-053 replaced the old top-light →
    /// bottom-dark depth gradient with this single `wall` fill).
    private func walls(cell: CGFloat) -> some View {
        let inset = scaled(BoardMetrics.wallInset, cell: cell)
        let size = cell - inset * 2
        let radius = scaled(BoardMetrics.radiusWall, cell: cell)
        return ForEach(Array(state.walls), id: \.self) { wall in
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.wall)
                .frame(width: size, height: size)
                .position(center(of: wall, cell: cell))
                .allowsHitTesting(false)
        }
    }

    /// Teleport pads (Phase 4.03 / D-070): a **first-pass** monochrome glyph — four
    /// bracketed corners (an open "frame") drawn at every portal cell. Paired pads share
    /// the identical glyph so the link reads at a glance, and the bracketed-corners shape
    /// is unambiguous against the other board marks: switches (open/filled circles), the
    /// exit (hollow ring), doors (bars), and walls (solid fill). Uses the `ink` token at a
    /// quiet opacity — **never the accent** (that stays reserved for the must-reach-now
    /// element). The jump itself is instantaneous this phase (the player just steps into
    /// the pad); **refine in a later Design pass.** Drawn beneath the pieces, hit-testing
    /// off, like the other structural marks.
    private func pads(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.padSize, cell: cell)
        let stroke = scaled(BoardMetrics.strokePad, cell: cell)
        return ForEach(state.portals) { portal in
            ForEach(Array(portal.cells.enumerated()), id: \.offset) { _, padCell in
                PadGlyph(armFraction: BoardMetrics.padCornerArm)
                    .stroke(theme.ink.opacity(BoardMetrics.padGlyph),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
                    .position(center(of: padCell, cell: cell))
                    .allowsHitTesting(false)
            }
        }
    }

    /// Exit: a hollow ring (§2.7). In v1 every room has a single, always-active goal,
    /// so the exit renders in its **active-goal** state — gold stroke + soft glow.
    /// The **default** (not-yet-the-goal) state — an ink ring at 0.55, no glow — is
    /// implemented alongside it (selected by `isActiveGoal`) so a later multi-exit /
    /// locked-exit room can use it with no redesign.
    @ViewBuilder
    private func exitRing(cell: CGFloat) -> some View {
        if let exit = state.exit {
            let size = scaled(BoardMetrics.exitSize, cell: cell)
            let stroke = scaled(BoardMetrics.strokeExitRing, cell: cell)
            let isActiveGoal = true
            Circle()
                .strokeBorder(isActiveGoal ? theme.goalGold
                                           : theme.ink.opacity(BoardMetrics.exitDefaultRing),
                              lineWidth: stroke)
                .frame(width: size, height: size)
                .accentGlow(isActiveGoal ? theme.goalGlow : .clear, cell: cell, enabled: isActiveGoal)
                .position(center(of: exit, cell: cell))
                .allowsHitTesting(false)
        }
    }

    /// Doors: closed = one solid high-contrast bar across the cell (ink @ 0.92);
    /// open = two short faint stubs at the bar's ends with an empty centre (ink @
    /// 0.22). Solidity *and* completeness change, so the two read apart at a glance
    /// (§2.5). Open-state is read from the model at the current turn.
    private func doorBars(cell: CGFloat) -> some View {
        let thickness = scaled(BoardMetrics.doorThickness, cell: cell)
        let stub = scaled(BoardMetrics.doorStub, cell: cell)
        let radius = scaled(BoardMetrics.radiusDoorBar, cell: cell)
        return ForEach(state.doors) { door in
            let open = state.isDoorOpen(door)
            ForEach(Array(door.cells.enumerated()), id: \.offset) { _, doorCell in
                ZStack {
                    if open {
                        // Two recessed remnant stubs at the ends.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(theme.ink.opacity(BoardMetrics.doorOpenRemnant))
                            .frame(width: stub, height: thickness)
                            .offset(x: -(cell - stub) / 2)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(theme.ink.opacity(BoardMetrics.doorOpenRemnant))
                            .frame(width: stub, height: thickness)
                            .offset(x: (cell - stub) / 2)
                    } else {
                        // One solid bar spanning the cell.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(theme.ink.opacity(BoardMetrics.doorClosedFill))
                            .frame(width: cell, height: thickness)
                    }
                }
                .frame(width: cell, height: thickness)
                .position(center(of: doorCell, cell: cell))
                .allowsHitTesting(false)
            }
        }
    }

    /// Switches: **open** = a quiet hollow ring (§2.4); **held** (keeping the player
    /// alive) = a filled gold circle + glow. The hollow-ring → filled-circle change
    /// is the shape-change that carries the meaning; gold is the bonus layer (D-041).
    private func switchMarks(cell: CGFloat) -> some View {
        ForEach(state.switches) { theSwitch in
            let held = state.isSwitchHeld(theSwitch.id)
            Group {
                if held {
                    let size = scaled(BoardMetrics.switchHeldSize, cell: cell)
                    Circle()
                        .fill(theme.goalGold)
                        .frame(width: size, height: size)
                        .accentGlow(theme.goalGlow, cell: cell)
                } else {
                    let size = scaled(BoardMetrics.switchOpenSize, cell: cell)
                    Circle()
                        .strokeBorder(theme.switchRing,
                                      lineWidth: scaled(BoardMetrics.strokeSwitchRing, cell: cell))
                        .frame(width: size, height: size)
                }
            }
            .position(center(of: theSwitch.cell, cell: cell))
            .allowsHitTesting(false)
        }
    }

    /// The folded echoes: a smaller, translucent rounded square per echo (§2.2),
    /// flat — no squash, no shadow. Each slides between its replayed cells on the
    /// same 120 ms `curve.standard` as the player (the slide comes from the
    /// `withAnimation` wrapping a committed move, so echoes glide in lockstep and a
    /// reset snaps). Drawn beneath the player and hit testing off.
    private func echoes(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.echoSize, cell: cell)
        let radius = scaled(BoardMetrics.radiusEcho, cell: cell)
        let stroke = scaled(BoardMetrics.strokeEcho, cell: cell)
        return ForEach(state.echoes) { echo in
            let position = state.position(of: echo)
            // The effects overlay owns an echo's appearance in two cases, so the
            // steady layer hides it to avoid a double-draw: while a death dissolves,
            // the echo(es) the player touched (gliding onto the contact tile, then
            // fizzing); and while a fold plays, the freshly-banked echo (peeling in
            // from the run-end). In both, the steady echo un-hides when the effect
            // clears, seamlessly taking over its resting render.
            let dissolving = death?.collidingEchoIDs.contains(echo.id) == true
            let peeling = fold?.newEchoID == echo.id
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.echoBase.opacity(theme.echoFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(theme.echoBase.opacity(theme.echoStrokeOpacity),
                                      lineWidth: stroke)
                )
                .frame(width: size, height: size)
                .position(center(of: position, cell: cell))
                .opacity(dissolving || peeling ? 0 : 1)
                .allowsHitTesting(false)
        }
    }

    /// The echo-trail aid (Phase 2.06; handover §8/§6f): per echo, a faint line of
    /// dots running from the echo's current cell centre through the centres of the
    /// cells it is about to enter (the pure `Echo.upcomingCells`). Dots are `3 pt`,
    /// centre-spaced `8 pt`, in `echo.base` @ 0.40 (both palettes). An exhausted echo
    /// has no upcoming path, so it shows no dots. Drawn beneath the player, hit-testing
    /// off; the aid reads existing intent only and changes no gameplay.
    private func echoTrail(cell: CGFloat) -> some View {
        let dotSize = scaled(BoardMetrics.trailDotSize, cell: cell)
        let spacing = scaled(BoardMetrics.trailDotSpacing, cell: cell)
        return ForEach(state.echoes) { echo in
            // Pad-aware (Phase 4.03): the trail reads the echo's pad-resolved upcoming
            // path, so it draws a teleport as the jump it is (D-071).
            let upcoming = state.upcomingCells(of: echo)
            if !upcoming.isEmpty {
                // Polyline = the echo's current cell centre, then each upcoming centre.
                let points = ([state.position(of: echo)] + upcoming)
                    .map { center(of: $0, cell: cell) }
                EchoTrailLayer(dots: trailDots(along: points, spacing: spacing),
                               dotSize: dotSize,
                               color: theme.echoBase,
                               active: showEchoTrail)
            }
        }
    }

    /// Resample a polyline (points already in board pixels) into evenly-spaced dots,
    /// one every `spacing` points, ordered outward from the echo (the order drives the
    /// reveal stagger). The first dot sits one `spacing` out from the echo centre, so
    /// the line reads as emanating from the echo rather than sitting under it.
    private func trailDots(along points: [CGPoint], spacing: CGFloat) -> [TrailDot] {
        guard points.count >= 2, spacing > 0 else { return [] }
        var dots: [TrailDot] = []
        var order = 0
        var carry = spacing                       // distance until the next dot
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            if length == 0 { continue }
            var distance = carry
            while distance <= length {
                let t = distance / length
                dots.append(TrailDot(id: order, point: CGPoint(x: a.x + dx * t, y: a.y + dy * t)))
                order += 1
                distance += spacing
            }
            carry = distance - length
        }
        return dots
    }

    /// Hazards: a red diamond — the only diamond on the board — with a darker
    /// outline, a focused inner core, and a soft contained glow (§2.6). The diamond
    /// is a rounded square rotated 45° (corner radius 3 pt → "slightly sharp"); the
    /// squash/anticipation and slide are applied in board axes on the whole piece, so
    /// the inner rotation never skews them. Each hazard slides on the heavier 140 ms
    /// `curve.standard` with a ~30 ms anticipation lean-in toward travel, no overshoot.
    private func hazardMarks(cell: CGFloat) -> some View {
        ForEach(state.hazards) { hazard in
            let current = hazard.position(at: state.turn)
            let previous = hazard.position(at: max(0, state.turn - 1))
            let moved = current != previous
            let horizontal = current.column != previous.column
            enemyDiamond(cell: cell)
                // Anticipation: a short squash toward travel before it sets off,
                // settling with no overshoot (§6e). Fires only when it actually moved.
                .keyframeAnimator(initialValue: Squash(), trigger: stepTick) { view, squash in
                    let s = moved ? squash : Squash()
                    view.scaleEffect(x: horizontal ? s.along : s.across,
                                     y: horizontal ? s.across : s.along)
                } keyframes: { _ in
                    KeyframeTrack(\.along) {
                        CubicKeyframe(0.92, duration: 0.030)
                        CubicKeyframe(1.0, duration: 0.110)
                    }
                    KeyframeTrack(\.across) {
                        CubicKeyframe(1.08, duration: 0.030)
                        CubicKeyframe(1.0, duration: 0.110)
                    }
                }
                .position(center(of: current, cell: cell))
                // Retime the lockstep slide from the player's 120 ms to the enemy's
                // 140 ms — but only when there is an animation (a committed step);
                // resets carry no animation and stay instant.
                .transaction { t in
                    if t.animation != nil { t.animation = Motion.enemyStep }
                }
                .allowsHitTesting(false)
        }
    }

    /// One enemy diamond: outer red diamond (outline) + inner core, built from two
    /// rotated rounded squares so the small corner radius reads as "slightly sharp,"
    /// with the contained glow around the silhouette.
    private func enemyDiamond(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.enemySize, cell: cell)           // point-to-point
        let side = size / sqrt(2)                                       // square side → p2p = size
        let coreSide = scaled(BoardMetrics.enemyCoreSize, cell: cell) / sqrt(2)
        let radius = scaled(BoardMetrics.radiusEnemyCorner, cell: cell)
        let outline = scaled(BoardMetrics.strokeEnemyOutline, cell: cell)
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.dangerRed)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(theme.dangerOutline, lineWidth: outline)
                )
                .frame(width: side, height: side)
                .rotationEffect(.degrees(45))
            RoundedRectangle(cornerRadius: radius * 0.6, style: .continuous)
                .fill(theme.dangerCore)
                .frame(width: coreSide, height: coreSide)
                .rotationEffect(.degrees(45))
        }
        .frame(width: size, height: size)
        .accentGlow(theme.dangerGlow, cell: cell)
    }

    /// The player — "you, now": the largest element (32 pt vs the echo's 28 pt),
    /// fully opaque ink, and the only shadow-caster, so it always reads as the
    /// clearest thing on the board (§2.1 / §3). On a survived step it slides 120 ms
    /// `curve.standard` (driven by `withAnimation` at the call site) with a departure
    /// squash-and-stretch and a soft-snap settle layered on as a keyframe scale.
    private func playerSquare(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.playerSize, cell: cell)
        let radius = scaled(BoardMetrics.radiusPlayer, cell: cell)
        // Capture the squash axis as a local so the keyframe closure references a
        // value, not the main-actor `@State` property (keeps the closure isolation-clean).
        let horizontal = lastStepHorizontal
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.ink)
            .frame(width: size, height: size)
            // Departure squash (94% along / 106% across by ~40 ms, back to 100% by
            // arrival) + a ~6% soft-snap overshoot settle in the 40 ms tail (§6b).
            // Realised as a keyframe scale so the position slide stays on the clean
            // 120 ms `curve.standard`; fires only on a survived step.
            .keyframeAnimator(initialValue: Squash(), trigger: stepTick) { view, squash in
                view.scaleEffect(x: horizontal ? squash.along : squash.across,
                                 y: horizontal ? squash.across : squash.along)
            } keyframes: { _ in
                KeyframeTrack(\.along) {
                    CubicKeyframe(0.94, duration: 0.040)   // squash along travel
                    CubicKeyframe(1.0, duration: 0.080)    // back to 100% by ~120 ms (arrival)
                    CubicKeyframe(1.06, duration: 0.020)   // soft-snap overshoot
                    CubicKeyframe(1.0, duration: 0.020)    // settle (~160 ms total)
                }
                KeyframeTrack(\.across) {
                    CubicKeyframe(1.06, duration: 0.040)   // stretch across travel
                    CubicKeyframe(1.0, duration: 0.080)
                    CubicKeyframe(1.06, duration: 0.020)   // uniform 6% overshoot with `along`
                    CubicKeyframe(1.0, duration: 0.020)
                }
            }
            // A survived wait's in-place "breath" (Phase 4.01): a gentle symmetric scale
            // up and back — no slide, no directional squash — so passing a turn reads as
            // its own quiet beat, distinct from a step and from a blocked move. Fires only
            // on `waitPulseTick`, so a step or a fatal wait never breathes.
            .keyframeAnimator(initialValue: Breath(), trigger: waitPulseTick) { view, breath in
                view.scaleEffect(breath.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.06, duration: 0.090)   // breathe out
                    CubicKeyframe(1.0, duration: 0.090)    // settle (~180 ms in place)
                }
            }
            .shadow(color: theme.shadowColor,
                    radius: scaled(BoardMetrics.shadowBlur, cell: cell),
                    x: 0,
                    y: scaled(BoardMetrics.shadowOffsetY, cell: cell))
            .position(center(of: state.player, cell: cell))
            // While a death is dissolving, the effects overlay draws the player
            // gliding onto the contact tile, freezing, then fizzing — so the steady
            // player is hidden until the run restarts (when it reappears at start).
            .opacity(death == nil ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - Geometry

    /// Scale a handover §1b point value (stated at the reference cell `C = 44 pt`) to
    /// the runtime cell size, so every proportion holds on any device.
    private func scaled(_ points: CGFloat, cell: CGFloat) -> CGFloat {
        points / BoardMetrics.referenceCell * cell
    }

    /// Pixel center of a grid cell, for `.position(_:)`.
    private func center(of coordinate: GridCoordinate, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(coordinate.column) + 0.5) * cell,
                y: (CGFloat(coordinate.row) + 0.5) * cell)
    }

    // MARK: - Input

    /// A tap on a cell orthogonally adjacent to the player steps into it; any other
    /// cell (diagonal, non-adjacent, or the player's own) does nothing.
    private func tap(_ cell: GridCoordinate) {
        guard let direction = Direction(from: state.player, to: cell) else { return }
        commitMove(direction)
    }

    /// A swipe whose dominant axis picks the direction → one step that way.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: Self.swipeThreshold)
            .onEnded { value in
                guard let direction = swipeDirection(value.translation) else { return }
                commitMove(direction)
            }
    }

    /// Maps a drag translation to a cardinal direction by its dominant axis (top-left
    /// origin: a negative height is upward, a negative width is left).
    private func swipeDirection(_ translation: CGSize) -> Direction? {
        if translation == .zero { return nil }
        if abs(translation.width) >= abs(translation.height) {
            return translation.width < 0 ? .left : .right
        } else {
            return translation.height < 0 ? .up : .down
        }
    }

    /// Run one move through the engine and choose how to *display* it. The engine is
    /// the sole authority on what happens; this only decides slide-vs-snap-vs-dissolve
    /// and fires the squash. The model's own public predicates are read (no mutation)
    /// to predict the outcome **before** committing, because the presentation choice
    /// has to wrap (or, for a death, defer) the mutation:
    ///   • A no-op (off-grid / wall / closed door / after a win) → nothing moves.
    ///   • A survived step → wrap the commit in `withAnimation(.step)` so the player
    ///     and every echo/hazard glide in lockstep, and bump `stepTick` so the
    ///     squash/anticipation fire.
    ///   • A fatal step → **do not mutate the model yet**: hand the death dissolve a
    ///     descriptor of the kill (where the player and the touched echo(es) glide to,
    ///     who the killer is) and let the effects overlay play the freeze → fizz →
    ///     red note. The (instant) restart the engine would perform happens in
    ///     `finishDeath()` once the dissolve has played (handover §6d restart = 0 ms).
    /// If the prediction ever disagreed with the engine it would only mis-pick the
    /// presentation, never the outcome — the engine still decides the move.
    private func commitMove(_ direction: Direction) {
        // Input is locked while a fold or death choreography is playing, so the held
        // model state a death relies on can't be moved out from under it.
        guard fold == nil, death == nil else { return }
        guard !state.hasWon else { return }
        // The **resolved** landing — through the shared teleport rule, exactly as
        // `GameState.move(_:)` does (Phase 4.03). On a step onto a pad this is the partner,
        // so the guards, the death prediction, and the death-contact tile all evaluate at
        // the landing — matching the engine — rather than at the pre-jump pad cell.
        let target = resolveLanding(from: state.player, step: direction, pads: state.padMap)
        // Same guards as `GameState.move(_:)` — a refused move animates nothing.
        guard state.contains(target),
              !state.isWall(target),
              !state.isClosedDoor(target) else { return }

        let fatal = state.playerCollides(previousPlayerCell: state.player,
                                         newPlayerCell: target,
                                         turn: state.turn + 1)
        if fatal {
            triggerDeath(previous: state.player, contact: target)
            // The soft error tap fires now, at the instant of contact — feeling the hit
            // when you hit is the intended feel, and a system tap can't be host-time
            // scheduled anyway. The death *sound* is offset by the audio layer to swell
            // on the §6d fizz (≈ step + deathFreeze later), so it is tap-then-sound, not
            // simultaneous. A fatal step never calls `state.move()` (the death is
            // predicted and the mutation deferred to `finishDeath()`), so the collision
            // haptic is fired here, at the point the death is committed — not by reading
            // `lastMoveOutcome` (which the model sets inside `move()`, a path this branch
            // bypasses).
            audio.playDeath()
            haptics.collision()
        } else {
            // Audio: one soft pitched tick per entity that steps this turn — the player
            // (always) and each echo whose recorded path still has a move at this turn.
            // Derived read-only from the public positions *before* the model advances
            // (echoes' per-turn directions are fixed by their recorded moves), and all
            // fired at one audio time so a multi-echo turn sounds as a chord, not a
            // flam. Hazards are deliberately not voiced — the rhythm is made of *your*
            // moves and their echoes (Phase 2.04). Adds no model API.
            let fromTurn = state.turn
            var ticks: [Direction] = [direction]
            for echo in state.echoes where fromTurn < echo.moves.count {
                ticks.append(echo.moves[fromTurn])
            }
            audio.playStep(directions: ticks)

            lastStepHorizontal = (direction == .left || direction == .right)
            stepTick &+= 1
            withAnimation(Motion.step) {
                _ = state.move(direction)
            }
            // Exactly one haptic per survived input (DoD: one tap per real outcome):
            // a winning step fires the success tap, an ordinary step fires the light
            // selection tick (in sync with the slide and its tick). The success tap
            // fires now, at the winning commit; the solve *sound* is offset one step by
            // the audio layer to resolve on arrival, so the win tap slightly leads its
            // flourish. Reaching the exit alive sets `hasWon` on this committed step.
            if state.hasWon {
                audio.playSolve()
                haptics.win()
            } else {
                haptics.step()
            }
        }
    }

    /// Pass a turn in place (Phase 4.01 / D-066/D-068), requested by the HUD's Wait
    /// control. Mirrors `commitMove`'s structure so a wait gets the same feedback and the
    /// same deferred-death handling, only the player never slides:
    ///   • Refused (nothing happens) while a fold/death effect plays or after a win — the
    ///     same locks `commitMove` honours.
    ///   • A **fatal wait** (a mover lands on the held tile this turn — predicted by the
    ///     model's own `playerCollides` at `turn + 1`, exactly as a fatal step is) **does
    ///     not** mutate the model: it hands the §6d dissolve a kill at the held tile and
    ///     fires the death sound + collision tap; `finishDeath()` performs the restart
    ///     `wait()` would have done. ("Holding position is risky," D-066.)
    ///   • A **survived wait** plays the calm `.stay` tick layered with any echoes that
    ///     step this turn (one chord), bumps the in-place breath pulse, then commits
    ///     `wait()` inside `withAnimation(.step)` so every echo/hazard glides in lockstep
    ///     (the player holds, so it does not slide), and fires the light step tap.
    private func commitWait() {
        guard fold == nil, death == nil else { return }
        guard !state.hasWon else { return }

        let held = state.player
        let fatal = state.playerCollides(previousPlayerCell: held,
                                         newPlayerCell: held,
                                         turn: state.turn + 1)
        if fatal {
            triggerDeath(previous: held, contact: held)
            audio.playDeath()
            haptics.collision()
        } else {
            // The wait's own calm tick, layered with each echo whose recorded path still
            // has a move at this turn — derived read-only before the model advances, fired
            // at one audio time so the turn sounds as a chord (matching `commitMove`).
            let fromTurn = state.turn
            var ticks: [Direction] = [.stay]
            for echo in state.echoes where fromTurn < echo.moves.count {
                ticks.append(echo.moves[fromTurn])
            }
            audio.playStep(directions: ticks)

            waitPulseTick &+= 1
            withAnimation(Motion.step) {
                _ = state.wait()
            }
            haptics.step()
        }
    }

    // MARK: - Effect triggers (presentation only)

    /// Begin the fold choreography over the just-rewound board. Called from
    /// `onChange(of: state.echoes.count)` — the model has already folded (player and
    /// every echo are back on `start`, turn 0). The newest echo (`echoes.last`) is the
    /// one just banked; its run-end cell (`position` at the end of its recorded path)
    /// is where present-you stood when folding, so the peel starts there and rewinds
    /// to `start`.
    private func triggerFold() {
        guard let newEcho = state.echoes.last else { return }
        let runEnd = newEcho.position(start: state.start, turn: newEcho.moves.count)
        foldGeneration &+= 1
        fold = FoldEffect(id: foldGeneration, origin: state.start, peelFrom: runEnd,
                          newEchoID: newEcho.id, start: Date())
        // The fold sound (warm, weighty) and the medium impact tap, landing on the §6c
        // hit-pause onset. Both fire whenever a fold actually happens (the echo count
        // rose) and never on a refused fold (empty run / budget / post-win — the count
        // doesn't change), so they stay in step with the visual whatever triggered it.
        audio.playFold()
        haptics.fold()
    }

    /// Capture the kill and start the death dissolve — **without** mutating the model.
    /// Everything the overlay needs is derived read-only from the same pure position
    /// functions the board draws from, at the turn the fatal step would land on
    /// (`turn + 1`):
    ///   • the colliding echo(es): those whose `turn + 1` cell is the contact tile —
    ///     they glide there from their current cell and fizz with the player;
    ///   • the killer hazard (if any): the one whose glow pulses once (§6d).
    /// `finishDeath()` performs the restart later.
    ///
    /// The colliding-echo set is matched by **land-on only** (`turn + 1` cell ==
    /// contact). The engine's `playerCollides` also has an echo cross-paths (swap)
    /// branch, but it is parity-dormant against echoes (player and echoes share an
    /// origin and a one-step cadence, so they can never trade adjacent tiles — see
    /// `GameState.playerCollides`), so land-on captures every *reachable* echo death.
    /// If a future mechanic ever made an echo move off the player's cadence, this
    /// would need the swap branch too; until then it is complete.
    private func triggerDeath(previous: GridCoordinate, contact: GridCoordinate) {
        // The recurring death caption (handover §6 / §8.2), fading in over the §6d
        // freeze frame. The only failure caption in the designed set, so it captions
        // every death dissolve — an echo touch or a hazard touch alike (D-052).
        guidance.showEaten()

        let deathTurn = state.turn + 1
        let collidingEchoes = state.echoes.filter {
            // Pad-aware (Phase 4.03): match the echo at its teleport-resolved tile, so an
            // echo that killed you in the far region is the one shown fizzing (D-070).
            $0.position(start: state.start, turn: deathTurn, pads: state.padMap) == contact
        }
        let killer = state.hazards.first { hazard in
            let now = hazard.position(at: deathTurn)
            if now == contact { return true }                        // land-on
            let before = hazard.position(at: state.turn)
            return before == contact && now == previous              // cross-paths (swap)
        }

        deathGeneration &+= 1
        death = DeathEffect(
            id: deathGeneration,
            previous: previous,
            contact: contact,
            echoOrigins: collidingEchoes.map { state.position(of: $0) },
            collidingEchoIDs: Set(collidingEchoes.map(\.id)),
            // Pulse the glow on the killer where its diamond is actually drawn — its
            // current (held) tile — so the "it got you" flare sits on the visible
            // enemy. The model is held at this turn during the dissolve, so the steady
            // diamond stays here; pulsing at its post-step tile would float the glow a
            // cell away from the enemy that caused it.
            killerHazard: killer.map { state.position(of: $0) },
            start: Date())
    }

    /// End the death dissolve by performing the restart the engine would have done on
    /// the fatal step — present-you back to `start`, the run scrapped, every folded
    /// echo intact (`restartRun()` is exactly that op). Instant and clean: not wrapped
    /// in an animation, so the board snaps back on the next frame (handover §6d).
    private func finishDeath() {
        state.restartRun()
        death = nil
    }
}

/// The per-axis scale used by the squash-and-stretch / anticipation keyframes:
/// `along` the travel axis, `across` it. Resting value is `(1, 1)`; the keyframe
/// tracks perturb it for ~160 ms (player) / ~140 ms (enemy) and return to rest.
private struct Squash {
    var along: CGFloat = 1
    var across: CGFloat = 1
}

/// The single symmetric scale used by the survived-wait "breath" keyframe (Phase 4.01).
/// Resting value is `1`; the keyframe lifts it to `1.06` and back over ~180 ms so a wait
/// reads as a gentle in-place pulse rather than a directional step squash.
private struct Breath {
    var scale: CGFloat = 1
}

/// The first-pass teleport-pad glyph (Phase 4.03 / D-070): four corner brackets framing a
/// cell, drawn as a single stroked path (an open square broken at the edge midpoints), so
/// a pad reads as a distinct "portal frame" against the round/bar/solid marks. `armFraction`
/// is each corner arm's length as a fraction of the (square) side. `nonisolated` so the
/// `Shape.path(in:)` requirement (a `nonisolated` protocol member) is satisfiable under the
/// app's default-MainActor isolation (D-040), matching the other value types here.
nonisolated struct PadGlyph: Shape {
    var armFraction: CGFloat = 0.32

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let arm = min(rect.width, rect.height) * armFraction
        let (minX, maxX, minY, maxY) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        // Top-left corner.
        p.move(to: CGPoint(x: minX, y: minY + arm))
        p.addLine(to: CGPoint(x: minX, y: minY))
        p.addLine(to: CGPoint(x: minX + arm, y: minY))
        // Top-right corner.
        p.move(to: CGPoint(x: maxX - arm, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY + arm))
        // Bottom-right corner.
        p.move(to: CGPoint(x: maxX, y: maxY - arm))
        p.addLine(to: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: maxX - arm, y: maxY))
        // Bottom-left corner.
        p.move(to: CGPoint(x: minX + arm, y: maxY))
        p.addLine(to: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX, y: maxY - arm))
        return p
    }
}

/// One dot of an echo-trail line. `id` is the dot's order outward from the echo, which
/// both keys it in the `ForEach` and drives its reveal stagger (Phase 2.06).
private struct TrailDot: Identifiable {
    let id: Int
    let point: CGPoint
}

/// One echo's upcoming-path dots, with the §6f reveal/fade behaviour. Kept as its own
/// view (one per echo) so each owns a `revealed` state: the dots reveal outward from
/// the echo with an `8 ms`-per-dot stagger on appear, hold while `active`, and fade
/// over `150 ms` `curve.easeIn` when the aid is switched off (`active` → false) before
/// `BoardView` unmounts the layer. Hit-testing off; purely a read of echo intent.
private struct EchoTrailLayer: View {
    let dots: [TrailDot]
    let dotSize: CGFloat
    /// The `echo.base` hue; the dot opacity (`opacity.trailDot` = 0.40) is applied here.
    let color: Color
    /// Whether the aid is on. When it flips to `false` the dots fade out.
    let active: Bool

    /// Flips true on appear to drive the staggered reveal (an initial mount does not
    /// animate, so the appearance is what the reveal animation keys off).
    @State private var revealed = false

    var body: some View {
        ZStack {
            ForEach(dots) { dot in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .position(dot.point)
                    .opacity(revealed && active ? BoardMetrics.trailDotOpacity : 0)
                    // Reveal (per-dot stagger) when turning on; plain easeIn fade when off.
                    .animation(active ? Motion.trailReveal.delay(Double(dot.id) * 0.008)
                                      : Motion.trailFadeOut,
                               value: revealed && active)
            }
        }
        .allowsHitTesting(false)
        .onAppear { revealed = true }
    }
}

private extension View {
    /// The handover's `glow.accent` (blur 8, spread 2 around the shape) approximated
    /// with two stacked colour shadows — a soft halo that renders *outside* the shape
    /// and is never clipped. `enabled == false` (or a `.clear` colour) draws nothing,
    /// so a non-glowing state pays no cost.
    @ViewBuilder
    func accentGlow(_ color: Color, cell: CGFloat, enabled: Bool = true) -> some View {
        if enabled {
            let blur = BoardMetrics.glowBlur / BoardMetrics.referenceCell * cell
            let spread = BoardMetrics.glowSpread / BoardMetrics.referenceCell * cell
            self
                .shadow(color: color, radius: blur)
                .shadow(color: color, radius: spread)   // a touch more bloom ≈ the "spread"
        } else {
            self
        }
    }
}

#Preview("Light") {
    BoardView(state: GameState(), audio: AudioManager(), haptics: HapticsManager(),
              showEchoTrail: false, guidance: GuidanceController())
        .environment(\.theme, .light)
        .background(Color(hex: 0xF5EDDD))
}

#Preview("Invert") {
    BoardView(state: GameState(), audio: AudioManager(), haptics: HapticsManager(),
              showEchoTrail: false, guidance: GuidanceController())
        .environment(\.theme, .invert)
        .background(Color(hex: 0x141210))
}
