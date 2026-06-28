//
//  FrameStatsTests.swift
//  ECHOTests
//
//  Phase 3.04 (Final feel + performance — device-gated groundwork). Deterministic
//  coverage for the pure math behind the developer-only performance overlay (D-063):
//  `FrameWindow`'s rolling-average / worst-in-window / dropped-frame-count statistics
//  and their composition into a `FrameStats` snapshot. The SwiftUI overlay and its
//  `CADisplayLink` cannot render real frames under Command Line Tools, which is exactly
//  why the math is factored into a `nonisolated` value type — so it can be verified here
//  by feeding known frame-interval sequences.
//
//  Frame intervals are chosen as exact binary fractions (0.25, 0.5, 0.75, …) wherever an
//  equality is asserted, so the comparisons are exact without an `accuracy:` tolerance;
//  the dropped-frame samples are kept clear of the threshold so the boolean is never
//  borderline. `@MainActor` to match the other suites' runner pattern; the types under
//  test are `nonisolated` and callable from here.
//

import XCTest
@testable import ECHO

@MainActor
final class FrameStatsTests: XCTestCase {

    /// Build a window of `capacity` and feed it `seconds` in order.
    private func window(capacity: Int = 120, _ seconds: [Double]) -> FrameWindow {
        var w = FrameWindow(capacity: capacity)
        for s in seconds { w.record(s) }
        return w
    }

    // MARK: - Empty / degenerate

    func testEmptyWindowReportsAllZero() {
        let w = FrameWindow()
        XCTAssertTrue(w.isEmpty)
        XCTAssertEqual(w.averageSeconds, 0)
        XCTAssertEqual(w.worstSeconds, 0)
        XCTAssertEqual(w.instantaneousSeconds, 0)
        XCTAssertEqual(w.fps, 0)                                   // guarded, not 1/0
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.5), 0)
        XCTAssertEqual(w.summary(budgetSeconds: 0.5), .zero)
    }

    func testZeroSnapshotAndEmptyWindowHaveFPSZeroNotInfinity() {
        XCTAssertEqual(FrameStats.zero.fps, 0)
        XCTAssertEqual(FrameWindow().fps, 0)
    }

    // MARK: - Core statistics

    func testInstantaneousAverageWorstAndFPS() {
        let w = window([0.25, 0.75])
        XCTAssertEqual(w.instantaneousSeconds, 0.75)   // the most recent sample
        XCTAssertEqual(w.averageSeconds, 0.5)          // (0.25 + 0.75) / 2
        XCTAssertEqual(w.worstSeconds, 0.75)           // the max in the window
        XCTAssertEqual(w.fps, 2.0)                      // 1 / average
    }

    func testWorstIsMaxNotMostRecent() {
        let w = window([0.75, 0.25])                    // the spike is the older sample
        XCTAssertEqual(w.instantaneousSeconds, 0.25)
        XCTAssertEqual(w.worstSeconds, 0.75)
    }

    // MARK: - Window capacity

    func testCapacityEvictsOldest() {
        let w = window(capacity: 3, [0.1, 0.2, 0.3, 0.4, 0.5])
        XCTAssertEqual(w.durations.count, 3)
        XCTAssertEqual(w.durations, [0.3, 0.4, 0.5])    // oldest two dropped
        XCTAssertEqual(w.instantaneousSeconds, 0.5)
    }

    func testCapacityClampedToAtLeastOne() {
        var w = FrameWindow(capacity: 0)
        XCTAssertEqual(w.capacity, 1)
        w.record(0.2)
        w.record(0.4)
        XCTAssertEqual(w.durations, [0.4])              // only the most recent survives
    }

    func testResetClearsSamplesButKeepsCapacity() {
        var w = window(capacity: 5, [0.05, 0.5, 0.02])  // includes a spike
        w.reset()
        XCTAssertTrue(w.isEmpty)
        XCTAssertEqual(w.capacity, 5)                   // capacity preserved
        XCTAssertEqual(w.worstSeconds, 0)               // stale spike gone
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.016), 0)
        w.record(0.01)                                  // still usable after reset
        XCTAssertEqual(w.durations, [0.01])
    }

    // MARK: - Bad samples ignored

    func testIgnoresNonPositiveAndNonFinite() {
        let w = window([0, -0.016, .nan, .infinity, 0.5])
        XCTAssertEqual(w.durations, [0.5])
        XCTAssertFalse(w.isEmpty)
    }

    // MARK: - Dropped / hitched frames

    func testDroppedCountThresholdAndTolerance() {
        // budget 0.01, default tolerance 1.5 → threshold 0.015; samples clear of it.
        let w = window([0.008, 0.02, 0.05, 0.009])
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.01, tolerance: 1.5), 2)  // 0.02, 0.05
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.01, tolerance: 4.0), 1)  // only 0.05 (> 0.04)
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.01, tolerance: 0.5), 4)  // all (> 0.005)
    }

    func testDroppedCountUsesDefaultToleranceOfOnePointFive() {
        let w = window([0.008, 0.02, 0.05, 0.009])
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.01), 2)  // same as tolerance 1.5
    }

    func testDroppedCountZeroOrNegativeInputsAreZero() {
        let w = window([0.05, 0.06])
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0), 0)
        XCTAssertEqual(w.droppedCount(budgetSeconds: -0.016), 0)
        XCTAssertEqual(w.droppedCount(budgetSeconds: 0.01, tolerance: 0), 0)
    }

    // MARK: - Snapshot composition

    func testSummaryComposesMillisecondsAndCount() {
        let w = window([0.25, 0.75])
        let s = w.summary(budgetSeconds: 0.5, tolerance: 1.0)   // threshold 0.5
        XCTAssertEqual(s.instantaneousMs, 750)                  // 0.75 * 1000
        XCTAssertEqual(s.averageMs, 500)                        // 0.5 * 1000
        XCTAssertEqual(s.worstMs, 750)
        XCTAssertEqual(s.fps, 2.0)
        XCTAssertEqual(s.droppedCount, 1)                       // only 0.75 > 0.5
    }
}
