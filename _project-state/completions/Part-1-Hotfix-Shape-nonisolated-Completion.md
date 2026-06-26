# Part 1 · Hotfix (Code) · `nonisolated` on custom `Shape` conformances — Completion Report
**Date:** 2026-06-26 · **Outcome (one line):** the first real Xcode build's compile error (`Diamond: Shape` crossing into main-actor-isolated code) is fixed with a local `nonisolated` annotation; D-013 is untouched.

## 1. What shipped (plain language)
The first time the project was opened in a full Xcode build, it refused to compile: one hand-drawn shape used for the hazard marker clashed with the project's "everything is main-actor by default" setting. The fix is a one-word annotation on that shape so it stays off the main actor, exactly as SwiftUI expects — no game logic changed, no project-wide setting changed. The specific error was reproduced and confirmed gone using the command-line Swift compiler that this machine does have. The full Xcode build, the test run, and the on-phone run still need to happen on Lazar's Mac, because this environment has only Command Line Tools (no Xcode, no iOS SDK, no Simulator).

## 2. Definition of Done
- ✅ **Every custom `Shape` conformance marked `nonisolated`** — evidence: an exhaustive search (`grep -rnE ":\s*(Shape|InsettableShape|Animatable|VectorArithmetic)\b"`) finds exactly one custom conformance, `Diamond` in [BoardView.swift:266](ECHO/Views/BoardView.swift:266), now `private nonisolated struct Diamond: Shape`. The model value types (`Echo`, `Hazard`, `Level`, `Switch`, `Door`, `GridCoordinate`, `Direction`) were already `nonisolated`; no other value type is flagged by the same rule. Built-in shapes (`Rectangle`, `Circle`, …) need no change.
- ✅ **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` unchanged (D-013 intact)** — evidence: `project.pbxproj` still carries the setting; the fix is local only.
- ⚠️ **App target builds clean in Xcode (zero concurrency errors, no new warnings)** — done as far as this toolchain allows: this Mac has only Command Line Tools (`xcodebuild`/iOS SDK/Simulator absent — `xcode-select -p` → `/Library/Developer/CommandLineTools`, `xcodebuild -version` errors). I instead **reproduced the exact error and confirmed the fix** against the same compiler (Swift 6.4) with the same isolation flag: `swiftc -typecheck -swift-version 6 -default-isolation MainActor -sdk <SDK> <file>` — a bare `struct Diamond: Shape` emits the identical `#ConformanceIsolation` error from the brief (exit 1), and `nonisolated struct Diamond: Shape` type-checks clean (exit 0). The full Xcode build is still owed on Lazar's machine.
- ⚠️ **XCTest suite runs and passes (report actual counts)** — **could not be run here.** XCTest is not available under Command Line Tools (no `xcodebuild test`, no `simctl`). Phase 1.08's logic was already verified by a standalone `swiftc` replay harness (130/130 checks) and the test file type-checks clean, but the real `⌘U` run (and its pass counts for `ECHOTests` and `RoomSolvabilityTests`) is **still owed on Lazar's Mac.** Reporting this honestly rather than inferring a pass.
- ⚠️ **Ten rooms confirmed to load and render distinctly on a real run (D-025)** — **static half confirmed, runtime half owed.** The `Levels` synchronized root group is present in `project.pbxproj` and attached to the app target's `fileSystemSynchronizedGroups`; all ten `Levels/room-*.json` decode and are distinctly populated (room-02: 16 walls; room-06: a hazard with no walls; room-09: the D-039 5×7 grid; room-10: the busy 8-wide board with hazard + 2 switches + 2 doors). So the loader's inputs are real and distinct. Whether the bundle actually contains them on-device (vs. the bare-board fallback) can only be confirmed on a real ⌘R.
- ✅ **Completion report states what each custom shape renders** — see §7: `Diamond` is the **hazard placeholder** — a rotated-square (diamond) outline, a deliberately distinct silhouette from the rounded-square player/echo. It is the only custom shape; all other board elements use built-in shapes.
- ✅ **`ECHO-Decisions.md` has the new entry (D-040)** — evidence: appended with rationale and the rejected alternative (disabling default-MainActor).
- ✅ **`current-state.md` reflects the fix, build/test results, rooms-load outcome, and updated "still owed" list** — evidence: header, new lead summary bullet, `BoardView` detail line, and verification section all updated.
- ✅ **A completion report is filed in `_project-state/completions/`** — this file.

## 3. Decisions I made during this phase
- **Annotated the whole `Diamond` type `nonisolated`, not just `path(in:)`.** Why: it also covers `animatableData`/`sizeThatFits` if ever added, and a pure-geometry shape holds no main-actor state. Alternative rejected: per-method `nonisolated func path(in:)` (narrower, needs re-adding for each future requirement). Needs a Decisions entry: **YES — logged as D-040.**
- **Reproduced the error with the CLI toolchain rather than claiming "builds clean."** Why: no Xcode here, and a fabricated build/test result is exactly the failure mode the reports exist to prevent. The reproduction uses the same compiler, protocol, and isolation flag, so it is high-fidelity for *this specific error class*, but it is not a substitute for the full app build. Needs a Decisions entry: NO (captured in D-040's verification note and here).

## 4. Deviations from the brief / spec
- **Tasks 4–6 (full Xcode build, XCTest run, on-device rooms-load render) were not executed** — not a scope choice, an environment limit: this Mac has only Command Line Tools (recorded in agent memory and consistent with D-025's earlier note). I performed the closest verifiable equivalents (error reproduction + fix confirmation; static bundling + JSON-distinctness check) and flagged the remainder as owed on Lazar's Mac. No checkmark was written from inference.

## 5. Changed files / deliverables
- **Code:** edited [ECHO/Views/BoardView.swift](ECHO/Views/BoardView.swift) — `private struct Diamond: Shape` → `private nonisolated struct Diamond: Shape` (one line). No files added/renamed/deleted.
- **Docs:** appended **D-040** to [ECHO-Decisions.md](ECHO-Decisions.md); updated [_project-state/current-state.md](_project-state/current-state.md); filed this report.
- **Branch / commit:** on `phase-1.08-teaching-rooms`; commit hash to be recorded after commit (not yet committed at time of writing — awaiting go-ahead).
- **Ops / manual:** none. No secrets.

## 6. State updates done (code phases)
- [x] `current-state.md` overwritten to reflect what actually shipped (hotfix lead bullet, `BoardView` detail, verification section, the reproduced-error result).
- [x] `file-map.md` — no add/rename/delete this hotfix; the existing `BoardView`/`Diamond` entry remains accurate (the `nonisolated` annotation doesn't change the file's role), so no edit was required.
- [x] `00_stack-and-config.md` — no dependency/tool/version changed; no append required.

## 7. Risks, follow-ups, what the next phase needs to know
- **Still owed on Lazar's Mac (full Xcode):** the iOS Simulator/device build, the `⌘U` XCTest run (report actual pass counts for `ECHOTests` + `RoomSolvabilityTests`), the on-device `⌘R`, and the **runtime** D-025 bundling confirmation (rooms render with walls/exit/hazard, not the bare-board fallback). These are the same carried items as 1.08 — the hotfix does not clear them, it unblocks the build that exercises them.
- **What `Diamond` renders:** the **hazard** marker — a hollow rotated-square (diamond) outline, chosen as a distinct silhouette from the rounded-square player/echo and the hollow-ring exit. It is a pre-design grey-box placeholder (real palette/accent are Part 2). It is the project's only custom `Shape`; everything else on the board uses built-in SwiftUI shapes.
- **Standing rule (D-040):** any future custom `Shape`/`Animatable`/`VectorArithmetic` value type added under the app target's default-MainActor isolation must be marked `nonisolated`, or the same conformance error returns. The earlier `swiftc -parse` checks will **not** catch it — only a full type-checking build does.
- **No behaviour change:** the fix is isolation metadata only; the diamond draws identically.

## 8. What's now possible that wasn't before
The project should compile in a real Xcode build, unblocking the first true `⌘U`/`⌘R` of Part 1 on Lazar's Mac.
