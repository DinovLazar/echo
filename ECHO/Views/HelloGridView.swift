//
//  HelloGridView.swift
//  ECHO
//
//  Phase 1.02 throwaway placeholder. Draws a static, non-interactive 5×5 grid
//  of square cells with thin grey borders, centered within the safe area. Its
//  only job is to prove the build pipeline renders a real grid on the paper
//  background — Phase 1.03 replaces it with the state-driven board.
//
//  Deliberately pre-design: no gameplay, no state, no animation, and no visual
//  styling beyond "grey boxes on paper." The real monochrome palette, accent,
//  and invert mode are locked later in Part 2 (Phase 2.01).
//

import SwiftUI

struct HelloGridView: View {
    /// Square grid: equal rows and columns so every cell is a square.
    private static let count = 5
    /// Thin neutral-grey cell border — reads clearly on warm paper and carries
    /// no design meaning yet (the real palette is a later phase).
    private static let border = Color(white: 0.7)
    private static let lineWidth: CGFloat = 1
    /// Fraction of the smaller screen dimension the board occupies, leaving a
    /// margin so it never crowds the safe-area edges.
    private static let fillFraction: CGFloat = 0.82

    var body: some View {
        GeometryReader { proxy in
            // Size from the smaller dimension so the board stays square and fits
            // within the safe area on any device size or orientation.
            let side = min(proxy.size.width, proxy.size.height) * Self.fillFraction
            let cell = side / CGFloat(Self.count)

            VStack(spacing: 0) {
                ForEach(0..<Self.count, id: \.self) { _ in
                    HStack(spacing: 0) {
                        ForEach(0..<Self.count, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: cell, height: cell)
                                .border(Self.border, width: Self.lineWidth)
                        }
                    }
                }
            }
            // Center the square board within the available (safe-area) space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    HelloGridView()
}
