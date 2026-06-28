//
//  GuidanceOverlay.swift
//  ECHO
//
//  Phase 2.06 (Settings, persistence, the echo-trail aid & the guidance microcopy).
//  The look + fade of the guidance message (handover §6), driven by the
//  `GuidanceController`'s current `message`. Mounted inside `BoardView`'s board ZStack
//  (above the pieces, hit-testing off) so it anchors to the board.
//
//  Style (handover §6): SF Pro Text 15 pt, weight `.medium`, tracking +0.2 pt, in the
//  `text.guidance` token only — no pill, no panel, no box, no border, no shadow;
//  visibly UI, not a board piece. Horizontally centred in the **lower third** of the
//  board, kept ≥ 24 pt above the board's bottom; if the live action (the player) is in
//  the lower third, it anchors to the **upper third** instead, same style. The message
//  slides nowhere — opacity only: fade-in 200 ms `curve.easeOut` (`Motion.guidanceIn`)
//  → linger (2200 ms one-time hint / 1600 ms feedback) → fade-out 350 ms `curve.easeIn`
//  (`Motion.guidanceOut`). The overlay self-times its own fade from the message it is
//  handed; a fresh message id (every fire) re-runs the sequence via `.task(id:)`.
//

import SwiftUI

struct GuidanceOverlay: View {
    /// The message to render, from the controller. A new `id` (every fire) re-triggers
    /// the fade sequence.
    let message: GuidanceMessage?
    /// The board's pixel size — the overlay positions itself within it.
    let boardSize: CGSize
    /// `true` when the player is in the board's lower third, so the message anchors to
    /// the upper third to stay clear of the live action (handover §6).
    let placeUpper: Bool
    /// The `text.guidance` colour for the active palette.
    let color: Color

    /// The message actually on screen (kept while it fades out, even after the
    /// controller's `message` identity moves on).
    @State private var shown: GuidanceMessage?
    /// Opacity-only fade (the message never moves).
    @State private var opacity: Double = 0
    /// The anchor third, **captured once when the message appears** and held for its
    /// whole life — so a message never moves while it is visible (handover §6: "the
    /// message slides nowhere — opacity only"). Recomputing `placeUpper` live would let
    /// the caption teleport the board height if the player crossed the lower-third
    /// boundary, or on the post-death restart, mid-fade.
    @State private var anchorUpper = false

    var body: some View {
        Text(shown?.text ?? "")
            // SF Pro Text 15 pt .medium, +0.2 tracking, guidance colour — no box/shadow.
            .font(.system(size: 15, weight: .medium))
            .tracking(0.2)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: boardSize.width * 0.9)
            .opacity(opacity)
            .position(x: boardSize.width / 2, y: anchorY)
            .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
            // Re-run the fade whenever a new message fires (id changes).
            .task(id: message?.id) { await play() }
    }

    /// The vertical anchor: centre of the lower third, or the upper third when the
    /// player was down there at fire time — clamped to stay ≥ 24 pt above the board's
    /// bottom edge. Reads the *captured* `anchorUpper`, not the live prop, so the
    /// message holds its position for its whole life.
    private var anchorY: CGFloat {
        let lower = min(boardSize.height * 5 / 6, boardSize.height - 24)
        let upper = boardSize.height / 6
        return anchorUpper ? upper : lower
    }

    /// Fade-in → linger (by category) → fade-out, opacity only. Cancels cleanly if a
    /// new message arrives mid-sequence (`.task(id:)` cancels the prior run).
    private func play() async {
        guard let message else { return }
        shown = message
        anchorUpper = placeUpper   // freeze the placement for this message's lifetime
        opacity = 0
        withAnimation(Motion.guidanceIn) { opacity = 1 }
        let linger = message.category == .hint
            ? Motion.Span.guidanceLingerHint
            : Motion.Span.guidanceLingerFeedback
        try? await Task.sleep(for: .seconds(Motion.Span.guidanceIn + linger))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.guidanceOut) { opacity = 0 }
    }
}
