//
//  ContentView.swift
//  ECHO
//
//  Root view. Fills the whole screen with the warm off-white "paper" background
//  described in the Plan (§5/§14) and composes the state-driven board on top.
//  It owns the `GameState` and, from Phase 1.08, the ordered list of the ten
//  teaching-room ids: it loads room 1 on launch and the throwaway debug bar's *Next*
//  cycles through the rooms by building a fresh `GameState` from each level.
//  The monochrome/accent/invert design system and the tuned feel arrive in
//  Part 2; this stays "grey boxes on paper" by design.
//

import SwiftUI

struct ContentView: View {
    // Warm off-white "paper" — the canvas the game is drawn on. This is a
    // deliberately minimal placeholder; the full palette and invert mode live in
    // a later design phase. Defined inline so the app has zero dependencies.
    private static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)

    /// The ten teaching rooms, in order. `Next` cycles through these (Phase 1.08),
    /// replacing the three throwaway proof rooms. The real Level Select is Part 3
    /// (D-037) — this is still a throwaway debug cycle with no saved progress.
    private static let roomIDs = [
        "room-01", "room-02", "room-03", "room-04", "room-05",
        "room-06", "room-07", "room-08", "room-09", "room-10",
    ]

    /// Index of the room currently loaded into `state`.
    @State private var roomIndex = 0

    /// The single source of truth for the board, owned here so both the board and
    /// the debug bar act on the same model. Loaded from the first teaching room (with
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

    /// Build a `GameState` for the teaching room at `index`, falling back to a bare
    /// board if the level resource is missing or unreadable.
    private static func makeState(forRoomAt index: Int) -> GameState {
        let id = roomIDs[index % roomIDs.count]
        if let level = LevelLoader.load(id) {
            return GameState(level: level)
        }
        return GameState()
    }

    /// Advance to the next teaching room (wrapping), loading it fresh.
    private func loadNextRoom() {
        roomIndex = (roomIndex + 1) % Self.roomIDs.count
        state = Self.makeState(forRoomAt: roomIndex)
    }

    // MARK: - Debug bar (TEMPORARY — remove in Parts 2–3)

    /// Throwaway development controls, intentionally kept out of `BoardView` so the
    /// board stays "just the board" and this strip is trivial to delete later. The
    /// real in-room control layout and feel are Part 2/Part 3; these are grey-box.
    ///
    /// *Fold* banks the current run as an echo and rewinds. *Step back* (Phase 1.07)
    /// undoes one committed move of the current run (disabled at turn 0, where it is
    /// a no-op anyway). *Reset run* (Phase 1.07) scraps the current attempt but
    /// **keeps banked echoes** — the `restartRun()` op the death restart uses. *Clear*
    /// wipes the room to pristine, **echoes and all** — a debug-only convenience,
    /// deliberately distinct from *Reset run*. *Next* loads the next teaching room. The
    /// readout shows the shared turn counter and the live echo count against the
    /// room's budget, plus a "Solved ✓" stand-in once the exit is reached (the real
    /// win overlay is Part 3). It sits below the board, clear of the swipe/tap area,
    /// so it never intercepts input.
    private var debugBar: some View {
        HStack(spacing: 12) {
            Button("Fold") { state.fold() }
            Button("Step back") { state.stepBack() }
                .disabled(state.turn == 0)
            Button("Reset run") { state.restartRun() }
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
    /// (the teaching rooms always carry a real small cap).
    private var budgetText: String {
        state.echoBudget == .max ? "∞" : "\(state.echoBudget)"
    }
}

#Preview {
    ContentView()
}
