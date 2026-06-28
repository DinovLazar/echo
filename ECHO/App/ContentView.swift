//
//  ContentView.swift
//  ECHO
//
//  Root view. Fills the whole screen with the warm "paper" background — now the
//  real Phase 2.01 vertical gradient (paper.top → paper.bottom) from the `Theme`
//  token layer — and composes the state-driven board on top. It owns the
//  `GameState` and, from Phase 1.08, the ordered list of the ten teaching-room ids:
//  it loads room 1 on launch and the in-room HUD's *Next* cycles through the
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
//  **Phase 2.07** promotes the old throwaway debug strip into the real in-room HUD: a
//  top strip (Settings gear · centred level number · turn/echoes readout) above the
//  board, and a bottom row of real action buttons (Fold / Step back / Reset run / Clear
//  / Next) in the reusable `ControlButtonStyle`. The *Next* button fills green when the
//  room is solved. Three interim behaviours persist for Part 3 to replace (D-054): Clear
//  is debug-only, Next is a debug room-cycle (not real Level-Select), and the controls
//  still mutate `state` without gating on `BoardView`'s input lock (cosmetic only).
//

import SwiftUI

struct ContentView: View {
    /// The full campaign, in order: the ten teaching rooms (Phase 1.08) followed by
    /// the ten Part-3 campaign rooms (Phase 3.01), so play runs straight through
    /// `room-01 → room-20` and ends at the finale. `Next` cycles through these. The
    /// real Level Select is Part 3 (D-037) — this is still a throwaway debug cycle
    /// with no saved progress.
    private static let roomIDs = [
        "room-01", "room-02", "room-03", "room-04", "room-05",
        "room-06", "room-07", "room-08", "room-09", "room-10",
        "room-11", "room-12", "room-13", "room-14", "room-15",
        "room-16", "room-17", "room-18", "room-19", "room-20",
    ]

    /// Index of the room currently loaded into `state`.
    @State private var roomIndex = 0

    /// The single source of truth for the board, owned here so both the board and
    /// the in-room HUD controls act on the same model. Loaded from the first teaching room (with
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

    /// Whether the Settings sheet is presented (from the top HUD's temporary gear).
    @State private var showingSettings = false

    /// Whether the temporary Echo Run arcade mode is showing (Phase 3.02). Interim, in
    /// the same throwaway lineage as the debug controls (D-017/D-026/D-054): the real
    /// Main Menu that hosts both modes is Phase 3.03. Removing this `@State`, the top
    /// HUD's entry button, and the `body` branch deletes the mode in one edit.
    @State private var showEchoRun = false

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
        Group {
            // INTERIM (Phase 3.02): switch to the throwaway Echo Run arcade mode, entered
            // from the top HUD's temporary button and returned from via `onExit`. The real
            // Main Menu that hosts both modes is Phase 3.03; deleting `showEchoRun`, the
            // entry button, and this branch removes the mode in one edit (D-017/D-026/D-054).
            if showEchoRun {
                EchoRunView(settings: settings, audio: audio, haptics: haptics,
                            onExit: { showEchoRun = false })
            } else {
                campaignScreen
            }
        }
        .environment(\.theme, theme)
        .tint(theme.ink)
    }

    /// The campaign board screen — the in-room HUD, the board, and the action row.
    /// Unchanged by Echo Run except that it is now one branch of `body` (the temporary
    /// arcade mode is the other).
    private var campaignScreen: some View {
        ZStack {
            // Paper stays full-bleed (under the notch and home indicator)...
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // ...while the HUD + board + controls sit within the safe area, in reading
            // order top-to-bottom: the top HUD strip, the board, the action row.
            VStack(spacing: 0) {
                topHUD
                BoardView(state: state, audio: audio, haptics: haptics,
                          showEchoTrail: settings.echoTrailEnabled, guidance: guidance)
                controlBar
            }
        }
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

    // MARK: - In-room HUD (Phase 2.07)

    /// The top HUD strip above the board (Phase 2.07 / D-054): three zones with the
    /// level number truly centred regardless of the side widths. Leading: the Settings
    /// **gear** — unchanged from Phase 2.06, it presents the real, persisted
    /// `SettingsView` sheet (the only invert control now, plus sound / haptics /
    /// echo-trail) and is still a temporary entry the Part 3 menu replaces (D-037).
    /// Centre: the current level number (`roomIndex + 1`, 1–10). Trailing: the live
    /// readout — the shared turn counter and the echo count against the room's budget.
    /// Sits above the board, clear of the swipe/tap area, so it never intercepts input.
    private var topHUD: some View {
        ZStack {
            // Centred level number — in its own layer so the side zones can't shift it.
            Text("\(roomIndex + 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(theme.textGuidance)
            HStack(spacing: 4) {
                // Settings (gear) — a deliberate temporary that replaces the old debug
                // *Invert* flip; presents the real, persisted Settings sheet. Removed
                // with the HUD's interim behaviours when Part 3 builds the real menu.
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .frame(minWidth: 44, minHeight: 44)
                // INTERIM (Phase 3.02): the throwaway entry into Echo Run, the arcade
                // survival mode. Same lineage as the gear / debug controls (D-017/D-026/
                // D-054) — replaced by the real Main Menu in Phase 3.03.
                Button { showEchoRun = true } label: { Image(systemName: "infinity") }
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

    /// The bottom action row (Phase 2.07 / D-054): the in-room controls as real buttons,
    /// each in the one reusable `ControlButtonStyle`, dividing the strip into equal,
    /// evenly-spaced shares. This layout + style is the **real in-room HUD spec** Part 3
    /// reuses rather than rebuilds.
    ///
    /// *Fold* banks the current run as an echo and rewinds. *Step back* (Phase 1.07)
    /// undoes one committed move of the current run (disabled at turn 0, where it is a
    /// no-op anyway, so it reads dimmed). *Reset run* (Phase 1.07) scraps the current
    /// attempt but **keeps banked echoes** — the `restartRun()` op the death restart
    /// uses. *Clear* wipes the room to pristine, **echoes and all** — a debug-only
    /// convenience kept until Part 3 (D-054), deliberately distinct from *Reset run*.
    /// *Next* loads the next teaching room — still a debug room-cycle, not the real
    /// Level-Select (Part 3, D-037); when the room is solved it fills solid green
    /// (`solvedGreen`) as the "you may advance" signal (D-055), replacing the old
    /// "Solved ✓" text.
    ///
    /// NOTE (D-017/D-054): these buttons still mutate `state` **directly**, bypassing
    /// `BoardView`'s fold/death input lock (`commitMove` refuses input while an effect
    /// plays). That remains acceptable for this interim HUD — pressing one mid-effect
    /// only produces a cosmetic glitch (e.g. a phantom echo / a stale overlay), never an
    /// invalid engine state. **The real Part 3 controls must gate on the same
    /// `fold == nil && death == nil` lock** (and wire real navigation), since a death
    /// defers its restart until the dissolve ends and must not be mutated out from under.
    private var controlBar: some View {
        HStack(spacing: 8) {
            Button("Fold") { state.fold() }
            Button("Step back") { state.stepBack() }
                .disabled(state.turn == 0)
            Button("Reset run") { state.restartRun() }
            Button("Clear") { state.clearEchoes() }
            // *Next* turns solid green once the room is solved (D-055) — the green is
            // confined to this one button's state and never reaches the board.
            Button("Next") { loadNextRoom() }
                .buttonStyle(state.hasWon
                             ? ControlButtonStyle(prominentFill: theme.solvedGreen,
                                                  prominentLabel: theme.paperTop)
                             : ControlButtonStyle())
        }
        .buttonStyle(ControlButtonStyle())
        .padding(.horizontal, 16)
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
