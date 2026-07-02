//
//  MirrorRoomView.swift
//  ECHO
//
//  Phase 4.05 (the mirror render path — D-074/D-075). The campaign room screen for
//  **mirror rooms**: the same shell as `RoomView` — top strip (back chevron, room
//  number, turn/echoes readout), the board, the four-control row, the win overlay
//  with the final-room branch — but driving `MirrorGameState` + `MirrorBoardView`.
//
//  A parallel screen rather than a generic one (the D-075 trade, matching Echo
//  Run's D-058 precedent): `RoomView` and its `GameState` wiring are verified and
//  stay byte-for-byte untouched; the duplication here is deliberate and small. The
//  win overlay, solved-state persistence, and Level Select all key on the room id,
//  which is engine-agnostic — a solved mirror room persists and shows solved like
//  any other. Controls route through the same input-lock discipline (D-059): every
//  action honours the board's fold/death lock, and Wait rides the `waitSignal`
//  counter into the board's guarded commit path (D-068).
//

import SwiftUI

struct MirrorRoomView: View {
    /// The mirror board state — owned by `ContentView` and passed in (a fresh
    /// `MirrorGameState(level:)` per room open).
    let state: MirrorGameState
    /// This room's id (the `Campaign.roomIDs` identifier).
    let roomID: String

    let settings: SettingsStore
    let audio: AudioManager
    let haptics: HapticsManager
    let guidance: GuidanceController

    /// Leave this room for Level Select. The root performs the fade.
    let onLevelSelect: () -> Void
    /// Advance to the given next room id (the win overlay's "Next room").
    let onAdvance: (String) -> Void

    @Environment(\.theme) private var theme

    /// Mirrors the board's fold/death input lock (D-059).
    @State private var inputLocked = false
    /// The "wait requested" counter the Wait control bumps (D-068).
    @State private var waitRequests = 0
    /// Whether the win overlay is showing.
    @State private var showWin = false
    /// Whether a "Next room" advance is in flight (the opaque cover — D-064).
    @State private var advancing = false

    /// The same win-reveal beat and advance-cover fade as `RoomView` (D-064).
    private static let winRevealDelay: TimeInterval = 0.45
    private static let advanceCoverFade: Animation = Motion.guidanceIn

    var body: some View {
        ZStack {
            paperField
            VStack(spacing: 0) {
                topHUD
                MirrorBoardView(state: state, audio: audio, haptics: haptics,
                                showEchoTrail: settings.echoTrailEnabled, guidance: guidance,
                                inputLock: $inputLocked, waitSignal: waitRequests)
                controlBar
            }
            if showWin {
                winOverlay
            }
            if advancing {
                paperField.transition(.opacity)
            }
        }
        .debugPerformanceOverlay()
        .task { guidance.enterRoom(roomID) }
        // Both bodies home flips `hasWon`: mark solved (the id-keyed, engine-agnostic
        // persistence), hold the D-064 beat, then reveal the win overlay.
        .task(id: state.hasWon) {
            guard state.hasWon, !showWin else { return }
            settings.markSolved(roomID)
            try? await Task.sleep(for: .seconds(Self.winRevealDelay))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.guidanceIn) { showWin = true }
        }
    }

    private var paperField: some View {
        LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    // MARK: - Top HUD

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

    // MARK: - Control row (input-lock-guarded — D-059/D-068)

    private var controlBar: some View {
        HStack(spacing: 8) {
            Button("Fold") { guard !inputLocked else { return }; state.fold() }
                .disabled(inputLocked)
            Button("Step back") { guard !inputLocked else { return }; state.stepBack() }
                .disabled(inputLocked || state.turn == 0)
            Button("Reset run") { guard !inputLocked else { return }; state.restartRun() }
                .disabled(inputLocked)
            Button("Wait") { guard !inputLocked else { return }; waitRequests &+= 1 }
                .disabled(inputLocked)
        }
        .buttonStyle(ControlButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Win overlay (identical shell to RoomView's)

    private var winOverlay: some View {
        let next = Campaign.next(after: roomID)
        return ZStack {
            theme.paperBottom.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
            VStack(spacing: 18) {
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
                Button("Next room") { advance(to: next) }
                    .buttonStyle(ControlButtonStyle(prominentFill: theme.solvedGreen,
                                                    prominentLabel: theme.paperTop))
            }
            Button("Level select") { onLevelSelect() }
                .buttonStyle(ControlButtonStyle())
        }
    }

    /// Advance behind the opaque paper cover (D-064 artifact 1), idempotent.
    private func advance(to next: String) {
        guard !advancing else { return }
        withAnimation(Self.advanceCoverFade) {
            advancing = true
        } completion: {
            onAdvance(next)
        }
    }

    // MARK: - Helpers

    private var budgetText: String {
        state.echoBudget == .max ? "∞" : "\(state.echoBudget)"
    }
}
