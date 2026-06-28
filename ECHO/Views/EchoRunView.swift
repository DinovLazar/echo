//
//  EchoRunView.swift
//  ECHO
//
//  Phase 3.02 (Echo Run — the arcade survival mode). The arcade board screen, driven by
//  the separate `EchoRunState` engine (D-058). It is a small, dedicated board view —
//  `BoardView` is tightly coupled to `GameState`/`Level` (walls, doors, switches,
//  hazards, guidance, the fold choreography), none of which Echo Run has — so rather
//  than bend it, this reuses the shared feel layer directly: `Theme`/`BoardMetrics` for
//  the look, `Motion` for the lockstep slide + squash, `BoardEffects` for the death
//  freeze + particle fizz, and `AudioManager`/`HapticsManager` for the same per-move
//  ticks and taps as the campaign. The player and shadow styling match `BoardView`'s
//  (ink rounded square + the only shadow; translucent-grey rounded squares that recede).
//
//  Death is handled exactly as the campaign's: the fatal turn is *predicted* (the engine
//  is not mutated yet) so `BoardEffectsOverlay` can play the glide → freeze → fizz over a
//  frozen board, then `finishDeath()` commits the move (finalizing `isOver`/`score`),
//  saves the high score through `SettingsStore`, and reveals the game-over panel.
//
//  Phase 3.03 (Navigation shell) wires the real flow (D-059): Echo Run is now entered
//  from the Main Menu, the top-bar chevron and the game-over "Main menu" both route back
//  to it via `onMainMenu`, and the interim game-over panel is replaced by the real
//  game-over overlay (the turns-survived score as the dominant number, "best N" / "new
//  best!", then Retry → `EchoRunState.reset()` and Main menu). The arcade board, the
//  deferred-death dissolve, and `EchoRunState` are unchanged — only the game-over and the
//  exit routing changed. Self-contained: it provides its own paper background.
//

import SwiftUI

struct EchoRunView: View {
    /// The arcade engine, created here and owned for the screen's lifetime.
    @State private var state = EchoRunState()

    /// The persisted store, for the Echo Run high score (read for display, written on
    /// death via `recordEchoRunScore`). Owned by `ContentView` and passed in.
    let settings: SettingsStore
    /// The shared audio manager (already started by `ContentView`) — Echo Run voices the
    /// same per-move tick chord and the death puff.
    let audio: AudioManager
    /// The shared haptics manager (already pre-warmed by `ContentView`) — a light tick on
    /// each committed turn, the soft error on a catch.
    let haptics: HapticsManager
    /// Leave Echo Run for the Main Menu — the top-bar chevron and the game-over "Main
    /// menu" both call this (Phase 3.03 / D-059). The root performs the fade.
    let onMainMenu: () -> Void

    @Environment(\.theme) private var theme

    /// Bumped once per **real** committed step (not a stall) to fire the player's
    /// squash-and-stretch, exactly as `BoardView` does.
    @State private var stepTick = 0
    /// Whether the last real step was horizontal — chooses the squash axis.
    @State private var lastStepHorizontal = true

    /// The in-flight death dissolve (glide → freeze → fizz), or `nil` at rest. Set the
    /// instant a fatal turn is predicted — **before** the engine is mutated — so the
    /// canvas can show the catch at the contact tile; `finishDeath()` commits + reveals
    /// game-over once it has played.
    @State private var death: DeathEffect? = nil
    /// The deferred fatal direction, committed by `finishDeath()` after the dissolve.
    @State private var pendingFatalDirection: Direction? = nil
    /// Monotonic generation so each death keys its own cleanup `task`.
    @State private var deathGeneration = 0

    /// Whether the interim game-over panel is showing (the run is over and dissolved).
    @State private var showGameOver = false
    /// Whether the run that just ended set a new high score (for the game-over caption).
    @State private var lastRunWasBest = false

    /// Board occupies this fraction of the smaller available dimension (matches `BoardView`).
    private static let fillFraction: CGFloat = 0.82
    /// Minimum drag distance that counts as a swipe rather than a tap (matches `BoardView`).
    private static let swipeThreshold: CGFloat = 20

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                board
            }
            if showGameOver {
                gameOverPanel
            }
        }
    }

    // MARK: - Top bar (interim)

    /// The score strip: a back chevron (→ Main Menu), the live score centred, and the
    /// best so far trailing. Sits above the board, clear of the swipe area.
    private var topBar: some View {
        ZStack {
            Text("\(state.score)")
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(theme.ink)
            HStack {
                Button { onMainMenu() } label: { Image(systemName: "chevron.left") }
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
                Text("best \(settings.echoRunHighScore)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.textGuidance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - The arcade board

    private var board: some View {
        GeometryReader { proxy in
            let available = min(proxy.size.width, proxy.size.height) * Self.fillFraction
            let cell = available / CGFloat(state.size)
            let boardSize = CGSize(width: cell * CGFloat(state.size),
                                   height: cell * CGFloat(state.size))

            ZStack(alignment: .topLeading) {
                lattice(cell: cell)
                echoes(cell: cell)
                playerSquare(cell: cell)
                if death != nil {
                    BoardEffectsOverlay(fold: nil, death: death, cell: cell, theme: theme)
                        .frame(width: boardSize.width, height: boardSize.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: boardSize.width, height: boardSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(swipeGesture)
            // Clear each death once it has fully played: commit the deferred fatal move
            // (finalizing the engine), save the high score, and reveal game-over.
            .task(id: deathGeneration) {
                guard death != nil else { return }
                let total = Motion.Span.step + Motion.Span.deathFreeze + Motion.Span.deathFizz
                try? await Task.sleep(for: .seconds(total))
                if !Task.isCancelled { finishDeath() }
            }
        }
    }

    /// The grid lattice — quiet hairline borders, each cell an independent tap target so a
    /// tap on a cell orthogonally adjacent to the player becomes a move (matches
    /// `BoardView`). This is the input layer; the pieces above have hit testing off.
    private func lattice(cell: CGFloat) -> some View {
        let hairline = scaled(BoardMetrics.strokeHairline, cell: cell)
        return VStack(spacing: 0) {
            ForEach(0..<state.size, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<state.size, id: \.self) { column in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: cell, height: cell)
                            .border(theme.tileHairline, width: hairline)
                            .contentShape(Rectangle())
                            .onTapGesture { tap(GridCoordinate(row: row, column: column)) }
                    }
                }
            }
        }
    }

    /// The shadows: a smaller translucent rounded square per echo (matches `BoardView`'s
    /// echo styling), flat — no squash, no shadow. They glide between their replayed
    /// cells on the same 120 ms `curve.standard` as the player (the slide comes from
    /// `withAnimation` wrapping the commit). A colliding shadow is hidden in this steady
    /// layer while the death overlay owns its dissolve, like the campaign.
    private func echoes(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.echoSize, cell: cell)
        let radius = scaled(BoardMetrics.radiusEcho, cell: cell)
        let stroke = scaled(BoardMetrics.strokeEcho, cell: cell)
        return ForEach(state.echoes) { echo in
            let position = state.position(of: echo)
            let dissolving = death?.collidingEchoIDs.contains(echo.id) == true
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.echoBase.opacity(theme.echoFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(theme.echoBase.opacity(theme.echoStrokeOpacity),
                                      lineWidth: stroke)
                )
                .frame(width: size, height: size)
                .position(center(of: position, cell: cell))
                .opacity(dissolving ? 0 : 1)
                .allowsHitTesting(false)
        }
    }

    /// The player — "you, now": the largest element, fully opaque ink, the only
    /// shadow-caster (matches `BoardView`). A real step slides 120 ms `curve.standard`
    /// with a departure squash-and-stretch + soft-snap settle; while a death dissolves,
    /// the overlay owns the player, so the steady square is hidden.
    private func playerSquare(cell: CGFloat) -> some View {
        let size = scaled(BoardMetrics.playerSize, cell: cell)
        let radius = scaled(BoardMetrics.radiusPlayer, cell: cell)
        let horizontal = lastStepHorizontal
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.ink)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: RunSquash(), trigger: stepTick) { view, squash in
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
            .shadow(color: theme.shadowColor,
                    radius: scaled(BoardMetrics.shadowBlur, cell: cell),
                    x: 0,
                    y: scaled(BoardMetrics.shadowOffsetY, cell: cell))
            .position(center(of: state.player, cell: cell))
            .opacity(death == nil ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - Game over

    /// The real game-over overlay (Phase 3.03 / D-059): over the frozen, dimmed arcade
    /// board, a small centred panel with the turns-survived score as the dominant number,
    /// "best N" (or "new best!" when this run set it) beneath, then Retry → `reset()` and
    /// Main menu → `onMainMenu`. Same restraint as the campaign win overlay — no fanfare.
    private var gameOverPanel: some View {
        ZStack {
            theme.paperBottom.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())   // capture taps so the frozen board behind is inert
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("\(state.score)")
                        .font(.system(size: 56, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.ink)
                    Text(lastRunWasBest ? "new best!" : "best \(settings.echoRunHighScore)")
                        .font(.footnote.monospacedDigit())
                        // Chrome-success green for a new best (D-055), not the board's goal
                        // gold; paired with the "new best!" text change so it is never the
                        // only cue.
                        .foregroundStyle(lastRunWasBest ? theme.solvedGreen : theme.textGuidance)
                }
                HStack(spacing: 8) {
                    Button("Retry") { retry() }
                        .buttonStyle(ControlButtonStyle(prominentFill: theme.ink,
                                                        prominentLabel: theme.paperTop))
                    Button("Main menu") { onMainMenu() }
                        .buttonStyle(ControlButtonStyle())
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.paperTop)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(theme.tileHairline, lineWidth: 1))
                    .shadow(color: theme.shadowColor, radius: 12, y: 4)
            )
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Input

    /// A tap on a cell orthogonally adjacent to the player steps into it (a tap can never
    /// produce a stall — that only an edge swipe can).
    private func tap(_ cell: GridCoordinate) {
        guard let direction = Direction(from: state.player, to: cell) else { return }
        commit(direction)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: Self.swipeThreshold)
            .onEnded { value in
                guard let direction = swipeDirection(value.translation) else { return }
                commit(direction)
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

    // MARK: - Commit (presentation + engine)

    /// Run one input through the arcade engine and choose how to *display* it, mirroring
    /// the campaign's `commitMove`:
    ///   • Input is locked while a death dissolve plays or the run is over.
    ///   • A fatal turn → **defer** the commit: hand `BoardEffects` a death descriptor
    ///     (glide from `previous` to `contact`, the touched shadows fizzing) and fire the
    ///     death puff + error tap now; `finishDeath()` commits and reveals game-over.
    ///   • A survived turn (real step or stall) → voice the per-move chord (the player's
    ///     tick, if it moved, plus one per stepping shadow), wrap the commit in
    ///     `withAnimation(.step)` so the player and shadows glide in lockstep, and (on a
    ///     real step only) bump the squash trigger.
    private func commit(_ direction: Direction) {
        guard death == nil, !showGameOver, !state.isOver else { return }
        let target = GridCoordinate(row: state.player.row + direction.offset.row,
                                    column: state.player.column + direction.offset.column)

        if let pending = state.pendingDeath(for: direction) {
            audio.playDeath()
            haptics.collision()
            pendingFatalDirection = direction
            deathGeneration &+= 1
            death = DeathEffect(id: deathGeneration,
                                previous: pending.previous,
                                contact: pending.contact,
                                echoOrigins: pending.echoes.map { state.position(of: $0) },
                                collidingEchoIDs: Set(pending.echoes.map(\.id)),
                                killerHazard: nil,
                                start: Date())
            return
        }

        let moved = state.contains(target)
        var ticks: [Direction] = moved ? [direction] : []
        ticks += state.echoMovesNextTurn
        audio.playStep(directions: ticks)

        if moved {
            lastStepHorizontal = (direction == .left || direction == .right)
            stepTick &+= 1
        }
        withAnimation(Motion.step) { _ = state.move(direction) }
        haptics.step()
    }

    /// End the death dissolve: commit the deferred fatal move (finalizing `isOver` and
    /// `score`), persist the high score, and show the interim game-over panel. The commit
    /// is unanimated — the board is mid-dissolve and about to be covered by the panel.
    private func finishDeath() {
        if let direction = pendingFatalDirection {
            state.move(direction)
            pendingFatalDirection = nil
        }
        lastRunWasBest = settings.recordEchoRunScore(state.score)
        death = nil
        showGameOver = true
    }

    /// Instant Retry — reset to turn 0 (empty recording, no shadows, player at centre).
    private func retry() {
        showGameOver = false
        lastRunWasBest = false
        state.reset()
    }

    // MARK: - Geometry (mirrors BoardView's)

    private func scaled(_ points: CGFloat, cell: CGFloat) -> CGFloat {
        points / BoardMetrics.referenceCell * cell
    }

    private func center(of coordinate: GridCoordinate, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(coordinate.column) + 0.5) * cell,
                y: (CGFloat(coordinate.row) + 0.5) * cell)
    }
}

/// The per-axis squash scale used by the player's squash-and-stretch keyframes (a local
/// copy of `BoardView`'s private `Squash`, since that one is file-private there).
private struct RunSquash {
    var along: CGFloat = 1
    var across: CGFloat = 1
}

#Preview("Light") {
    EchoRunView(settings: SettingsStore(), audio: AudioManager(), haptics: HapticsManager(),
                onMainMenu: {})
        .environment(\.theme, .light)
}

#Preview("Invert") {
    EchoRunView(settings: SettingsStore(), audio: AudioManager(), haptics: HapticsManager(),
                onMainMenu: {})
        .environment(\.theme, .invert)
}
