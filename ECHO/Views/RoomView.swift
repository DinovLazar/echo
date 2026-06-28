//
//  RoomView.swift
//  ECHO
//
//  Phase 3.03 (Navigation shell). The campaign room screen (Plan §4 screens 4–5). It
//  reuses `BoardView` as-is for the board and composes the real in-room HUD around it —
//  the 2.07 layout (D-054), with the interim entry buttons replaced by a real back
//  affordance and the debug `Next`/`Clear` removed:
//    • a top strip — a back chevron (→ Level Select), the centred room number, and the
//      live turn/echoes readout;
//    • the board (`BoardView`);
//    • a bottom action row of three real `ControlButtonStyle` buttons — Fold / Step back /
//      Reset run.
//
//  The `GameState` is owned by `ContentView` (built once per room open and passed in), so
//  this view stays free of a custom `@State` initializer; it is given a fresh identity per
//  room (`.id(roomID)` at the call site), so its win overlay never leaks between rooms.
//
//  Correctness cleanup (D-059): the controls route through the **input-lock-guarded** path
//  — they honour `BoardView`'s `fold == nil && death == nil` lock (mirrored into
//  `inputLocked`) instead of mutating `state` directly mid-effect, which a deferred death
//  required (its restart is committed only once the dissolve ends). On reaching the exit,
//  the room is marked solved (`SettingsStore.markSolved`) and the real win overlay is
//  shown, with the final-room "Campaign complete" branch.
//

import SwiftUI

struct RoomView: View {
    /// The board state for this room — owned by `ContentView` and passed in (a fresh
    /// `GameState(level:)` per room open). Observed, so this view re-renders on a move.
    let state: GameState
    /// This room's id (the `Campaign.roomIDs` identifier).
    let roomID: String

    let settings: SettingsStore
    let audio: AudioManager
    let haptics: HapticsManager
    let guidance: GuidanceController

    /// Leave this room for Level Select (the back chevron, and the win overlay's "Level
    /// select"). The root performs the fade.
    let onLevelSelect: () -> Void
    /// Advance to the given next room id (the win overlay's "Next room"). Only offered when
    /// `Campaign.next(after:)` is non-nil (not the final room).
    let onAdvance: (String) -> Void

    @Environment(\.theme) private var theme

    /// Mirrors `BoardView`'s fold/death input lock so the out-of-board controls honour it
    /// (D-059). `BoardView` writes it through the `inputLock` binding.
    @State private var inputLocked = false
    /// Whether the win overlay is showing (set when `state.hasWon` flips true).
    @State private var showWin = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topHUD
                BoardView(state: state, audio: audio, haptics: haptics,
                          showEchoTrail: settings.echoTrailEnabled, guidance: guidance,
                          inputLock: $inputLocked)
                controlBar
            }
            if showWin {
                winOverlay
            }
        }
        // Fire this room's one-time guidance hint when the screen appears (once per room —
        // the screen has a fresh identity per room, D-052).
        .task { guidance.enterRoom(roomID) }
        // Reaching the exit alive flips `hasWon`: mark the room solved and reveal the win
        // overlay on a soft fade.
        .onChange(of: state.hasWon) { _, won in
            guard won else { return }
            settings.markSolved(roomID)
            withAnimation(Motion.guidanceIn) { showWin = true }
        }
    }

    // MARK: - Top HUD

    /// The top strip: a back chevron (top-left, mirroring the old gear placement) → Level
    /// Select, the centred room number, and the live turn/echoes readout. Sits above the
    /// board, clear of the swipe/tap area.
    private var topHUD: some View {
        ZStack {
            Text("\(Campaign.number(of: roomID) ?? 0)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(theme.textGuidance)
            HStack(spacing: 4) {
                Button(action: onLevelSelect) { Image(systemName: "chevron.left") }
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
                Text("turn \(state.turn) · echoes \(state.echoes.count)/\(budgetText)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.textGuidance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Control row (routed through the input-lock-guarded path — D-059)

    /// Fold / Step back / Reset run, each in the reusable `ControlButtonStyle`. Every
    /// action is gated on the mirrored input lock so it never mutates `state` while a fold
    /// or death effect is playing (the deferred-death restart must not be pre-empted);
    /// Step back is additionally a no-op at turn 0.
    private var controlBar: some View {
        HStack(spacing: 8) {
            Button("Fold") { guard !inputLocked else { return }; state.fold() }
                .disabled(inputLocked)
            Button("Step back") { guard !inputLocked else { return }; state.stepBack() }
                .disabled(inputLocked || state.turn == 0)
            Button("Reset run") { guard !inputLocked else { return }; state.restartRun() }
                .disabled(inputLocked)
        }
        .buttonStyle(ControlButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Win overlay

    /// The win moment: the solved board dimmed behind a soft scrim, a small centred panel
    /// with the closed/filled exit-ring as the quiet "solved" mark, then the navigation.
    /// Non-final rooms offer "Next room" (the D-055 success-green styling) + "Level
    /// select"; the final room replaces "Next room" with a quiet "Campaign complete" line
    /// and keeps only "Level select." Understated — no stars, no score.
    private var winOverlay: some View {
        let next = Campaign.next(after: roomID)
        return ZStack {
            theme.paperBottom.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())   // capture taps so the board/controls behind are inert
            VStack(spacing: 18) {
                // The closed/filled exit-ring as the quiet "solved" mark — monochrome
                // ink, matching the Level-Select solved disc and keeping the green "Next
                // room" as the overlay's single accent (D-041/D-055).
                Circle()
                    .fill(theme.ink)
                    .frame(width: 30, height: 30)
                    .accessibilityLabel(Text("Solved"))
                if next == nil {
                    Text("Campaign complete")
                        .font(.headline)
                        .foregroundStyle(theme.ink)
                }
                buttons(next: next)
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
        .transition(.opacity)
    }

    @ViewBuilder
    private func buttons(next: String?) -> some View {
        HStack(spacing: 8) {
            if let next {
                Button("Next room") { onAdvance(next) }
                    .buttonStyle(ControlButtonStyle(prominentFill: theme.solvedGreen,
                                                    prominentLabel: theme.paperTop))
            }
            Button("Level select") { onLevelSelect() }
                .buttonStyle(ControlButtonStyle())
        }
    }

    // MARK: - Helpers

    /// The echo budget as text — the number, or "∞" for the uncapped bare board.
    private var budgetText: String {
        state.echoBudget == .max ? "∞" : "\(state.echoBudget)"
    }
}

#Preview("Light") {
    RoomView(state: GameState(level: LevelLoader.load("room-01") ?? Level(
                id: "x", name: "x", width: 7, height: 7,
                start: GridCoordinate(row: 3, column: 3),
                exit: GridCoordinate(row: 0, column: 3), echoBudget: 1)),
             roomID: "room-01",
             settings: SettingsStore(), audio: AudioManager(),
             haptics: HapticsManager(), guidance: GuidanceController(),
             onLevelSelect: {}, onAdvance: { _ in })
        .environment(\.theme, .light)
        .tint(Theme.light.ink)
}
