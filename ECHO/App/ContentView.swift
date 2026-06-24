//
//  ContentView.swift
//  ECHO
//
//  Phase 1.02 (First device install) placeholder. Fills the whole screen with
//  the warm off-white "paper" background described in the Plan (§5/§14) and
//  draws a static "hello grid" centered on it — just enough to prove the build
//  pipeline renders a real grid. No gameplay yet; the real board, controls, and
//  the monochrome/invert design system are built in later phases.
//

import SwiftUI

struct ContentView: View {
    // Warm off-white "paper" — the canvas the game is drawn on. This is a
    // deliberately minimal placeholder; the full palette and invert mode live in
    // a later design phase. Defined inline so the scaffold has zero dependencies.
    private static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)

    var body: some View {
        ZStack {
            // Paper stays full-bleed (under the notch and home indicator)...
            Self.paper
                .ignoresSafeArea()
            // ...while the grid sits within the safe area so it's never clipped.
            HelloGridView()
        }
    }
}

#Preview {
    ContentView()
}
