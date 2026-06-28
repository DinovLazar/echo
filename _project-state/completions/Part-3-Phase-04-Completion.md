# Part 3 · Phase 04 · Code — Final feel + performance (device-gated groundwork) — Completion Report
**Date:** 2026-06-28 · **Outcome (one line):** the two flagged transition glitches are fixed, a developer-only frame-rate overlay exists (gated out of release), a complete action→feedback audit and a feel-constant audit are written — **without** any claim that 60fps or the feel bar is met (that remains an owed on-device pass, D-062).

> One phase = one completion report = one git commit. This report is judged against the **Verifiable here** checklist only; the **Owed on device** list is reproduced as still owed and **no device-gated line is ticked**.

## 1. What shipped (plain language)
This is the half of the phase-plan's "3.04" that can actually be done on a Mac with no Xcode and no iPhone. Two transition glitches that were flagged in 3.03 are fixed: advancing to the next room no longer flashes the new board behind the fading "solved" scrim, and the win panel now waits a beat so you see the solved board first. A small developer-only frame-rate readout was added so the eventual on-device session can *measure* 60fps instead of guessing — it is compiled completely out of any shipping build. And two documents were written for that session: a row-by-row map of every action to the sound/buzz/animation it should produce (`docs/feel-audit.md`), and an audit confirming the motion/audio timing numbers in the code still match their locked specs. **Nothing here asserts the game feels right or runs at 60fps** — that needs the real device, which still hasn't happened.

## 2. Definition of Done

### Verifiable here (this phase)
- ✅ **Transition artifact 1 fixed (room→room scrim leak).** On "Next room," `RoomView.advance(to:)` raises an opaque `paperField` cover (`advancing`) via `withAnimation(Self.advanceCoverFade){ advancing = true } completion: { onAdvance(next) }`, so the room swaps only once the outgoing board is hidden — the incoming board can no longer render behind the outgoing scrim. Named/commented constant `advanceCoverFade` (= `Motion.guidanceIn`). Engine/`AppRoute` untouched. Evidence: `ECHO/Views/RoomView.swift` (`advance(to:)`, the `advancing` cover branch); type-checks clean.
- ✅ **Transition artifact 2 fixed (win pre-delay).** The reveal is now `.task(id: state.hasWon)` → mark solved → `Task.sleep(winRevealDelay = 0.45 s)` → fade the overlay in. Named constant `winRevealDelay`, commented "tune on device." Evidence: `ECHO/Views/RoomView.swift`.
- ✅ **Performance overlay exists**, own file `ECHO/Views/PerformanceOverlay.swift`, **`#if DEBUG`** gated, **no external packages**, `@MainActor`/`nonisolated` regime, mountable on **both** `RoomView` and `EchoRunView` via `.debugPerformanceOverlay()`, showing **FPS + instantaneous + rolling-average + worst frame-time (ms) + dropped-frame count**. **Absent from any release path**: `debugPerformanceOverlay()` resolves to `self` (no-op) when `DEBUG` is undefined (verified by the release-path type-check). Not wired into Settings/HUD; neutral (non-`Theme`) chrome; `allowsHitTesting(false)`. Evidence: the file; both type-checks (below).
- ✅ **Pure math unit-tested headlessly.** `ECHO/Diagnostics/FrameStats.swift` (`FrameWindow`/`FrameStats`, `nonisolated`/`Sendable`) is covered by `ECHOTests/FrameStatsTests.swift` (rolling average, worst-in-window, dropped-count + tolerance, capacity eviction/clamp, window reset, bad-sample rejection, ms/count composition). Evidence: suite run below.
- ✅ **`docs/feel-audit.md` exists** and maps every action in Task 3 (both modes) to visual/audio/haptic, each marked **WIRED vs — none**, cross-referenced to handover §/decision, with a top **"Gaps found"** section (G1–G7) and an OWED-on-device list. Evidence: the file.
- ✅ **Feel-constant audit done** — table in §4 below; **no drift** (every value matches spec); nothing re-tuned. Two defined-but-unwired tokens (`Motion.stepSnap`, `Motion.denyShake`) flagged, not changed.
- ✅ **Engine + data byte-for-byte unchanged.** `git diff HEAD` touches only `ECHO/Views/RoomView.swift`, `ECHO/Views/EchoRunView.swift` (+ new files); `GameState`/`Echo`/`Hazard`/`Level`/`LevelLoader`/`GridCoordinate`/`Direction`/`EchoRunState` and every `Levels/*.json` are unchanged (verified per-file with `git diff --quiet`). `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` intact (2 occurrences in `.pbxproj`).
- ✅ **Suite green** via the harness: **140 methods / 1724 assertions, 0 failures** (3.03 tip 128 / 1685 → **+12 methods / +39 assertions**, all in `FrameStatsTests`; no other suite changed).
- ✅ **App type-checks clean** (exit 0, **0 warnings**) in the app regime with the CLT macro substitution, **both** without `-D DEBUG` (release path; overlay compiled out) **and** with `-D DEBUG` (overlay compiled). The iOS-only `CADisplayLink` body is behind `#if canImport(UIKit)` (device-checkable-only, like `AudioManager`/`HapticsManager`).
- ✅ **D-062 / D-063 / D-064 appended** at the true next-free ids (highest was D-061 → no shift); `current-state.md`, `file-map.md`, `00_stack-and-config.md` synced; this report filed.
- ✅ **Branch cut from the 3.03 tip** (`phase-3.04-final-feel` ← `phase-3.03-navigation`); `DEVELOPMENT_TEAM` left unstaged; no direct commit to `main`.

### Owed on device (NOT this phase — left unchecked, carried forward)
- [ ] App builds, installs, and launches on the iPhone at all (owed since 1.02; D-025 `Levels/` bundling confirmed).
- [ ] **60fps confirmed** on device using the new overlay, across busy campaign rooms and a long Echo Run.
- [ ] **No jank / dropped frames** during the step slide, fold peel, death fizz, navigation fades, and Echo Run stacked-shadow steps.
- [ ] **Every action's feel judged** against `docs/feel-audit.md` — the "OWED on device" column checked off (audio heard, haptics felt, motion seen, incl. the stacked-shadow audio chord).
- [ ] **Both transition fixes confirmed visually**, and their constants tuned to taste.
- [ ] **Xcode 27 / iOS SDK build numbers captured** into `00_stack-and-config.md` (owed since 1.02).

## 3. Decisions I made during this phase
- **Pure frame-math placed in a new `ECHO/Diagnostics/` folder, not `Models/`.** Why: it's a developer instrument, not part of the game model, but it must be SwiftUI-free to live in the headless test module — so it can't sit in `Views/` (SwiftUI) and shouldn't pollute `Models/` (game domain). A small `Diagnostics/` group (rides the synchronized root group, no `.pbxproj` edit) is the honest home. **Decisions entry? NO** — a file-location choice within the spirit of D-063; documented here and in `file-map.md`.
- **Overlay is always-visible-when-DEBUG, non-interactive, top-trailing, neutral pill.** The brief said "default to whatever is least intrusive." I read that as: visible without a tap (the device pass wants the numbers while playing) but `allowsHitTesting(false)` so it can never eat a board gesture, tucked in the corner clear of the HUD, and deliberately not `Theme`-styled so it stays out of the D-055 chrome discipline. **Decisions entry? NO.**
- **Dropped-frame = interval > budget × 1.5 (tolerance), budget read live from the display link.** A defined, tunable hitch metric (a spike, not the average). **Decisions entry? NO** (documented in code + audit).
- **No feel gap was "fixed."** G1–G7 in `docs/feel-audit.md` (blocked-move/refused-fold have no feedback; `denyShake` unwired; spawn has no cue; stall == step haptically; menu/retry silent; game-over no pre-delay) are all documented, none invented — each implies a feel/design decision unobservable here, and the scope forbids re-tuning/adding feel. **Decisions entry? NO** (this *is* the documented gap list; deciding them is the device pass).
- **Two adversarial-review nits applied (robustness only).** (a) `advance(to:)` guarded on `advancing` so a fast double-tap can't re-fire `onAdvance` (matches the control row's own guard pattern). (b) `FrameRateMonitor.start()` now `FrameWindow.reset()`s the window (+ `stats = .zero`) so a stop→start re-appear doesn't carry a stale worst/dropped spike. Both presentation/diagnostic-only, +1 test method. **Decisions entry? NO.**
- **Verified with a dual type-check (with and without `-D DEBUG`)** so both the release path (overlay absent) and the debug path (overlay compiled) are proven clean — `#if DEBUG` code is otherwise invisible to the established single type-check. **Decisions entry? NO** (a verification-method improvement; noted in `00_stack-and-config.md`).

*(D-062/D-063/D-064 were pre-authored in the brief and appended verbatim.)*

## 4. Feel-constant audit (Task 4 — spec vs code)
No value was re-tuned; this confirms the code still matches the locked specs. ✅ = matches.

| Constant | Spec value | In code | Action |
|---|---|---|---|
| Step slide | 120 ms ease-in-out (§6b) | `Motion.step = Curve.standard(0.120)`; `standard` = `(0.42,0,0.58,1)` | ✅ match |
| Step squash | 94 % along / 106 % across (§6b) | `BoardView` player keyframes `0.94`/`1.06` | ✅ match |
| Soft-snap settle | 40 ms `softSnap` (§6b) | realised as the player keyframe overshoot (`1.06` over the 40 ms tail); **`Motion.stepSnap = Curve.softSnap(0.040)` defined but unwired** | ✅ value present; token unused — **flagged, not re-tuned** |
| Fold hit-pause | ~50 ms (§6c) | `Span.foldHitPause = 0.050` | ✅ |
| Fold ripple | 220 ms easeOut (§6c) | `Span.foldRipple = 0.220` / `Motion.foldRipple = Curve.easeOut(0.220)` | ✅ |
| Fold peel | 180 ms easeOut (D-044) | `Span.foldPeel = 0.180` / `Motion.foldPeel` | ✅ |
| Fold peel colour | ink → `echo.base` @ 0.24 (D-044) | peel crossfades to `echoBase.opacity(echoFillOpacity)`; Light `0.24` | ✅ (Invert `0.22` by §4) |
| Fold peel size | 32 → 28 pt (D-044) | `BoardMetrics.playerSize 32` → `echoSize 28` | ✅ |
| Death glide | 120 ms (D-043) | `Span.step = 0.120` | ✅ |
| Death freeze | 66 ms (D-043) | `Span.deathFreeze = 0.066` | ✅ |
| Death fizz | 320 ms (D-043) | `Span.deathFizz = 0.320` | ✅ |
| Death vignette | ~200 ms (§6d) | `Span.deathVignette = 0.200` | ✅ |
| Nav fades | ~200 ms (D-059) | `Motion.guidanceIn = Curve.easeOut(0.200)` | ✅ |
| Guidance hint linger | 2200 ms (§6) | `Span.guidanceLingerHint = 2.2` | ✅ |
| Guidance feedback linger | 1600 ms (§6) | `Span.guidanceLingerFeedback = 1.6` | ✅ |
| Audio step tick | on the committed step / turn (D-045/46) | `playStep` at `futureTime(after: 0)` from commit | ✅ |
| Audio death | swells on the fizz, `step + freeze` later (D-045) | `playDeath` offset `Span.step + Span.deathFreeze` | ✅ |
| Audio solve | resolves on arrival, +1 step | `playSolve` offset `Span.step` | ✅ |
| Win pre-delay (NEW) | first guess, tune on device (D-064) | `RoomView.winRevealDelay = 0.45 s` | ➕ new, named/commented |
| Advance cover (NEW) | first guess, tune on device (D-064) | `RoomView.advanceCoverFade = Motion.guidanceIn` | ➕ new, named/commented |
| `Motion.denyShake` | 260 ms `decayShake` (§6a) | **defined, never wired** — blocked move / refused fold have no feedback | ⚠️ feel gap (G1/G2), **not drift**; not wired here |

## 5. Changed files / deliverables
- **New:** `ECHO/Diagnostics/FrameStats.swift` (pure `FrameWindow`/`FrameStats` + `reset()`), `ECHO/Views/PerformanceOverlay.swift` (`#if DEBUG` overlay + `CADisplayLink` monitor + `.debugPerformanceOverlay()`), `ECHOTests/FrameStatsTests.swift` (+12 methods), `docs/feel-audit.md`.
- **Edited (presentation-only):** `ECHO/Views/RoomView.swift` (D-064 win pre-delay + advance cover + re-entry guard; mounts the overlay), `ECHO/Views/EchoRunView.swift` (mounts the overlay), `ECHO-Decisions.md` (D-062/063/064).
- **Unstaged (repo rule):** `ECHO.xcodeproj/project.pbxproj` — only the local `DEVELOPMENT_TEAM = X74CK53A6Q` lines Xcode re-adds; left out of the commit.
- **Branch:** `phase-3.04-final-feel` (cut from `phase-3.03-navigation`). Commit hash: *(filled at commit).*
- **Design:** no handover this phase (the locked Part-2-Phase-01 handover governs the feel specs the audit checks against).

## 6. State updates done
- [x] `current-state.md` overwritten to reflect what actually shipped (3.04 snapshot).
- [x] `file-map.md` updated for every add (FrameStats, PerformanceOverlay, FrameStatsTests, feel-audit) + the RoomView/EchoRunView edits + the report line.
- [x] `00_stack-and-config.md` appended (3.04 entry: no dep/tool/version change; the dual type-check + the model-module file addition recorded). *(Also recorded that 3.03 never appended here.)*

## 7. Risks, follow-ups, what the next phase needs to know
- **This phase does NOT close the phase-plan's 3.04.** "feel is in / 60fps" (Plan §15) is device-observable and remains an **owed on-device pass** (D-062). The next session must: build/run on the iPhone (⌘R), read 60fps/jank off the new overlay across busy rooms + a long Echo Run, walk `docs/feel-audit.md` ticking the OWED column (audio/haptics/motion), confirm both transition fixes visually and tune `winRevealDelay` + `advanceCoverFade`, decide G1–G7, and finally capture the Xcode 27 / iOS SDK build numbers.
- **The overlay's CADisplayLink path is unexercised here** (no real frames under CLT) — only its pure math is tested. First on-device run should confirm the readout actually updates and the dropped-count budget tracks ProMotion (it reads `targetTimestamp − timestamp` live).
- **Branch debt:** `phase-3.03-navigation` and `phase-3.04-final-feel` are both unmerged; `main` is still at 3.02 / D-058.
- **Adversarial review outcome:** 15 findings → 6 real (5 positive DoD confirmations + 1 nit), 1 uncertain, 8 false-positive. **No blockers/majors.** The 2 actionable nits were fixed (advance re-entry guard; monitor window reset).

## 8. What's now possible that wasn't before
The owed on-device feel/performance session can now be run as a *measured, checklist-driven* pass — read 60fps off the overlay, tick the feedback audit row by row — instead of an eyeball, with the two transition glitches already gone.
