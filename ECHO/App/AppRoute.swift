//
//  AppRoute.swift
//  ECHO
//
//  Phase 3.03 (Navigation shell). The single root route that drives the whole screen
//  flow (D-059). Through 3.02 the app reached its screens via throwaway scaffolding — an
//  `infinity` button + `showEchoRun` branch for Echo Run, a debug `Next` room-cycle and
//  `Clear` for the campaign, an interim `onExit`/game-over in `EchoRunView`. This enum
//  replaces all of it: `ContentView` holds one `AppRoute` and switches its `body` on it,
//  and every screen routes by setting it. (D-017/D-026/D-054 are retired by this.)
//
//  A root enum was chosen over `NavigationStack` (D-059): for a full-screen, turn-based
//  game the system back-swipe and navigation-bar model fight a custom full-bleed board,
//  and a root enum gives full control of the (light, ~120 ms fade) transitions and a
//  clean one-edit teardown of the interim flags. The downside — hand-rolled transitions —
//  is accepted.
//
//  `nonisolated` + `Equatable`/`Sendable` like the other value types (D-013), so it can
//  drive `.animation(_:value:)`, be compared in `.onChange`, and stay usable from any
//  context. The room case carries the room id (the existing `String` identifier — see
//  `Campaign`), so `.room(id)` is the one way a specific room is opened.
//

/// Which screen is on. The flow is: `.title` → `.mainMenu` → { `.levelSelect` → `.room`
/// → win overlay } / `.echoRun` → game-over / `.settings`. Held at the app root
/// (`ContentView`) and switched in `body` (D-059).
nonisolated enum AppRoute: Equatable, Sendable {
    /// The launch screen — the "Echo" wordmark + motif; the whole screen taps to the menu.
    case title
    /// The three-button hub: Campaign, Echo Run, Settings.
    case mainMenu
    /// The 4×5 grid of the twenty rooms (free pick — D-060).
    case levelSelect
    /// One campaign room, identified by its `Campaign.roomIDs` id.
    case room(String)
    /// The Echo Run arcade survival mode.
    case echoRun
    /// The persisted Settings screen.
    case settings
}
