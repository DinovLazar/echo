//
//  TitleView.swift
//  ECHO
//
//  Phase 3.03 (Navigation shell). The launch screen (Plan §4 screen 1). A full paper
//  field with the wordmark "Echo" centered in the system font, large and ink-black, in
//  heavy negative space. The only ornament is the game's own motif — one solid ink
//  square with one translucent-grey echo square offset just behind it, reusing the
//  campaign player/echo styling (the same ink fill, the same `echoBase` translucency and
//  corner radius as `BoardView`). A small grey "tap to begin" sits beneath. The whole
//  screen is the tap target → Main Menu, on a soft fade owned by the root (`ContentView`).
//
//  No new visual system: every colour/size is read from the `Theme` token layer, so the
//  screen inherits Light/Invert from the root like every other screen. The word "Echo" is
//  the display name and stays trivially swappable here if the title is ever renamed (that
//  rename remains out of scope — brief §Approved visual direction).
//

import SwiftUI

struct TitleView: View {
    /// Tapping anywhere advances to the Main Menu (the root performs the fade).
    let onBegin: () -> Void

    @Environment(\.theme) private var theme

    /// The motif squares are sized off the reference cell so they read like a real
    /// player/echo pair lifted from the board.
    private let playerSide: CGFloat = 56
    private let echoSide: CGFloat = 48

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                motif
                VStack(spacing: 14) {
                    Text("Echo")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("tap to begin")
                        .font(.callout)
                        .foregroundStyle(theme.textGuidance)
                }
            }
        }
        // The whole screen is the tap target (the background takes the hit too).
        .contentShape(Rectangle())
        .onTapGesture { onBegin() }
    }

    /// The motif: the solid ink player with its single translucent-grey echo offset just
    /// behind it, exactly as they read on the board (the echo recedes — smaller, lower
    /// opacity, drawn beneath).
    private var motif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.echoBase.opacity(theme.echoFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.echoBase.opacity(theme.echoStrokeOpacity), lineWidth: 2)
                )
                .frame(width: echoSide, height: echoSide)
                .offset(x: 18, y: 18)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.ink)
                .frame(width: playerSide, height: playerSide)
                .shadow(color: theme.shadowColor, radius: 8, x: 0, y: 3)
        }
        .offset(x: -9, y: -9)   // re-center the pair around the stack's axis
    }
}

#Preview("Light") {
    TitleView(onBegin: {})
        .environment(\.theme, .light)
}

#Preview("Invert") {
    TitleView(onBegin: {})
        .environment(\.theme, .invert)
}
