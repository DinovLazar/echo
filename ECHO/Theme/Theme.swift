//
//  Theme.swift
//  ECHO
//
//  Phase 2.02 (The board's real look + motion). The central colour-token source —
//  the single place every board colour comes from. It implements the locked Phase
//  2.01 visual handover (§1a colour tokens, §1b geometry/opacity tokens) as two
//  authoritative palettes — **Light** (default) and **Invert** (true white-on-black)
//  — that are identical in geometry and differ only in token *values* (handover §4).
//
//  The board reads its palette through a single SwiftUI environment value
//  (`\.theme`). That environment value is the **one internal switch point** a later
//  Settings phase (2.06) will bind to a user toggle with persistence; this phase
//  only builds both palettes and defaults to Light — no toggle UI, no persistence
//  (the throwaway debug bar's *Invert* button just flips the seam for on-device
//  verification, like *Next*/*Fold* — it is not the real setting).
//
//  Two **board** accent colours only — red = danger, gold = goal — each always carried
//  by an already-distinct shape, never the sole signal (D-041; handover §0). A single
//  UI-chrome success colour (`solvedGreen`, Phase 2.07 / D-055) also lives here, but it
//  is confined to the in-room HUD's solved-*Next* button and never touches the board, so
//  the board's strict two-accent discipline holds. Geometry and glow/shadow metrics live
//  in `BoardMetrics`; the named motion curves live in `Motion.swift`.
//
//  Isolation: every type here is `nonisolated` (and `Sendable` where it holds
//  state). The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
//  (D-013), so an un-annotated `EnvironmentKey`/`Color` extension would be implicitly
//  main-actor-isolated and could not satisfy SwiftUI's `nonisolated` requirements —
//  the same class of error D-040 fixed for `Shape`. Marking these `nonisolated`
//  keeps the token layer usable from any context and the conformances clean.
//

import SwiftUI

// MARK: - Hex colour helper

extension Color {
    /// Build a colour from a `0xRRGGBB` literal plus an optional opacity. Marked
    /// `nonisolated` so the palette statics can be constructed off the main actor
    /// (D-013/D-040). All handover §1a values are written as hex here.
    nonisolated init(hex: UInt, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Theme mode

/// Which palette is in force. `light` is the default; `invert` is the white-on-black
/// presentation. This enum is the *value* the 2.06 settings toggle will choose
/// between; `Theme.make(_:)` resolves it to a concrete palette.
nonisolated enum ThemeMode: String, CaseIterable, Sendable {
    case light
    case invert
}

// MARK: - Colour palette

/// One fully-resolved colour palette: every handover §1a token as a concrete
/// `Color`, plus the two mode-specific opacity/shadow tokens that §1b/§4 vary
/// between Light and Invert. Geometry is mode-independent and lives in
/// `BoardMetrics`.
nonisolated struct Theme: Sendable {

    // Paper (board background gradient) + primary ink.
    let paperTop: Color
    let paperBottom: Color
    let ink: Color

    // Walls — one flat solid tone (Phase 2.07 / D-053 replaced the old top-light →
    // bottom-dark gradient pair with a single fill at the gradient's visual midpoint).
    let wall: Color

    // Echoes — the base hue plus its two mode-specific opacities (handover §1b token
    // table gives Light 0.24/0.55; §4 prose gives Invert 0.22/0.50 — both honoured).
    let echoBase: Color
    let echoFillOpacity: Double
    let echoStrokeOpacity: Double

    // Switch ring (open / inactive).
    let switchRing: Color

    // Danger accent (red) — fill, outline, inner core, and the soft glow (the glow
    // token already carries its mode opacity, 0.35 light / 0.45 invert).
    let dangerRed: Color
    let dangerOutline: Color
    let dangerCore: Color
    let dangerGlow: Color

    // Goal accent (gold) — used by the active exit and a held switch — plus its glow.
    let goalGold: Color
    let goalGlow: Color

    // Quietest marks.
    let textGuidance: Color
    let tileHairline: Color

    // Player drop shadow (the only shadow on the board). Colour carries its opacity
    // (ink @ 0.22 light / near-black @ 0.40 invert — handover §1b/§4).
    let shadowColor: Color

    // UI-chrome success colour (Phase 2.07 / D-055) — the solid fill the in-room HUD's
    // *Next* button takes when a room is solved (the conventional "you may advance"
    // green). This is the **only** place a third hue appears, and it is confined to UI
    // chrome: it may never be drawn on the board or encode board meaning, so D-041's
    // strict two-accent board discipline (red = danger, gold = goal) is preserved.
    let solvedGreen: Color

    /// The Light palette (default).
    static let light = Theme(
        paperTop: Color(hex: 0xF5EDDD),
        paperBottom: Color(hex: 0xEADFCA),
        ink: Color(hex: 0x16130F),
        wall: Color(hex: 0x312D29),
        echoBase: Color(hex: 0x4A453E),
        echoFillOpacity: 0.24,
        echoStrokeOpacity: 0.55,
        switchRing: Color(hex: 0x7A7163),
        dangerRed: Color(hex: 0xC0473B),
        dangerOutline: Color(hex: 0x7E2A22),
        dangerCore: Color(hex: 0x7E2A22),
        dangerGlow: Color(hex: 0xC0473B, opacity: 0.35),
        goalGold: Color(hex: 0xC99A3A),
        goalGlow: Color(hex: 0xC99A3A, opacity: 0.35),
        textGuidance: Color(hex: 0x5C5346),
        tileHairline: Color(hex: 0xC7BAA3),
        shadowColor: Color(hex: 0x16130F, opacity: 0.22),
        solvedGreen: Color(hex: 0x5C8A52)
    )

    /// The Invert palette — a true warm white-on-black, not a dimmed copy; red and
    /// gold are re-tuned (brighter, higher-opacity glows) to stay legible on the
    /// dark sheet (handover §4).
    static let invert = Theme(
        paperTop: Color(hex: 0x1A1713),
        paperBottom: Color(hex: 0x0E0C0A),
        ink: Color(hex: 0xF2EBDD),
        wall: Color(hex: 0x2F2B25),
        echoBase: Color(hex: 0xC9C1B2),
        echoFillOpacity: 0.22,
        echoStrokeOpacity: 0.50,
        switchRing: Color(hex: 0x8A8275),
        dangerRed: Color(hex: 0xD85A4C),
        dangerOutline: Color(hex: 0xF0A89E),
        dangerCore: Color(hex: 0x8E2C22),
        dangerGlow: Color(hex: 0xD85A4C, opacity: 0.45),
        goalGold: Color(hex: 0xE0B450),
        goalGlow: Color(hex: 0xE0B450, opacity: 0.45),
        textGuidance: Color(hex: 0x9A8F7E),
        tileHairline: Color(hex: 0x332E27),
        // A deeper ambient shadow so the off-white player still lifts off near-black
        // paper (handover §4: "ink-on-dark @ 0.40").
        shadowColor: Color(hex: 0x000000, opacity: 0.40),
        // Brighter, warmer green so the solved-Next chrome stays legible on the dark
        // sheet (mirrors how red/gold re-tune for Invert).
        solvedGreen: Color(hex: 0x77B86A)
    )

    /// Resolve a `ThemeMode` to its palette. This is the seam 2.06 will drive from a
    /// persisted user toggle.
    static func make(_ mode: ThemeMode) -> Theme {
        switch mode {
        case .light: light
        case .invert: invert
        }
    }
}

// MARK: - Geometry, stroke & glow metrics (handover §1b — mode-independent)

/// Every size, radius, stroke, opacity, shadow and glow metric from handover §1b,
/// in points **at the reference cell `C = 44 pt`**. The board scales by the runtime
/// cell size — multiply any of these by `cell / referenceCell` (see `BoardView`'s
/// `scaled(_:)`), so proportions hold on any device. Sizes that the handover states
/// as a fraction of `C` resolve to the same number either way (e.g. player `32 pt`
/// = `0.727·C`).
nonisolated enum BoardMetrics {
    /// The reference cell the handover anchors all geometry to.
    static let referenceCell: CGFloat = 44

    // Element sizes (pt at reference C).
    static let playerSize: CGFloat = 32        // 0.727·C, inset 6 per side
    static let echoSize: CGFloat = 28          // 0.636·C, inset 8 per side (smaller than player)
    static let wallInset: CGFloat = 1          // wall is C − 2 pt → 1 pt inset per side
    static let enemySize: CGFloat = 30         // point-to-point, 0.68·C
    static let enemyCoreSize: CGFloat = 10     // inner core, point-to-point
    static let switchOpenSize: CGFloat = 22    // open ring diameter, 0.5·C
    static let switchHeldSize: CGFloat = 20    // held filled-circle diameter
    static let exitSize: CGFloat = 30          // exit ring diameter, 0.68·C
    static let doorThickness: CGFloat = 10     // door bar thickness
    static let doorStub: CGFloat = 8           // open-door remnant stub length
    static let padSize: CGFloat = 30           // teleport-pad glyph side (bracketed corners)
    static let padCornerArm: CGFloat = 0.32    // corner-bracket arm as a fraction of the side

    // Corner radii (pt).
    static let radiusPlayer: CGFloat = 7
    static let radiusEcho: CGFloat = 7
    static let radiusWall: CGFloat = 4
    static let radiusDoorBar: CGFloat = 3
    static let radiusEnemyCorner: CGFloat = 3  // deliberately small — "slightly sharp"

    // Strokes (pt).
    static let strokeEcho: CGFloat = 1.5
    static let strokeSwitchRing: CGFloat = 3
    static let strokeExitRing: CGFloat = 3
    static let strokeEnemyOutline: CGFloat = 2
    static let strokeHairline: CGFloat = 0.5
    static let strokePad: CGFloat = 2.5        // teleport-pad bracket stroke

    // Opacities (mode-independent).
    static let doorClosedFill: Double = 0.92
    static let doorOpenRemnant: Double = 0.22  // open-door stub opacity
    static let exitDefaultRing: Double = 0.55  // ink ring opacity when not the active goal
    static let padGlyph: Double = 0.50         // teleport-pad bracket opacity (ink; monochrome, not accent)

    // Mirror divide (Phase 4.05 / D-074 — first-pass, Design-refinable). The visible
    // vertical centerline of a mirror room: a quiet ink rule, clearly structural
    // (like the hairlines, louder) and never the accent.
    static let divideWidth: CGFloat = 2        // centerline rule thickness
    static let divideOpacity: Double = 0.30    // centerline rule opacity (ink; monochrome)

    // Echo-trail aid (Phase 2.06; handover §8/§1b). The optional dotted upcoming-path
    // preview. Same `echo.base` token + opacity in both palettes (handover §8).
    static let trailDotSize: CGFloat = 3       // dot diameter
    static let trailDotSpacing: CGFloat = 8    // centre-to-centre spacing along the path
    static let trailDotOpacity: Double = 0.40  // `opacity.trailDot`

    // Player drop shadow (colour/opacity is in `Theme.shadowColor`).
    static let shadowBlur: CGFloat = 6
    static let shadowOffsetY: CGFloat = 2

    // Accent glow (colour/opacity is in `Theme.dangerGlow` / `Theme.goalGlow`).
    static let glowBlur: CGFloat = 8
    static let glowSpread: CGFloat = 2
}

// MARK: - Environment plumbing (the single switch point)

/// The environment key carrying the active palette. Default is Light. Marked
/// `nonisolated` so the `EnvironmentKey` conformance (whose `defaultValue` is a
/// `nonisolated` requirement) is satisfiable under default-MainActor isolation
/// (D-013/D-040).
nonisolated struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .light
}

extension EnvironmentValues {
    /// The active board palette. Read it with `@Environment(\.theme)`; set it once,
    /// high in the tree, with `.environment(\.theme, Theme.make(mode))`. This is the
    /// single seam 2.06 will bind to the user's invert toggle.
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
