//
//  ContentView.swift
//  ECHO
//
//  Phase 1.01 (Scaffold) placeholder. Fills the whole screen with the warm
//  off-white "paper" background described in the Plan (§5/§14) and nothing else.
//  The real board, controls, and the monochrome/invert design system are built
//  in later phases — keep this view free of gameplay.
//

import SwiftUI

struct ContentView: View {
    // Warm off-white "paper" — the canvas the game is drawn on. This is a
    // deliberately minimal placeholder; the full palette and invert mode live in
    // a later design phase. Defined inline so the scaffold has zero dependencies.
    private static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)

    var body: some View {
        Self.paper
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
