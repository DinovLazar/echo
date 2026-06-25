//
//  BoardView.swift
//  ECHO
//
//  Phase 1.03 (Grid + Move) → 1.04 (Fold) → 1.06 (Room contents). The real,
//  state-driven board. It renders the placeholder grey lattice, the room's
//  contents (walls, exit, doors, switches, hazards), any folded **echoes**, and a
//  solid black rounded-square player on top, and routes both taps and swipes
//  through the single `GameState.move(_:)` rule so the world advances one step at
//  a time.
//
//  The board no longer owns its state — `ContentView` holds the `GameState` and
//  passes it in, so the throwaway debug bar there can drive fold/clear/next on the
//  same model. The board stays "just the board": no buttons live here.
//
//  Collision and win are turn-engine rules (Phases 1.05–1.06), not UI ones:
//  touching an echo or hazard dissolves the player and restarts the run inside
//  `GameState`, reaching the exit alive sets its win flag, and because the model is
//  `@Observable` the board reacts for free. Switch/door open-state is read from the
//  model per turn, so a door drawn here just reflects `state.isDoorOpen(_:)` at the
//  current turn.
//
//  Visuals stay deliberately pre-design — legible grey boxes on paper, clearly
//  distinct from each other and from the black player and translucent-grey echoes.
//  The real monochrome palette/accent/invert mode is Phase 2.01 and the tuned
//  motion is Phase 2.02. Hit testing is off on every drawn piece so a tap falls
//  through to the cell beneath it (the lattice cells are the input layer).
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
    /// The player / echo squares fill most of their cell (the player's identity).
    private static let playerFraction: CGFloat = 0.76
    /// Minimum drag distance that counts as a swipe rather than a tap.
    private static let swipeThreshold: CGFloat = 20

    // Element placeholder palettes (all greyscale; meaning lives in shape + state,
    // never colour — the real design is Phase 2.01).
    /// Echo: a mid-grey translucent fill with a thin darker outline, beneath the player.
    private static let echoFill = Color(white: 0.5).opacity(0.35)
    private static let echoOutline = Color(white: 0.25).opacity(0.55)
    /// Wall: a solid dark-grey cell (distinct from the pure-black player).
    private static let wallFill = Color(white: 0.28)
    /// Exit: a hollow ring outline.
    private static let exitStroke = Color(white: 0.2)
    /// Switch: a hollow circle that fills in when held.
    private static let switchStroke = Color(white: 0.2)
    /// Door bar (shown only while closed).
    private static let doorFill = Color(white: 0.15)
    /// Hazard: a hollow diamond, denser than an echo and a different shape.
    private static let hazardFill = Color(white: 0.4).opacity(0.5)
    private static let hazardOutline = Color(white: 0.12)

    var body: some View {
        GeometryReader { proxy in
            // Square cells sized so the whole board fits within `fillFraction` of
            // the smaller dimension. `max(width, height)` keeps cells square if a
            // level loads a non-square board.
            let available = min(proxy.size.width, proxy.size.height) * Self.fillFraction
            let cell = available / CGFloat(max(state.width, state.height))
            let boardSize = CGSize(width: cell * CGFloat(state.width),
                                   height: cell * CGFloat(state.height))

            ZStack(alignment: .topLeading) {
                lattice(cell: cell)
                walls(cell: cell)
                exitRing(cell: cell)
                doorBars(cell: cell)
                switchMarks(cell: cell)
                echoes(cell: cell)
                hazardMarks(cell: cell)
                playerSquare(cell: cell)
            }
            .frame(width: boardSize.width, height: boardSize.height)
            // Center the board within the available (safe-area) space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(swipeGesture)
        }
    }

    // MARK: - Pieces

    /// The grey-box lattice. Each cell is independently tappable so a tap on a
    /// cell orthogonally adjacent to the player can become a move. This is the
    /// input layer; every other layer has hit testing off so taps reach it.
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

    /// Walls: a solid dark-grey square filling each impassable cell.
    private func walls(cell: CGFloat) -> some View {
        ForEach(Array(state.walls), id: \.self) { wall in
            Rectangle()
                .fill(Self.wallFill)
                .frame(width: cell, height: cell)
                .position(center(of: wall, cell: cell))
                .allowsHitTesting(false)
        }
    }

    /// Exit: a hollow ring on the exit cell (drawn beneath everything that can sit
    /// on it, so the player/echo/hazard read clearly on top).
    @ViewBuilder
    private func exitRing(cell: CGFloat) -> some View {
        if let exit = state.exit {
            let size = cell * Self.playerFraction
            Circle()
                .strokeBorder(Self.exitStroke, lineWidth: max(2, Self.lineWidth * 2))
                .frame(width: size, height: size)
                .position(center(of: exit, cell: cell))
                .allowsHitTesting(false)
        }
    }

    /// Doors: a thick bar drawn across each closed door cell; nothing when open
    /// (the bar "retracts"). Open-state is read from the model at the current turn.
    private func doorBars(cell: CGFloat) -> some View {
        ForEach(state.doors) { door in
            let open = state.isDoorOpen(door)
            ForEach(Array(door.cells.enumerated()), id: \.offset) { _, doorCell in
                Rectangle()
                    .fill(Self.doorFill)
                    .frame(width: cell * 0.9, height: max(3, cell * 0.16))
                    .position(center(of: doorCell, cell: cell))
                    .opacity(open ? 0 : 1)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Switches: a small hollow circle that fills in when held (player or echo on
    /// its cell this turn).
    private func switchMarks(cell: CGFloat) -> some View {
        let size = cell * 0.42
        return ForEach(state.switches) { theSwitch in
            let held = state.isSwitchHeld(theSwitch.id)
            Circle()
                .strokeBorder(Self.switchStroke, lineWidth: max(2, Self.lineWidth * 2))
                .background(Circle().fill(held ? Self.switchStroke : Color.clear))
                .frame(width: size, height: size)
                .position(center(of: theSwitch.cell, cell: cell))
                .allowsHitTesting(false)
        }
    }

    /// The folded echoes: one translucent grey rounded square per echo, each at
    /// its current cell and sliding between turns just like the player. Drawn
    /// *beneath* the player and hazards (the black square always reads clearest)
    /// and with hit testing off so a tap falls straight through to the cell
    /// beneath. Touching one is fatal — but that is a turn-engine rule in
    /// `GameState`, not a property of this view.
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
                .position(center(of: position, cell: cell))
                .animation(.easeInOut, value: position)
                .allowsHitTesting(false)
        }
    }

    /// Hazards: a hollow diamond (a different shape from the rounded-square echo so
    /// the two never blur together), at the hazard's current cell, sliding between
    /// turns. Lethal on contact — again, a `GameState` rule, not a view property.
    private func hazardMarks(cell: CGFloat) -> some View {
        let size = cell * Self.playerFraction
        return ForEach(state.hazards) { hazard in
            let position = state.position(of: hazard)
            Diamond()
                .fill(Self.hazardFill)
                .overlay(Diamond().stroke(Self.hazardOutline, lineWidth: max(2, Self.lineWidth * 2)))
                .frame(width: size, height: size)
                .position(center(of: position, cell: cell))
                .animation(.easeInOut, value: position)
                .allowsHitTesting(false)
        }
    }

    /// The player: a solid black rounded square filling most of its cell, centered
    /// on its current cell. It slides on a committed move (a plain default ease —
    /// the tuned curve is Phase 2.02).
    private func playerSquare(cell: CGFloat) -> some View {
        let size = cell * Self.playerFraction
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.black)
            .frame(width: size, height: size)
            .position(center(of: state.player, cell: cell))
            .animation(.easeInOut, value: state.player)
            .allowsHitTesting(false)
    }

    // MARK: - Geometry

    /// Pixel center of a grid cell, for `.position(_:)`.
    private func center(of coordinate: GridCoordinate, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(coordinate.column) + 0.5) * cell,
                y: (CGFloat(coordinate.row) + 0.5) * cell)
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

/// A diamond (rotated-square) outline used as the hazard placeholder — a distinct
/// silhouette from the rounded-square player/echo. Pure shape, no design meaning.
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    BoardView(state: GameState())
}
