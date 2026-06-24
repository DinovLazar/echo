# file-map.md

> Every meaningful file/folder in the repo, one line each, kept greppable so anyone can find where a thing lives. **Code updates this on every add, rename, or delete.**

## How Code maintains this
- Add a line the moment a file is created; update it on rename; remove it on delete.
- One line per file: `path — what it's for` (plain language).
- Group by folder. Keep paths exact so they can be searched.
- If this map and the real repo ever disagree, the map is wrong — fix it (and note the slip in the next completion report).

---

## Project docs (repo root)
- `ECHO-Project-Instructions.md` — the orchestrator rulebook; pasted at the start of every chat
- `ECHO-Plan.md` — the master spec for the finished game
- `ECHO-Phase-Plan.md` — the living index of every phase
- `ECHO-Decisions.md` — append-only decision log
- `CLAUDE.md` — Claude Code's project guide (read first, every session)
- `AGENTS.md` — vendor-neutral agent guide (mirror of CLAUDE.md)
- `README.md` — short public-facing description + build/run pointer
- `.gitignore` — Swift/Xcode ignore rules (build products, DerivedData, user state, .DS_Store)
- *(missing at kickoff: `ECHO-Notion-Checklist.md` — not present in the repo; flagged in the Phase 1.01 report)*

## Project state (`_project-state/`)
- `_project-state/current-state.md` — live repo snapshot (overwritten each phase)
- `_project-state/file-map.md` — this file
- `_project-state/00_stack-and-config.md` — append-only stack/config log with pinned versions
- `_project-state/completions/Part-X-Phase-YY-Completion.md` — completion-report template
- `_project-state/completions/Part-1-Phase-01-Completion.md` — Phase 1.01 (Scaffold) completion report
- `_project-state/completions/Part-1-Phase-02-Completion.md` — Phase 1.02 (First device install) completion report
- `_project-state/completions/Part-1-Phase-02-grid-layout-reference.svg` — deterministic layout reference for the hello-grid (NOT a Simulator screenshot)
- `_project-state/completions/Part-1-Phase-03-Completion.md` — Phase 1.03 (Grid + Move) completion report
- `_project-state/completions/Part-1-Phase-04-Completion.md` — Phase 1.04 (Fold — record & replay) completion report

## Xcode project (`ECHO.xcodeproj/`)
- `ECHO.xcodeproj/project.pbxproj` — the project definition (targets, build settings, synchronized groups)
- `ECHO.xcodeproj/project.xcworkspace/contents.xcworkspacedata` — implicit workspace pointer
- `ECHO.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` — workspace check defaults
- `ECHO.xcodeproj/xcshareddata/xcschemes/ECHO.xcscheme` — shared build/run/test scheme (committed)

## App source (`ECHO/`)
- `ECHO/App/ECHOApp.swift` — `@main` SwiftUI App entry point; hosts `ContentView`
- `ECHO/App/ContentView.swift` — root view: full-bleed paper background; **owns the `GameState`** and lays out `BoardView` above a throwaway debug bar (Fold / Clear / `turn · echoes` readout, D-017)
- `ECHO/Models/GameState.swift` — `@MainActor @Observable` board state: dimensions (param, default 7×7), stored `start` cell (default center), player cell, turn counter, current run (`[Direction]`) and echoes (`[Echo]`); `move(_:)` (one tile, clamp off-grid, +1 turn, records the move), `fold()`, `clearEchoes()`, `position(of:)`. Pure, unit-tested (D-013, D-014, D-015)
- `ECHO/Models/Echo.swift` — `nonisolated` value type for one folded run: stable `id: UUID` + recorded `moves: [Direction]`; `position(start:turn:)` is a pure function of start+moves+turn (exhausted echo stands still). `Identifiable`/`Equatable`/`Sendable` (D-014)
- `ECHO/Models/GridCoordinate.swift` — `nonisolated` value type for a grid cell (`row`, `column`; origin top-left); `Equatable`/`Hashable`/`Sendable`
- `ECHO/Models/Direction.swift` — `nonisolated` enum of the four orthogonal moves; `offset` (row/col delta) + `init?(from:to:)` adjacency rule used by tap input
- `ECHO/Views/BoardView.swift` — the real board: grey lattice with per-cell tap targets + translucent grey echoes (drawn beneath, no collision in 1.04) + black rounded-square player on top; takes the `GameState` injected from `ContentView`; swipe (drag) and tap input route through `GameState.move(_:)`; placeholder `.easeInOut` slide
- `ECHO/Audio/` — reserved: generative percussion, Part 2. **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
- `ECHO/Haptics/` — reserved: Core Haptics mapping, Part 2. **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
- `ECHO/Resources/Assets.xcassets/Contents.json` — asset catalog root
- `ECHO/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — app icon set (no artwork yet)
- `ECHO/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — accent color (system default)

## Levels (`Levels/`)
- `Levels/.gitkeep` — reserved for room JSON files (added from Phase 1.06; not yet wired into the build)

## Tests (`ECHOTests/`)
- `ECHOTests/ECHOTests.swift` — `@MainActor` XCTest coverage of the move model (four directions, four edge no-ops, turn-counter rule, defaults, tap rule) **plus the fold/replay suite** (recording, fold→one echo + rewind, replay fidelity, exhausted-echo standstill, two independent echoes, different-length lockstep, empty-fold no-op, `clearEchoes()` pristine, no-op-not-recorded)

## Reserved
- `docs/design-handovers/.gitkeep` — reserved for Design-phase handover docs
