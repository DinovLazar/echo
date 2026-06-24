# CLAUDE.md

Guidance for any AI coding agent (Claude Code especially) working in this repo. Read this first, every session. If this file and `AGENTS.md` ever disagree, **CLAUDE.md wins**.

---

## What this is

**ECHO** — a native iOS puzzle game, built for its owner (Lazar) to play on his own iPhone. Offline, single-player, no App Store, no monetization, no network. It is installed by **sideloading** a free-signed build via **SideStore** (not the App Store).

The game: a turn-based black-and-white grid. You move one square. You can **fold** a run — record your moves and replay them as a grey **echo**. You solve each room by stacking echoes that hold switches, block hazards, and trip mechanisms. **Touching any echo dissolves you and restarts the current run** (existing echoes persist). Reach the exit to win.

## Non-negotiable design constraints

These define the game; don't quietly change them:
- **Turn-based and deterministic.** The world advances **only** when the player takes a step. Every echo takes its next recorded step at the same instant, locked to a single shared **turn counter**. Replays must be exact and repeatable — no randomness in the core.
- **One verb (move) + one meta-verb (fold),** plus two supporting controls (**reset run**, **step back**). Don't add inputs to fix difficulty — add interacting constraints (another switch/hazard/tighter echo budget).
- **Collision = same tile on the same turn.** No physics, no real-time loop, no collision math beyond grid-cell equality.
- **Monochrome.** Black ink, warm off-white paper, translucent-grey echoes, at most **one muted accent** color — and the accent is never the *only* cue (meaning lives in shape, position, motion too). Ships with an **invert mode**.
- **Feel targets:** input-to-response under ~100 ms; every action paired with visual feedback (plus audio/haptic from Part 2); restarts instant and "your fault"; target 60fps. Motion is ease-in-out (~120 ms slides) with a slight squash-and-stretch — never linear/instant teleporting.
- **Depth targets:** the rule of a room should be graspable in under ~30 s **with no text** — the level teaches itself. If one dominant trick emerges that trivializes a room, fix it with an interacting constraint (another switch/hazard/tighter echo budget), **never a new button**.

The full spec is in `ECHO-Plan.md` §5, §14. The signature feature (Part 2): each move plays a soft percussive tick, so stacked echoes layer their ticks into a generative rhythm — a solved room *sounds* like a loop you composed.

## Stack

- **Swift 6.4 / SwiftUI** foundation. Build with **Xcode 27** (Swift 6.4) on **macOS 26.4+ / Apple silicon**.
- **Deployment target: iOS 17.0** (runs through iOS 27).
- **Swift Package Manager** for dependencies — but **aim for zero external packages**. If you must add one, pin the exact version, record it in `_project-state/00_stack-and-config.md`, and log the choice in `ECHO-Decisions.md`.
- Particles: **SwiftUI Canvas** first; a thin **SpriteKit** layer only if Canvas can't do the death-fizz / fold-ripple.
- Audio: **AVAudioEngine**. Haptics: **Core Haptics + UIFeedbackGenerator** (pre-warm generators; pair every haptic with a visual change).
- Levels: **plain JSON** in `Levels/`. Save data: **UserDefaults**. Tests: **XCTest**.

## Repo layout

```
ECHO.xcodeproj          ← the Xcode project
ECHO/                   ← Swift source (App/, Models/, Views/, Audio/, Haptics/, Resources/)
Levels/                 ← room JSON files
ECHOTests/              ← XCTest unit tests
docs/design-handovers/  ← Design phase handovers (read before writing UI for a matching phase)
_project-state/         ← current-state.md, file-map.md, 00_stack-and-config.md, completions/
```

**Path note (D-007):** project-state lives at `_project-state/` at the **repo root**, not under a `src/` — an iOS app has no `src/`; its sources live in `ECHO/`. Don't relocate it.

## Build / run / test

- **Run on the connected iPhone:** open `ECHO.xcodeproj` in Xcode, select the device, **⌘R**. (Free signing → the install lasts 7 days; that's expected.)
- **Tests:** **⌘U** in Xcode, or from the terminal:
  `xcodebuild test -scheme ECHO -destination 'platform=iOS,name=<device name>'`
- **Build from terminal:**
  `xcodebuild -scheme ECHO -configuration Debug -destination 'generic/platform=iOS'`
- **The on-phone install that survives without the cable:** the app is packaged into an `.ipa` and installed through **SideStore**, which re-signs it with the owner's free Apple ID and auto-refreshes the 7-day certificate in the background. The exact repeatable steps are defined in the **Phase 3.05** workflow doc — don't improvise a distribution flow before then; during development, **⌘R** to the device is enough.

## How work happens here (the workflow)

This is a multi-agent project. Your lane as the coding agent:
- **Read the phase prompt** you were given, plus any **Design handover** it references (`docs/design-handovers/Part-X-Phase-YY-Handover.md`), **before** writing code. Build exactly that phase — don't pull future phases forward.
- **One phase = one completion report = one git commit.** Work on `main` (solo project — no PR gate, no branch protection; small local feature branches are fine if you prefer, merged to `main`).
- **At the end of every phase**, before closing it:
  1. Copy `_project-state/completions/Part-X-Phase-YY-Completion.md`, fill it in **from verified evidence** (run the command, don't write checkmarks from memory).
  2. **Overwrite** `_project-state/current-state.md` so it mirrors what actually shipped (it's a snapshot, not a changelog).
  3. Update `_project-state/file-map.md` for every file added/renamed/deleted.
  4. Append to `_project-state/00_stack-and-config.md` if any dependency/tool/version changed (exact pinned versions).
  - A phase is **not closed** until `current-state.md` matches reality.
  - **Precedence:** if `current-state.md` and `ECHO-Plan.md` ever disagree, the **live code wins** — `current-state.md` reflects what actually shipped; the Plan is the intent. Fix the stale doc.
- **Surface every decision you had to make** that the prompt didn't specify, in the report's §3 — even if it seems obvious. The orchestrator decides what to ratify; your job is to put every choice on the table. If it changes scope/stack/approach, it needs a `ECHO-Decisions.md` entry.

## Quality bar

- No shortcuts, no "TODO later" when the real fix is in reach.
- Plain, factual language in reports and comments — no marketing tone.
- The repo is **public**: never commit secrets, keys, or tokens (none should be needed anyway).
- Keep the core logic (turn engine, replay, collision, win detection) under **XCTest** — it's pure and deterministic, so it should be thoroughly covered; tests are what keep late, tightly-choreographed rooms trustworthy.

## Canonical docs

`ECHO-Project-Instructions.md` (the rulebook) · `ECHO-Plan.md` (the spec) · `ECHO-Phase-Plan.md` (phase index) · `ECHO-Decisions.md` (why things are the way they are). Read the Plan for any gameplay detail this file summarizes.
