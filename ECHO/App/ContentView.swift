//
//  ContentView.swift
//  ECHO
//
//  Root view. Fills the whole screen with the warm off-white "paper" background
//  described in the Plan (§5/§14) and composes the state-driven board on top.
//  It owns the `GameState` and, from Phase 1.06, the ordered list of proof-room
//  ids: it loads room 1 on launch and the throwaway debug bar's *Next* cycles
//  through the rooms by building a fresh `GameState` from each level.
//  The monochrome/accent/invert design system and the tuned feel arrive in
//  Part 2; this stays "grey boxes on paper" by design.
//

import SwiftUI

struct ContentView: View {
    // Warm off-white "paper" — the canvas the game is drawn on. This is a
    // deliberately minimal placeholder; the full palette and invert mode live in
    // a later design phase. Defined inline so the app has zero dependencies.
    private static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)

    /// The proof rooms, in order. `Next` cycles through these (Phase 1.06). The
    /// real Level Select is Part 3 — this is a throwaway debug cycle.
    private static let roomIDs = ["p1-06-a", "p1-06-b", "p1-06-c"]

    /// Index of the room currently loaded into `state`.
    @State private var roomIndex = 0

    /// The single source of truth for the board, owned here so both the board and
    /// the debug bar act on the same model. Loaded from the first proof room (with
    /// a bare-board fallback if the resource can't be read, so the app never
    /// crashes on a missing/broken level).
    @State private var state = ContentView.makeState(forRoomAt: 0)

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

    // MARK: - Room loading

    /// Build a `GameState` for the proof room at `index`, falling back to a bare
    /// board if the level resource is missing or unreadable.
    private static func makeState(forRoomAt index: Int) -> GameState {
        let id = roomIDs[index % roomIDs.count]
        if let level = LevelLoader.load(id) {
            return GameState(level: level)
        }
        return GameState()
    }

    /// Advance to the next proof room (wrapping), loading it fresh.
    private func loadNextRoom() {
        roomIndex = (roomIndex + 1) % Self.roomIDs.count
        state = Self.makeState(forRoomAt: roomIndex)
    }

    // MARK: - Debug bar (TEMPORARY — remove in Parts 2–3)

    /// Throwaway development controls, intentionally kept out of `BoardView` so the
    /// board stays "just the board" and this strip is trivial to delete later.
    /// *Fold* banks the current run as an echo and rewinds; *Clear* wipes the room
    /// to pristine (a debug stand-in — the real "reset run" is Phase 1.07, not
    /// this); *Next* loads the next proof room. The readout shows the shared turn
    /// counter and the live echo count against the room's budget, plus a "Solved ✓"
    /// stand-in once the exit is reached (the real win overlay is Part 3). It sits
    /// below the board, clear of the swipe/tap area, so it never intercepts input.
    private var debugBar: some View {
        HStack(spacing: 16) {
            Button("Fold") { state.fold() }
            Button("Clear") { state.clearEchoes() }
            Button("Next") { loadNextRoom() }
            Spacer()
            if state.hasWon {
                Text("Solved ✓").fontWeight(.semibold)
            }
            Text("turn \(state.turn) · echoes \(state.echoes.count)/\(budgetText)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// The echo budget as text — the number, or "∞" for the uncapped bare board
    /// (the proof rooms always carry a real small cap).
    private var budgetText: String {
        state.echoBudget == .max ? "∞" : "\(state.echoBudget)"
    }
}

#Preview {
    ContentView()
}
