//
//  ContentView.swift
//  ECHO
//
//  Root view. Fills the whole screen with the warm off-white "paper" background
//  described in the Plan (§5/§14) and composes the state-driven board on top.
//  It owns the `GameState` so the throwaway debug bar below the board can drive
//  fold/clear on the same model the board renders.
//  The monochrome/accent/invert design system and the tuned feel arrive in
//  Part 2; this stays "grey boxes on paper" by design.
//

import SwiftUI

struct ContentView: View {
    // Warm off-white "paper" — the canvas the game is drawn on. This is a
    // deliberately minimal placeholder; the full palette and invert mode live in
    // a later design phase. Defined inline so the app has zero dependencies.
    private static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)

    /// The single source of truth for the board, owned here so both the board and
    /// the debug bar act on the same model (defaults to 7×7, centered).
    @State private var state = GameState()

    var body: some View {
        ZStack {
            // Paper stays full-bleed (under the notch and home indicator)...
            Self.paper
                .ignoresSafeArea()
            // ...while the board + debug bar sit within the safe area.
            VStack(spacing: 0) {
                BoardView(state: state)
                debugBar
            }
        }
    }

    // MARK: - Debug bar (TEMPORARY — remove in Parts 2–3)

    /// Throwaway development controls, intentionally kept out of `BoardView` so the
    /// board stays "just the board" and this strip is trivial to delete later.
    /// *Fold* banks the current run as an echo and rewinds; *Clear* wipes the room
    /// to pristine (a debug stand-in — the real "reset run" is Phase 1.07, not
    /// this). The readout shows the shared turn counter and the live echo count.
    /// It sits below the board, clear of the board's swipe/tap area, so it never
    /// intercepts gameplay input.
    private var debugBar: some View {
        HStack(spacing: 16) {
            Button("Fold") { state.fold() }
            Button("Clear") { state.clearEchoes() }
            Spacer()
            Text("turn \(state.turn) · echoes \(state.echoes.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

#Preview {
    ContentView()
}
