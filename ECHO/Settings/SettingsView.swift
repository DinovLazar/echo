//
//  SettingsView.swift
//  ECHO
//
//  Phase 2.06 (Settings, persistence, the echo-trail aid & the guidance microcopy).
//  The four-toggle Settings screen — Invert mode, Sound, Haptics, Echo trail — bound
//  to the persisted `SettingsStore`. Presented as a `.sheet` from a temporary gear
//  button in the debug bar (D-050); the real menu that will host Settings is Part 3
//  (D-037), so this is a deliberately minimal, palette-styled functional screen, not a
//  Part-3 polish pass (screen polish is Phase 3.03).
//
//  Styling: paper-gradient background, `ink` text/tint, system SF (the toggles use a
//  monochrome ink tint, never the platform green, to keep the two-accent colour rule —
//  D-041). The toggles bind straight to the store, so flipping one persists it and
//  updates the live app at once (the board flips palette, the audio/haptics re-gate,
//  the trail appears/fades). Bindings are built by hand (not `@Bindable`) so the file
//  type-checks under the no-Xcode CLT macro substitution exactly like the rest of the
//  app; iOS-only navigation chrome is avoided so it also compiles against the macOS SDK.
//

import SwiftUI

struct SettingsView: View {
    /// The persisted preference store, owned by `ContentView`.
    let settings: SettingsStore
    /// Dismiss the sheet (the gear's `isPresented` binding is owned by `ContentView`).
    let onClose: () -> Void

    /// The active palette, so the sheet matches the board (and flips live when the
    /// Invert toggle is changed).
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Invert mode", isOn: bind(\.invertEnabled))
                    Toggle("Sound", isOn: bind(\.soundEnabled))
                    Toggle("Haptics", isOn: bind(\.hapticsEnabled))
                    Toggle("Echo trail", isOn: bind(\.echoTrailEnabled))
                }
            }
            .scrollContentBackground(.hidden)
            .background(paper)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .tint(theme.ink)
        .foregroundStyle(theme.ink)
    }

    /// The board's paper gradient, full-bleed behind the form.
    private var paper: some View {
        LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    /// A two-way binding to one `Bool` preference. Written by hand (rather than via
    /// `@Bindable`) to keep the file free of the property-wrapper macro the CLT
    /// type-check substitutes; writing through the binding still persists and notifies
    /// (the store's `didSet` writes `UserDefaults`; `@Observable` re-renders observers).
    private func bind(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { settings[keyPath: keyPath] = $0 })
    }
}

#Preview("Light") {
    SettingsView(settings: SettingsStore(), onClose: {})
        .environment(\.theme, .light)
}

#Preview("Invert") {
    SettingsView(settings: SettingsStore(), onClose: {})
        .environment(\.theme, .invert)
}
