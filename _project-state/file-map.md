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
- `_project-state/completions/Part-1-Phase-05-Completion.md` — Phase 1.05 (Collision + restart) completion report
- `_project-state/completions/Part-1-Phase-06-Completion.md` — Phase 1.06 (Room contents, level data & win) completion report
- `_project-state/completions/Part-1-Phase-07-Completion.md` — Phase 1.07 (Reset run & step back) completion report
- `_project-state/completions/Part-1-Phase-08-Completion.md` — Phase 1.08 (The first teaching rooms) completion report

## Xcode project (`ECHO.xcodeproj/`)
- `ECHO.xcodeproj/project.pbxproj` — the project definition (targets, build settings, synchronized groups: `ECHO`, `ECHOTests`, and `Levels` (room JSON bundled into the app target, D-025))
- `ECHO.xcodeproj/project.xcworkspace/contents.xcworkspacedata` — implicit workspace pointer
- `ECHO.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` — workspace check defaults
- `ECHO.xcodeproj/xcshareddata/xcschemes/ECHO.xcscheme` — shared build/run/test scheme (committed)

## App source (`ECHO/`)
- `ECHO/App/ECHOApp.swift` — `@main` SwiftUI App entry point; hosts `ContentView`
- `ECHO/App/ContentView.swift` — root view: full-bleed paper background; **owns the `GameState`** and the ordered ten-teaching-room id list (`room-01`…`room-10`, Phase 1.08) + index; loads room 1 on launch (`LevelLoader`, bare-board fallback) and lays out `BoardView` above a throwaway debug bar — **Fold / Step back (`stepBack()`, disabled at turn 0) / Reset run (`restartRun()`, keeps echoes) / Clear (`clearEchoes()`, wipes echoes — debug-only, kept distinct from Reset run) / Next (cycle rooms)** / `turn · echoes M/budget B` readout / **Solved ✓** stand-in (D-017/D-029)
- `ECHO/Models/GameState.swift` — `@MainActor @Observable` board state: full room config as `let`s — dimensions, `start`, `exit: GridCoordinate?`, `echoBudget` (`.max` on bare board), `walls: Set`, `switches`, `doors`, `hazards` — plus player cell, turn counter, current run, echoes, and `hasWon`. Designated `init(...)` (all room fields defaulted) + `convenience init(level:)`. `move(_:)` (no-op on off-grid / wall / closed door / after win; commits → collision-first then win), `playerCollides(...)` (land-on OR cross-paths over **echoes + hazards**; swap live vs hazards, D-018/D-022), pure derivations `isWall`/`isCellHeld`/`isSwitchHeld`/`isDoorOpen`/`isClosedDoor` (D-019), `position(of: Echo)`/`position(of: Hazard)`, `fold()` (empty/budget/win guards, D-027), `restartRun()` (also the **reset-run** op, D-029) / `clearEchoes()` (both clear `hasWon`), and **`stepBack()`** — pure single-move undo: pops `currentRun`, decrements `turn`, replays `player` from `start`; no collision/win check, never touches `echoes`; no-op at turn 0, refused while won (D-028/D-030/D-031). Pure, unit-tested (D-013..D-032)
- `ECHO/Models/Level.swift` — `nonisolated` Decodable room schema: `Level` (`id`/`name`/`width`/`height`/`start`/`exit`/`echoBudget` + `walls`/`switches`/`doors`/`hazards`; element arrays optional → empty), `Switch` (`id`,`cell`), `Door` (`id`,`cells[]`,`heldBy[]` AND-array), and `enum LevelLoader` (`load(_ id:in:) -> Level?`, flat + `Levels/`-subdir bundle lookup, nil on failure). The locked v1 format (D-024)
- `ECHO/Models/Hazard.swift` — `nonisolated` Decodable value type for a moving lethal cell: `id`, `start`, `path: [Direction]`, `loops` (defaults true; absent path → empty); `position(at turn:)` applies one path step/turn (empty/turn-0 → start; `loops:false` stands still when exhausted; `loops:true` indexes modulo path length). Lethal on contact, not solid, doesn't hold switches (D-021)
- `ECHO/Models/Echo.swift` — `nonisolated` value type for one folded run: stable `id: UUID` + recorded `moves: [Direction]`; `position(start:turn:)` is a pure function of start+moves+turn (exhausted echo stands still). `Identifiable`/`Equatable`/`Sendable` (D-014)
- `ECHO/Models/GridCoordinate.swift` — `nonisolated` value type for a grid cell (`row`, `column`; origin top-left); `Equatable`/`Hashable`/`Sendable`/`Codable` (decodes a level-JSON `{row,column}`)
- `ECHO/Models/Direction.swift` — `nonisolated` `String`-raw-value enum of the four orthogonal moves (`Codable`/`Sendable`; raw values match the JSON hazard-path names); `offset` (row/col delta) + `init?(from:to:)` adjacency rule used by tap input
- `ECHO/Views/BoardView.swift` — the real board: grey lattice with per-cell tap targets + grey-box element layers (walls = solid dark cells; exit = hollow ring; door bars shown while closed; switch circles that fill when held; hazard = a hollow `Diamond` shape) + translucent grey echoes + black rounded-square player on top, all reading current-turn state from `GameState`; every drawn piece has hit-testing off so taps reach the lattice; swipe/tap route through `GameState.move(_:)`; placeholder `.easeInOut` slide doubles as the death snap-back / win reaction (all rules are in the model, the board reacts via Observation)
- `ECHO/Audio/` — reserved: generative percussion, Part 2. **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
- `ECHO/Haptics/` — reserved: Core Haptics mapping, Part 2. **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
- `ECHO/Resources/Assets.xcassets/Contents.json` — asset catalog root
- `ECHO/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — app icon set (no artwork yet)
- `ECHO/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — accent color (system default)

## Levels (`Levels/`)
> The ten teaching rooms (Phase 1.08, D-033). The three throwaway proof rooms (`p1-06-a/b/c.json`) were deleted — no test referenced them and they were replaced in the play sequence. All bundled into the app target via the `Levels` synchronized root group (D-025).
- `Levels/room-01.json` — "Straight Line" (move; budget 0)
- `Levels/room-02.json` — "The Turn" (walls; budget 0)
- `Levels/room-03.json` — "First Fold" (echo holds a switch → door; budget 1)
- `Levels/room-04.json` — "Mind the Past" (echo is a lethal obstacle, route around it; budget 1)
- `Levels/room-05.json` — "Two Selves" (two echoes hold two doors in series; budget 2)
- `Levels/room-06.json` — "The Patrol" (time a moving hazard; budget 0)
- `Levels/room-07.json` — "Hold, Then Time" (hold a door open while timing a patrol; budget 1)
- `Levels/room-08.json` — "Two Jobs" (two held doors + a patrol; echo B reaches its switch through echo A's door; budget 2)
- `Levels/room-09.json` — "Contested" (thread a patrolled centre, two held necks; **regrown 5×7 with a stall pocket**, D-039; budget 2)
- `Levels/room-10.json` — "Capstone" (everything at once; switch-dependency keeps it to two echoes; budget 2)
- *(`Levels/.gitkeep` removed in 1.06; no `.gitkeep` here — outside `ECHO/`, so no D-012 collision either way)*

## Tests (`ECHOTests/`)
- `ECHOTests/ECHOTests.swift` — `@MainActor` XCTest coverage of the move model, the fold/replay suite, the collision/restart suite (1.03–1.05), and the 1.06 suite (walls; switch/door + echo-holds-switch canonical solve; hazard land-on / cross-paths-swap / loop-non-loop-stationary; win + input lock; collision-before-win; echo-budget refusal; JSON decode; level-load reset), **plus the 1.07 suite**: step-back rollback; turn-0 no-op + no-un-fold guard; repeated step-back to turn 0 (echoes preserved); step-back refused while won; step-back-then-branch-move (invariant `turn == currentRun.count`); derived-world rollback (switch+door + hazard + echo → turn-1 values); reset-run preserving echoes incl. reset-while-won. No prior test needed re-pathing (1.07 changes no move/fold/collision/win semantics)
- `ECHOTests/RoomSolvabilityTests.swift` — **Phase 1.08** `@MainActor` per-room suite (D-034): one solvability test per `room-01`…`room-10` that loads the JSON via `LevelLoader` (source-tree fallback), replays a verified reference solution through the real `GameState` (asserting every move lands, each fold banks one echo within budget, the final run reaches `exit` with `hasWon`), plus the negative tests for rooms 04/06/07 (the named naive run dissolves and does not win) and a hazard-trace test (each patrol's one-period trace + period wrap matches the documented path)

## Reserved
- `docs/design-handovers/.gitkeep` — reserved for Design-phase handover docs
