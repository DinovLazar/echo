//
//  MirrorBoardView.swift
//  ECHO
//
//  Phase 4.05 (the mirror render path — D-074/D-075). The two-body board for mirror
//  rooms, driven by the separate `MirrorGameState` engine. A dedicated view, like
//  Echo Run's (D-058): the verified single-body `BoardView` is tightly coupled to
//  `GameState` and stays untouched, so this reuses the shared feel layer directly —
//  `Theme`/`BoardMetrics` for the look, `Motion` for the lockstep slide + squash +
//  the wait "breath", `BoardEffects` for the fold peel and the death freeze + fizz
//  (one overlay per half, so each body's choreography plays at its own tiles), and
//  `AudioManager`/`HapticsManager` for the same ticks and taps as the campaign.
//
//  Drawn (all authored on the full grid): the centerline **divide** (a quiet ink
//  rule — structural, never the accent); both halves' walls / switches / doors /
//  hazards; **two exits** (each in the existing active-goal state — no new accent
//  rule); **two live bodies** (the black rounded square, one per half); each mirror
//  echo as **two grey bodies**; and the optional echo-trail aid per body.
//
//  **First-pass visuals — Design-refinable.** The divide, the two-body read, and the
//  double fold/death choreography are first guesses for a later Design pass.
//
//  Presentation only, one rule: every movement/death *prediction* here is read from
//  the engine's own pure surface — `plan(for:)` for the partial-movement resolution
//  and `bodyCollides` for the fatal check — never re-implemented (the Phase 4.03
//  lesson: a view-side copy of the engine's landing logic silently diverged; this
//  view deliberately has no copy to diverge). Like `BoardView`, a predicted fatal
//  input defers the model mutation until the dissolve has played (`finishDeath()`
//  performs the restart), and input is locked while any effect is in flight.
//
//  One known first-pass simplification: the death overlay matches colliding
//  echo-bodies by land-on only (as `BoardView` does). In mirror the echo cross-paths
//  branch is *live* (desync breaks parity), so a swap-death shows the dying bodies'
//  dissolve without the swapping echo-body's glide — the outcome is the engine's
//  either way; only that echo's cameo is missed. Design-refinable.
//

import SwiftUI

struct MirrorBoardView: View {
    /// The mirror board's state, owned by `ContentView` and passed in.
    let state: MirrorGameState

    /// The shared generative-audio manager — the same per-move tick chord, fold and
    /// death sounds as the campaign board (Phase 2.04).
    let audio: AudioManager

    /// The shared haptics manager — step / fold / collision / win taps on the same
    /// commit paths as the campaign board (Phase 2.05).
    let haptics: HapticsManager

    /// Whether the optional echo-trail aid is on (D-051) — drawn per echo-body here.
    let showEchoTrail: Bool

    /// The guidance microcopy controller (D-052); the death path fires `showEaten()`.
    let guidance: GuidanceController

    /// Outward report of this view's input lock, so `MirrorRoomView`'s controls honour
    /// the same fold/death lock the board's own input uses (D-059).
    var inputLock: Binding<Bool>? = nil

    /// The "wait requested" counter from the HUD's Wait control (D-068) — each
    /// increment runs one wait through the same guarded commit path a tap/swipe uses.
    var waitSignal: Int = 0

    @Environment(\.theme) private var theme

    /// Per-body squash triggers — bumped only for a body that actually moved on a
    /// survived step, so a blocked (desynced) body never squashes.
    @State private var leftStepTick = 0
    @State private var rightStepTick = 0
    /// Whether the last survived input was horizontal — the shared squash axis (the
    /// two bodies mirror, so both move horizontally or both vertically).
    @State private var lastStepHorizontal = true
    /// Bumped once per survived wait — both bodies share the in-place breath pulse.
    @State private var waitPulseTick = 0

    /// The in-flight fold choreography, one per half (the mirror fold banks a
    /// two-body echo, so each half plays its own §6c ripple + peel at its own start).
    @State private var foldLeft: FoldEffect? = nil
    @State private var foldRight: FoldEffect? = nil
    /// The in-flight death dissolve, one per body — a mirror death dissolves BOTH
    /// bodies (D-074), each at its own contact tile.
    @State private var deathLeft: DeathEffect? = nil
    @State private var deathRight: DeathEffect? = nil
    /// Monotonic generations keying each effect's cleanup task.
    @State private var foldGeneration = 0
    @State private var deathGeneration = 0

    /// Echo-trail mount state (mirrors `BoardView`'s: mounted while on or fading off).
    @State private var trailMounted = false

    /// Board fill fraction and swipe threshold — match `BoardView`.
    private static let fillFraction: CGFloat = 0.82
    private static let swipeThreshold: CGFloat = 20

    /// Whether any transient effect is in flight (the input lock).
    private var effectInFlight: Bool {
        foldLeft != nil || foldRight != nil || deathLeft != nil || deathRight != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let available = min(proxy.size.width, proxy.size.height) * Self.fillFraction
            let cell = available / CGFloat(max(state.width, state.height))
            let boardSize = CGSize(width: cell * CGFloat(state.width),
                                   height: cell * CGFloat(state.height))

            ZStack(alignment: .topLeading) {
                lattice(cell: cell)
                divide(cell: cell, boardSize: boardSize)
                walls(cell: cell)
                exitRings(cell: cell)
                doorBars(cell: cell)
                switchMarks(cell: cell)
                echoBodies(cell: cell)
                if trailMounted {
                    echoTrails(cell: cell)
                }
                hazardMarks(cell: cell)
                bodySquare(cell: cell, position: state.leftBody,
                           stepTick: leftStepTick, hidden: deathLeft != nil)
                bodySquare(cell: cell, position: state.rightBody,
                           stepTick: rightStepTick, hidden: deathRight != nil)
                // One effects overlay per half, mounted only while in flight — each
                // body's fold peel / death dissolve plays at its own tiles.
                if foldLeft != nil || deathLeft != nil {
                    BoardEffectsOverlay(fold: foldLeft, death: deathLeft, cell: cell, theme: theme)
                        .frame(width: boardSize.width, height: boardSize.height)
                        .allowsHitTesting(false)
                }
                if foldRight != nil || deathRight != nil {
                    BoardEffectsOverlay(fold: foldRight, death: deathRight, cell: cell, theme: theme)
                        .frame(width: boardSize.width, height: boardSize.height)
                        .allowsHitTesting(false)
                }
                GuidanceOverlay(message: guidance.message,
                                boardSize: boardSize,
                                placeUpper: max(state.leftBody.row, state.rightBody.row)
                                    >= state.height * 2 / 3,
                                color: theme.textGuidance)
                    .frame(width: boardSize.width, height: boardSize.height)
                    .allowsHitTesting(false)
            }
            .frame(width: boardSize.width, height: boardSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(swipeGesture)
            // A fold is the only thing that grows the echo count — play both halves'
            // choreography over the rewound board.
            .onChange(of: state.echoes.count) { old, new in
                if new > old { triggerFold() }
            }
            // Report the fold/death input lock outward (D-059).
            .onChange(of: effectInFlight) { _, locked in
                inputLock?.wrappedValue = locked
            }
            // A wait requested by the HUD's Wait control (D-068).
            .onChange(of: waitSignal) { _, _ in commitWait() }
            // Clear each effect once it has fully played; a death commits its deferred
            // restart here, at the end of the dissolve (§6d restart = 0 ms).
            .task(id: foldGeneration) {
                guard foldLeft != nil || foldRight != nil else { return }
                let total = Motion.Span.foldHitPause + max(Motion.Span.foldRipple, Motion.Span.foldPeel)
                try? await Task.sleep(for: .seconds(total))
                if !Task.isCancelled { foldLeft = nil; foldRight = nil }
            }
            .task(id: deathGeneration) {
                guard deathLeft != nil || deathRight != nil else { return }
                let total = Motion.Span.step + Motion.Span.deathFreeze + Motion.Span.deathFizz
                try? await Task.sleep(for: .seconds(total))
                if !Task.isCancelled { finishDeath() }
            }
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

    // MARK: - Structural marks

    /// The tap lattice — the input layer, exactly as `BoardView`'s.
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

    /// The centerline divide (first-pass): one quiet vertical ink rule down the
    /// middle of the board — clearly structural (louder than a hairline, far quieter
    /// than a wall), monochrome, never the accent. Design-refinable.
    private func divide(cell: CGFloat, boardSize: CGSize) -> some View {
        let width = scaled(BoardMetrics.divideWidth, cell: cell)
        return Rectangle()
            .fill(theme.ink.opacity(BoardMetrics.divideOpacity))
            .frame(width: width, height: boardSize.height)
            .position(x: CGFloat(state.midColumn) * cell, y: boardSize.height / 2)
            .allowsHitTesting(false)
    }

    /// Walls — the flat solid tile, matching `BoardView` (D-053).
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

    /// The two exits — both are always the live goal (you must reach both), so both
    /// render in the existing active-goal state (gold ring + glow). No new accent
    /// rule: this is exactly the single-exit treatment, twice.
    private func exitRings(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.exitSize, cell: cell)
        let stroke = scaled(BoardMetrics.strokeExitRing, cell: cell)
        return ForEach([state.exitLeft, state.exitRight], id: \.self) { exit in
            Circle()
                .strokeBorder(theme.goalGold, lineWidth: stroke)
                .frame(width: size, height: size)
                .accentGlow(theme.goalGlow, cell: cell)
                .position(center(of: exit, cell: cell))
                .allowsHitTesting(false)
        }
    }

    /// Doors — closed bar / open stubs, matching `BoardView` (state read per turn).
    private func doorBars(cell: CGFloat) -> some View {
        let thickness = scaled(BoardMetrics.doorThickness, cell: cell)
        let stub = scaled(BoardMetrics.doorStub, cell: cell)
        let radius = scaled(BoardMetrics.radiusDoorBar, cell: cell)
        return ForEach(state.doors) { door in
            let open = state.isDoorOpen(door)
            ForEach(Array(door.cells.enumerated()), id: \.offset) { _, doorCell in
                ZStack {
                    if open {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(theme.ink.opacity(BoardMetrics.doorOpenRemnant))
                            .frame(width: stub, height: thickness)
                            .offset(x: -(cell - stub) / 2)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(theme.ink.opacity(BoardMetrics.doorOpenRemnant))
                            .frame(width: stub, height: thickness)
                            .offset(x: (cell - stub) / 2)
                    } else {
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

    /// Switches — hollow ring (open) / filled gold + glow (held), matching `BoardView`.
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

    // MARK: - Pieces

    /// Each mirror echo as two grey bodies — one per half, each the standard
    /// translucent echo square, sliding in lockstep with the shared turn. A body is
    /// hidden while an effects overlay owns its appearance (fold peel / death fizz).
    private func echoBodies(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.echoSize, cell: cell)
        let radius = scaled(BoardMetrics.radiusEcho, cell: cell)
        let stroke = scaled(BoardMetrics.strokeEcho, cell: cell)
        return ForEach(state.echoes) { pair in
            ForEach([(pair.left, state.leftPosition(of: pair)),
                     (pair.right, state.rightPosition(of: pair))], id: \.0.id) { body, position in
                let dissolving = deathLeft?.collidingEchoIDs.contains(body.id) == true
                    || deathRight?.collidingEchoIDs.contains(body.id) == true
                let peeling = foldLeft?.newEchoID == body.id || foldRight?.newEchoID == body.id
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
    }

    /// The echo-trail aid, per echo-body (a deliberate small copy of `BoardView`'s
    /// private trail layer — D-075 accepts duplicated rendering to keep the verified
    /// board untouched).
    private func echoTrails(cell: CGFloat) -> some View {
        let dotSize = scaled(BoardMetrics.trailDotSize, cell: cell)
        let spacing = scaled(BoardMetrics.trailDotSpacing, cell: cell)
        return ForEach(state.echoes) { pair in
            ForEach([(pair.left.id, state.leftPosition(of: pair), state.leftUpcomingCells(of: pair)),
                     (pair.right.id, state.rightPosition(of: pair), state.rightUpcomingCells(of: pair))],
                    id: \.0) { _, position, upcoming in
                if !upcoming.isEmpty {
                    let points = ([position] + upcoming).map { center(of: $0, cell: cell) }
                    MirrorTrailLayer(dots: trailDots(along: points, spacing: spacing),
                                     dotSize: dotSize,
                                     color: theme.echoBase,
                                     active: showEchoTrail)
                }
            }
        }
    }

    /// Resample a polyline into evenly-spaced dots (a copy of `BoardView`'s).
    private func trailDots(along points: [CGPoint], spacing: CGFloat) -> [MirrorTrailDot] {
        guard points.count >= 2, spacing > 0 else { return [] }
        var dots: [MirrorTrailDot] = []
        var order = 0
        var carry = spacing
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            if length == 0 { continue }
            var distance = carry
            while distance <= length {
                let t = distance / length
                dots.append(MirrorTrailDot(id: order, point: CGPoint(x: a.x + dx * t, y: a.y + dy * t)))
                order += 1
                distance += spacing
            }
            carry = distance - length
        }
        return dots
    }

    /// Hazards — the red diamond with anticipation lean-in, matching `BoardView`.
    private func hazardMarks(cell: CGFloat) -> some View {
        ForEach(state.hazards) { hazard in
            let current = hazard.position(at: state.turn)
            let previous = hazard.position(at: max(0, state.turn - 1))
            let moved = current != previous
            let horizontal = current.column != previous.column
            enemyDiamond(cell: cell)
                .keyframeAnimator(initialValue: MirrorSquash(), trigger: leftStepTick &+ rightStepTick) { view, squash in
                    let s = moved ? squash : MirrorSquash()
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
                .transaction { t in
                    if t.animation != nil { t.animation = Motion.enemyStep }
                }
                .allowsHitTesting(false)
        }
    }

    /// One enemy diamond (a copy of `BoardView`'s private builder).
    private func enemyDiamond(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.enemySize, cell: cell)
        let side = size / sqrt(2)
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

    /// One live body — "you, now", twice: the same ink square, squash-and-stretch,
    /// wait breath, and sole-shadow treatment as the single-body player (§2.1/§3).
    /// Each body squashes only when it actually moved (`stepTick` is per body), so a
    /// blocked, desynced body visibly holds still — the mechanic's own feedback.
    private func bodySquare(cell: CGFloat, position: GridCoordinate,
                            stepTick: Int, hidden: Bool) -> some View {
        let size = scaled(BoardMetrics.playerSize, cell: cell)
        let radius = scaled(BoardMetrics.radiusPlayer, cell: cell)
        let horizontal = lastStepHorizontal
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.ink)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: MirrorSquash(), trigger: stepTick) { view, squash in
                view.scaleEffect(x: horizontal ? squash.along : squash.across,
                                 y: horizontal ? squash.across : squash.along)
            } keyframes: { _ in
                KeyframeTrack(\.along) {
                    CubicKeyframe(0.94, duration: 0.040)
                    CubicKeyframe(1.0, duration: 0.080)
                    CubicKeyframe(1.06, duration: 0.020)
                    CubicKeyframe(1.0, duration: 0.020)
                }
                KeyframeTrack(\.across) {
                    CubicKeyframe(1.06, duration: 0.040)
                    CubicKeyframe(1.0, duration: 0.080)
                    CubicKeyframe(1.06, duration: 0.020)
                    CubicKeyframe(1.0, duration: 0.020)
                }
            }
            .keyframeAnimator(initialValue: MirrorBreath(), trigger: waitPulseTick) { view, breath in
                view.scaleEffect(breath.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.06, duration: 0.090)
                    CubicKeyframe(1.0, duration: 0.090)
                }
            }
            .shadow(color: theme.shadowColor,
                    radius: scaled(BoardMetrics.shadowBlur, cell: cell),
                    x: 0,
                    y: scaled(BoardMetrics.shadowOffsetY, cell: cell))
            .position(center(of: position, cell: cell))
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(false)
    }

    // MARK: - Geometry

    private func scaled(_ points: CGFloat, cell: CGFloat) -> CGFloat {
        points / BoardMetrics.referenceCell * cell
    }

    private func center(of coordinate: GridCoordinate, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(coordinate.column) + 0.5) * cell,
                y: (CGFloat(coordinate.row) + 0.5) * cell)
    }

    // MARK: - Input

    /// A tap on a cell orthogonally adjacent to EITHER body becomes the input that
    /// steps that body there: adjacent to the left body → the direction itself (the
    /// input drives the left body directly); adjacent to the right body → the
    /// direction's mirror (so the right body, which mirrors the input, steps toward
    /// the tap). Anything else is ignored.
    private func tap(_ cell: GridCoordinate) {
        if let direction = Direction(from: state.leftBody, to: cell) {
            commitMove(direction)
        } else if let direction = Direction(from: state.rightBody, to: cell) {
            commitMove(direction.horizontallyMirrored)
        }
    }

    /// A swipe's dominant axis is the input direction (left-body semantics — the
    /// right body mirrors it), exactly the campaign's swipe rule.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: Self.swipeThreshold)
            .onEnded { value in
                guard let direction = swipeDirection(value.translation) else { return }
                commitMove(direction)
            }
    }

    private func swipeDirection(_ translation: CGSize) -> Direction? {
        if translation == .zero { return nil }
        if abs(translation.width) >= abs(translation.height) {
            return translation.width < 0 ? .left : .right
        } else {
            return translation.height < 0 ? .up : .down
        }
    }

    // MARK: - Commit (presentation + engine; the engine's own predicates predict)

    /// Run one input through the mirror engine and choose how to display it. The
    /// prediction reads only the engine's pure surface: `plan(for:)` resolves the
    /// partial movement (which bodies move, where they land) and `bodyCollides`
    /// decides fatality at the planned tiles — the exact predicates `move(_:)` runs,
    /// so the presentation can never disagree with the outcome.
    private func commitMove(_ direction: Direction) {
        guard !effectInFlight else { return }
        guard !state.hasWon else { return }
        let plan = state.plan(for: direction)
        guard plan.commits else { return }             // both bodies blocked: nothing moves

        let deathTurn = state.turn + 1
        let leftFatal = state.bodyCollides(previousBodyCell: state.leftBody,
                                           newBodyCell: plan.leftTarget, turn: deathTurn)
        let rightFatal = state.bodyCollides(previousBodyCell: state.rightBody,
                                            newBodyCell: plan.rightTarget, turn: deathTurn)
        if leftFatal || rightFatal {
            // Either body's touch dissolves BOTH (D-074): defer the model mutation and
            // play a dissolve per body, each at its own landing tile.
            triggerDeath(leftContact: plan.leftTarget, rightContact: plan.rightTarget)
            audio.playDeath()
            haptics.collision()
        } else {
            // One tick per stepping entity this turn: each live body's actual step
            // (a blocked body contributes its calm `.stay` — desync is audible) plus
            // each echo-body's recorded move, all as one chord (Phase 2.04).
            let fromTurn = state.turn
            var ticks: [Direction] = [plan.leftStep, plan.rightStep]
            for pair in state.echoes {
                if fromTurn < pair.left.moves.count { ticks.append(pair.left.moves[fromTurn]) }
                if fromTurn < pair.right.moves.count { ticks.append(pair.right.moves[fromTurn]) }
            }
            audio.playStep(directions: ticks)

            lastStepHorizontal = (direction == .left || direction == .right)
            if plan.leftStep != .stay { leftStepTick &+= 1 }
            if plan.rightStep != .stay { rightStepTick &+= 1 }
            withAnimation(Motion.step) {
                _ = state.move(direction)
            }
            if state.hasWon {
                audio.playSolve()
                haptics.win()
            } else {
                haptics.step()
            }
        }
    }

    /// Pass a turn in place — both bodies hold and breathe (D-066/D-068). Mirrors
    /// `commitMove`'s structure; a fatal wait (a mover landing on either held body)
    /// defers exactly like a fatal step.
    private func commitWait() {
        guard !effectInFlight else { return }
        guard !state.hasWon else { return }

        let deathTurn = state.turn + 1
        let leftFatal = state.bodyCollides(previousBodyCell: state.leftBody,
                                           newBodyCell: state.leftBody, turn: deathTurn)
        let rightFatal = state.bodyCollides(previousBodyCell: state.rightBody,
                                            newBodyCell: state.rightBody, turn: deathTurn)
        if leftFatal || rightFatal {
            triggerDeath(leftContact: state.leftBody, rightContact: state.rightBody)
            audio.playDeath()
            haptics.collision()
        } else {
            let fromTurn = state.turn
            var ticks: [Direction] = [.stay]
            for pair in state.echoes {
                if fromTurn < pair.left.moves.count { ticks.append(pair.left.moves[fromTurn]) }
                if fromTurn < pair.right.moves.count { ticks.append(pair.right.moves[fromTurn]) }
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

    /// Play both halves' fold choreography over the rewound board — the mirror fold
    /// banks one two-body echo, so each half ripples from its own start and peels its
    /// own grey body in from its half's run-end.
    private func triggerFold() {
        guard let pair = state.echoes.last else { return }
        foldGeneration &+= 1
        foldLeft = FoldEffect(id: foldGeneration,
                              origin: state.startLeft,
                              peelFrom: pair.left.position(start: state.startLeft,
                                                           turn: pair.left.moves.count),
                              newEchoID: pair.left.id, start: Date())
        foldRight = FoldEffect(id: foldGeneration,
                               origin: state.startRight,
                               peelFrom: pair.right.position(start: state.startRight,
                                                             turn: pair.right.moves.count),
                               newEchoID: pair.right.id, start: Date())
        audio.playFold()
        haptics.fold()
    }

    /// Capture the kill and start BOTH bodies' dissolves without mutating the model
    /// — a mirror death dissolves both (D-074), each at its own landing tile. The
    /// colliding echo-bodies and any killer hazard are matched per contact tile from
    /// the same pure position functions the board draws from (land-on; see header).
    private func triggerDeath(leftContact: GridCoordinate, rightContact: GridCoordinate) {
        guidance.showEaten()
        let deathTurn = state.turn + 1
        deathGeneration &+= 1
        deathLeft = makeDeathEffect(previous: state.leftBody, contact: leftContact,
                                    deathTurn: deathTurn)
        deathRight = makeDeathEffect(previous: state.rightBody, contact: rightContact,
                                     deathTurn: deathTurn)
    }

    /// One body's death descriptor: the echo-bodies that land on its contact tile
    /// this turn (they glide there and fizz with it) and the killer hazard, if any.
    private func makeDeathEffect(previous: GridCoordinate, contact: GridCoordinate,
                                 deathTurn: Int) -> DeathEffect {
        var origins: [GridCoordinate] = []
        var ids: Set<UUID> = []
        for pair in state.echoes {
            if pair.left.position(start: state.startLeft, turn: deathTurn) == contact {
                origins.append(state.leftPosition(of: pair))
                ids.insert(pair.left.id)
            }
            if pair.right.position(start: state.startRight, turn: deathTurn) == contact {
                origins.append(state.rightPosition(of: pair))
                ids.insert(pair.right.id)
            }
        }
        let killer = state.hazards.first { hazard in
            let now = hazard.position(at: deathTurn)
            if now == contact { return true }                        // land-on
            let before = hazard.position(at: deathTurn - 1)
            return before == contact && now == previous              // cross-paths (swap)
        }
        return DeathEffect(id: deathGeneration,
                           previous: previous,
                           contact: contact,
                           echoOrigins: origins,
                           collidingEchoIDs: ids,
                           killerHazard: killer.map { state.position(of: $0) },
                           start: Date())
    }

    /// End the dissolve by performing the restart the engine would have done on the
    /// fatal input — both bodies back to their starts, the run scrapped, every mirror
    /// echo intact. Instant, unanimated (§6d restart = 0 ms).
    private func finishDeath() {
        state.restartRun()
        deathLeft = nil
        deathRight = nil
    }
}

/// Per-axis squash for the body/enemy keyframes (a local copy of `BoardView`'s
/// private `Squash`, like Echo Run's `RunSquash`).
private struct MirrorSquash {
    var along: CGFloat = 1
    var across: CGFloat = 1
}

/// The wait "breath" scale (a local copy of `BoardView`'s private `Breath`).
private struct MirrorBreath {
    var scale: CGFloat = 1
}

/// One trail dot (a local copy of `BoardView`'s private `TrailDot`).
private struct MirrorTrailDot: Identifiable {
    let id: Int
    let point: CGPoint
}

/// One echo-body's upcoming-path dots with the §6f reveal/fade behaviour (a local
/// copy of `BoardView`'s private `EchoTrailLayer` — D-075 accepts this duplication
/// to keep the verified single-body board untouched).
private struct MirrorTrailLayer: View {
    let dots: [MirrorTrailDot]
    let dotSize: CGFloat
    let color: Color
    let active: Bool

    @State private var revealed = false

    var body: some View {
        ZStack {
            ForEach(dots) { dot in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .position(dot.point)
                    .opacity(revealed && active ? BoardMetrics.trailDotOpacity : 0)
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
    /// The soft accent halo (a local copy of `BoardView`'s private `accentGlow` —
    /// same two stacked colour shadows, never clipped).
    @ViewBuilder
    func accentGlow(_ color: Color, cell: CGFloat, enabled: Bool = true) -> some View {
        if enabled {
            let blur = BoardMetrics.glowBlur / BoardMetrics.referenceCell * cell
            let spread = BoardMetrics.glowSpread / BoardMetrics.referenceCell * cell
            self
                .shadow(color: color, radius: blur)
                .shadow(color: color, radius: spread)
        } else {
            self
        }
    }
}
