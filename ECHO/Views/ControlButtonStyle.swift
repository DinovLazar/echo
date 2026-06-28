//
//  ControlButtonStyle.swift
//  ECHO
//
//  Phase 2.07 (In-room HUD & solid walls). The one reusable button style for every
//  in-room action control — the bottom-row buttons (Fold / Step back / Reset run /
//  Clear / Next) all wear it, and Part 3's real in-room controls reuse it rather than
//  rebuild one (D-054).
//
//  The look is a calm "chip": a continuous-radius rounded rectangle in a faint ink
//  wash with a hairline border for definition, an ink label at footnote weight, and a
//  ≥44×44 pt tap target. Pressing it scales the chip down a touch and deepens the wash;
//  a disabled control dims. Every colour is read from the active palette through
//  `@Environment(\.theme)`, so the chip adapts to Light/Invert with no per-call tuning.
//
//  The chip stretches to fill its container's width (`maxWidth: .infinity`) so a row of
//  them divides the strip into equal, evenly-spaced shares that always fit — place them
//  in an `HStack` (the in-room control row) or a `VStack`.
//
//  One **prominent** variant exists: pass `prominentFill`/`prominentLabel` and the chip
//  fills solid with that colour and recolours its label (the solved-room *Next* button
//  uses `theme.solvedGreen` + a paper-tone label — D-055). With both left `nil` it is
//  the normal chip.
//
//  Isolation: a plain view-layer type under the app's `SWIFT_DEFAULT_ACTOR_ISOLATION =
//  MainActor` (D-013), like `BoardView`/`ContentView`. `ButtonStyle.makeBody` is
//  main-actor-isolated (as `View.body` is), so no `nonisolated` is needed here; the
//  body is split into a small private `View` so it can read the environment.
//

import SwiftUI

struct ControlButtonStyle: ButtonStyle {
    /// When set, the chip renders as a solid filled "prominent" button in this colour
    /// instead of the normal translucent-ink chip (the solved *Next* uses `solvedGreen`).
    var prominentFill: Color? = nil
    /// The label colour for the prominent variant — the paper tone (`theme.paperTop`),
    /// which is near-white in Light and a deep warm tone in Invert, staying high-contrast
    /// against the fill in both. Ignored when `prominentFill` is `nil`.
    var prominentLabel: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration,
             prominentFill: prominentFill,
             prominentLabel: prominentLabel)
    }

    /// The chip body, split out so it can read the active palette and the enabled state
    /// from the environment (a `ButtonStyle` itself has no environment).
    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let prominentFill: Color?
        let prominentLabel: Color?

        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled

        /// Continuous-radius shape shared by the fill and the border.
        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 11, style: .continuous) }

        var body: some View {
            let pressed = configuration.isPressed
            return configuration.label
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.85)   // keep the calm single-line chip on narrow devices (e.g. 375 pt)
                .foregroundStyle(prominentLabel ?? theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(background(pressed: pressed))
                .scaleEffect(pressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }

        @ViewBuilder
        private func background(pressed: Bool) -> some View {
            if let fill = prominentFill {
                // Prominent solid variant (solved *Next*): a solid fill that darkens a
                // touch on press; no hairline — the solid block already reads as a button.
                shape.fill(fill).brightness(pressed ? -0.04 : 0)
            } else {
                // Normal chip: a faint ink wash that deepens on press, plus a hairline
                // border for definition.
                shape.fill(theme.ink.opacity(pressed ? 0.12 : 0.07))
                    .overlay(shape.strokeBorder(theme.tileHairline.opacity(0.6), lineWidth: 1))
            }
        }
    }
}
