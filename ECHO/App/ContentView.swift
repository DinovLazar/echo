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
//  Phase 2.02 wired the colour-token system in; **Phase 2.06** gives the three switch
//  points (the `\.theme` palette seam, `audio.isEnabled`, `haptics.isEnabled`) a real,
//  persisted home. This view now owns a `SettingsStore` (the single source of truth for
//  invert / sound / haptics / echo-trail, over `UserDefaults`) and derives the palette
//  from `settings.invertEnabled`, keeps the two managers in sync with their toggles, and
//  passes the echo-trail flag into `BoardView`. The Settings screen is reached via a
//  temporary gear button that replaces the old debug *Invert* flip (the real menu is
//  Part 3, D-037). It also owns a `GuidanceController` and notifies it of the active
//  room on launch / `loadNextRoom` so the one-time hints fire (Phase 2.06).
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

    /// The persisted user preferences (Phase 2.06) — the single source of truth for the
    /// four toggles (invert / sound / haptics / echo-trail), backed by `UserDefaults`.
    /// Owned here, mirroring `audio`/`haptics`; the three already-built switch points
    /// (the `\.theme` seam, `audio.isEnabled`, `haptics.isEnabled`) are now driven from
    /// it, and `SettingsView` edits it. Relaunch restores the last state (D-050/D-051).
    @State private var settings = SettingsStore()

    /// The guidance-microcopy controller (Phase 2.06) — owns the current on-board
    /// message and the one-time-hint seen-once persistence. Owned here and injected into
    /// `BoardView` like `audio`/`haptics`; `ContentView` notifies it of the active room
    /// on launch and on each `loadNextRoom` (D-052).
    @State private var guidance = GuidanceController()

    /// Whether the Settings sheet is presented (from the debug bar's temporary gear).
    @State private var showingSettings = false

    /// The generative-audio manager (Phase 2.04), created here and `start()`-ed at
    /// launch so the first tick has no spin-up latency, then kept for the session.
    /// Passed into `BoardView`, which fires its sounds from the same step/fold/death
    /// paths the motion uses. Its `isEnabled` switch is the binding point the Settings
    /// sound-toggle (2.06) will use; no toggle UI or persistence is built this phase.
    @State private var audio = AudioManager()

    /// The haptic-feedback manager (Phase 2.05), created here and pre-warmed at launch
    /// so the first tap has no Taptic-Engine spin-up latency, then kept for the session.
    /// Passed into `BoardView`, which fires its taps from the same step/fold/death
    /// paths the audio and motion use. Its `isEnabled` switch is the binding point the
    /// Settings haptics-toggle (2.06) will use; no toggle UI or persistence is built
    /// this phase. A safe no-op on hardware without haptics and in the Simulator.
    @State private var haptics = HapticsManager()

    /// The resolved palette, derived from the persisted Invert preference (Phase 2.06).
    /// Owned here (not read from the environment) because this view is what *provides*
    /// the environment value to its children; reading `settings.invertEnabled` here is
    /// what flips the whole board live when the Settings toggle changes.
    private var theme: Theme { Theme.make(settings.invertEnabled ? .invert : .light) }

    var body: some View {
        ZStack {
            // Paper stays full-bleed (under the notch and home indicator)...
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // ...while the board + debug bar sit within the safe area.
            VStack(spacing: 0) {
                BoardView(state: state, audio: audio, haptics: haptics,
                          showEchoTrail: settings.echoTrailEnabled, guidance: guidance)
                debugBar
            }
        }
        .environment(\.theme, theme)
        .tint(theme.ink)
        // Pre-warm at launch (idempotent; no-ops in previews / where unsupported), so
        // the first tick and the first tap fire with no spin-up latency. Both are kept
        // for the session. The managers are initialised to the persisted preferences
        // first (so a disabled toggle never pre-warms), and the launch room's one-time
        // hint is fired (room-01 → `swipe to move`, if not seen before).
        .task {
            audio.isEnabled = settings.soundEnabled
            haptics.isEnabled = settings.hapticsEnabled
            audio.start()
            haptics.prepare()
            guidance.enterRoom(Self.roomIDs[roomIndex])
        }
        // Keep the two managers in sync with the live toggles.
        .onChange(of: settings.soundEnabled) { _, on in audio.isEnabled = on }
        .onChange(of: settings.hapticsEnabled) { _, on in haptics.isEnabled = on }
        // The Settings screen (temporary gear entry; the real menu is Part 3). Re-inject
        // the palette so the sheet matches the board and flips live with the Invert toggle.
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings, onClose: { showingSettings = false })
                .environment(\.theme, theme)
        }
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

    /// Advance to the next teaching room (wrapping), loading it fresh, and notify the
    /// guidance controller so the room's one-time hint fires if it hasn't been seen.
    private func loadNextRoom() {
        roomIndex = (roomIndex + 1) % Self.roomIDs.count
        state = Self.makeState(forRoomAt: roomIndex)
        guidance.enterRoom(Self.roomIDs[roomIndex])
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
    /// The **gear** (Phase 2.06) replaces the old debug *Invert* flip: it presents the
    /// real, persisted `SettingsView` as a sheet (the only invert control now, plus
    /// sound / haptics / echo-trail) — itself a temporary entry the Part 3 menu replaces.
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
            // The Settings (gear) entry — a deliberate temporary that replaces the old
            // debug *Invert* flip; it presents the real, persisted Settings sheet (the
            // only invert control now). Removed with the bar when Part 3 builds the menu.
            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
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
