# Part 1 · Phase 08 · Code — Completion Report
**Date:** 2026-06-26 · **Outcome (one line):** ECHO now has ten handcrafted teaching rooms that ramp a new player from "tap to move" to juggling two echoes and a patrol, wired into the play sequence and each backed by a solvability test against the real engine.

> Filed against the Phase 1.08 brief. Plain, factual language. ⌘U / ⌘R results are reported honestly: this environment has only Command Line Tools (no Xcode), so those were **not** run here — the deterministic logic was instead verified against the **real** engine sources with a `swiftc` harness (the established Phase 1.07 substitute), and the new test file was type-checked under a CLT shim.

## 1. What shipped (plain language)
The game is now playable start to finish: ten rooms in `Levels/room-01.json … room-10.json` teach one idea at a time — move, walls, your first fold, "your echo is a solid lethal body," two echoes at once, a moving hazard, holding a door while timing a patrol, and two combination "capstone" rooms — and the debug **Next** button walks through them in order. Each room ships with an automated test that actually solves it through the real game engine, so a future change that quietly breaks a room is caught. Two of the tightest rooms had their timing corrected to match how the engine really opens doors (it checks the door the instant *before* you step, not as you land), and one of those (room 09) had to be regrown by one row because, as written, the player had no legal first move.

## 2. Definition of Done
- ✅ **Ten files `room-01.json` … `room-10.json` exist, decode cleanly, and match their specs** — evidence: `Levels/room-01.json`…`room-10.json`; the `swiftc` harness decoded all ten through the real `Level` Decodable and asserted start/exit/echoBudget/wall-count/switch→door/hazard-count for each (130/130 checks). *Note:* rooms are at repo-root **`Levels/`**, not `ECHO/Levels/` — that is where the proof rooms and the loader (`LevelLoader`, `Level.swift:121`) live; "bundle them the same way the proof rooms are" governs (see §3, §4).
- ⚠️ **All ten rooms are bundled into the app target and load at runtime (D-025 confirmed in a real Xcode build)** — done structurally (the `Levels` synchronized root group is in the app target's `fileSystemSynchronizedGroups`, `project.pbxproj`), and every file decodes via the real `Level` type, but **not build-confirmed here** (no Xcode). Owed: Lazar confirms on first ⌘R. Same standing caveat as D-025 since 1.06.
- ✅ **Debug Next advances `room-01 … room-10` in order; the three proof rooms are no longer in the sequence** — evidence: `ECHO/App/ContentView.swift:25` `roomIDs = ["room-01", … , "room-10"]`; the three `p1-06-*.json` were deleted (no test referenced them — `grep` confirmed).
- ✅ **No `.gitkeep` under `ECHO/` or `ECHOTests/` (D-012)** — evidence: `find ECHO ECHOTests -name .gitkeep` is empty (the only `.gitkeep` is `docs/design-handovers/.gitkeep`, outside both).
- ✅ **Each room has an XCTest replaying its reference solution (moves land, folds within budget, final reaches exit with `hasWon`, ≤ budget folds)** — evidence: `ECHOTests/RoomSolvabilityTests.swift` (`testRoom01…testRoom10` via `assertSolves`); logic verified 130/130 by the harness; file type-checks clean under the CLT shim (exit 0).
- ✅ **Rooms 04, 06, 07 each have the negative assertion (named naive run does not win)** — evidence: `testRoom04NaiveStraightRunHitsEchoAndDoesNotWin`, `testRoom06NaiveStraightRunHitsPatrolOnExit`, `testRoom07NaiveStraightRunAfterFoldHitsPatrol`; harness confirmed all three restart and do not win.
- ✅ **Each hazard's one-period trace matches the documented trace** — evidence: `testHazardTracesMatchDocumentedPaths` + harness trace checks for rooms 06/07/08/09/10 (period + wrap).
- ✅ **No echo path and no hazard path passes through a wall or a door closed under it (D-020)** — evidence: harness path-legality check (echo recorded paths + hazard one-period paths vs the wall set) passed for all ten; rooms are authored so echoes/hazards never need to traverse a closed door.
- ⚠️ **Full suite passes under ⌘U on the Mac** — **not run here** (no XCTest under CLT). Substitute evidence: the real engine replay harness is **130/130**, and `RoomSolvabilityTests.swift` type-checks clean. Owed: Lazar runs ⌘U once. An on-device ⌘R smoke of rooms 01/03/06 is likewise owed.
- ✅ **Decision entries D-033 … D-037 appended** — evidence: `ECHO-Decisions.md` (plus **D-038, D-039** for the two room tweaks the brief's "If a room needs a tweak" clause requires).
- ✅ **No new engine mechanics or rule changes** — evidence: `git diff` touches only `ContentView.swift` (room-id list + comments), the new `Levels/*.json`, the new test file, the deleted proof rooms, and docs. `GameState.swift` et al. are unchanged.
- ✅ **Any cell-level room tweak reported as a decision** — evidence: D-038 (room 05 stall), D-039 (room 09 layout). See §3/§4.

## 3. Decisions I made during this phase
1. **Rooms live in repo-root `Levels/`, not `ECHO/Levels/`.** The brief's paths say `ECHO/Levels/room-XX.json`, but the live repo bundles levels from repo-root `Levels/` (Plan §7, D-025; the loader and the proof rooms are there). "Bundle them the same way the proof rooms are" + "live code wins" → I placed them in `Levels/`. **Needs decision entry?** Covered by existing D-025; noted here.
2. **Decisions/log path.** The brief said `_project-state/ECHO-Decisions.md`; the real file is repo-root `ECHO-Decisions.md`. Appended there. No new entry needed.
3. **Pre-step door timing → Room 05 stall lengthened (D-038).** The engine checks `isClosedDoor(target)` *before* committing the move, so a switch-held door opens for the player only when the echo is on the switch the turn the player is **adjacent**. The brief's room-05 stall (`up,down`) leaves door A closed when the player reaches it (echo arrives a turn later, and parity forces the entry to an even turn); lengthened to `up,down,up,down`. Geometry unchanged. **Decision entry: YES (D-038).**
4. **Room 09 regrown 5×6 → 5×7 (D-039).** Under the pre-step rule the brief's room 09 is **unsolvable**: after folding both echoes the live player at `(0,2)` has no legal non-fatal first move (both flanks hold echoes at turn 1, the door below is closed at turn 0, up is off-grid). Added a one-cell stall pocket above a shifted-down start, preserving budget 2, the lesson, and the shape. **Decision entry: YES (D-039).**
5. **Deleted the three `p1-06-*.json` proof rooms.** The brief permits deletion if no test references them (none does). Removing them keeps `Levels/` to the ten real rooms. **Decision entry?** NO — within the brief's explicit allowance; noted here and in file-map.
6. **Test loads rooms via `LevelLoader` with a source-tree fallback.** The room JSON is bundled into the *app* target, not necessarily the *test* target; the helper tries `LevelLoader` (test bundle, then `.main`) and falls back to reading `Levels/<id>.json` resolved from `#filePath`, decoding via the same real `Level` Decodable. Keeps ⌘U green regardless of test-bundle resource copying, without a blind `.pbxproj` edit. **Decision entry?** NO — a test-robustness choice; noted here.
7. **Decision-log entries carry today's date** (`### D-0XX · 2026-06-26 · …`) to match the repo's existing format, though the brief listed them undated.

## 4. Deviations from the brief / spec
- **Room paths:** `Levels/` not `ECHO/Levels/` (§3.1). **Decisions log:** repo-root file (§3.2).
- **Room 05:** final-run stall lengthened by one up-down; **geometry identical to the brief** (D-038).
- **Room 09:** grid changed from the brief's **5×6 (start `(0,2)`, hazard start `(2,0)`)** to the shipped **5×7 (start `(1,2)`, exit `(6,2)`, hazard start `(3,0)`)** with a top stall pocket — because the original is unsolvable under the real engine (D-039). Budget (2), lesson, and shape preserved.
- **No real win/transition overlay, Level Select, or persistence** — out of scope by the brief (D-037).
- Nothing else in the brief was skipped. No engine rule was added or changed.

## 5. Changed files / deliverables
- **Code:**
  - Added: `Levels/room-01.json … room-10.json` (ten rooms).
  - Added: `ECHOTests/RoomSolvabilityTests.swift` (per-room solvability + negatives + hazard traces).
  - Edited: `ECHO/App/ContentView.swift` (room-id list → ten rooms; comment refreshes).
  - Deleted: `Levels/p1-06-a.json`, `p1-06-b.json`, `p1-06-c.json`.
  - Docs: `ECHO-Decisions.md` (+D-033…D-039); `_project-state/current-state.md` (overwritten), `_project-state/file-map.md` (updated), this report.
  - **Branch / commit:** see the PR opened for this phase (work on a feature branch, not `main`, per `CLAUDE.md`).
- **Design:** none (pre-design grey-box phase; no handover).
- **Ops / manual:** none. No secrets.

## 6. State updates done (code phases)
- [x] `current-state.md` overwritten to reflect Phase 1.08
- [x] `file-map.md` updated (ten rooms in / three proof rooms out; new test file; this report; ContentView line)
- [ ] `00_stack-and-config.md` — **no change** (no dependency/tool/version change this phase; the carried toolchain-pin debt is unchanged and still owed)

## 7. Risks, follow-ups, what the next phase needs to know
- **⌘U / ⌘R / bundling are owed to Lazar's Mac.** Run ⌘U (expect the new `RoomSolvabilityTests` green alongside `ECHOTests`); ⌘R rooms 01/03/06 to confirm the `Levels` JSON bundles and loads (D-025). If a room won't load, the bare-board fallback keeps the app running.
- **Two brief deviations to ratify (D-038, D-039).** The pre-step door rule is the real engine behaviour; future door/patrol rooms must be authored to it. If the orchestrator prefers room 09 stay 5×6, it needs a different mechanic — flagged rather than invented.
- **Reference tests are solvability, not uniqueness (D-034).** Editing a room means editing its test.
- **Verification method:** the `swiftc` harness (real model sources + on-disk room JSON) is the ⌘U-equivalent for deterministic logic — 130/130 (10 solutions, 3 negatives, 5 hazard traces, 7 doors-closed-unsolvable, 1 path-legality, plus structural asserts). It is a throwaway dev tool, not committed.
- **Independent adversarial audit (4 parallel agents):** to de-risk the spec-fidelity and the two room tweaks beyond the harness, a four-perspective audit ran — JSON/schema fidelity, an independent turn-by-turn re-simulation of the four hardest rooms, a DoD/wiring check, and an adversarial reviewer that built its **own** engine reimplementation + BFS solver. Result: **zero real findings.** It independently confirmed (a) every JSON matches the brief and the Codable schema; (b) all ten reference solutions win within budget; (c) **every room's minimum fold count equals its budget** — no fewer-fold/lesson-skipping bypass in any room; (d) all hazard traces match and no echo/hazard path lands on a wall (D-020); (e) the room-05 stall is genuinely load-bearing under the pre-step door rule (D-038); and (f) the original 5×6 room 09 is genuinely unsolvable (D-039). The only nits were the dangling `p1-06-b` id in a `Level.swift` doc comment (now changed to a neutral `"example"`) and the not-yet-committed git state (resolved by the phase commit).

## 8. What's now possible that wasn't before
There is an actual game to sit down and play — ten rooms that teach themselves — and a test net that keeps every one of them solvable as Part 2 starts adding feel.
