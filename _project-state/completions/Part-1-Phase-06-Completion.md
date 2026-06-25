# Part 1 · Phase 06 · Code — Completion Report
**Date:** 2026-06-25 · **Outcome (one line):** the board is now a real puzzle — walls, switches/doors, an exit + win check, and patrolling hazards, all loaded from small per-room JSON files, so a room can be loaded and beaten for the first time.

## 1. What shipped (plain language)
The empty grid became a playable room. Rooms are now described in tiny JSON files (board size, start, exit, echo budget, walls, switches, doors, hazards); the app loads one on launch and a debug **Next** button cycles three proof rooms. Walls block you, switches held by you or an echo open doors, a moving hazard kills you on contact (so you must time your crossing), and stepping onto the exit alive shows **Solved ✓**. Three small proof rooms each demonstrate one feature and are verified solvable.

## 2. Definition of Done
- ✅ **`Level` Codable model + locked JSON schema; coords `{row,column}`, origin top-left, 0-indexed** — `ECHO/Models/Level.swift` (`Level`/`Switch`/`Door`, `Decodable`); `GridCoordinate` gained `Codable`, `Direction` a `String` raw value + `Codable`. Evidence: decode test green in harness; type-checks clean.
- ✅ **≥3 proof rooms under `Levels/`, bundled into the app target, loadable at runtime; one each walls / switch+door / hazard** — `Levels/p1-06-a.json` (Wall Maze), `p1-06-b.json` (Held Door), `p1-06-c.json` (The Crossing). Bundled via a `Levels` synchronized root group on the app target (D-025). Evidence: harness loads each from disk and decodes + solves it. ⚠️ **Runtime bundling not build-verified here** (no Xcode) — see §7.
- ✅ **Loader decodes a level by id; `GameState` initializes from it (all fields); loading resets player→start, turn→0, run empty, echoes empty, win flag false** — `LevelLoader.load(_:in:)` + `GameState.init(level:)`. Evidence: `testGameStateLoadsFromLevelAndResets` (harness "level-load reset").
- ✅ **Walls block the player (no tick, no record); off-grid still a no-op** — `GameState.move` guards `isWall(target)`. Evidence: `testWallBlocksPlayerMovement`.
- ✅ **Switch held-state derived per turn from player + echoes; door open iff every `heldBy` switch held; closed door blocks, open door passable; rendering reflects current-turn state** — `isSwitchHeld`/`isDoorOpen`/`isClosedDoor`; `BoardView` reads them. Evidence: `testSwitchHeldAndDoorOpenDerivedFromOccupancy`, `testEchoHoldsSwitchToOpenDoorCanonicalSolve`.
- ✅ **Echoes and hazards replay verbatim, unaffected by walls/doors; proof rooms never make an echo/hazard traverse a wall or a door closed under it** — no re-validation in replay (D-020); rooms authored to satisfy this (verified by the harness solves). Evidence: harness room solves are collision/wall-clean.
- ✅ **Hazards advance one tile/turn; `loops:true` repeats, `loops:false` stands still when exhausted; kill via land-on OR swap; don't block movement; don't hold switches** — `Hazard.position(at:)`; collision in `playerCollides`. Evidence: `testHazardLoopsNonLoopAndStationary`, `testHazardLandOnKillsPlayer`, `testHazardCrossPathsSwapKillsPlayer`.
- ✅ **Collision evaluates both echoes and hazards; the swap branch fires against a hazard (covered by a test)** — `playerCollides` loops echoes then hazards (D-022). Evidence: `testHazardCrossPathsSwapKillsPlayer` (isolates the swap: land-on cannot fire there).
- ✅ **Reaching the exit alive sets the win flag; collision before win on the same step (exit+lethal = death); "Solved ✓" + "Next" in the debug bar; Next loads the next room; input locked after a win** — `move` checks collision then exit; `hasWon`; `ContentView` debug bar. Evidence: `testReachingExitAliveSetsWinAndLocksInput`, `testCollisionTakesPrecedenceOverWin`.
- ✅ **`echoBudget` carried in JSON and enforced — `fold()` refused at cap; debug bar shows echoes/budget** — `fold` budget guard (D-027); readout `echoes M/budget B`. Evidence: `testFoldRefusedAtEchoBudget` (incl. budget 0).
- ✅ **XCTest suite extended to cover all listed cases; existing 1.03/1.04/1.05 tests still pass** — `ECHOTests/ECHOTests.swift` (11 new methods). No prior test needed re-pathing (new room fields default to empty/uncapped, leaving the bare-`GameState()` tests untouched). Evidence: harness runs the full suite logic 172/172; test source type-checks against the model via the XCTest shim.
- ✅ **Model stays pure/view-independent and `@Observable`-driven; sources type-check clean under both isolation regimes; standalone harness all green** — see §below. Evidence: model app-regime + test-regime type-check exit 0; views+model app-regime exit 0; harness **172/172 PASS**.
- ✅ **No external packages (still zero); no secrets; single branch `main`; one commit** — confirmed; commit is this phase's single commit on `main`.
- ✅ **`current-state.md` overwritten; `file-map.md` updated; `00_stack-and-config.md` appended; decisions logged** — done (D-019…D-027).
- ✅ **Completion report filed, stating what was verified here vs owed in full Xcode** — this file (§7).
- ⚠️ **⌘U / Simulator build / on-device ⌘R / Xcode-SDK build pin** — not possible in this CLT-only environment; owed on Lazar's Mac (§7).

## 3. Decisions I made during this phase
All nine brief-listed decisions were logged as **D-019…D-027** (switch/door derivation + doors-block-not-kill; verbatim replay ignoring walls/doors; hazards loop-by-default/lethal/not-solid; collision over echoes+hazards with swap live; collision-before-win; v1 JSON format locked; Levels bundled from repo root; in-session win only; budget enforced at fold). Additional choices the brief did not spell out:
- **`exit` is optional on `GameState`; bare board uses `echoBudget = .max`.** So `GameState()` (previews, all pre-1.06 tests) stays a contentless, un-winnable, uncapped board and **no existing test needed changing**. Alternative (give the bare board a real exit/budget) would have broken the fold tests. Folded into D-026/D-027. **Needs entry: NO** (covered).
- **`GameState(level:)` is a fresh init per room (not a mutating `load`).** Board config is immutable per instance (`let`s), so loading = constructing; `ContentView` reassigns its `@State` to switch rooms. The brief allowed "load(_:) or equivalent init". **Needs entry: NO.**
- **Loader returns `Level?` and `ContentView` falls back to a bare board on failure.** So a missing/corrupt JSON or a failed bundling never crashes the app. **Needs entry: NO** (noted in D-024/D-025).
- **Bundling mechanism = a third synchronized root group (a blind `.pbxproj` edit).** This is the substantive risk of the phase — logged as **D-025** with the blind-edit caveat; see §7.
- **Room C hazard tuned so the *fastest* crossing is lethal.** First draft (a full-width sweep) left the natural crossing safe; I shortened the patrol (cols 0–4, period 8) so the natural arrival at the gap-approach cell dies and a 2-step retiming wins — a genuine timing puzzle. Verified by the harness (naive path dies, retimed path wins). **Needs entry: NO** (room authoring, not a rule change).

## 4. Deviations from the brief / spec
None of substance. The collision-before-win test uses a **hazard** sitting on the exit rather than an echo, because an echo whose recorded run ends on the exit would itself trigger a win while being recorded — the hazard version proves the same precedence rule cleanly. Everything in scope was implemented; everything out of scope (real reset/step-back, menus, persistence, Echo Run, audio/haptics, design, the full teaching set) was left untouched.

## 5. Changed files / deliverables
- **New code:** `ECHO/Models/Level.swift` (Level/Switch/Door + LevelLoader), `ECHO/Models/Hazard.swift`.
- **Edited code:** `ECHO/Models/GameState.swift` (room config, walls/switch/door derivations, hazard collision, win, budget), `ECHO/Models/GridCoordinate.swift` (+Codable), `ECHO/Models/Direction.swift` (+String raw/Codable), `ECHO/Views/BoardView.swift` (element rendering + `Diamond` shape), `ECHO/App/ContentView.swift` (room list, Next, win UI, budget readout), `ECHOTests/ECHOTests.swift` (1.06 suite).
- **New level data:** `Levels/p1-06-a.json`, `Levels/p1-06-b.json`, `Levels/p1-06-c.json`. **Deleted:** `Levels/.gitkeep`.
- **Project file:** `ECHO.xcodeproj/project.pbxproj` — added the `Levels` synchronized root group to the app target (D-025).
- **Docs:** `ECHO-Decisions.md` (D-019…D-027), `_project-state/current-state.md` (overwritten), `_project-state/file-map.md`, `_project-state/00_stack-and-config.md`, this report.
- **Design:** none (phase is pre-design grey boxes; no handover by design).
- **Ops / manual:** none. No secrets anywhere.
- **Commit / branch:** `main` — phase commit **`2d10fb0`** ("feat: room contents, level data & win … (Phase 1.06)"), plus this hash-recording docs follow-up (the repo's established per-phase pattern).

## 6. State updates done (code phases)
- [x] `current-state.md` overwritten to reflect what actually shipped
- [x] `file-map.md` updated for every add/rename/delete
- [x] `00_stack-and-config.md` appended (no dependency change; recorded the `.pbxproj` Levels edit, the regime facts, and verification)

## 7. Risks, follow-ups, what the next phase needs to know
- **Verify the Levels bundling on first ⌘R (D-025).** The `.pbxproj` edit that bundles `Levels/*.json` (a third synchronized root group on the app target) was made **blind** — the CLT has no `xcodebuild` to validate it. It mirrors the existing `ECHO`/`ECHOTests` synchronized-group entries exactly. On first run, confirm the rooms load (the board shows walls/exit/hazard). If bundling failed, the loader's bare-board fallback keeps the app from crashing while it's fixed. If it didn't bundle, the simplest fix in Xcode is to drag `Levels/` into the project navigator as a folder reference added to the ECHO target.
- **Run ⌘U once** to confirm the suite against the real XCTest host (verified here only by the equivalent harness, 172/172, + a shim type-check).
- **Still owed from 1.02:** pin the exact **Xcode 27 / iOS SDK build numbers** in `00_stack-and-config.md` (paste `xcodebuild -version`).
- **Death is still an immediate snap-back** (no fizz/freeze) — that's Phase 2.03; don't add a timer to the engine to fake it (kills determinism).
- **For Phase 1.07:** the real **reset run** should call `GameState.restartRun()` (which now also clears `hasWon`); **step back** needs its own move-history undo (fold's total rewind isn't a per-move inverse, per D-015). The debug bar's `Clear`/`Next` remain throwaway.
- **Authoring discipline (D-020):** any new room must keep echo/hazard paths off walls and off doors closed under them — replay is verbatim and won't re-validate.

## 8. What's now possible that wasn't before
For the first time you can load a hand-authored room and actually **beat it** — hold a door with an echo, time a hazard, reach the exit — which is the foundation the teaching levels (1.08) and all of Part 2's juice are built on.
