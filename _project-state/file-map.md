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

## Xcode project (`ECHO.xcodeproj/`)
- `ECHO.xcodeproj/project.pbxproj` — the project definition (targets, build settings, synchronized groups)
- `ECHO.xcodeproj/project.xcworkspace/contents.xcworkspacedata` — implicit workspace pointer
- `ECHO.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` — workspace check defaults
- `ECHO.xcodeproj/xcshareddata/xcschemes/ECHO.xcscheme` — shared build/run/test scheme (committed)

## App source (`ECHO/`)
- `ECHO/App/ECHOApp.swift` — `@main` SwiftUI App entry point; hosts `ContentView`
- `ECHO/App/ContentView.swift` — root view: full-bleed paper background + centered `HelloGridView` (Phase 1.02 hello-grid placeholder)
- `ECHO/Models/` — reserved: grid, turn engine, echo/replay, collision, win checks. **Not git-tracked while empty** (no `.gitkeep` — it collides in Xcode synchronized groups, see D-012); reappears when its first source file lands (Phase 1.03)
- `ECHO/Views/HelloGridView.swift` — Phase 1.02 throwaway placeholder: static, non-interactive 5×5 grey square grid (replaced by the real board in Phase 1.03)
- `ECHO/Audio/` — reserved: generative percussion, Part 2. **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
- `ECHO/Haptics/` — reserved: Core Haptics mapping, Part 2. **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
- `ECHO/Resources/Assets.xcassets/Contents.json` — asset catalog root
- `ECHO/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — app icon set (no artwork yet)
- `ECHO/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — accent color (system default)

## Levels (`Levels/`)
- `Levels/.gitkeep` — reserved for room JSON files (added from Phase 1.06; not yet wired into the build)

## Tests (`ECHOTests/`)
- `ECHOTests/ECHOTests.swift` — one trivial passing test proving the test target compiles and runs

## Reserved
- `docs/design-handovers/.gitkeep` — reserved for Design-phase handover docs
