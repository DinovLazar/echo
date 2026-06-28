//
//  PerformanceOverlay.swift
//  ECHO
//
//  Phase 3.04 (Final feel + performance — device-gated groundwork). A developer-only
//  frame-rate readout (D-063). "60fps / no jank" can only be judged on a real iPhone,
//  and eyeballing a fast board is unreliable — a stutter is a *spike* (a dropped frame),
//  not a lower average — so the on-device verification session needs an instrument, not
//  a guess. This overlay samples real frame timing with a `CADisplayLink` (no external
//  package) and shows the instantaneous frame time, a rolling average, the implied FPS,
//  and a worst-frame / dropped-frame count over a window.
//
//  Gated out of release at COMPILE TIME with `#if DEBUG`, so it can never appear in the
//  shipping UI: the `debugPerformanceOverlay()` modifier resolves to a no-op in a
//  release build, and the readout/monitor types do not exist there at all. It is also
//  deliberately NOT wired into the real Settings screen or HUD chrome, and it uses a
//  neutral translucent pill (not the `Theme` tokens), so the app's clean look and the
//  D-055 colour discipline are untouched. The readout is non-interactive
//  (`allowsHitTesting(false)`), so it can never eat a swipe/tap meant for the board.
//
//  The pure statistics live in `FrameStats` / `FrameWindow` (`ECHO/Diagnostics/`,
//  Foundation-only, `nonisolated`/`Sendable`) so the math is unit-tested headlessly;
//  this file is only the `@MainActor` plumbing that feeds them from the display link and
//  draws the numbers. The `CADisplayLink` itself is iOS-only, so it sits behind
//  `#if canImport(UIKit)` (the same graceful-degradation pattern as `AudioManager`'s
//  `AVAudioSession` and `HapticsManager`'s `UIKit` surface) — off-iOS the monitor is a
//  no-op skeleton and the readout simply shows zeros, which keeps the type-check clean
//  against the macOS SDK in the no-Xcode dev environment.
//

import SwiftUI

extension View {
    /// Mount the developer-only frame-rate readout in the top-trailing corner. A no-op
    /// in release (the whole body is compiled out by `#if DEBUG`) and on any platform
    /// without `CADisplayLink`. Applied on both boards where frame rate matters — the
    /// campaign `RoomView` and `EchoRunView` (the stacked-shadow worst case) — so the
    /// device pass can watch either (D-063).
    ///
    /// - Parameter enabled: a debug-only on/off; defaults to on (the device pass wants
    ///   the numbers visible while it plays). Never a user-facing setting.
    @ViewBuilder
    func debugPerformanceOverlay(_ enabled: Bool = true) -> some View {
        #if DEBUG
        modifier(PerformanceOverlayModifier(enabled: enabled))
        #else
        self
        #endif
    }
}

#if DEBUG

/// Overlays the readout on top of its content, top-trailing. Debug-only.
private struct PerformanceOverlayModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if enabled { PerformanceReadout() }
        }
    }
}

/// The corner readout. Renders the latest `FrameStats` the monitor publishes; the
/// monitor runs only while this view is on screen. Non-interactive and theme-independent
/// on purpose (it is an instrument, not chrome).
private struct PerformanceReadout: View {
    @State private var monitor = FrameRateMonitor()

    var body: some View {
        let stats = monitor.stats
        VStack(alignment: .trailing, spacing: 1) {
            Text(String(format: "%.0f fps", stats.fps))
            Text(String(format: "now %.1f ms", stats.instantaneousMs))
            Text(String(format: "avg %.1f ms", stats.averageMs))
            Text(String(format: "max %.1f ms", stats.worstMs))
            Text("dropped \(stats.droppedCount)")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.top, 36)        // clear the in-room HUD / Echo Run top bar
        .padding(.trailing, 8)
        .allowsHitTesting(false)  // never intercept a board swipe/tap
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

/// Samples real frame timing via a `CADisplayLink` and publishes a throttled
/// `FrameStats` snapshot for the readout. `@MainActor @Observable` (D-013); the pure
/// window/statistics math is delegated to the `nonisolated` `FrameWindow`. Cheap by
/// design — every frame is recorded into the window (a tiny array op), but the observed
/// snapshot is republished only a few times a second, so the readout's own redraws do
/// not measurably cost the frame rate it is measuring.
@MainActor
@Observable
final class FrameRateMonitor {
    /// The latest published snapshot — the only observed property, so the readout
    /// re-renders at the publish cadence, not every frame.
    private(set) var stats: FrameStats = .zero

    @ObservationIgnored private var window = FrameWindow(capacity: 120)
    /// The display's expected frame interval (≈ 1 / maxRefreshHz), tracked live so the
    /// dropped-frame budget follows 60 Hz vs ProMotion 120 Hz automatically.
    @ObservationIgnored private var budgetSeconds: Double = 1.0 / 60.0
    @ObservationIgnored private var lastTimestamp: Double = 0
    @ObservationIgnored private var sincePublish = 0
    /// Republish the snapshot every Nth frame (~10 Hz at 60 fps) — frequent enough to
    /// read, infrequent enough not to disturb the measurement.
    private static let publishEvery = 6

    #if canImport(UIKit)
    @ObservationIgnored private var link: CADisplayLink?
    #endif

    /// Begin sampling. Idempotent; a no-op off-iOS (no `CADisplayLink`). Clears the window
    /// so a re-appear (stop → start on the same monitor) starts from fresh frames rather
    /// than carrying a stale worst/dropped spike from the previous run.
    func start() {
        #if canImport(UIKit)
        guard link == nil else { return }
        window.reset()
        stats = .zero
        lastTimestamp = 0
        sincePublish = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        #endif
    }

    /// Stop sampling and release the display link (breaking its retain on `self`).
    func stop() {
        #if canImport(UIKit)
        link?.invalidate()
        link = nil
        #endif
    }

    /// Ingest one frame: `timestamp` is its host time (seconds), `expected` its budget.
    /// Kept free of `UIKit` (the `CADisplayLink` that feeds it is iOS-only) so the
    /// window/throttle math type-checks on every platform.
    func ingest(timestamp: Double, expected: Double) {
        if expected > 0 { budgetSeconds = expected }
        // The first callback has no previous timestamp to difference against.
        if lastTimestamp > 0 { window.record(timestamp - lastTimestamp) }
        lastTimestamp = timestamp

        sincePublish += 1
        if sincePublish >= Self.publishEvery {
            sincePublish = 0
            stats = window.summary(budgetSeconds: budgetSeconds)
        }
    }

    #if canImport(UIKit)
    @objc private func step(_ link: CADisplayLink) {
        ingest(timestamp: link.timestamp,
               expected: link.targetTimestamp - link.timestamp)
    }
    #endif
}

#endif
