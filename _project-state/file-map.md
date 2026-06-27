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
- `_project-state/completions/Part-1-Hotfix-Shape-nonisolated-Completion.md` — Part 1 hotfix (`nonisolated` on the `Diamond` `Shape`) completion report
- `_project-state/completions/Part-2-Phase-02-Completion.md` — Phase 2.02 (The board's real look + motion) completion report
- `_project-state/completions/Part-2-Phase-03-Completion.md` — Phase 2.03 (The fold choreography & the death dissolve) completion report
- `_project-state/completions/Part-2-Phase-04-Completion.md` — Phase 2.04 (Generative move-audio — the signature feature) completion report

## Xcode project (`ECHO.xcodeproj/`)
- `ECHO.xcodeproj/project.pbxproj` — the project definition (targets, build settings, synchronized groups: `ECHO`, `ECHOTests`, and `Levels` (room JSON bundled into the app target, D-025))
- `ECHO.xcodeproj/project.xcworkspace/contents.xcworkspacedata` — implicit workspace pointer
- `ECHO.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` — workspace check defaults
- `ECHO.xcodeproj/xcshareddata/xcschemes/ECHO.xcscheme` — shared build/run/test scheme (committed)

## App source (`ECHO/`)
- `ECHO/App/ECHOApp.swift` — `@main` SwiftUI App entry point; hosts `ContentView`
- `ECHO/App/ContentView.swift` — root view: full-bleed **paper gradient** (`paper.top → paper.bottom`, Phase 2.02); **owns the `GameState`** and the ordered ten-teaching-room id list (`room-01`…`room-10`, Phase 1.08) + index; loads room 1 on launch (`LevelLoader`, bare-board fallback). **Owns the active `ThemeMode`** (the single internal switch point for 2.06) and injects the resolved `Theme` into the environment (`.environment(\.theme,…)`). **Owns the `AudioManager`** (Phase 2.04) and `start()`s it at launch (`.task`), passing it into `BoardView`. Lays out `BoardView` above a throwaway debug bar — **Fold / Step back (`stepBack()`, disabled at turn 0) / Reset run (`restartRun()`, keeps echoes) / Clear (`clearEchoes()`, debug-only) / Next (cycle rooms) / Invert (flip palette — throwaway debug, not the real 2.06 toggle)** / `turn · echoes M/budget B` readout / **Solved ✓** stand-in (D-017/D-029/D-041)
- `ECHO/Models/GameState.swift` — `@MainActor @Observable` board state: full room config as `let`s — dimensions, `start`, `exit: GridCoordinate?`, `echoBudget` (`.max` on bare board), `walls: Set`, `switches`, `doors`, `hazards` — plus player cell, turn counter, current run, echoes, and `hasWon`. Designated `init(...)` (all room fields defaulted) + `convenience init(level:)`. `move(_:)` (no-op on off-grid / wall / closed door / after win; commits → collision-first then win), `playerCollides(...)` (land-on OR cross-paths over **echoes + hazards**; swap live vs hazards, D-018/D-022), pure derivations `isWall`/`isCellHeld`/`isSwitchHeld`/`isDoorOpen`/`isClosedDoor` (D-019), `position(of: Echo)`/`position(of: Hazard)`, `fold()` (empty/budget/win guards, D-027), `restartRun()` (also the **reset-run** op, D-029) / `clearEchoes()` (both clear `hasWon`), and **`stepBack()`** — pure single-move undo: pops `currentRun`, decrements `turn`, replays `player` from `start`; no collision/win check, never touches `echoes`; no-op at turn 0, refused while won (D-028/D-030/D-031). Pure, unit-tested (D-013..D-032)
- `ECHO/Models/Level.swift` — `nonisolated` Decodable room schema: `Level` (`id`/`name`/`width`/`height`/`start`/`exit`/`echoBudget` + `walls`/`switches`/`doors`/`hazards`; element arrays optional → empty), `Switch` (`id`,`cell`), `Door` (`id`,`cells[]`,`heldBy[]` AND-array), and `enum LevelLoader` (`load(_ id:in:) -> Level?`, flat + `Levels/`-subdir bundle lookup, nil on failure). The locked v1 format (D-024)
- `ECHO/Models/Hazard.swift` — `nonisolated` Decodable value type for a moving lethal cell: `id`, `start`, `path: [Direction]`, `loops` (defaults true; absent path → empty); `position(at turn:)` applies one path step/turn (empty/turn-0 → start; `loops:false` stands still when exhausted; `loops:true` indexes modulo path length). Lethal on contact, not solid, doesn't hold switches (D-021)
- `ECHO/Models/Echo.swift` — `nonisolated` value type for one folded run: stable `id: UUID` + recorded `moves: [Direction]`; `position(start:turn:)` is a pure function of start+moves+turn (exhausted echo stands still). `Identifiable`/`Equatable`/`Sendable` (D-014)
- `ECHO/Models/GridCoordinate.swift` — `nonisolated` value type for a grid cell (`row`, `column`; origin top-left); `Equatable`/`Hashable`/`Sendable`/`Codable` (decodes a level-JSON `{row,column}`)
- `ECHO/Models/Direction.swift` — `nonisolated` `String`-raw-value enum of the four orthogonal moves (`Codable`/`Sendable`; raw values match the JSON hazard-path names); `offset` (row/col delta) + `init?(from:to:)` adjacency rule used by tap input
- `ECHO/Views/BoardView.swift` — the real board (Phase 2.02 look + motion; **2.03 fold/death events**), driven by the `Theme` token layer in both Light and Invert: faint `tile.hairline` lattice with per-cell tap targets + element layers to handover §2 spec (walls = top-light gradient tile; exit = gold active-goal ring + glow / ink default ring; door = solid closed bar vs two faint open stubs; switch = hollow ring vs filled-gold held circle + glow; enemy = red diamond [rotated rounded square] + inner core + outline + glow) + translucent recede-behind echoes + fully-opaque ink player (the largest piece and the only shadow-caster, §3). Step motion: `commitMove(_:)` reads the model's public predicates to pick slide-vs-snap-vs-dissolve — a survived step runs `withAnimation(Motion.step)` (player + echoes glide 120 ms `curve.standard` in lockstep; hazards retimed to 140 ms via `.transaction`) and bumps `stepTick` to fire the player squash-and-stretch + soft-snap and each hazard's anticipation lean-in (keyframe scales). **Phase 2.03:** a fold (detected via `.onChange(of: echoes.count)`) plays the §6c choreography and a **fatal step defers** the model mutation (`triggerDeath` → `BoardEffectsOverlay` plays the §6d dissolve → `finishDeath()` calls `restartRun()`); input is locked while an effect plays; the dissolving player + colliding echo(es) and the peeling new echo are hidden in the steady layers while the overlay owns them; reset/step-back/room-load still snap. **Phase 2.04** injects an `AudioManager` and fires it from the same paths (behind the same input lock): a survived step plays a chord of direction-pitched ticks — one per moving entity, derived read-only from the public positions (`playStep`) — plus `playSolve()` if it won; a fatal step plays `playDeath()`; a fold plays `playFold()`. Engine untouched; the board reacts via Observation. Hit-testing off on every drawn piece; glows/shadow render outside the cell, never clipped
- `ECHO/Views/BoardEffects.swift` — **Phase 2.03.** The transient SwiftUI **Canvas** effect overlay (no SpriteKit, zero new deps): `nonisolated` `FoldEffect`/`DeathEffect` descriptors (read-only captures of an event the engine already decided), and `BoardEffectsOverlay` = `TimelineView(.animation) { Canvas { … } }`, mounted by `BoardView` only while an effect is in flight. Draws the **fold** (grid ripple in `tile.hairline`, then the new echo peeling from the run-end back to `start`, ink→`echoBase` crossfade, 32→28 pt) and the **death** (the player + colliding echo(es) glide onto the contact tile → calm freeze → bounded deterministic particle **fizz**, ~14 ink + ~10 grey per echo → faint `dangerRed` @ 0.08 vignette + one `dangerGlow` enemy pulse). Every colour from the injected `Theme` (both palettes); timings/curves from `Motion.Span`/`Ease`
- `ECHO/Theme/Theme.swift` — **the central colour-token source** (Phase 2.02): `Color(hex:)` helper; `ThemeMode` (light/invert); `Theme` struct holding both authoritative palettes for every handover §1a token (defaults to Light); `BoardMetrics` (all §1b geometry/stroke/opacity/shadow/glow values, in pt at the reference cell C = 44); and the `\.theme` `EnvironmentValues` key — the single switch point 2.06 will bind. All `nonisolated`/`Sendable` (D-013/D-040). No toggle UI, no persistence this phase (D-041)
- `ECHO/Theme/Motion.swift` — **the named motion curves** (Phase 2.02; **2.03 additions**): `Curve` = the five handover §6a easing curves (`standard`/`easeOut`/`easeIn`/`softSnap` as duration-parameterised `timingCurve`s with the exact control points; `decayShake` as the `interpolatingSpring(stiffness:320,damping:14)`); `Motion` = the §1c motion tokens built from them (`step` 120 ms, `stepSnap` 40 ms, `enemyStep` 140 ms; fold/death/deny/guidance/trail `Animation` tokens). **Phase 2.03 added** `Motion.Span` — the §1c phase durations as raw seconds (`foldHitPause`/`foldRipple`/`foldPeel`/`deathFreeze`/`deathFizz`/`deathVignette`/`step`) for the Canvas layer (which advances by elapsed time, not a baked `Animation`) — and `Ease` — the §6a curves as scalar cubic-Bézier easings (`standard`/`easeOut`/`easeIn` + a `bezier` solver) so canvas-driven effects share the exact curve shapes. All `nonisolated`
- `ECHO/Audio/AudioManager.swift` — **Phase 2.04.** The generative-audio manager: a `@MainActor final class` owning one `AVAudioEngine` + a pool of 16 `AVAudioPlayerNode`s into the main mixer, playing short `AVAudioPCMBuffer`s **synthesized once at startup** (no bundled audio — D-045). `start()` configures the `AVAudioSession` (`.ambient` + `.mixWithOthers`, iOS-only behind `#if os(iOS)` — D-047), pre-warms (`prepare()`) and starts the engine, and keeps the pool playing so a fire is one sample-aligned `scheduleBuffer(at:)` at a shared future host time. Sound bank: four **direction-pitched** marimba-like step ticks on a fixed pentatonic set (up higher / down lower / left-right middle — D-046), a warm **fold** settle, a calm muted **death** puff (low tone + filtered noise), and a gentle ascending **solve** figure. `playStep(directions:)` fires a turn's ticks as one chord; `playFold`/`playDeath`/`playSolve` align to `Motion.Span` beats. `var isEnabled` (default `true`) gates all playback — the single Settings hook for 2.06 (no toggle UI/persistence here)
- `ECHO/Audio/` — now populated (above); generative percussion, Part 2 (Phase 2.04)
- `ECHO/Haptics/` — reserved: Core Haptics mapping, Part 2 (Phase 2.05). **Not git-tracked while empty** (no `.gitkeep`, see D-012); reappears when populated
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

## Design handovers (`docs/design-handovers/`)
- `docs/design-handovers/Part-2-Phase-01-Handover.md` — the locked Phase 2.01 visual design (every colour hex, geometry pt, opacity, motion curve/duration); the source of truth implemented by Phase 2.02
