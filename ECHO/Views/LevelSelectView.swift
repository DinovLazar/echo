//
//  LevelSelectView.swift
//  ECHO
//
//  Phase 3.03 (Navigation shell). Level Select (Plan §4 screen 3): a 4-column × 5-row
//  grid of the twenty rooms in `Campaign.roomIDs` order, each a bordered square tile
//  (echoing the wall/chrome language) showing its room number plus the exit-ring motif.
//
//  Two state cues, both within the locked palette:
//    • **Solved is marked by shape, never colour alone (D-060):** an unsolved tile shows
//      the *open* exit-ring (a hollow ink ring); a solved tile shows the *closed/filled*
//      variant (a filled ink disc). Read from `SettingsStore.isSolved`.
//    • **The single muted accent tints only the one "next to play" tile** — the first
//      unsolved room in order (`Campaign.firstUnsolved`); if all are solved, none. The
//      accent (goal-gold, the game's "the one thing you'd reach now" colour) is a border
//      + faint wash, and is never the only cue (that tile is also the first unsolved,
//      and still carries the hollow ring) — consistent with D-041.
//
//  **Free pick (D-060):** every tile is tappable regardless of solved-state → opens that
//  room; there is no unlock gating. A back affordance ("Menu", a chevron) sits top-left,
//  mirroring the in-game gear placement. No new visual system — `Theme` tokens only.
//

import SwiftUI

struct LevelSelectView: View {
    /// The persisted store, read for the per-room solved-state and the next-to-play tile.
    let settings: SettingsStore
    /// Back to the Main Menu (the root performs the fade).
    let onBack: () -> Void
    /// Open a room (any room — there is no gating, D-060).
    let onPick: (String) -> Void

    @Environment(\.theme) private var theme

    /// Four equal columns; the grid flows over all `Campaign.roomIDs` (25 as of Phase 4.02).
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.paperTop, theme.paperBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Campaign.roomIDs, id: \.self) { id in
                            tile(for: id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    /// The next room to play — the first unsolved room in order (D-060). `nil` once every
    /// room is solved, so no tile is accented.
    private var nextToPlay: String? {
        Campaign.firstUnsolved(solved: settings.solvedRooms)
    }

    // MARK: - Header (back affordance, top-left — mirrors the in-game gear)

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Menu")
                }
                .font(.body)
                .foregroundStyle(theme.ink)
            }
            .frame(minHeight: 44)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - One room tile

    private func tile(for id: String) -> some View {
        let solved = settings.isSolved(id)
        let isNext = (id == nextToPlay)
        let number = Campaign.number(of: id) ?? 0
        return Button { onPick(id) } label: {
            ZStack {
                tileBackground(isNext: isNext)
                VStack(spacing: 8) {
                    exitRingMark(solved: solved)
                    Text("\(number)")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(theme.ink)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Room \(number)\(solved ? ", solved" : "")"))
    }

    /// The bordered cell — a faint ink wash + hairline, in the chrome language. The
    /// next-to-play tile takes the muted accent: a gold border + a faint gold wash.
    private func tileBackground(isNext: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape
            .fill(isNext ? theme.goalGold.opacity(0.12) : theme.ink.opacity(0.05))
            .overlay(
                shape.strokeBorder(isNext ? theme.goalGold : theme.tileHairline,
                                   lineWidth: isNext ? 2 : 1)
            )
    }

    /// The exit-ring motif: open (a hollow ink ring) when unsolved, closed/filled (a
    /// filled ink disc) when solved — the shape-based solved mark (D-060). Monochrome, so
    /// the accent stays reserved for the next-to-play tile.
    @ViewBuilder
    private func exitRingMark(solved: Bool) -> some View {
        let size: CGFloat = 22
        if solved {
            Circle()
                .fill(theme.ink)
                .frame(width: size, height: size)
        } else {
            Circle()
                .strokeBorder(theme.ink.opacity(BoardMetrics.exitDefaultRing), lineWidth: 3)
                .frame(width: size, height: size)
        }
    }
}

#Preview("Light — none solved") {
    LevelSelectView(settings: SettingsStore(), onBack: {}, onPick: { _ in })
        .environment(\.theme, .light)
        .tint(Theme.light.ink)
}

#Preview("Invert") {
    LevelSelectView(settings: SettingsStore(), onBack: {}, onPick: { _ in })
        .environment(\.theme, .invert)
        .tint(Theme.invert.ink)
}
