# Part 1 · Phase 03 · Code — Completion Report
**Date:** 2026-06-24 · **Outcome (one line):** The throwaway hello-grid is replaced by a real, state-driven 7×7 board with a black player square you move one tile at a time by tap or swipe, on a turn-based clock.

## 1. What shipped (plain language)
ECHO now has a real board instead of a static placeholder: a centered 7×7 grey grid with a solid black rounded-square player on the middle cell. You move it one square at a time — swipe in a direction, or tap a cell right next to the player — and it slides over. The player can't walk off the edge (an off-grid move just does nothing), and every real move ticks a hidden turn counter by one. The move rule lives in a small, pure model that's covered by unit tests, ready for fold/replay to build on next.

## 2. Definition of Done
- ✅ **Real, state-driven board renders (HelloGridView removed); grey-box grid + solid black rounded-square player on the correct cell** — evidence: `ECHO/Views/BoardView.swift` (lattice + `playerSquare`), `git rm` of `ECHO/Views/HelloGridView.swift`, player read from `state.player`. Views type-check clean under the app regime (exit 0, `@State`/`#Preview` macros excluded only because Command Line Tools lack the SwiftUI macro plugins).
- ✅ **Swipe (cardinal) moves one tile; tap on an orthogonally-adjacent cell steps into it** — evidence: `swipeGesture` (`DragGesture(minimumDistance: 20)` → `swipeDirection`) and per-cell `onTapGesture` → `tap` → `Direction(from:to:)`; both call `GameState.move(_:)`.
- ✅ **Orthogonal, one tile per input; player cannot leave the grid (off-grid is a no-op)** — evidence: `GameState.move` guards on `contains(target)`; harness checks "off top/bottom/left/right edge no-op" all PASS.
- ✅ **Turn counter increments by exactly one per committed move, unchanged on a no-op** — evidence: `move` does `turn += 1` only after the guard; harness checks "turn == 3 after 3 legal moves" and "turn unchanged on no-ops" PASS.
- ✅ **Dimensions and start cell are model parameters (default 7×7, center), not magic numbers** — evidence: `GameState.init(width: Int = 7, height: Int = 7, start: GridCoordinate? = nil)`, start defaults to `GridCoordinate(row: height/2, column: width/2)`; `BoardView` sizes from `state.width`/`state.height`.
- ✅ **Move logic in a testable model type in `Models/`, independent of the view** — evidence: `ECHO/Models/{GameState,GridCoordinate,Direction}.swift`; no SwiftUI import in the model; driven directly by the standalone harness and the tests.
- ⚠️ **Unit tests cover four directions, four edge no-ops, the turn-counter rule; all tests pass (⌘U)** — the tests are written (`ECHOTests/ECHOTests.swift`, `@MainActor`, 13 methods incl. the tap rule). They could **not** be run via ⌘U here because XCTest ships only with full Xcode (this env has Command Line Tools only). Instead the **identical scenarios were run via a standalone harness compiled from the real model sources → 18/18 PASS**, and the test file type-checks against the model under the test-target isolation regime. **Owed:** Lazar runs ⌘U once in Xcode.
- ✅ **Square visibly slides between cells; tuned motion NOT implemented** — evidence: `.animation(.easeInOut, value: state.player)` on `playerSquare` (plain default ease); no 120 ms curve / squash-and-stretch / snap-on-arrival.
- ⚠️ **Builds clean for the iOS 17+ Simulator; deployment target unchanged (iOS 17.0)** — deployment target confirmed unchanged (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`). Full Simulator build **not runnable here** (no `xcodebuild`/`simctl` under CLT); verified instead by clean `swiftc -typecheck` of all sources under the app target's `-default-isolation MainActor` regime (exit 0). **Owed:** Lazar's ⌘R on the Simulator.
- ✅ **No code in `Audio/` or `Haptics/`; no level JSON, fold, collision, win, or exit code** — evidence: only `Models/` and `Views/` touched; `Audio/`/`Haptics/` remain empty/untracked.
- ✅ **`current-state.md` overwritten, `file-map.md` updated, `00_stack-and-config.md` appended; committed and pushed to `main`** — evidence: see §5/§6 and the commit hash below.
- ✅ **Off-spec decisions flagged in this report and logged in `ECHO-Decisions.md`** — evidence: §3 below and **D-013**.

## 3. Decisions I made during this phase
- **Concurrency / actor-isolation model** — chose `@MainActor @Observable final class GameState`, `nonisolated`+`Sendable` `GridCoordinate`/`Direction`, and a `@MainActor` test class. *Why:* the app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this keeps the observed state on the main actor (its natural home) while keeping the pure values isolation-free and decode-ready for Phase 1.06; the test target doesn't set that default, so the test class is annotated instead of doing a blind `.pbxproj` edit. *Rejected:* unannotated value types (would silently become main-actor-isolated), a `struct` model (loses Observation), editing the test target's build settings. **Needs Decisions entry: YES → D-013.**
- **`move(_:)` returns `@discardableResult Bool`** — reports whether the step committed. *Why:* lets later phases pair feedback/echo-recording to a *real* step (a no-op should not record or tick); harmless now (`@discardableResult` avoids unused-result warnings). *Rejected:* `Void` return (would force callers to re-derive legality). Decisions entry: NO (small, additive).
- **Tap input via per-cell `onTapGesture` + `Direction(from:to:)`** rather than hit-testing a tap location against the grid. *Why:* each cell already exists as a view; mapping a tapped cell to a direction is pure and unit-testable, and naturally ignores diagonal/non-adjacent taps. *Rejected:* computing the cell from a tap coordinate (more math, less testable). Decisions entry: NO.
- **Swipe threshold `minimumDistance: 20`; tap/drag coexist** — a board-level drag with a 20 pt minimum so a tap (no movement) falls through to the cell's tap gesture. *Why:* clean separation of tap vs swipe without gesture-priority gymnastics. Decisions entry: NO (a placeholder constant; feel is tuned in 2.02).
- **Player visual constants** — fills 76% of its cell, corner radius 22% of its size, `.easeInOut` slide. *Why:* "most of the cell" per the spec, with a plainly-visible placeholder slide. These are explicitly placeholders for Phase 2.01/2.02. Decisions entry: NO.
- **Cell sizing uses `max(width, height)`** so cells stay square even if a later phase loads a non-square board; for the default 7×7 this is identical to the old hello-grid (`side / 7`). Decisions entry: NO.

## 4. Deviations from the brief / spec
- **⌘U and the Simulator/device build were not run in this environment** — not a scope change; a hard toolchain limit (Command Line Tools only: no `xcodebuild`/`simctl`/XCTest, and no SwiftUI macro plugins). Mitigated by type-checking every source under both isolation regimes and running all test scenarios through a standalone harness (18/18 PASS). Lazar still owes one ⌘R + ⌘U in full Xcode. Carries forward the pinning still owed from 1.02 (exact Xcode 27 / iOS SDK build numbers).

## 5. Changed files / deliverables
- **Code (new):** `ECHO/Models/GameState.swift`, `ECHO/Models/GridCoordinate.swift`, `ECHO/Models/Direction.swift`, `ECHO/Views/BoardView.swift`.
- **Code (edited):** `ECHO/App/ContentView.swift` (composes `BoardView` instead of `HelloGridView`), `ECHOTests/ECHOTests.swift` (real move-model coverage).
- **Code (deleted):** `ECHO/Views/HelloGridView.swift`.
- **Docs:** `ECHO-Decisions.md` (+D-013); `_project-state/current-state.md` (overwritten); `_project-state/file-map.md` (updated); `_project-state/00_stack-and-config.md` (Phase 1.03 entry); this report.
- **Project file:** no `.pbxproj` change needed — synchronized groups auto-pick-up the new `Models/`/`Views/` files.
- **Commit / branch:** `main` — phase commit `fc47d28` (this hash line corrected in the immediately-following doc commit, since a commit can't contain its own hash).
- **Ops / manual:** none. No secrets.

## 6. State updates done (code phases)
- [x] `current-state.md` overwritten to reflect what actually shipped
- [x] `file-map.md` updated for every add/rename/delete (added 3 `Models/` files + `BoardView.swift`, removed `HelloGridView.swift`, updated `ContentView`/tests/report lines)
- [x] `00_stack-and-config.md` appended (no version change; recorded the isolation regime + verification method)

## 7. Risks, follow-ups, what the next phase needs to know
- **Run ⌘U and ⌘R once in Xcode** to confirm against the real XCTest host and Simulator; pin the exact Xcode 27 / iOS SDK build numbers in `00_stack-and-config.md` while there.
- **Phase 1.04 (fold/record/replay)** builds directly on this: `GameState.turn` is the shared clock and `Direction` is the unit a recording is made of. `move(_:)`'s `Bool` return marks a *committed* step — the right hook for "record this move into the current fold." Echoes will need to step in lockstep with `turn`.
- **Where state lives:** `GameState` is currently owned by `BoardView` via `@State`. If 1.04 needs the run/echo controls outside the board, expect to lift ownership up to `ContentView` (or an environment object) — a small, clean refactor.
- **`nonisolated` value types** are intentional (D-013) so they decode off-main in Phase 1.06; don't "tidy" the annotations away.

## 8. What's now possible that wasn't before
The deterministic move-and-turn spine exists and is tested — so Phase 1.04 can record a run of these moves and replay it as a grey echo locked to the same turn counter.
