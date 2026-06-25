# Part 1 · Phase 07 · Code — Reset run & step back — Completion Report
**Date:** 2026-06-26 · **Outcome (one line):** The two everyday comfort controls now exist — undo one move (**step back**), and restart the current attempt without losing banked echoes (**reset run**) — both as pure model operations, surfaced in the throwaway debug bar and unit-tested.

## 1. What shipped (plain language)
You can now take back a single move, or scrap the whole current attempt and start it over, without throwing away the grey echoes you've already folded. "Step back" walks you back one tile at a time and rewinds the entire board — every echo, hazard, switch, and door — to exactly how it looked a turn ago. "Reset run" puts you back at the start with your echoes intact (unlike the debug "Clear", which wipes everything). Fiddling with a tricky room is no longer punishing.

## 2. Definition of Done
- ✅ **`GameState.stepBack()` exists** — pops the last `Direction` of `currentRun`, decrements `turn` by 1, restores `player` by replaying `currentRun` from `start`; **no** collision/win evaluation, **never** alters `echoes`. Evidence: [`ECHO/Models/GameState.swift`](../../ECHO/Models/GameState.swift) `stepBack()`; harness `testStepBackUndoesOneMoveToPriorTurn` passes (player returns to its turn-2 tile after one undo).
- ✅ **No-op at turn 0 + no un-fold** — `turn`, `currentRun`, `player`, `echoes` all unchanged after a fold at turn 0; no banked echo removed. Evidence: `testStepBackAtTurnZeroIsNoOpAndNeverUnfolds` (asserts `stepBack()` returns `false`, echo count stays 1, echo moves intact).
- ✅ **Repeated step-back to turn 0, echoes preserved** — K calls after K moves return `player`→`start`, `turn`→0, `currentRun` empty, echo count unchanged throughout. Evidence: `testRepeatedStepBackWalksRunToTurnZeroKeepingEchoes`.
- ✅ **Refused while `hasWon`** — no state change. Evidence: `testStepBackRefusedWhileWon` (won 3×3 room; `stepBack()` returns `false`, position/turn/run unchanged).
- ✅ **Reset run wired to `restartRun()`** — `player`→`start`, `turn`→0, `currentRun` cleared, `hasWon` cleared, echoes preserved (count unchanged); works won or not; distinct from `clearEchoes()`. Evidence: [`ECHO/App/ContentView.swift`](../../ECHO/App/ContentView.swift) `Button("Reset run") { state.restartRun() }`; harness `testResetRunPreservesEchoesAndClearsRunIncludingAfterWin` (2 echoes survive a mid-run reset; 1 echo survives a reset after a win, `hasWon` cleared).
- ✅ **Step-back then branch-move; invariant holds** — after `stepBack()`, a `move(_:)` records onto the shortened run, ticks `turn` from the rolled-back value, lands on the new branch; `turn == currentRun.count`. Evidence: `testStepBackThenBranchMoveRecordsOnShortenedRun` (`[.up,.up,.up]` → step back → branch `.right` → `[.up,.up,.right]`, turn 3, `currentRun.count == turn`).
- ✅ **Derived world rolls back with the turn** — with a switch+door, a hazard, and a folded echo, after one `stepBack()` the `isSwitchHeld`/`isDoorOpen` flags, the hazard's `position(at:)`, and the echo's replay position all equal their turn-1 values. Evidence: `testDerivedWorldRollsBackWithTheTurn` (turn 2 → door open, hazard (0,0), echo (4,2); step back → all revert to the captured turn-1 readings).
- ✅ **Debug bar exposes both, keeps the rest, Clear ≠ Reset run** — bar now reads `Fold / Step back / Reset run / Clear / Next` + readout + `Solved ✓`; *Step back* → `stepBack()` (disabled at turn 0), *Reset run* → `restartRun()` (keeps echoes), *Clear* → `clearEchoes()` (wipes echoes) are separate buttons. Evidence: [`ECHO/App/ContentView.swift`](../../ECHO/App/ContentView.swift) `debugBar`.
- ✅ **XCTest coverage added; all prior pass** — 7 new cases added; the full 1.03–1.07 suite (47 methods) runs green. Evidence: harness **334/334 checks pass** (see §below and §7). No prior test re-pathed.
- ✅ **Verified honestly** — pass count is from the **standalone harness against the real model sources**, not ⌘U (which is unavailable under Command Line Tools). The difference is stated explicitly here and in `current-state.md`. No claim of an Xcode build, ⌘U run, on-device run, or D-025 bundling confirmation.
- ✅ **Close-out** — decision log appended (**D-028…D-032**, renumbered — see §3); `current-state.md` overwritten for 1.07; `file-map.md` updated; this report filed; one commit on `main`. Outstanding Xcode/device/⌘U/D-025/toolchain-pin items carried forward, not marked done (§7).

**Verification commands run (Command Line Tools only; `swiftc` 6.4, no Xcode):**
- Harness — real model sources + counting XCTest shim + verbatim test bodies + runner: `ECHO harness — 334/334 checks passed / ALL PASS` (exit 0). Decodes the 3 proof rooms from disk through the real `Level` Decodable as well.
- Type-check, app-target regime (`-default-isolation MainActor`): model + `ECHOApp`/`ContentView`/`BoardView` → exit 0 (CLT substitution: a box-backed `@State` equivalent with `nonmutating set`, `#Preview` neutralized; production files keep the real `@State`/`#Preview`).
- Type-check, test-target regime (default isolation): full model → exit 0.

## 3. Decisions I made during this phase
- **Decision-log renumber D-027…D-031 → D-028…D-032 · YES (already logged).** The brief supplied the five new entries numbered D-027…D-031 and said to "verify D-026 is still the prior highest before appending." It was **not**: D-027 already exists (the echo-budget decision, shipped in 1.06 and referenced by `GameState.fold()` and the 1.06 report). Per the log's own "IDs are permanent, never reused" convention, I appended the five entries as **D-028…D-032** and renumbered their internal cross-references to match (D-029→D-030 "step-back never removes echoes"; D-030→D-029 "reset run"). Content is otherwise the brief's verbatim text. A `Note (numbering)` was added to D-028 recording this. All code comments and docs reference the new numbers.
- **`stepBack()` returns `@discardableResult Bool` · NO (idiomatic, no new entry).** The brief didn't specify a return type. I matched the established "did it happen" convention of `move(_:)` and `fold()` (Bool, `@discardableResult`; cf. D-015), so the debug bar / tests can tell a real undo from a refused no-op. The button discards the result; tests assert on it.
- **Wired the control directly to `restartRun()` (no `resetRun()` alias) · NO.** D-029 permits either. The existing `restartRun()` doc already said "wire that control here, don't duplicate this," so I called it directly and only refreshed its doc comment to say the reset-run control is now attached. One canonical restart path, nothing to keep in sync.
- **Disabled "Step back" at `turn == 0` in the debug bar · NO.** The brief lists this as optional. It's a one-line `.disabled(state.turn == 0)`; `stepBack()` is already a safe no-op, so this is cosmetic legibility only, not behavior.
- **Replay-from-`start` (not offset-subtraction) for the rollback · NO (this is the spec'd approach, ratified as D-028).** Keeps `currentRun` the single source of truth so `player` can't drift.

## 4. Deviations from the brief / spec
- **Decision IDs shifted by one** (D-027…D-031 → D-028…D-032) because D-027 was already taken — see §3. This is the only deviation from the brief's literal text, forced by the never-reuse-IDs rule; the decisions' substance is unchanged.
- **Single commit, no separate hash-recording docs commit.** The brief says "one commit on `main`," so — unlike prior phases, which added a small follow-up `docs: record … commit hash` commit — this phase is a single commit. The hash is therefore read from `git log` rather than embedded inside the committed report (embedding it would require a second commit/amend).
- Everything else built exactly as specified. No redo/step-forward (D-032), no un-fold control (D-030), no styling/animation, no change to `move`'s synchronous death restart, no change to `Echo.swift`/`Hazard.swift`.

## 5. Changed files / deliverables
- **Code (edited):**
  - [`ECHO/Models/GameState.swift`](../../ECHO/Models/GameState.swift) — added `stepBack()`; refreshed `restartRun()` doc and the file header for 1.07.
  - [`ECHO/App/ContentView.swift`](../../ECHO/App/ContentView.swift) — debug bar gained `Step back` and `Reset run` buttons (and the doc/comment for the strip).
  - [`ECHOTests/ECHOTests.swift`](../../ECHOTests/ECHOTests.swift) — 7 new XCTest cases (Phase 1.07 sections).
  - No new/deleted source files; `Echo.swift`, `Hazard.swift`, `Level.swift`, `GridCoordinate.swift`, `Direction.swift`, `BoardView.swift`, the level JSONs, and `.pbxproj` are untouched.
- **Docs:** `ECHO-Decisions.md` (D-028…D-032), `_project-state/current-state.md` (overwritten), `_project-state/file-map.md` (3 file descriptions + this report listed), this report.
- **Commit / branch:** one commit on `main`; hash visible via `git log` (HEAD of this phase's work).
- **Design / Ops:** none. No design handover this phase (pre-design grey boxes). No secrets created or referenced.
- **Harness (not committed):** the verification harness lives under `/tmp/echo-harness/` (throwaway, outside the repo) — a counting XCTest shim + the verbatim test bodies + a runner, compiled against the real model sources.

## 6. State updates done (code phases)
- [x] `current-state.md` overwritten to reflect what actually shipped (reset-run/step-back moved into "Works now"; per-file detail updated for `GameState.swift`, `ContentView.swift`, `ECHOTests.swift`; verification + carried-forward items refreshed).
- [x] `file-map.md` updated (descriptions for the 3 changed files; this report added). No add/rename/delete of files.
- [x] `00_stack-and-config.md` — **not appended**: no dependency/tool/version changed this phase (still zero external packages, same Swift 6.4 toolchain). The 1.02-carried toolchain version pin is still owed (carried forward, §7) — that's a pre-existing gap, not a 1.07 change.

## 7. Risks, follow-ups, what the next phase needs to know
- **Carried forward, still owed (none done this phase):** the iOS Simulator build, the on-device **⌘R** run, the **⌘U** XCTest run, the **D-025 `Levels/` bundling confirmation** on first ⌘R, and the **1.02-carried toolchain pin** (exact Xcode 27 / iOS SDK build numbers in `00_stack-and-config.md`). This environment has only Command Line Tools — `swiftc` works, but `xcodebuild`/`simctl` and the SwiftUI/XCTest macro plugins are absent.
- **Harness ≠ ⌘U.** The 334/334 figure is the real test bodies executed against the real model via a shim, plus a proof-room decode — strong evidence the deterministic logic is correct, but Lazar should still run ⌘U once in Xcode to confirm under the real XCTest runner and the app/test target isolation.
- **Why this phase was low-risk to the rest of the engine:** `stepBack()` and the reset-run op change none of `move`/`fold`/collision/win semantics; they're plain `turn`/`player`/`currentRun` mutations on the already-observed model, so the board reacts through Observation with no `BoardView` change. That's why no prior test needed re-pathing.
- **For 1.08 (the ~10 teaching rooms):** step-back/reset are now available as authoring/play affordances; rooms can assume the player can cheaply undo and restart. The debug bar is still the throwaway grey-box surface — the real in-room controls and any backward-motion feel are Part 2/Part 3.

## 8. What's now possible that wasn't before
The core loop is finally comfortable to sit and play — you can experiment, undo a misstep, or restart an attempt without losing the echoes you've already composed.
</content>
