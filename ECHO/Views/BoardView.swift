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
                exitRing(cell: cell)
                doorBars(cell: cell)
                switchMarks(cell: cell)
                echoes(cell: cell)
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
    /// with a top-light → bottom-dark gradient that gives just enough depth to read
    /// as solid matter, not a drawn outline (§2.3).
    private func walls(cell: CGFloat) -> some View {
        let inset = scaled(BoardMetrics.wallInset, cell: cell)
        let size = cell - inset * 2
        let radius = scaled(BoardMetrics.radiusWall, cell: cell)
        return ForEach(Array(state.walls), id: \.self) { wall in
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [theme.wallTop, theme.wallBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .position(center(of: wall, cell: cell))
                .allowsHitTesting(false)
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
        let target = GridCoordinate(row: state.player.row + direction.offset.row,
                                    column: state.player.column + direction.offset.column)
        // Same guards as `GameState.move(_:)` — a refused move animates nothing.
        guard state.contains(target),
              !state.isWall(target),
              !state.isClosedDoor(target) else { return }

        let fatal = state.playerCollides(previousPlayerCell: state.player,
                                         newPlayerCell: target,
                                         turn: state.turn + 1)
        if fatal {
            triggerDeath(previous: state.player, contact: target)
        } else {
            lastStepHorizontal = (direction == .left || direction == .right)
            stepTick &+= 1
            withAnimation(Motion.step) {
                _ = state.move(direction)
            }
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
        let deathTurn = state.turn + 1
        let collidingEchoes = state.echoes.filter {
            $0.position(start: state.start, turn: deathTurn) == contact
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
    BoardView(state: GameState())
        .environment(\.theme, .light)
        .background(Color(hex: 0xF5EDDD))
}

#Preview("Invert") {
    BoardView(state: GameState())
        .environment(\.theme, .invert)
        .background(Color(hex: 0x141210))
}
