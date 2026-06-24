//
//  ContentView.swift
//  ECHO
//
//  Root view. Fills the whole screen with the warm off-white "paper" background
//  described in the Plan (§5/§14) and composes the state-driven board on top.
//  The monochrome/accent/invert design system and the tuned feel arrive in
//  Part 2; this stays "grey boxes on paper" by design.
//

import SwiftUI

struct ContentView: View {
    // Warm off-white "paper" — the canvas the game is drawn on. This is a
    // deliberately minimal placeholder; the full palette and invert mode live in
    // a later design phase. Defined inline so the app has zero dependencies.
    private static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)

    var body: some View {
        ZStack {
            // Paper stays full-bleed (under the notch and home indicator)...
            Self.paper
                .ignoresSafeArea()
            // ...while the board sits within the safe area so it's never clipped.
            BoardView()
        }
    }
}

#Preview {
    ContentView()
}
