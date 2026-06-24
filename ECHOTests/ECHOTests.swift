//
//  ECHOTests.swift
//  ECHOTests
//
//  Phase 1.01 (Scaffold): a single trivial passing test that proves the test
//  target compiles and runs. Real coverage of the deterministic core (turn
//  engine, replay, collision, win detection) arrives with that code in later
//  phases.
//

import XCTest
@testable import ECHO

final class ECHOTests: XCTestCase {

    /// Proves the ECHOTests target builds, links against the app, and runs.
    func testScaffoldCompilesAndRuns() {
        XCTAssertEqual(2 + 2, 4)
    }
}
