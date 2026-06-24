# AGENTS.md

Vendor-neutral guidance for any AI coding agent working in this repo (Codex, Cursor, Claude Code, etc.). This mirrors `CLAUDE.md`; if the two ever disagree, **`CLAUDE.md` is the source of truth**.

---

## Project

**ECHO** — a native iOS puzzle game built for its owner to play on his own iPhone. Offline, single-player, **no App Store** (installed by sideloading a free-signed build via **SideStore**), no monetization, no network.

A turn-based black-and-white grid. You move one square. You can **fold** a run — record your moves and replay them as a grey **echo** — and solve each room by stacking echoes that hold switches and block hazards. **Touching an echo restarts your current run** (existing echoes persist). Reach the exit to win.

## Hard constraints (don't quietly change)

- **Turn-based + deterministic:** the world advances only on a player step; all echoes step in lockstep on one shared turn counter; replays are exact, no randomness in the core.
- **Inputs are fixed:** move + fold, plus reset-run and step-back. Fix difficulty with interacting constraints, never new inputs.
- **Collision = same grid cell on the same turn.** No physics, no real-time loop.
- **Monochrome:** black / warm off-white / translucent grey, at most one muted accent that is never the only cue; ships with an invert mode.
- **Feel:** response under ~100 ms, ease-in-out motion (~120 ms), every action gives feedback, restarts instant and blame-free, target 60fps.
- **Depth:** a room's rule should be graspable in under ~30s with no text; fix a dominant trick with an interacting constraint, never a new button.

## Stack & build

- **Swift 6.4 / SwiftUI**, built with **Xcode 27** on **macOS 26.4+ / Apple silicon**. **Deployment target: iOS 17.0.**
- **Swift Package Manager**; target **zero** external packages. Any addition: pin the exact version, record it in `_project-state/00_stack-and-config.md`, and log it in `ECHO-Decisions.md`.
- Particles via SwiftUI Canvas (thin SpriteKit only if needed); audio via AVAudioEngine; haptics via Core Haptics + UIFeedbackGenerator; levels as JSON in `Levels/`; save via UserDefaults; tests via XCTest.
- **Run on device:** open `ECHO.xcodeproj`, select the iPhone, **⌘R** (free signing lasts 7 days — expected). **Test:** **⌘U** or `xcodebuild test -scheme ECHO -destination 'platform=iOS,name=<device>'`. The cable-free install is packaged as an `.ipa` and installed via **SideStore**; the exact flow is defined in the **Phase 3.05** workflow doc — don't improvise distribution before then.

## Repo layout

```
ECHO.xcodeproj · ECHO/ (App, Models, Views, Audio, Haptics, Resources)
Levels/ · ECHOTests/ · docs/design-handovers/ · _project-state/ (+ completions/)
```

**Path note (D-007):** `_project-state/` lives at the repo root, not under a `src/` — an iOS app has no `src/`; sources live in `ECHO/`.

## Workflow (multi-agent project)

- Read your **phase prompt** and any **Design handover** it references (`docs/design-handovers/Part-X-Phase-YY-Handover.md`) **before** writing code. Build only that phase.
- **One phase = one completion report = one commit.** Solo project: work on `main`, no PR gate.
- At the end of every phase, before closing it: file a completion report (copy `_project-state/completions/Part-X-Phase-YY-Completion.md`, fill from **verified** evidence), **overwrite** `_project-state/current-state.md` to match reality, update `_project-state/file-map.md` for every file change, and append to `_project-state/00_stack-and-config.md` on any version change. The phase isn't closed until `current-state.md` is accurate. **If `current-state.md` and `ECHO-Plan.md` ever disagree, the live code wins** — fix the stale doc.
- **Surface every decision** the prompt didn't specify in the report's §3, even if obvious; scope/stack/approach changes get a `ECHO-Decisions.md` entry.

## Quality bar

- No shortcuts; plain factual language (no marketing tone).
- The repo is **public** — never commit secrets/keys/tokens.
- Keep the deterministic core (turn engine, replay, collision, win detection) well covered by XCTest.

## Canonical docs

`ECHO-Project-Instructions.md` · `ECHO-Plan.md` · `ECHO-Phase-Plan.md` · `ECHO-Decisions.md`. See `ECHO-Plan.md` (§5, §14) for full gameplay and design detail.
