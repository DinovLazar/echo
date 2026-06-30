//
//  TeleportTests.swift
//  ECHOTests
//
//  Phase 4.03 (Teleport — linked pads). Drives the **real** `GameState`/`Echo`/`Level`
//  to pin the teleport mechanic (D-070–D-072): the shared single-step `resolveLanding`
//  resolver, pad-aware `move`/`stepBack`/echo position/`isCellHeld`/collision, the
//  level-format v2 `portals` extension, and the headline payoff — the **wait + teleport
//  relay**: one folded echo holds switch A, waits, then relocates *through a portal* to
//  switch B in the other region, opening two doors at two times so present-you wins. No
//  re-implementation of the engine: every assertion runs the real turn/collision/door/
//  teleport rules.
//
//  `GameState` is `@MainActor`, so the case is `@MainActor` to drive it directly, matching
//  the other engine suites. The existing suite needs **no** migration — with no portals the
//  pad-aware walk equals the old offset sum, byte-for-byte (D-071).
//

import XCTest
@testable import ECHO

@MainActor
final class TeleportTests: XCTestCase {

    /// Shorthand for a cell.
    private func g(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    /// A bidirectional pad map for one portal pair.
    private func pads(_ a: GridCoordinate, _ b: GridCoordinate) -> [GridCoordinate: GridCoordinate] {
        [a: b, b: a]
    }

    // MARK: - The shared resolver (D-070/D-071)

    /// `resolveLanding` is identity-plus-offset with empty pads (so a no-portal walk equals
    /// the old offset sum), jumps to the partner on a **displacing** step onto a pad, leaves
    /// a non-pad step alone, and **never** teleports a zero-offset `.stay` even on a pad.
    func testResolveLandingRuleAndEmptyPadsIdentity() {
        // Empty pads: every step is just cell + offset.
        for (dir, expected) in [(Direction.up, g(2, 3)), (.down, g(4, 3)), (.left, g(3, 2)), (.right, g(3, 4)), (.stay, g(3, 3))] {
            XCTAssertEqual(resolveLanding(from: g(3, 3), step: dir, pads: [:]), expected,
                           "empty pads: \(dir) should be a plain offset")
        }

        let p = pads(g(0, 1), g(0, 5))
        // A displacing step ONTO a pad lands on its partner (one jump, terminal — no re-fire).
        XCTAssertEqual(resolveLanding(from: g(0, 0), step: .right, pads: p), g(0, 5))
        XCTAssertEqual(resolveLanding(from: g(0, 6), step: .left, pads: p), g(0, 1))
        // A step that does NOT land on a pad is unchanged.
        XCTAssertEqual(resolveLanding(from: g(0, 0), step: .down, pads: p), g(1, 0))
        // `.stay` (zero offset) never teleports, even while resting on a pad cell.
        XCTAssertEqual(resolveLanding(from: g(0, 1), step: .stay, pads: p), g(0, 1))
        XCTAssertEqual(resolveLanding(from: g(0, 5), step: .stay, pads: p), g(0, 5))
    }

    // MARK: - move() lands on the partner (D-070)

    /// A move onto a pad lands on the partner that **same turn**: one turn ticks, the run
    /// records the input direction (not the destination), and the player ends on the partner.
    func testMoveOntoPadLandsOnPartnerThatTurn() {
        let state = GameState(width: 7, height: 1, start: g(0, 0), exit: g(0, 6),
                              portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])])
        XCTAssertTrue(state.move(.right))             // (0,0)->(0,1) pad -> (0,5)
        XCTAssertEqual(state.turn, 1, "exactly one turn ticked")
        XCTAssertEqual(state.player, g(0, 5), "landed on the partner, not the pad")
        XCTAssertEqual(state.currentRun, [.right], "the recorded run stores the input direction")
        XCTAssertEqual(state.lastMoveOutcome, .stepped)
    }

    /// Arrival on the partner is **terminal** — it does not re-fire back — and a `.stay`
    /// (wait) on the partner pad keeps you there (no bounce).
    func testPartnerDoesNotRefireAndWaitOnPadHolds() {
        let state = GameState(width: 7, height: 1, start: g(0, 0),
                              portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])])
        XCTAssertTrue(state.move(.right))             // teleport to (0,5)
        XCTAssertEqual(state.player, g(0, 5))         // did NOT bounce back to (0,1)
        XCTAssertTrue(state.wait())                   // a wait on the pad
        XCTAssertEqual(state.player, g(0, 5), "a `.stay` on a pad does not teleport")
        XCTAssertEqual(state.turn, 2)
    }

    /// Stepping off a pad and back onto it teleports **again** — a pad is not consumed.
    func testSteppingOffAndBackOntoPadTeleportsAgain() {
        // Pads at (0,1) and (0,5); start in the middle so we can step onto either.
        let state = GameState(width: 7, height: 1, start: g(0, 3),
                              portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])])
        XCTAssertTrue(state.move(.left))              // (0,3)->(0,2)
        XCTAssertTrue(state.move(.left))              // (0,2)->(0,1) pad -> (0,5)
        XCTAssertEqual(state.player, g(0, 5))
        XCTAssertTrue(state.move(.left))              // (0,5)->(0,4) (off the pad)
        XCTAssertEqual(state.player, g(0, 4))
        XCTAssertTrue(state.move(.right))             // (0,4)->(0,5) pad -> (0,1) (teleports again)
        XCTAssertEqual(state.player, g(0, 1))
        XCTAssertEqual(state.turn, 4)
    }

    // MARK: - Echoes teleport too (D-070)

    /// An echo that recorded a step onto a pad teleports on replay (pad-aware `position`),
    /// and so **holds a switch in the far region** (pad-aware `isCellHeld`/`isSwitchHeld`).
    func testEchoReplayingStepOntoPadTeleportsAndHoldsFarSwitch() {
        let state = GameState(
            width: 7, height: 1, start: g(0, 0),
            switches: [Switch(id: "sFar", cell: g(0, 5))],
            portals: [Portal(id: "p", cells: [g(0, 2), g(0, 5)])]
        )
        // Record an echo that walks onto the pad at (0,2) -> teleports to (0,5) = sFar.
        XCTAssertTrue(state.move(.right))                       // (0,1)
        XCTAssertTrue(state.move(.right))                       // (0,2) pad -> (0,5)
        XCTAssertEqual(state.player, g(0, 5))
        XCTAssertTrue(state.fold())
        let echo = try! XCTUnwrap(state.echoes.first)
        XCTAssertEqual(echo.moves, [.right, .right])

        // The echo's pad-aware position jumps at turn 2 (the recorded teleport).
        XCTAssertEqual(echo.position(start: state.start, turn: 1, pads: state.padMap), g(0, 1))
        XCTAssertEqual(echo.position(start: state.start, turn: 2, pads: state.padMap), g(0, 5))
        XCTAssertEqual(echo.position(start: state.start, turn: 9, pads: state.padMap), g(0, 5)) // exhausted, holds

        // Drive the shared turn forward (live player waits): at turn 2 the echo holds sFar.
        XCTAssertFalse(state.isSwitchHeld("sFar"), "turn 0: echo on start, not the far switch")
        XCTAssertTrue(state.wait())                             // turn 1
        XCTAssertFalse(state.isSwitchHeld("sFar"), "turn 1: echo at (0,1)")
        XCTAssertTrue(state.wait())                             // turn 2
        XCTAssertTrue(state.isSwitchHeld("sFar"), "turn 2: the echo teleported and now holds the far switch")
    }

    // MARK: - Danger is checked where you land (D-070)

    /// Collision is evaluated at the **landing** (the partner): a hazard resting on the
    /// partner cell when you teleport in kills you.
    func testCollisionEvaluatedAtTheLandingAgainstHazard() {
        let state = GameState(
            width: 7, height: 1, start: g(0, 0), exit: g(0, 6),
            hazards: [Hazard(id: "h", start: g(0, 5), path: [], loops: true)],   // stationary on the partner
            portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])]
        )
        XCTAssertTrue(state.move(.right))             // teleport to (0,5) where the hazard sits
        XCTAssertEqual(state.lastMoveOutcome, .died, "landing on the hazard at the partner is a death")
        XCTAssertEqual(state.player, state.start)     // restarted
        XCTAssertEqual(state.turn, 0)
        XCTAssertFalse(state.hasWon)
    }

    /// Collision at the landing against an **echo** resting on the partner cell: teleporting
    /// in on the turn the echo is there is a death.
    func testCollisionAtTheLandingAgainstEcho() {
        let state = GameState(
            width: 7, height: 1, start: g(0, 0),
            portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])]
        )
        // Bank an echo that ends (and rests) on the partner cell (0,5).
        XCTAssertTrue(state.move(.right))             // teleport to (0,5)
        XCTAssertTrue(state.fold())                   // echo holds (0,5) from turn 1 on
        // Now the live player teleports into (0,5) on a turn the echo is resting there.
        XCTAssertTrue(state.move(.right))             // (0,0)->(0,1) pad -> (0,5), echo there
        XCTAssertEqual(state.lastMoveOutcome, .died)
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - A blocked resolved landing is a no-op (D-070)

    /// A move whose **resolved landing** is a closed door is a no-op — you cannot teleport
    /// into a blocked cell, exactly like walking into a wall (turn doesn't advance, nothing
    /// is recorded).
    func testTeleportIntoClosedDoorIsANoOp() {
        let state = GameState(
            width: 7, height: 1, start: g(0, 0),
            switches: [Switch(id: "sNever", cell: g(0, 3))],          // held by no one
            doors: [Door(id: "d", cells: [g(0, 5)], heldBy: ["sNever"])], // closed, covers the partner
            portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])]
        )
        XCTAssertFalse(state.move(.right), "the partner (0,5) is a closed door, so the teleport is refused")
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
        XCTAssertTrue(state.currentRun.isEmpty)
    }

    /// A move whose resolved landing is a **wall** is likewise a no-op (the plain non-pad
    /// guard path, unchanged by teleport).
    func testMoveIntoWallStillNoOp() {
        let state = GameState(width: 3, height: 1, start: g(0, 0), walls: [g(0, 1)])
        XCTAssertFalse(state.move(.right))
        XCTAssertEqual(state.player, state.start)
        XCTAssertEqual(state.turn, 0)
    }

    // MARK: - stepBack over a teleport (D-071)

    /// `stepBack()` rolls a teleporting move back to the correct **pre-teleport** cell — it
    /// replays the shortened run through the same pad-aware walk, not an offset subtraction.
    func testStepBackUndoesATeleportingMove() {
        let state = GameState(width: 7, height: 1, start: g(0, 0),
                              portals: [Portal(id: "p", cells: [g(0, 1), g(0, 5)])])
        XCTAssertTrue(state.move(.right))             // teleport to (0,5), run [.right]
        XCTAssertTrue(state.move(.right))             // (0,5)->(0,6), run [.right,.right]
        XCTAssertEqual(state.player, g(0, 6))

        XCTAssertTrue(state.stepBack())               // undo the second move
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.player, g(0, 5), "step-back returns to the teleported cell, not the pad")

        XCTAssertTrue(state.stepBack())               // undo the teleporting move
        XCTAssertEqual(state.turn, 0)
        XCTAssertEqual(state.player, state.start)
        XCTAssertTrue(state.currentRun.isEmpty)
    }

    // MARK: - Empty-pads regression (D-071)

    /// With **no portals**, `move`/`stepBack` behave byte-for-byte as before — the engine is
    /// pad-aware but indistinguishable from the v1 engine when `padMap` is empty.
    func testEmptyPadsRegressionMoveAndStepBackUnchanged() {
        let state = GameState(width: 5, height: 1, start: g(0, 0), exit: g(0, 4))
        XCTAssertTrue(state.padMap.isEmpty)
        XCTAssertTrue(state.move(.right)); XCTAssertEqual(state.player, g(0, 1))
        XCTAssertTrue(state.move(.right)); XCTAssertEqual(state.player, g(0, 2))
        XCTAssertTrue(state.stepBack());  XCTAssertEqual(state.player, g(0, 1))
        XCTAssertEqual(state.turn, 1)
        XCTAssertTrue(state.move(.right)); XCTAssertTrue(state.move(.right)); XCTAssertTrue(state.move(.right))
        XCTAssertEqual(state.player, g(0, 4))
        XCTAssertTrue(state.hasWon, "a no-portal board still wins the ordinary way")
    }

    // MARK: - Level format v2 decode + padMap (D-072)

    /// A level JSON **with** a `portals` array decodes it; `GameState` builds a bidirectional
    /// `padMap`. A level **without** `portals` decodes with an empty array (every v1 room).
    func testLevelDecodesWithAndWithoutPortalsAndPadMapIsBidirectional() throws {
        let withPortals = """
        { "id": "t", "name": "T", "width": 7, "height": 1,
          "start": { "row": 0, "column": 0 }, "exit": { "row": 0, "column": 6 },
          "echoBudget": 1,
          "portals": [ { "id": "p1", "cells": [ { "row": 0, "column": 1 }, { "row": 0, "column": 5 } ] } ] }
        """
        let level = try JSONDecoder().decode(Level.self, from: Data(withPortals.utf8))
        XCTAssertEqual(level.portals.count, 1)
        XCTAssertEqual(level.portals.first?.id, "p1")
        XCTAssertEqual(level.portals.first?.cells, [g(0, 1), g(0, 5)])

        let state = GameState(level: level)
        XCTAssertEqual(state.padMap[g(0, 1)], g(0, 5))
        XCTAssertEqual(state.padMap[g(0, 5)], g(0, 1))
        XCTAssertEqual(state.padMap.count, 2)

        // No `portals` key ⇒ empty, exactly as every v1 room JSON decodes.
        let noPortals = """
        { "id": "t2", "name": "T2", "width": 3, "height": 1,
          "start": { "row": 0, "column": 0 }, "exit": { "row": 0, "column": 2 }, "echoBudget": 0 }
        """
        let v1 = try JSONDecoder().decode(Level.self, from: Data(noPortals.utf8))
        XCTAssertTrue(v1.portals.isEmpty)
        XCTAssertTrue(GameState(level: v1).padMap.isEmpty)
    }

    // MARK: - The wait + teleport relay proof (the headline of D-070)

    /// One echo does **two jobs across two regions, joined by a portal**: it walks to switch
    /// A and **waits** there to hold door A open while present-you crosses it; then it
    /// relocates — walking to a pad and **teleporting** to the far region — to switch B,
    /// holding door B open for present-you's later crossing. The relay is genuinely required
    /// (door A is shut with no echo), and replaying the relay echo + the timed live run
    /// reaches the exit with `hasWon`. This is the wait (Phase 4.01) threaded through a
    /// portal (Phase 4.03) — the mechanic room 29 is built on.
    func testWaitPlusTeleportRelayOneEchoHoldsThenRelocatesAcrossAPortalToWin() {
        // A 7-wide × 5-tall board. Player corridor = row 2: S(2,0) → dA(2,2) → dB(2,4) →
        // exit(2,6). Switch A=(0,0) (top region), switch B=(4,6) (bottom region, reachable
        // only by the echo via the portal). Portal: padTop(0,3) ↔ padBottom(4,3).
        func makeState() -> GameState {
            GameState(
                width: 7, height: 5, start: g(2, 0), exit: g(2, 6), echoBudget: 1,
                switches: [Switch(id: "sA", cell: g(0, 0)),
                           Switch(id: "sB", cell: g(4, 6))],
                doors: [Door(id: "dA", cells: [g(2, 2)], heldBy: ["sA"]),
                        Door(id: "dB", cells: [g(2, 4)], heldBy: ["sB"])],
                portals: [Portal(id: "p", cells: [g(0, 3), g(4, 3)])]
            )
        }

        // Without any echo, door A is shut — an immediate cross is refused (relay needed).
        let bare = makeState()
        XCTAssertTrue(bare.move(.right))                   // (2,1)
        XCTAssertFalse(bare.move(.right), "door A must be shut with no echo holding switch A")
        XCTAssertEqual(bare.player, g(2, 1))

        // Record the relay echo: up to sA, hold (wait×2), walk the top row to the pad,
        // TELEPORT to the bottom region, walk to sB.
        let state = makeState()
        XCTAssertTrue(state.move(.up))      // (1,0)
        XCTAssertTrue(state.move(.up))      // (0,0) = sA
        XCTAssertTrue(state.wait())         // hold sA
        XCTAssertTrue(state.wait())         // hold sA
        XCTAssertTrue(state.move(.right))   // (0,1)
        XCTAssertTrue(state.move(.right))   // (0,2)
        XCTAssertTrue(state.move(.right))   // (0,3) = padTop -> teleport to (4,3)
        XCTAssertEqual(state.player, g(4, 3), "the echo teleported across the portal")
        XCTAssertTrue(state.move(.right))   // (4,4)
        XCTAssertTrue(state.move(.right))   // (4,5)
        XCTAssertTrue(state.move(.right))   // (4,6) = sB
        XCTAssertEqual(state.player, g(4, 6))
        XCTAssertTrue(state.fold())
        XCTAssertEqual(state.echoes.count, 1)

        // The echo holds sA early (turns 2–4) and, after teleporting, sB late (turn 10 on).
        let echo = try! XCTUnwrap(state.echoes.first)
        XCTAssertEqual(echo.position(start: state.start, turn: 2, pads: state.padMap), g(0, 0))   // on sA
        XCTAssertEqual(echo.position(start: state.start, turn: 4, pads: state.padMap), g(0, 0))   // still on sA (waited)
        XCTAssertEqual(echo.position(start: state.start, turn: 7, pads: state.padMap), g(4, 3))   // teleported
        XCTAssertEqual(echo.position(start: state.start, turn: 10, pads: state.padMap), g(4, 6))  // relocated to sB
        XCTAssertEqual(echo.position(start: state.start, turn: 14, pads: state.padMap), g(4, 6))  // holds sB (exhausted)

        // The live run: wait so the echo settles on sA, cross door A early, walk to (2,3),
        // wait for the echo to teleport and reach sB, cross door B late, step onto the exit.
        XCTAssertTrue(state.wait())                                   // t1
        XCTAssertTrue(state.move(.right))                             // t2 -> (2,1)
        XCTAssertTrue(state.move(.right), "door A should be open (sA held at t2)") // t3 cross dA -> (2,2)
        XCTAssertEqual(state.player, g(2, 2))
        XCTAssertTrue(state.move(.right))                             // t4 -> (2,3)
        XCTAssertEqual(state.player, g(2, 3))
        for _ in 0..<6 { XCTAssertTrue(state.wait()) }                // t5..t10 — wait out the relocation
        XCTAssertTrue(state.move(.right), "door B should be open (sB held at t10)") // t11 cross dB -> (2,4)
        XCTAssertEqual(state.player, g(2, 4))
        XCTAssertTrue(state.move(.right))                             // t12 -> (2,5)
        XCTAssertTrue(state.move(.right))                             // t13 -> exit (2,6)

        XCTAssertTrue(state.hasWon, "the relay (hold A, wait, teleport to B) should win")
        XCTAssertEqual(state.player, g(2, 6))
        XCTAssertEqual(state.echoes.count, 1)   // one self did both jobs across two regions (budget 1)
    }
}
