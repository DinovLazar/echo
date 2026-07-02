//
//  ContentView.swift
//  ECHO
//
//  The app root. Phase 3.03 (Navigation shell) turns this from a debug harness into the
//  real screen flow: it holds a single `AppRoute` and switches `body` on it (D-059),
//  retiring every interim affordance — the `showEchoRun` flag + `infinity` button, the
//  debug `Next` room-cycle and `Clear`, and the campaign-vs-EchoRun `Group` branch are
//  all gone (the interim-navigation lineage D-017/D-026/D-054 is superseded).
//
//  It owns the session-long services (the persisted `SettingsStore`, the
//  `GuidanceController`, and the pre-warmed `AudioManager`/`HapticsManager`), derives the
//  palette from `settings.invertEnabled`, and lifts the `\.theme` / `.tint` injection to
//  the root so every screen inherits theme + invert mode. The campaign board state for
//  the open room is built fresh on each room open (`openRoom`) and held here so it
//  survives re-renders; `RoomView` is given a fresh identity per room (`.id`) so its win
//  overlay never leaks between rooms.
//
//  Screen flow (Plan §3–§4): `.title` → `.mainMenu` → { `.levelSelect` → `.room` → win
//  overlay } / `.echoRun` → game-over / `.settings`. Transitions are a soft ~200 ms fade
//  (reusing the existing `Motion` easing) owned here — light by design (not a feel phase).
//

import SwiftUI

struct ContentView: View {
    /// The current screen — the single source of truth for the whole flow (D-059).
    @State private var route: AppRoute = .title

    /// The persisted user preferences (Phase 2.06) + the campaign solved set (3.03) and
    /// the Echo Run high score (3.02) — the single save layer, owned here and shared with
    /// every screen.
    @State private var settings = SettingsStore()

    /// The guidance-microcopy controller (Phase 2.06). Owned here and injected into the
    /// board; `RoomView` notifies it of the active room on entry.
    @State private var guidance = GuidanceController()

    /// The generative-audio manager (Phase 2.04), started at launch so the first tick has
    /// no spin-up latency, then kept for the session and shared by both modes.
    @State private var audio = AudioManager()

    /// The haptic-feedback manager (Phase 2.05), pre-warmed at launch, then kept for the
    /// session and shared by both modes.
    @State private var haptics = HapticsManager()

    /// The campaign board for the currently-open room — built fresh on each room open
    /// (Level Select tap or the win overlay's "Next room") and held here so it survives
    /// re-renders. A bare board until the first room is opened.
    @State private var roomState = GameState()

    /// The mirror board for the currently-open room, when it is a mirror room (Phase
    /// 4.05 / D-074/D-075): `openRoom` sets this iff the decoded level carries a
    /// `mirror` block, and `.room` shows `MirrorRoomView` instead of `RoomView` while
    /// it is non-nil. `nil` for every normal room, so the single-body path — screen,
    /// board, and engine — is exactly as before.
    @State private var mirrorRoomState: MirrorGameState? = nil

    /// The resolved palette, derived from the persisted Invert preference (Phase 2.06).
    private var theme: Theme { Theme.make(settings.invertEnabled ? .invert : .light) }

    var body: some View {
        ZStack {
            switch route {
            case .title:
                TitleView(onBegin: { go(.mainMenu) })
                    .transition(.opacity)
            case .mainMenu:
                MainMenuView(onCampaign: { go(.levelSelect) },
                             onEchoRun: { go(.echoRun) },
                             onSettings: { go(.settings) })
                    .transition(.opacity)
            case .levelSelect:
                LevelSelectView(settings: settings,
                                onBack: { go(.mainMenu) },
                                onPick: { openRoom($0) })
                    .transition(.opacity)
            case .room(let id):
                // A mirror room (the level carried a `mirror` block) runs the separate
                // two-body screen + engine (Phase 4.05); every normal room takes the
                // exact path it always has.
                if let mirrorRoomState {
                    MirrorRoomView(state: mirrorRoomState, roomID: id,
                                   settings: settings, audio: audio, haptics: haptics,
                                   guidance: guidance,
                                   onLevelSelect: { go(.levelSelect) },
                                   onAdvance: { openRoom($0) })
                        .id(id)   // fresh identity per room → the win overlay never leaks across rooms
                        .transition(.opacity)
                } else {
                    RoomView(state: roomState, roomID: id,
                             settings: settings, audio: audio, haptics: haptics, guidance: guidance,
                             onLevelSelect: { go(.levelSelect) },
                             onAdvance: { openRoom($0) })
                        .id(id)   // fresh identity per room → the win overlay never leaks across rooms
                        .transition(.opacity)
                }
            case .echoRun:
                EchoRunView(settings: settings, audio: audio, haptics: haptics,
                            onMainMenu: { go(.mainMenu) })
                    .transition(.opacity)
            case .settings:
                SettingsView(settings: settings, onClose: { go(.mainMenu) })
                    .transition(.opacity)
            }
        }
        .environment(\.theme, theme)
        .tint(theme.ink)
        // Light screen transitions (~200 ms fade), reusing existing easing.
        .animation(Motion.guidanceIn, value: route)
        // Pre-warm the managers at launch (idempotent; no-ops where unsupported), set to
        // the persisted preferences first so a disabled toggle never pre-warms.
        .task {
            audio.isEnabled = settings.soundEnabled
            haptics.isEnabled = settings.hapticsEnabled
            audio.start()
            haptics.prepare()
        }
        // Keep the two managers in sync with the live toggles.
        .onChange(of: settings.soundEnabled) { _, on in audio.isEnabled = on }
        .onChange(of: settings.hapticsEnabled) { _, on in haptics.isEnabled = on }
    }

    // MARK: - Routing

    /// Switch screens. The fade is owned by the root `.animation(value: route)`.
    private func go(_ destination: AppRoute) {
        route = destination
    }

    /// Open a campaign room: build its board fresh (a bare-board fallback if the level
    /// resource is missing or unreadable, so the app never crashes on a broken level),
    /// then route to it. Used by the Level-Select tap and the win overlay's "Next room".
    /// A level carrying a `mirror` block builds the two-body engine instead (Phase
    /// 4.05); a normal level clears it, so the single-body path is exactly as before.
    private func openRoom(_ id: String) {
        if let level = LevelLoader.load(id) {
            if level.mirror != nil {
                mirrorRoomState = MirrorGameState(level: level)
            } else {
                mirrorRoomState = nil
                roomState = GameState(level: level)
            }
        } else {
            mirrorRoomState = nil
            roomState = GameState()
        }
        route = .room(id)
    }
}

#Preview {
    ContentView()
}
