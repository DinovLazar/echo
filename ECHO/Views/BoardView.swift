//
//  BoardView.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move) → 1.04 (Fold). The real, state-driven board. It
//  renders the placeholder grey lattice, any folded **echoes** as translucent
//  grey squares, and a solid black rounded-square player on top, and routes both
//  taps and swipes through the single `GameState.move(_:)` rule so the world
//  advances one step at a time.
//
//  The board no longer owns its state — `ContentView` holds the `GameState` and
//  passes it in, so the throwaway debug bar there can drive fold/clear on the same
//  model. The board stays "just the board": no buttons live here.
//
//  No collision in 1.04 (Phase 1.05): echoes and the player may share a tile, so
//  echoes are drawn with hit-testing off and the player simply draws last / on
//  top. Visuals stay deliberately pre-design ("grey boxes on paper"): the real
//  monochrome palette/accent/invert mode is Phase 2.01 and the tuned ~120 ms
//  ease-in-out + squash-and-stretch motion is Phase 2.02. The slide here is a
//  plain default animation placeholder, nothing more.
//

import SwiftUI

struct BoardView: View {
    /// The board's state, owned by `ContentView` and passed in (Observation
    /// re-renders this view when the state it reads changes).
    let state: GameState

    // Placeholder look only — the real palette and motion land in Part 2.
    /// Thin neutral-grey cell border (carries no design meaning yet).
    private static let gridLine = Color(white: 0.7)
    private static let lineWidth: CGFloat = 1
    /// Board occupies this fraction of the smaller available dimension, leaving a
    /// margin from the safe-area edges (kept from the hello-grid).
    private static let fillFraction: CGFloat = 0.82
    /// The player square fills most of its cell (the player's locked identity).
    private static let playerFraction: CGFloat = 0.76
    /// Minimum drag distance that counts as a swipe rather than a tap.
    private static let swipeThreshold: CGFloat = 20
    /// Echo placeholder look (the real echo design is Phase 2.01): a mid-grey,
    /// ~35%-opacity fill with a thin darker outline, drawn beneath the player.
    private static let echoFill = Color(white: 0.5).opacity(0.35)
    private static let echoOutline = Color(white: 0.25).opacity(0.55)

    var body: some View {
        GeometryReader { proxy in
            // Square cells sized so the whole board fits within `fillFraction` of
            // the smaller dimension. For the default square board this is the same
            // sizing as the hello-grid (side / 7); using `max` keeps cells square
            // if a later phase loads a non-square board.
            let available = min(proxy.size.width, proxy.size.height) * Self.fillFraction
            let cell = available / CGFloat(max(state.width, state.height))
            let boardSize = CGSize(width: cell * CGFloat(state.width),
                                   height: cell * CGFloat(state.height))

            ZStack(alignment: .topLeading) {
                lattice(cell: cell)
                echoes(cell: cell)
                playerSquare(cell: cell)
            }
            .frame(width: boardSize.width, height: boardSize.height)
            // Center the square board within the available (safe-area) space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(swipeGesture)
        }
    }

    // MARK: - Pieces

    /// The grey-box lattice. Each cell is independently tappable so a tap on a
    /// cell orthogonally adjacent to the player can become a move.
    private func lattice(cell: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<state.height, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<state.width, id: \.self) { column in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: cell, height: cell)
                            .border(Self.gridLine, width: Self.lineWidth)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tap(GridCoordinate(row: row, column: column))
                            }
                    }
                }
            }
        }
    }

    /// The folded echoes: one translucent grey rounded square per echo, each at
    /// its current cell and sliding between turns just like the player. Drawn
    /// *beneath* the player (the black square always reads clearest) and with hit
    /// testing off — there is no collision in 1.04, so they share tiles freely and
    /// taps fall straight through to the cell beneath. Each echo has a stable `id`
    /// so SwiftUI animates them independently.
    private func echoes(cell: CGFloat) -> some View {
        let size = cell * Self.playerFraction
        return ForEach(state.echoes) { echo in
            let position = state.position(of: echo)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Self.echoFill)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(Self.echoOutline, lineWidth: Self.lineWidth)
                )
                .frame(width: size, height: size)
                .position(x: (CGFloat(position.column) + 0.5) * cell,
                          y: (CGFloat(position.row) + 0.5) * cell)
                .animation(.easeInOut, value: position)
                .allowsHitTesting(false)
        }
    }

    /// The player: a solid black rounded square filling most of its cell,
    /// centered on its current cell. It slides on a committed move (a plain
    /// default ease — the tuned curve is Phase 2.02). Hit testing is off so taps
    /// fall through to the cell beneath it.
    private func playerSquare(cell: CGFloat) -> some View {
        let size = cell * Self.playerFraction
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.black)
            .frame(width: size, height: size)
            .position(x: (CGFloat(state.player.column) + 0.5) * cell,
                      y: (CGFloat(state.player.row) + 0.5) * cell)
            .animation(.easeInOut, value: state.player)
            .allowsHitTesting(false)
    }

    // MARK: - Input

    /// A tap on a cell orthogonally adjacent to the player steps into it; any
    /// other cell (diagonal, non-adjacent, or the player's own) does nothing.
    private func tap(_ cell: GridCoordinate) {
        guard let direction = Direction(from: state.player, to: cell) else { return }
        state.move(direction)
    }

    /// A swipe whose dominant axis picks the direction → one step that way.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: Self.swipeThreshold)
            .onEnded { value in
                guard let direction = swipeDirection(value.translation) else { return }
                state.move(direction)
            }
    }

    /// Maps a drag translation to a cardinal direction by its dominant axis
    /// (top-left origin: a negative height is upward, a negative width is left).
    private func swipeDirection(_ translation: CGSize) -> Direction? {
        if translation == .zero { return nil }
        if abs(translation.width) >= abs(translation.height) {
            return translation.width < 0 ? .left : .right
        } else {
            return translation.height < 0 ? .up : .down
        }
    }
}

#Preview {
    BoardView(state: GameState())
}
