# ECHO — Decisions

> An **append-only** record of *why the project is the way it is*. One decision per entry; always name the alternative rejected and the honest downside accepted. Read the highest ID before adding; continue from there. Never renumber or rewrite a past entry — if a decision is reversed, change only its **Status** to `Superseded by D-0YY` and add a new entry.

---

### D-001 · 2026-06-24 · Platform: native iOS app via free Apple ID sideload
- **Status:** Accepted
- **Context:** Lazar wants a fun, good-looking game he can play on his iPhone, with no commercial or App Store goal. We had to choose how the game reaches the phone.
- **Decision:** Build a real native iOS app and install it by **sideloading**, signed with the free certificate a personal Apple ID provides, kept alive by **SideStore**. Not the App Store; not a web/home-screen PWA; not the paid TestFlight route.
- **Alternatives considered:** (a) Free home-screen web app/PWA — simplest to build and zero upkeep, but it's a web page under Safari, not a true app — rejected because Lazar specifically wants a real app. (b) Paid Apple Developer Program ($99/yr) + TestFlight — real app, 1-year signing, shareable links, no weekly refresh — rejected because it costs money for a personal toy and sharing isn't a goal. (c) Public App Store release — review overhead and name-collision concerns for no benefit — rejected.
- **Consequences:** $0 cost and a genuine app, but free signing means the certificate expires every **7 days** and must be re-signed; SideStore auto-refreshes in the background to make this mostly invisible. Caps at 3 sideloaded apps / 10 app-IDs per week (a non-issue for one game). Creates a hard dependency on Xcode and on SideStore continuing to work.
- **Links:** Plan §6, §16; Phase 1.02; Phase 3.05; D-009.

### D-002 · 2026-06-24 · Engine/stack: Swift + SwiftUI foundation (no game engine)
- **Status:** Accepted
- **Context:** ECHO is turn-based and grid-based, with no physics and no real-time loop. We had to pick what to build it on.
- **Decision:** Build on **Swift + SwiftUI** as the foundation. Add a thin **SpriteKit** layer only if SwiftUI's Canvas can't handle the particle effects. No third-party game engine.
- **Alternatives considered:** (a) SpriteKit-first (Apple's 2D game framework) — better at particles, but heavier than needed for a state-driven grid and weaker for standard UI/menus — rejected as the foundation, kept as an optional particle layer. (b) Unity/Godot — full engines, massive overkill for a grid puzzle, larger builds, more to learn — rejected. (c) Web tech in a wrapper — contradicts D-001 — rejected.
- **Consequences:** The grid-as-state model maps directly to SwiftUI; animation, audio, and haptics are all native and free. Trade: if particles get ambitious, we add a small SpriteKit layer later. Locks the project to Apple platforms — acceptable, since it's iPhone-only by design.
- **Links:** Plan §6; Phases 2.02–2.05.

### D-003 · 2026-06-24 · GitHub repo: DinovLazar/echo, public
- **Status:** Accepted
- **Context:** The project needs a home for source code and docs, plus a backup.
- **Decision:** Use GitHub repo **`DinovLazar/echo`**, **public** visibility, single branch `main`.
- **Alternatives considered:** Private — recommended by Chat (it's a personal project; no reason to expose it) — but Lazar chose public.
- **Consequences:** Code and docs are world-readable. Practical effect for a solo offline game is minimal; the one rule it imposes is **never commit secrets** (none are expected here anyway).
- **Links:** Plan §16; Phase 1.01.

### D-004 · 2026-06-24 · Name: ECHO (kept)
- **Status:** Accepted
- **Context:** The design doc flagged "ECHO" as a crowded App Store name and suggested alternatives.
- **Decision:** Keep the name **ECHO**.
- **Alternatives considered:** Encore, Trace, Lapse, Selfsame, Wake — all viable, but the name-crowding concern only matters for App Store discoverability.
- **Consequences:** Since this is a sideloaded personal build that will never be listed in the App Store, name collisions don't matter. Renaming later is trivial if Lazar changes his mind.
- **Links:** Plan §2.

### D-005 · 2026-06-24 · Project size: three parts
- **Status:** Accepted
- **Context:** We had to choose how to break the build into parts.
- **Decision:** **Three parts** — Part 1 foundation + core mechanic (grey boxes); Part 2 the juice/feel; Part 3 content + Echo Run + sideload/refresh workflow.
- **Alternatives considered:** Single part (too large to run as one stretch) or two parts (would cram juice and content together, blurring the "prove the core before juicing it" gate) — both rejected for weaker checkpoints.
- **Consequences:** Clear milestones, with the Part 1 milestone as a hard gate before any polish. Slightly more ceremony than a single run, but far better checkpoints for a non-developer owner.
- **Links:** Phase Plan (all parts).

### D-006 · 2026-06-24 · Target iOS 17+; build with Xcode 27
- **Status:** Accepted
- **Context:** Lazar's iPhone and Mac are on iOS/macOS 27 (currently a beta; public release expected ~Sept 2026). We needed a deployment floor and a build toolchain.
- **Decision:** Set the **deployment target to iOS 17.0** and build with **Xcode 27** (Swift 6.4, currently beta).
- **Alternatives considered:** Target iOS 27 only — needlessly narrow and tied to a beta — rejected. Use an older Xcode — can't install onto an iOS 27 device — rejected (Xcode 27 supports on-device install for iOS 17+).
- **Consequences:** iOS 17 is a stable, widely-supported baseline; Xcode 27 is required to install onto the iOS 27 beta device and needs macOS 26.4+ on Apple silicon (Lazar's setup satisfies this).
- **Links:** Plan §6; D-009; Phases 1.01–1.02.

### D-007 · 2026-06-24 · Folder convention adapted for macOS/iOS
- **Status:** Accepted
- **Context:** The base orchestration playbook assumed a Windows web project with a `src/_project-state/` path. ECHO is a macOS-built iOS app with no `src/` folder.
- **Decision:** Keep `docs/design-handovers/` as-is; place the live project-state docs at **`_project-state/`** at the repo root (dropping the `src/` prefix), and file completion reports in **`_project-state/completions/`**.
- **Alternatives considered:** Force a `src/` folder to match the original literal path — artificial for an iOS project — rejected.
- **Consequences:** Paths match the platform; all canonical-doc references use the adapted paths. No functional impact.
- **Links:** Plan §7; Project-Instructions §11.

### D-008 · 2026-06-24 · Scope excludes website layers and heavy repo machinery
- **Status:** Accepted
- **Context:** The base playbook covers web-product layers and a team-grade repo setup. ECHO is an offline single-player solo game.
- **Decision:** Exclude CMS, email, CRM, analytics, hosting/CDN, i18n, SEO/schema, and legal-page tooling; also exclude branch protection, AI-review bots (CodeRabbit/Codex), and CI/CD pipelines.
- **Alternatives considered:** Include the full team setup — adds friction and maintenance with zero benefit for a solo offline game — rejected.
- **Consequences:** A lean repo and workflow. Trade: fewer automated guardrails (no PR review gate) — acceptable for a solo project, where Lazar plus Code's own XCTest suite are the check.
- **Links:** Plan §8–§13; CLAUDE.md.

### D-009 · 2026-06-24 · Known risk: building on/for a beta OS
- **Status:** Accepted (risk logged)
- **Context:** iOS 27 is in beta (public release expected ~Sept 14, 2026), and free-sideloading depends on SideStore working.
- **Decision:** Proceed building now rather than waiting for the stable release, and record the risk.
- **Alternatives considered:** Wait until iOS 27 ships publicly in September — an unnecessary delay, since the iOS 17 floor is stable regardless — rejected.
- **Consequences:** Two small risks — (a) beta OSes can be flakier; (b) a new iOS beta can briefly outpace SideStore until it updates, which could interrupt a refresh for a few days. Usually self-resolves. Targeting the stable iOS 17 baseline limits exposure.
- **Links:** D-001, D-006; Phase 3.05.

### D-010 · 2026-06-24 · Added CLAUDE.md and AGENTS.md to the deliverables
- **Status:** Accepted
- **Context:** Lazar requested agent-instruction files in addition to the standard project docs.
- **Decision:** Generate **`CLAUDE.md`** (Claude Code's project guide) and **`AGENTS.md`** (vendor-neutral equivalent) at the repo root, using the canonical **uppercase** filenames so the tools detect them.
- **Alternatives considered:** Lowercase filenames as Lazar typed them — rejected because Claude Code and the agents.md convention look for uppercase and may ignore lowercase. A single file only — rejected because different coding agents read different filenames.
- **Consequences:** Whichever coding agent works in the repo gets ECHO-specific guidance on first read. Two files to keep aligned; **CLAUDE.md is the source of truth** if they ever diverge.
- **Links:** CLAUDE.md, AGENTS.md.

### D-011 · 2026-06-24 · Xcode project created by hand-authoring a synchronized-groups `.pbxproj` (no generator, no IDE)
- **Status:** Accepted
- **Context:** Phase 1.01 had to produce `ECHO.xcodeproj`, but the environment where the scaffold was built had only the Xcode **Command Line Tools** installed (Swift 6.4), **not full Xcode** — so the project could not be created through the IDE, and could not be compiled or run in the Simulator to verify. The phase prompt allows either a project-generation tool (e.g. XcodeGen) or hand-authoring as build-time tooling.
- **Decision:** **Hand-author `project.pbxproj`** in the modern Xcode 16/26/27 **file-system synchronized-groups** format (`objectVersion = 77`, `PBXFileSystemSynchronizedRootGroup` for `ECHO/` and `ECHOTests/`, hosted unit-test target). No project-generation tool was installed. The result was machine-validated (`plutil -lint` passes; every object reference resolves; both targets resolve their sync groups) and cross-checked against real Xcode-26/27 project files.
- **Alternatives considered:** (a) **XcodeGen via Homebrew** — deterministic output, but adds a build-time tool dependency, generates classic file-listing groups that don't auto-pick-up files added in later phases, and still could not be build-verified without Xcode — rejected to keep zero tooling and to get auto-syncing folders. (b) **Wait and create the project in full Xcode** — would block all of Phase 1.01 on an Xcode install — rejected; the structure is needed now and the format is well-understood. (c) **Classic (non-synchronized) groups by hand** — would require listing every file and re-editing the project file each time a source file is added — rejected as more fragile.
- **Consequences:** No tool dependency; empty folders and any files added in later phases appear automatically. **Honest downside:** the project was **not** compiled or run in the Simulator during 1.01 (no Xcode in that environment), so Phase 1.02 must open it in Xcode 27, ⌘R to confirm the build and the paper screen, and pin the exact Xcode/SDK build numbers in `00_stack-and-config.md`. Residual risk is low (file is well-formed and matches the current schema) but non-zero until that first real build.
- **Links:** Phase 1.01 completion report §2, §3, §7; `00_stack-and-config.md` (2026-06-24 scaffold entry); D-006; Phase 1.02.

### D-012 · 2026-06-24 · Empty in-target folders are not kept with `.gitkeep` (it breaks the Xcode build)
- **Status:** Accepted
- **Context:** Phase 1.01 used `.gitkeep` files to keep the reserved empty source folders (`ECHO/Models`, `ECHO/Audio`, `ECHO/Haptics`, and the now-removed `ECHO/Views`) tracked in git, assuming Xcode's file-system synchronized groups would ignore dotfiles. That assumption was wrong. On Lazar's first real Xcode build (Phase 1.02), the compile failed with `Multiple commands produce '…/ECHO.app/.gitkeep'` plus two "duplicate output file" warnings: synchronized groups (`PBXFileSystemSynchronizedRootGroup`) treat `.gitkeep` as a **bundle resource** and copy it, so the three identically-named `.gitkeep` files all collided at one output path.
- **Decision:** **Remove the `.gitkeep` files from every folder inside a synchronized group** (`ECHO/`, `ECHOTests/`). Those reserved folders are now simply untracked while empty and reappear in git the moment their first real source file is added (Models in Phase 1.03; Audio/Haptics in Part 2). `.gitkeep` files **outside** any synchronized group (`Levels/`, `docs/design-handovers/`) are not copied into a target and were kept.
- **Alternatives considered:** (a) **Exclude each `.gitkeep` from the target via a `PBXFileSystemSynchronizedBuildFileExceptionSet`** — the "correct" Xcode mechanism, keeps the folders tracked, but required hand-editing the `.pbxproj` with no way to verify it in this no-Xcode environment; a malformed project file is a worse outcome for a non-developer owner than three temporarily-untracked empty folders — rejected as too risky to apply blind. (b) **Rename the keepers to unique names** (e.g. `.keep-models`) — avoids the collision but still bundles junk files into the shipping app — rejected. (c) **Leave it** — the project does not build — rejected.
- **Consequences:** The build is unblocked with a zero-risk change. **Honest downside:** the empty `Models/`, `Audio/`, `Haptics/` folders are not visible in a fresh clone (or in Xcode's navigator) until populated — a minor, self-correcting cosmetic loss for a solo repo. If keeping those folders tracked ever matters, revisit option (a) once a working Xcode can validate the exception set. **Repo rule going forward:** never put a `.gitkeep` (or any duplicate-named throwaway) inside `ECHO/` or `ECHOTests/`. Lazar must Clean Build Folder (⇧⌘K) and rebuild to clear the stale DerivedData entries.
- **Links:** Phase 1.02 completion report §7 (addendum); `00_stack-and-config.md` (2026-06-24 Phase-1.02 entry); supersedes the dotfile assumption in the Phase 1.01 report (§7) and D-011's synchronized-groups choice (refines, does not reverse it).

### D-013 · 2026-06-24 · Concurrency model: `@MainActor` observable state, `nonisolated` pure value types
- **Status:** Accepted
- **Context:** The app target builds in Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every unannotated declaration is inferred main-actor-isolated. Phase 1.03 adds the first real model (`GameState`, `GridCoordinate`, `Direction`) and the first real tests; the **test target does not** set that default isolation. We had to decide how the model is isolated so it is correct under strict concurrency **and** cleanly unit-testable, and the prompt didn't specify this.
- **Decision:** Make the observed model **`@MainActor @Observable final class GameState`** (it is the SwiftUI-observed UI state, so the main actor is its natural home). Make the pure value types **`GridCoordinate` and `Direction` explicitly `nonisolated` and `Sendable`** so they are isolation-free values usable from any context (view, model, and future off-main `Codable` level decoding). Mark the XCTest case **`@MainActor`** so it can drive the main-actor model directly.
- **Alternatives considered:** (a) Leave the value types unannotated — under the MainActor default they'd silently become main-actor-isolated, which is wrong for pure coordinates and would block off-main use such as JSON level decoding in Phase 1.06 — rejected. (b) Make `GameState` a `struct` instead of an `@Observable` class — loses Observation's automatic view updates and the reference semantics the shared turn engine wants — rejected. (c) Add `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to the test target instead of annotating the test class — needs a blind `.pbxproj` edit unverifiable without full Xcode (cf. D-012) when a one-line source annotation does the job — rejected.
- **Consequences:** Model and tests type-check clean under their respective isolation regimes (verified locally: `swiftc -default-isolation MainActor` for the app regime, plain default for the test regime) and the move logic runs green in a standalone harness. Pure values stay decode-ready and thread-free for later phases. **Honest downside:** every future test case that touches `GameState` must also be `@MainActor` (or `await` it), and the value types carry explicit `nonisolated` annotations that read as unusual until you know the project defaults to main-actor isolation.
- **Links:** Phase 1.03 completion report §3; `00_stack-and-config.md` (2026-06-24 Phase-1.03 entry); D-006 (Swift 6.4 / Xcode 27), D-012 (no blind `.pbxproj` edits).

### D-014 · 2026-06-24 · Echo replay model: an echo is a recorded `[Direction]`; its position is a pure function of (start, recording, turn)
- **Status:** Accepted
- **Context:** Phase 1.04 needs echoes that replay a folded run in exact, repeatable lockstep with the single shared turn counter (Plan §14, points 1–2). We had to choose how an echo stores its run and how its on-board position is derived each turn.
- **Decision:** An `Echo` stores the **ordered list of moves** it walked (`[Direction]`) plus a stable `UUID` id. Its cell at any turn `t` is computed on demand as `start` advanced by the **first `min(t, k)`** of its `k` recorded moves (`Echo.position(start:turn:)`). There is **no per-turn imperative "step each echo" pass** and no stored per-turn position cache: because position is a pure function of `(start, moves, turn)`, every echo advances automatically as `turn` ticks. A direct consequence of the `min(t, k)` clamp is that an **exhausted echo stands still on its last tile** for every `t ≥ k` — the behaviour that later lets an echo "hold" a switch, so it is required, not incidental.
- **Alternatives considered:** (a) **Store an echo as the sequence of absolute cells** it occupied per turn — equivalent at turn ≤ k but redundant (the start + moves already determine it), larger, and it would need its own clamp/standing-still logic baked in — rejected as derived data masquerading as state. (b) **Imperatively step each echo one cell whenever the player moves** (mutating a per-echo cursor) — introduces mutable replay state that can desync from `turn`, exactly the "separate step pass to get wrong" the turn-counter design exists to avoid — rejected. (c) Store moves but **re-clamp each replayed step to the board** — unnecessary in 1.04 because recorded moves were legal from `start` on this unchanged board; deferred until walls/level data could make a recorded path illegal — rejected for now.
- **Consequences:** Replay is trivially exact and testable (the replay-fidelity guarantee is just "the pure function equals the live path" — proven by the harness/tests), and the standing-still rule falls out for free. **Honest downside:** position is recomputed from the start each time it's read (O(k) per echo per turn); negligible for the small runs this game uses, but if echo counts/lengths ever grow large enough to matter, add a memoised cursor behind the same pure interface. When walls arrive (Phase 1.05+), revisit whether a recorded path needs re-validation (alternative c).
- **Links:** Plan §14 (points 1–2); Phase 1.04 completion report §2–§3; `ECHO/Models/Echo.swift`, `ECHO/Models/GameState.swift` (`position(of:)`); D-015, D-016.

### D-015 · 2026-06-24 · Fold rewinds the whole board to turn 0; folding an empty run is a no-op
- **Status:** Accepted
- **Context:** Plan §14 point 2 says folding "rewinds time to turn zero." We had to pin exactly what `fold()` does to the live board and what happens when there is nothing to fold.
- **Decision:** `fold()` banks the current run as a new echo, then **rewinds the entire board**: player back to `start`, `turn` back to 0, current run emptied. Every previously-banked echo therefore returns to `start` too — automatically, since each echo's position at turn 0 is `start` (D-014), with no extra reset code. Folding when the **current run is empty is a no-op**: no zero-move echo is ever created and no rewind happens (so the control can be pressed harmlessly at any time). `fold()` returns a `Bool` reporting whether a fold occurred, mirroring `move(_:)`'s committed-step signal.
- **Alternatives considered:** (a) **Fold without rewinding** (bank the echo but leave the player where it is and keep the turn running) — contradicts the spec's "time rewinds to turn zero" and breaks the mental model that every fold restarts the room with one more self — rejected. (b) **Allow an empty fold** to create a zero-move echo and/or rewind — pollutes the echo list with do-nothing echoes and lets a stray button press reset a run the player didn't intend to fold — rejected. (c) Make `fold()` return `Void` — loses the cheap "did anything happen" signal a future undo/feedback path may want — rejected (matches D-013's `@discardableResult` reasoning for `move`).
- **Consequences:** One fold = one more self + a clean restart from `start`, which is the core loop the whole game is built on; the empty-run guard makes the debug/real controls idempotent and safe. **Honest downside:** because the rewind is total, a future "step back"/undo (Phase 1.07) cannot be a simple inverse of `fold` — it will need its own history handling; noted for that phase.
- **Links:** Plan §14 (point 2); Phase 1.04 completion report §3; `ECHO/Models/GameState.swift` (`fold()`); D-014; Phase 1.07 (reset run / step back).

### D-016 · 2026-06-24 · Collision is deferred to Phase 1.05 — echoes are intentionally pass-through in 1.04
- **Status:** Accepted
- **Context:** Plan §14 point 4 ("touching an echo dissolves you and restarts the current run") is the game's one hard constraint, but the Phase 1.04 brief scopes it **out** — 1.04 only records and replays. We had to decide whether to add any collision handling now.
- **Decision:** Implement **no collision** in 1.04. The live player and any number of echoes may occupy the same tile, and the player walks straight through echoes with no effect. Echoes are drawn beneath the player with hit-testing off, and `move(_:)` is unchanged except for appending to the current run. This pass-through behaviour is **intended for this phase**, not a bug, and is recorded so a future reader doesn't "fix" it prematurely.
- **Alternatives considered:** (a) **Add collision now** while the replay code is fresh — couples two phases, makes 1.04 harder to verify in isolation, and risks landing collision before the room/exit context that gives it meaning — rejected; keeping collision out is what keeps this phase clean (per the brief). (b) Add a half-measure (e.g. detect a collision but don't act on it) — dead, untested code — rejected.
- **Consequences:** 1.04 stays small and provably correct (record/replay only). **Honest downside:** the build is temporarily "wrong" against the full spec — you can stand on your own echo — until Phase 1.05 adds collision (same-tile-same-turn = dissolve + restart the current run, existing echoes persisting). The pure position functions from D-014 are exactly what 1.05 will compare for that check.
- **Links:** Plan §14 (point 4); Phase 1.04 completion report §4; Phase 1.05 (collision); D-014.

### D-017 · 2026-06-24 · `GameState` ownership lifted to `ContentView`; fold/clear driven from a throwaway debug bar
- **Status:** Accepted
- **Context:** Until now `BoardView` owned its `GameState` via `@State`. Phase 1.04 needs *Fold*/*Clear* controls and a turn/echo readout that act on the **same** model the board renders, and the brief says to keep those controls out of `BoardView` (so the board stays "just the board" and the temporary bar is trivial to delete later).
- **Decision:** Move ownership of the `GameState` up to **`ContentView`** (`@State private var state`), and have `BoardView` take it as an injected `let state: GameState` (the Observation framework still re-renders the board when the state it reads changes). `ContentView` lays out the board above a **throwaway debug bar** — `Fold` → `state.fold()`, `Clear` → `state.clearEchoes()`, and a `turn N · echoes M` readout — placed **below** the board, outside its swipe/tap area, and marked in a comment as temporary UI to be removed in Parts 2–3. `Clear` is an explicit debug stand-in, **not** the real "reset run" (Phase 1.07).
- **Alternatives considered:** (a) **Keep state in `BoardView`** and add the buttons inside it — violates the brief's "board stays just the board," and risks the controls sitting inside the gesture area — rejected. (b) Hoist the state into a shared `@Observable` **environment object** — more ceremony than a one-screen app needs right now; a plain `let` injection is the smallest correct step (and was anticipated by the 1.03 report) — rejected for now, revisit if the view tree deepens. (c) Put the debug bar in an **overlay on top of the board** — would intercept gameplay input — rejected in favour of a separate strip below.
- **Consequences:** Board and debug controls share one source of truth with a minimal, idiomatic Observation wiring; the bar is isolated to `ContentView` and deletes cleanly. **Honest downside:** `ContentView` is no longer purely presentational (it owns game state), and the debug bar is deliberately unstyled throwaway UI that must actually be removed in Parts 2–3 — tracked in `current-state.md` and the completion report so it isn't forgotten.
- **Links:** Phase 1.04 completion report §3; `ECHO/App/ContentView.swift`, `ECHO/Views/BoardView.swift`; Phase 1.03 report §7 (anticipated this lift); D-013 (Observation/`@MainActor` model); Phase 1.07 (real reset run / step back).

### D-018 · 2026-06-24 · Echo collision counts cross-paths (swaps), not only shared tiles
- **Status:** Accepted
- **Context:** Phase 1.05 makes echoes lethal. Two collision models exist: land-on only (die only if you end a turn on an echo's tile) vs. land-on + cross-paths (also die if you and a thing that moved this step traded adjacent tiles).
- **Decision:** Both count — the collision predicate fires on land-on OR cross-paths. Past selves are solid walls you can never pass through.
- **Alternatives considered:** Land-on only — rejected because the strict rule is the correct general predicate, it future-proofs the moving hazards / sliding blocks arriving in Phase 1.06 (which CAN cross paths with the player), and it costs nothing to write once now versus revisiting collision later.
- **Consequences:** A defensive cross-paths clause that is currently unreachable against echoes — player and echoes share an origin and one-step-per-turn cadence, so they are always the same checkerboard parity at a given turn, while a swap requires opposite-parity adjacent tiles. So for echoes specifically this is behaviourally identical to land-on only today; the clause first becomes reachable with independently-moving hazards (Phase 1.06).
- **Links:** Phase 1.05; Phase 1.06 (hazards); ECHO-Plan §14 point 4; relates to D-016 (which deferred collision to this phase).

### D-019 · 2026-06-25 · Switches/doors are pure per-turn derivations; doors block (never kill); switches held by player/echoes only
- **Status:** Accepted
- **Context:** Phase 1.06 adds switches and doors. We had to decide whether held/open state is stored mutable state advanced each turn, or derived; what "open at turn N" means for the player's move; and whether hazards can hold switches.
- **Decision:** Held/open state is **derived, not stored**. A switch is held at turn N iff the player or any echo occupies its cell at turn N; a door is open at turn N iff **every** switch in its `heldBy` is held (AND). The player may enter a door cell on the N→N+1 step only if the door is open at turn N — the **visible state before** the move; a closed door is a no-op block exactly like a wall. **Doors never kill.** Hazards do **not** hold switches. All derivations are evaluated at the current turn (the only turn the live engine and rendering ever ask about), reading `player`/`turn`/`echoes`.
- **Alternatives considered:** (a) Store mutable held/open booleans and toggle them each turn — reintroduces the desync-prone per-turn bookkeeping the pure-position design (D-014) exists to avoid — rejected. (b) Evaluate door-open at turn N+1 (after the move) — would let the player walk into a door that closes under them and contradicts "visible state before the move" — rejected. (c) Let hazards hold switches — muddies the timing model and isn't wanted by any room — rejected.
- **Consequences:** Door/switch logic is a handful of pure predicates with no cache to invalidate, trivially testable. **Honest downside:** the derivations are only correct *at the current turn* (the player's history isn't stored), which is fine because no live use ever needs another turn; documented on the methods so a future caller doesn't pass an arbitrary turn expecting a historical answer.
- **Links:** Plan §14 (point 3); Phase 1.06 completion report §3; `ECHO/Models/GameState.swift` (`isSwitchHeld`/`isDoorOpen`/`isClosedDoor`); D-014, D-020.

### D-020 · 2026-06-25 · Echoes and hazards replay verbatim, ignoring walls/doors; verbatim replay is the keystone, not special-cased
- **Status:** Accepted
- **Context:** With walls and doors in the world, a replaying echo or an authored hazard path could in principle point at a wall or a door that is closed under it on this run. We had to decide whether replay re-validates legality each turn.
- **Decision:** Neither echoes nor hazards re-evaluate path legality during replay — each reproduces its recorded/authored path **verbatim**. Walls are static and authored paths are wall-legal, so walls never bite. Doors can differ between runs, but the **door nuance is handled by level design**: proof rooms are authored so no echo/hazard ever needs to traverse a tile that is a closed door under it (the canonical use is an echo standing on a switch while present-you walks the door tile). Verbatim replay is the keystone of the whole mechanic and is **not special-cased**.
- **Alternatives considered:** (a) Re-clamp/re-validate each replayed step against walls and doors — breaks exact, repeatable replay (the same recording could diverge between runs), defeating the determinism the game is built on — rejected (this is alternative (c) deferred in D-014, now resolved as "don't"). (b) Make echoes/hazards solid against doors — adds collision math the engine deliberately avoids — rejected.
- **Consequences:** Replay stays a pure function of (start, recording/path, turn) — exact and testable. **Honest downside:** correctness now partly depends on **authoring discipline**; a carelessly authored room could send an echo "through" a closed door visually. Accepted because authored rooms are small and reviewed, and the alternative compromises the core guarantee.
- **Links:** Plan §14 (points 1–2); Phase 1.06 completion report §3; D-014 (alternative c), D-019.

### D-021 · 2026-06-25 · Hazards loop their path by default; lethal on contact, not solid, don't hold switches
- **Status:** Accepted
- **Context:** Phase 1.06 introduces moving hazards. We had to define their motion past the end of the authored path, and exactly how they interact with the player and the world.
- **Decision:** A hazard's `path` is applied one step per turn from its `start`. `loops` defaults to **`true`** (the patrol repeats, indexing the path modulo its length); `loops:false` makes it **stand still on its last tile** once exhausted (the same rule as an echo, D-014); an empty path is stationary. Hazards are **lethal to present-you on contact** (land-on OR cross-paths) but are **not solid** (you can step onto a hazard's tile — and die — they never block a move) and do **not** hold switches.
- **Alternatives considered:** (a) Hazards stand still when exhausted (like echoes) by default — a patrol that stops after one sweep is rarely what a hazard wants; looping is the common case, so it is the default, with `loops:false` available — rejected as the default. (b) Make hazards solid (block movement) — turns them into moving walls and changes the puzzle from timing to pathing, and isn't the intended threat — rejected. (c) Let hazards hold switches — see D-019 — rejected.
- **Consequences:** Hazards read as patrolling threats you time your crossing against; their position is a pure function like an echo's, so replay/tests stay deterministic. **Honest downside:** a looping hazard's position is O(turn) to compute (no `min` clamp like an echo), negligible for real rooms but worth memoising behind the same pure interface if turn counts ever grow large (mirrors D-014's note).
- **Links:** Plan §14 (point 3); Phase 1.06 completion report §3; `ECHO/Models/Hazard.swift`; D-014, D-022.

### D-022 · 2026-06-25 · Collision now evaluates echoes AND hazards; the cross-paths/swap branch goes live against hazards
- **Status:** Accepted
- **Context:** `playerCollides(...)` implemented land-on OR cross-paths since 1.05 (D-018), but the swap branch could never fire against echoes (parity-locked). Hazards move independently and can move opposite the player.
- **Decision:** Collision evaluates **both** echoes and hazards with the same land-on/cross-paths predicate. Because a hazard can trade the same adjacent pair with the player on one step, the **cross-paths/swap branch (D-018) is now live** — covered by a dedicated test that isolates a swap (the hazard's turn-N tile is the player's *old* cell, so land-on does not fire).
- **Alternatives considered:** Land-on only for hazards — would let a player "pass through" a hazard by swapping with it head-on, which is exactly the case the strict predicate exists to catch — rejected. Writing a second, hazard-specific predicate — needless duplication; the existing predicate generalises by construction — rejected.
- **Consequences:** Past selves and hazards are both impassable in the strict sense; the defensive clause written in 1.05 is now exercised in real play. **Honest downside:** none of note — the predicate was designed for this; 1.06 just feeds it hazards.
- **Links:** Phase 1.05; Phase 1.06 completion report §3; `ECHO/Models/GameState.swift` (`playerCollides`); D-018.

### D-023 · 2026-06-25 · On a committed step, collision is evaluated before win; an exit-and-lethal tile is a death
- **Status:** Accepted
- **Context:** A single committed step can both reach the exit and touch an echo/hazard on the exit tile. We had to fix the order.
- **Decision:** After a committed step, **collision is checked first**. If present-you died, the run restarts and there is no win. Only a survived step checks the exit. So a tile that is **both the exit and lethal is a death** — you must reach the exit *alive*.
- **Alternatives considered:** Check win first (reaching the exit wins even if something is on it) — trivialises rooms where a hazard guards the exit and contradicts "reach the exit alive" — rejected.
- **Consequences:** Exit-guarding hazards/echoes are meaningful; the rule is one ordering in `move(_:)`. **Honest downside:** none of note; it matches the spec's intent.
- **Links:** Plan §14 (point 5); Phase 1.06 completion report §3; `ECHO/Models/GameState.swift` (`move`); D-022.

### D-024 · 2026-06-25 · The v1 level JSON format is locked
- **Status:** Accepted
- **Context:** Rooms are authored as plain JSON (Plan §6/§7). We had to lock a schema before authoring so rooms don't drift field names.
- **Decision:** Lock the v1 format: top-level `id`, `name`, `width`, `height`, `start`, `exit` (single), `echoBudget`, and the element arrays `walls`, `switches`, `doors`, `hazards`. Coordinates are `{ "row": R, "column": C }`, origin top-left, 0-indexed (a `GridCoordinate`). `switches` are `{ id, cell }`; `doors` are `{ id, cells[], heldBy[] }` where `heldBy` is an **AND-array** and `cells` is an array (so multi-tile / multi-switch doors need no format bump); `hazards` are `{ id, start, path[], loops }` where `path` is a `Direction` name list and `loops` defaults `true`. The element arrays may be omitted (decode to empty); the core fields are required.
- **Alternatives considered:** (a) Multi-`exit` / non-id-based references now — unused by any planned room and adds surface to get wrong — rejected; deferred to a future format bump. (b) Require every array explicitly — noisier authoring with no safety gain since absence is unambiguous — rejected (absent = empty).
- **Consequences:** Rooms are small, hand-editable, and stable to author against; the arrays future-proof multi-tile/multi-switch doors. **Honest downside:** a malformed room fails to decode and (per D-025's loader) falls back to a bare board rather than surfacing the error loudly in-app; acceptable for a solo dev who watches the room load.
- **Links:** Plan §6/§7; Phase 1.06 completion report §2; `ECHO/Models/Level.swift`; D-025.

### D-025 · 2026-06-25 · Levels live in repo-root `Levels/` and are bundled via a third file-system synchronized root group on the app target
- **Status:** Accepted
- **Context:** Plan §7 places room JSON in repo-root `Levels/` (not under `ECHO/`). The brief requires the JSON bundled into the app target and loadable at runtime, and says to surface any bundling obstacle rather than silently relocating the folder. The project uses file-system synchronized groups for `ECHO/` and `ECHOTests/`.
- **Decision:** Keep the rooms in repo-root **`Levels/`** and add a **third `PBXFileSystemSynchronizedRootGroup` (`Levels`)** to the app target's `fileSystemSynchronizedGroups` — the same mechanism already used for the two source roots, so Xcode classifies the `.json` files as bundle resources automatically. The loader (`LevelLoader`) reads by id with `Bundle.main.url(forResource:withExtension:)` and falls back to a `Levels/` subdirectory lookup, so it works whether the bundling flattens (synchronized group) or nests (folder reference). The obsolete `Levels/.gitkeep` was removed (the folder now holds real files; outside `ECHO/`, so no D-012 collision).
- **Alternatives considered:** (a) **Relocate `Levels/` under `ECHO/`** so the existing `ECHO` synchronized group bundles it — explicitly discouraged by the brief and contradicts Plan §7 — rejected. (b) Add the rooms as an explicit folder reference + `PBXBuildFile` in the Resources phase — more `.pbxproj` surface than the synchronized-group entry and a less faithful match to the project idiom — rejected. (c) A resource group with individual file references — most edits, most fragile to hand-author — rejected.
- **Consequences:** Rooms stay where the docs say and bundle with a minimal, symmetric project-file edit. **Honest downside — unverified blind `.pbxproj` edit:** this environment has only Command Line Tools (no `xcodebuild`/Xcode), so the edit could **not** be build-verified here. It mirrors the existing synchronized-group entries exactly, but per D-012's "no blind `.pbxproj` edits we can't verify" caution it is flagged in the completion report for Lazar to confirm on first ⌘R that the JSON bundles and the loader finds it (if not, the in-app fallback shows a bare board rather than crashing).
- **Links:** Plan §7; Phase 1.06 completion report §2/§7; `ECHO.xcodeproj/project.pbxproj`; `ECHO/Models/Level.swift` (`LevelLoader`); D-012 (synchronized groups / no blind edits), D-024.

### D-026 · 2026-06-25 · Win is in-session only for 1.06 (a `GameState` flag); persistence and Level Select are deferred to Part 3
- **Status:** Accepted
- **Context:** 1.06 needs a win signal, but full menus, a real win overlay, and saving solved levels are later scope (Part 3).
- **Decision:** Model the win as a `private(set) var hasWon` on `GameState`, set when present-you reaches the exit alive and cleared on reset/reload. It locks input (`move`/`fold` no-op) until the throwaway debug bar's *Next* loads the next room or *Clear* resets. **No UserDefaults persistence and no Level Select** — both deferred to Part 3.
- **Alternatives considered:** Persist solved rooms now — out of scope and couples 1.06 to a save format not yet designed — rejected. A real win overlay now — that's Part 3 / 3.03 — rejected; the debug "Solved ✓ / Next" is a deliberate stand-in.
- **Consequences:** A minimal, testable win with no storage. **Honest downside:** progress is lost on relaunch (no persistence) and "Next" just cycles a hardcoded list — both intended for this phase and tracked for Part 3.
- **Links:** Plan §14 (point 5); Phase 1.06 completion report §3; `ECHO/Models/GameState.swift` (`hasWon`), `ECHO/App/ContentView.swift`; Part 3 (3.03 menus, persistence).

### D-027 · 2026-06-25 · The echo budget is enforced at fold time (fold refused at the cap)
- **Status:** Accepted
- **Context:** Each room carries an `echoBudget` (max echoes). We had to decide where the cap is enforced.
- **Decision:** Enforce it in `fold()`: a fold is refused (a no-op, returning `false`) when `echoes.count >= echoBudget`, alongside the existing empty-run and post-win guards. A refused fold neither banks an echo nor rewinds the run. The bare default board uses `echoBudget == .max` (uncapped) so non-level play and the existing fold tests are unaffected.
- **Alternatives considered:** Enforce at the UI layer (disable the fold button at the cap) — leaves the model accepting over-budget folds and untestable in isolation — rejected; the cap is a game rule, so it lives in the model. Throw/return an error — heavier than the established `Bool` "did it happen" signal (D-015) — rejected.
- **Consequences:** The budget is a single model guard, unit-tested, with the UI free to reflect it (the debug bar shows `echoes M / budget B`). **Honest downside:** none of note.
- **Links:** Plan §14 (point 1); Phase 1.06 completion report §3; `ECHO/Models/GameState.swift` (`fold`); D-015.

---

### Decision-log conventions
- **Append, never rewrite.** Past entries are frozen except their **Status** line.
- **One decision per entry.** Bundling several makes them impossible to supersede independently later.
- **Always include** an Alternative considered and a Consequence (the honest downside). An entry with neither is an assertion, not a decision.
- **Reversals:** mark the old entry `Superseded by D-0YY`, then add a new entry that links back to it.
- **IDs** are zero-padded and sequential (`D-001`, `D-002`, …), permanent, never reused.
