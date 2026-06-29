# Part 4 · Phases 01–02 · Code — The wait action + Rooms 21–25 — Completion Report
**Date:** 2026-06-29 · **Outcome (one line):** the game gains its fifth action — passing a turn in place (`wait`) — and the first five rooms (21–25) built on it, where one past self can hold a switch, wait, and move on to another.

> Combined report for the two bundled phases: **4.01** (the wait engine + control + feedback) and **4.02** (rooms 21–25 + their tests + the grown catalog). Part A (engine) was completed and its tests made green before Part B (rooms) was authored against the real, now-with-wait engine.

## 1. What shipped (plain language)
The campaign now has a **Wait** button: you can pass a turn standing still, which lets a folded echo hold a switch *for a while* and then walk on to a second job — something the game could never express before. Built on that, five new rooms (21–25) grow the campaign from 20 to 25: a clean "one self does two jobs" intro, a two-relay coordination room, a relay-plus-patrol room, an "be in two places at once then hand off" AND-door room, and an oversized hard capstone ("Clockwork") with a three-way AND-door and two patrols. Everything is verified against the real engine headlessly; the *feel* of the wait and how the rooms *play* are owed on the phone (this Mac still can't run the app).

## 2. Definition of Done

**Verifiable in this environment** (the `swiftc` + `XCTest`-shim harness; both build configs type-checked):
- ✅ `Direction.stay` exists (offset `(0,0)`); `init?(from:to:)` never returns it; `move(.stay)` is a no-op — evidence: `ECHO/Models/Direction.swift`; `WaitActionTests.testStayIsAZeroOffsetFifthDirectionTheTapRuleNeverProduces`, `testMoveStayIsANoOp` (green).
- ✅ `GameState.wait()` has the task-2 semantics, incl. **collision on wait**; refused while won; `stepBack`/`fold` handle `.stay`; an echo replays a recorded wait — evidence: `ECHO/Models/GameState.swift` `wait()`; `WaitActionTests.testWaitAdvancesTurnAppendsOneStayLeavesPlayerPut`, `testWaitRefusedWhileWon`, `testWaitIsFatalWhenAMoverLandsOnTheHeldTile`, `testStepBackPopsStayAndUnwindsAMixedRunToTurnZeroWithEchoesIntact`, `testFoldBanksARunWithStayAndTheEchoReplaysTheWait`.
- ✅ `WaitActionTests.swift` covers every Part-A case **including the dwell-then-relocate proof**, and passes — evidence: `testDwellThenRelocateOneEchoHoldsThenRelocatesAcrossTwoDoors` (one budget-1 echo holds switch A, waits, relocates to switch B; present-you crosses door A early and door B later and wins; plus a "door A shut without the echo" sub-assertion). 8 methods, all green.
- ✅ `Levels/room-21.json … room-25.json` exist in the locked format; each is **solvable within its budget** and **unsolvable with doors closed**; the named negative runs (rooms 23 & 25) fail as asserted; every new hazard's trace matches — evidence: the five JSON files; `RoomSolvabilityTests.testRoom21Relay`…`testRoom25Clockwork`, `testRoom23NaiveRunHitsPatrol`, `testRoom25NaiveRushHitsPatrol`, and the extended `testHazardTracesMatchDocumentedPaths`. Cross-checked first against a Python engine-mirror (validated by reproducing shipped rooms 08/12 + their hazard traces), then ground-truthed on the real engine.
- ✅ `Campaign.roomIDs` lists 25 rooms in order; `NavigationTests` updated to 25 and passing — evidence: `ECHO/Models/Campaign.swift`; `NavigationTests.testCampaignCatalogIsTwentyFiveRoomsInOrder` + the boundary/`contains` updates.
- ✅ The full test suite passes; counts before/after — evidence: headless run **155 methods / 2344 assertions, 0 failures** (was **140 / 1724** at the 3.04 tip → **+15 methods / +620 assertions**: WaitActionTests +8, RoomSolvabilityTests +7 [5 solvability + 2 negatives; hazard-trace + `assertSolves` extended in place], NavigationTests assertions adjusted). The existing suite passed **with no migration** (storing a wait as a `Direction` case kept every run a `[Direction]`).
- ✅ App type-checks clean (exit 0, 0 warnings) under the CLT macro substitution **both** with and without `-D DEBUG` — evidence: `typecheck.sh` → both regimes "EXIT 0 — warnings: 0".
- ✅ Rooms 01–20, `Hazard`, `EchoRunState`/`EchoRunView`, the nav shell, and the locked level format (D-024) are unchanged — evidence: `Hazard.swift`, `EchoRunState.swift`, `EchoRunView.swift`, every `Levels/room-0*/1*.json` byte-for-byte unchanged; the only nav touch is `Campaign.roomIDs` (20→25) + a one-line `LevelSelectView` comment ("Level Select naturally showing the new rooms").
- ✅ D-065–D-069 appended verbatim; `ECHO-Phase-Plan.md`, `current-state.md`, `file-map.md` updated; this report filed.

**Owed on device** (carried forward honestly — not verifiable here):
- ⚠️ The Wait button appears/taps; a wait reads as a distinct in-place beat and sounds/feels distinct from a step and a blocked move — first-pass pulse (a symmetric "breath" scale), a low quiet C3 tick, and `haptics.step()` are wired; **tuning is owed on the phone.**
- ⚠️ Rooms 21–25 *play* well (difficulty/feel) and the new mechanic is confirmed fun before the next band — owed on device.
- ⚠️ Folds into the standing device debt (⌘R/⌘U, `Levels/` bundling D-025, 60fps, the Xcode/iOS build-number pin) — not cleared here (D-062).

## 3. Decisions I made during this phase
- **Wait routed through `BoardView.commitWait` via a `waitRequests` counter, not a direct `state.wait()` in the button.** Why: a fatal wait must get the same deferred death **dissolve** as a fatal step (predict via `playerCollides`, play the §6d effect, restart in `finishDeath`), and a survived wait must get its pulse/tick/haptic — a direct `state.wait()` call would restart synchronously and bypass all of that. Rejected: button calls `state.wait()` directly. Consistent with D-068 (the Wait control through the input-lock-guarded path) — **NO** new Decisions entry; it is how D-068 is realised.
- **Room 24 budget = 2** (D-069 left it "2 or 3, your call from solvability"). The 2-switch AND-door + the hand-off relay is tight at 2 (the Python cheese-check shows `min_echoes == 2`). **NO** entry — within D-069's stated latitude.
- **Room 25's AND-door is a *three-switch* AND (`heldBy:[sA,sB,sC]`),** an escalation past the 2-switch ANDs of rooms 12/17/20, so budget 3 is genuinely tight (the 3-way AND needs all three echoes on their switches at once). Uses the existing locked format unchanged (`heldBy` is already an array). **NO** entry — an authoring choice within D-069; the format (D-024) is untouched.
- **First-pass wait feedback values** (the breath keyframe `1.0→1.06→1.0` over ~180 ms; the wait tick = a quiet C3 a full octave under the pentatonic step set; `haptics.step()` on a survived wait). First guesses to tune on device, in the spirit of D-043/D-044/D-064. **NO** entry.
- **Relay-hold lengths in rooms 23/24 trimmed** (from the first generous guess) so present-you idles only briefly while the past self relocates. Pure authoring tuning. **NO** entry.

## 4. Deviations from the brief / spec
None of substance. The two in-latitude authoring choices (room-24 budget 2; room-25's 3-switch AND) are logged in §3. No teleport/mirror/room-26+ work was pulled forward; no change to `Hazard`, `EchoRunState`, the level format, or the `move(_:)` four-direction behaviour.

## 5. Changed files / deliverables
- **Code — new:** `ECHOTests/WaitActionTests.swift`; `Levels/room-21.json … room-25.json`.
- **Code — edited:** `ECHO/Models/Direction.swift` (`.stay`), `ECHO/Models/GameState.swift` (`wait()` + `move(.stay)` guard), `ECHO/Models/Echo.swift` (doc-only — `.stay` replay), `ECHO/Models/Campaign.swift` (roomIDs 20→25), `ECHO/Views/RoomView.swift` (Wait button + `waitRequests`), `ECHO/Views/BoardView.swift` (`waitSignal`/`commitWait`/breath pulse/`Breath`), `ECHO/Audio/AudioManager.swift` (`.stay` wait tick), `ECHO/Views/LevelSelectView.swift` (one comment), `ECHOTests/RoomSolvabilityTests.swift` (wait-aware `assertSolves`/`replayRun` + 7 tests + hazard traces), `ECHOTests/NavigationTests.swift` (25-room catalog), `ECHOTests/EchoRunTests.swift` (one-line `allCases`→four-directions fix).
- **Docs:** `ECHO-Decisions.md` (D-065–D-069), `ECHO-Phase-Plan.md` (Part 4 table), `_project-state/current-state.md`, `_project-state/file-map.md`.
- **Branch / commit:** working tree on `main`; **commit pending the owner's go-ahead** (the harness rule is "commit only when asked"). No `.pbxproj` structural edit — new files ride the existing `ECHO`/`ECHOTests`/`Levels` synchronized groups; the unstaged `DEVELOPMENT_TEAM` line is left untouched.
- **Ops / manual:** none. No secrets. Still **zero external packages** (`00_stack-and-config.md` needs no append — no dependency/tool/version changed).

## 6. State updates done (code phases)
- [x] `current-state.md` overwritten to reflect what actually shipped
- [x] `file-map.md` updated for every add/rename/delete
- [x] `00_stack-and-config.md` — no append (nothing changed: same Swift 6.4 / Xcode 27 target, zero packages)

## 7. Risks, follow-ups, what the next phase needs to know
- **Device-feel debt grew (intended, D-062).** The wait's pulse/tick/haptic and rooms 21–25's difficulty are unseen/unheard/unfelt. The strong intent (D-065) is to play this band on the phone before building the teleport band.
- **`Hazard.path` can now technically decode `"stay"`** (a harmless, unused pausing-patrol capability — D-067). No room uses it; the schema (D-024) is otherwise unchanged.
- **Authoring tools:** a throwaway Python engine-mirror (with the wait, the door pre-step rule, collision, and a BFS live-solver + a min-echoes cheese check) made room iteration fast and is the recommended approach for the teleport/mirror bands; the real `swiftc` + XCTest-shim harness remains ground truth.
- **Next:** the owed on-device pass for this band, then **Phase 4.03** (the teleport engine, proven before rooms 26–30).

## 8. What's now possible that wasn't before
A past self can **hold a switch, wait, and move on** — so a single echo can do two jobs in sequence, and the campaign now teaches that idea across five new rooms.
