//
//  FrameStats.swift
//  ECHO
//
//  Phase 3.04 (Final feel + performance — device-gated groundwork). The pure,
//  view-independent math behind the developer-only performance overlay (D-063): a
//  rolling window of recent frame intervals and the statistics derived from it —
//  instantaneous frame time, a rolling average, the corresponding FPS, the single
//  worst frame in the window, and a dropped/hitched-frame count.
//
//  Kept Foundation-only and `nonisolated`/`Sendable` (no SwiftUI, no CADisplayLink) so
//  it is fully unit-testable headlessly, exactly like the engine value types — the
//  whole point of factoring the math out of the SwiftUI overlay (which can never render
//  real frames under Command Line Tools). The overlay in `PerformanceOverlay.swift`
//  feeds this from a `CADisplayLink` on device; the numbers it reports are this type's.
//
//  Lives in `ECHO/Diagnostics/` rather than `Models/` because it is a developer
//  instrument, not part of the game model — but it is a pure value type in the same
//  spirit (`GridCoordinate`/`Direction`/`Campaign`), so it rides the same headless test
//  module. It is NOT `#if DEBUG`-gated: it is harmless pure code with no side effects
//  and is never instantiated in a release build (only the overlay that uses it is gated
//  out), so it costs nothing shipped and stays trivially testable without a DEBUG flag.
//

import Foundation

/// One immutable snapshot of the recent frame-timing statistics, ready for display.
/// Built by `FrameWindow.summary(budgetSeconds:)`. `nonisolated`/`Sendable` like the
/// other pure value types (D-013/D-040).
nonisolated struct FrameStats: Equatable, Sendable {
    /// The most recent single frame interval, in milliseconds.
    let instantaneousMs: Double
    /// The mean frame interval across the window, in milliseconds.
    let averageMs: Double
    /// Frames per second implied by the rolling average (`1 / averageSeconds`).
    let fps: Double
    /// The single longest frame interval in the window, in milliseconds — the spike
    /// that reads as a stutter (jank is the worst frame, not the average).
    let worstMs: Double
    /// How many frames in the window exceeded the display budget enough to count as a
    /// hitch (see `FrameWindow.droppedCount`).
    let droppedCount: Int

    /// The all-zero snapshot used before any frame has been recorded.
    static let zero = FrameStats(instantaneousMs: 0, averageMs: 0, fps: 0,
                                 worstMs: 0, droppedCount: 0)
}

/// A fixed-capacity rolling window of recent frame intervals (seconds), and the pure
/// statistics over it. A value type: the device overlay holds one and `record(_:)`s
/// each frame; the math methods are total and side-effect-free, so they unit-test by
/// feeding a known sequence. `nonisolated`/`Sendable`.
nonisolated struct FrameWindow: Equatable, Sendable {
    /// The most this window retains; older samples are dropped as new ones arrive.
    let capacity: Int

    /// The retained frame intervals in seconds, oldest first, most-recent last.
    private(set) var durations: [Double]

    /// - Parameter capacity: how many recent frames to keep (clamped to ≥ 1). 120 ≈ one
    ///   to two seconds of history at 60–120 Hz — enough to surface a spike "over a
    ///   window" without smearing the rolling average across many seconds.
    init(capacity: Int = 120) {
        self.capacity = Swift.max(1, capacity)
        self.durations = []
    }

    /// Append one frame interval (seconds), evicting the oldest sample(s) once the
    /// window is full. Non-finite or non-positive intervals are ignored (a paused or
    /// just-started display link can report 0 or a garbage delta — those are not frames).
    mutating func record(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        durations.append(seconds)
        if durations.count > capacity {
            durations.removeFirst(durations.count - capacity)
        }
    }

    /// Drop every retained sample (keeping the capacity), so a restarted monitor begins
    /// from a clean window rather than carrying stale spikes into worst/dropped.
    mutating func reset() {
        durations.removeAll(keepingCapacity: true)
    }

    /// True until the first valid frame is recorded.
    var isEmpty: Bool { durations.isEmpty }

    /// The most recent frame interval, in seconds (0 if none yet).
    var instantaneousSeconds: Double { durations.last ?? 0 }

    /// The mean frame interval across the window, in seconds (0 if empty).
    var averageSeconds: Double {
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// The single longest frame interval in the window, in seconds (0 if empty).
    var worstSeconds: Double { durations.max() ?? 0 }

    /// Frames per second implied by the rolling average (0 if empty).
    var fps: Double { averageSeconds > 0 ? 1 / averageSeconds : 0 }

    /// How many frames in the window are hitches: an interval longer than the display's
    /// frame budget by more than `tolerance` (default 1.5×). A hitch — not the average —
    /// is what reads as a dropped frame, so the count surfaces spikes the mean hides.
    /// `budgetSeconds` is the expected interval (≈ `1 / maxRefreshHz`, e.g. 1/60 or
    /// 1/120); the device overlay reads it live from the display link.
    func droppedCount(budgetSeconds: Double, tolerance: Double = 1.5) -> Int {
        guard budgetSeconds > 0, tolerance > 0 else { return 0 }
        let threshold = budgetSeconds * tolerance
        return durations.reduce(0) { $0 + ($1 > threshold ? 1 : 0) }
    }

    /// Compose a display-ready snapshot from the current window for the given display
    /// budget. Pure — the overlay calls this a few times a second to publish.
    func summary(budgetSeconds: Double, tolerance: Double = 1.5) -> FrameStats {
        FrameStats(instantaneousMs: instantaneousSeconds * 1000,
                   averageMs: averageSeconds * 1000,
                   fps: fps,
                   worstMs: worstSeconds * 1000,
                   droppedCount: droppedCount(budgetSeconds: budgetSeconds, tolerance: tolerance))
    }
}
