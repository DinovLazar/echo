//
//  ContentView.swift
//  ECHO
//
//  Root view. Fills the whole screen with the warm "paper" background — now the
//  real Phase 2.01 vertical gradient (paper.top → paper.bottom) from the `Theme`
//  token layer — and composes the state-driven board on top. It owns the
//  `GameState` and, from Phase 1.08, the ordered list of the ten teaching-room ids:
//  it loads room 1 on launch and the throwaway debug bar's *Next* cycles through the
//  rooms by building a fresh `GameState` from each level.
//
//  Phase 2.02 wires the colour-token system in: this view owns the active
//  `ThemeMode` (the **single internal switch point** 2.06 will bind to a real,
//  persisted user toggle) and injects the resolved palette into the environment so
//  `BoardView` reads it. There is no Settings UI or persistence this phase; the
//  debug bar's *Invert* button just flips the seam in place so both palettes can be
//  verified on device — it is a throwaway debug control, not the real setting.
//

import SwiftUI

struct ContentView: View {
    /// The ten teaching rooms, in order. `Next` cycles through these (Phase 1.08),
    /// replacing the three throwaway proof rooms. The real Level Select is Part 3
    /// (D-037) — this is still a throwaway debug cycle with no saved progress.
    private static let roomIDs = [
        "room-01", "room-02", "room-03", "room-04", "room-05",
        "room-06", "room-07", "room-08", "room-09", "room-10",
    ]

    /// Index of the room currently loaded into `state`.
    @State private var roomIndex = 0

    /// The single source of truth for the board, owned here so both the board and
    /// the debug bar act on the same model. Loaded from the first teaching room (with
    /// a bare-board fallback if the resource can't be read, so the app never
    /// crashes on a missing/broken level).
    @State private var state = ContentView.makeState(forRoomAt: 0)

    /// The active palette mode — **the one internal switch point** a later Settings
    /// phase (2.06) will replace with a binding to a persisted user preference.
    /// Defaults to Light; the throwaway debug *Invert* button flips it.
    @State private var themeMode: ThemeMode = .light

    /// The generative-audio manager (Phase 2.04), created here and `start()`-ed at
    /// launch so the first tick has no spin-up latency, then kept for the session.
    /// Passed into `BoardView`, which fires its sounds from the same step/fold/death
    /// paths the motion uses. Its `isEnabled` switch is the binding point the Settings
    /// sound-toggle (2.06) will use; no toggle UI or persistence is built this phase.
    @State private var audio = AudioManager()

    /// The resolved palette for this mode. Owned here (not read from the environment)
    /// because this view is what *provides* the environment value to its children.
    private var theme: Theme { Theme.make(themeMode) }

    var body: some View {
        ZStack {
            // Paper stays full-bleed (under the notch and home indicator)...
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // ...while the board + debug bar sit within the safe area.
            VStack(spacing: 0) {
                BoardView(state: state, audio: audio)
                debugBar
            }
        }
        .environment(\.theme, theme)
        .tint(theme.ink)
        // Pre-warm and start the audio engine at launch (idempotent; a no-op in
        // previews). Kept running for the session so ticks fire with no latency.
        .task { audio.start() }
    }

    // MARK: - Room loading

    /// Build a `GameState` for the teaching room at `index`, falling back to a bare
    /// board if the level resource is missing or unreadable.
    private static func makeState(forRoomAt index: Int) -> GameState {
        let id = roomIDs[index % roomIDs.count]
        if let level = LevelLoader.load(id) {
            return GameState(level: level)
        }
        return GameState()
    }

    /// Advance to the next teaching room (wrapping), loading it fresh.
    private func loadNextRoom() {
        roomIndex = (roomIndex + 1) % Self.roomIDs.count
        state = Self.makeState(forRoomAt: roomIndex)
    }

    // MARK: - Debug bar (TEMPORARY — remove in Parts 2–3)

    /// Throwaway development controls, intentionally kept out of `BoardView` so the
    /// board stays "just the board" and this strip is trivial to delete later. The
    /// real in-room control layout and feel are Part 2/Part 3; these are grey-box.
    ///
    /// *Fold* banks the current run as an echo and rewinds. *Step back* (Phase 1.07)
    /// undoes one committed move of the current run (disabled at turn 0, where it is
    /// a no-op anyway). *Reset run* (Phase 1.07) scraps the current attempt but
    /// **keeps banked echoes** — the `restartRun()` op the death restart uses. *Clear*
    /// wipes the room to pristine, **echoes and all** — a debug-only convenience,
    /// deliberately distinct from *Reset run*. *Next* loads the next teaching room.
    /// *Invert* flips the palette (Phase 2.02) so both Light and Invert can be checked
    /// on device — a throwaway debug control, **not** the real Settings toggle (2.06).
    /// The readout shows the shared turn counter and the live echo count against the
    /// room's budget, plus a "Solved ✓" stand-in once the exit is reached (the real
    /// win overlay is Part 3). It sits below the board, clear of the swipe/tap area,
    /// so it never intercepts input.
    ///
    /// NOTE (Phase 2.03): these buttons mutate `state` **directly**, bypassing
    /// `BoardView`'s fold/death input lock (`commitMove` refuses input while an effect
    /// plays). That is acceptable for this throwaway bar — pressing one mid-effect only
    /// produces a cosmetic glitch (e.g. a phantom echo / a stale overlay), never an
    /// invalid engine state. **The real in-room controls (Part 2/3) must gate on the
    /// same `fold == nil && death == nil` lock**, since a death defers its restart
    /// until the dissolve ends and must not be mutated out from under.
    private var debugBar: some View {
        HStack(spacing: 12) {
            Button("Fold") { state.fold() }
            Button("Step back") { state.stepBack() }
                .disabled(state.turn == 0)
            Button("Reset run") { state.restartRun() }
            Button("Clear") { state.clearEchoes() }
            Button("Next") { loadNextRoom() }
            Button(themeMode == .light ? "Invert" : "Light") {
                themeMode = (themeMode == .light) ? .invert : .light
            }
            Spacer()
            if state.hasWon {
                Text("Solved ✓").fontWeight(.semibold)
            }
            Text("turn \(state.turn) · echoes \(state.echoes.count)/\(budgetText)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(theme.textGuidance)
        }
        .font(.footnote)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// The echo budget as text — the number, or "∞" for the uncapped bare board
    /// (the teaching rooms always carry a real small cap).
    private var budgetText: String {
        state.echoBudget == .max ? "∞" : "\(state.echoBudget)"
    }
}

#Preview {
    ContentView()
}
