//
//  MainMenuView.swift
//  ECHO
//
//  Phase 3.03 (Navigation shell). The Main Menu (Plan §4 screen 2) — the hub both modes
//  and Settings hang off. Same paper field; a centered vertical stack of three real
//  `ControlButtonStyle` buttons with generous vertical rhythm — **Campaign**, **Echo
//  Run**, **Settings** — and a small "Echo" wordmark above. Nothing else on screen
//  (brief §Approved visual direction).
//
//  No new visual system: it lays out existing parts — the `ControlButtonStyle` chips
//  (which already adapt to Light/Invert from the `\.theme` seam) and the `Theme` tokens.
//  Each button just sets the root route; the root owns the fade between screens.
//

import SwiftUI

struct MainMenuView: View {
    let onCampaign: () -> Void
    let onEchoRun: () -> Void
    let onSettings: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 44) {
                Text("Echo")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(theme.ink)

                VStack(spacing: 18) {
                    Button("Campaign", action: onCampaign)
                    Button("Echo Run", action: onEchoRun)
                    Button("Settings", action: onSettings)
                }
                .buttonStyle(ControlButtonStyle())
                .frame(maxWidth: 280)
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview("Light") {
    MainMenuView(onCampaign: {}, onEchoRun: {}, onSettings: {})
        .environment(\.theme, .light)
        .tint(Theme.light.ink)
}

#Preview("Invert") {
    MainMenuView(onCampaign: {}, onEchoRun: {}, onSettings: {})
        .environment(\.theme, .invert)
        .tint(Theme.invert.ink)
}
