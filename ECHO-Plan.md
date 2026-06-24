# ECHO — Plan

> The master spec for the finished game. This is **aspirational** — it describes the intended end state. If it ever disagrees with `_project-state/current-state.md`, **the live code wins**; this Plan is the intent, `current-state.md` is the reality.

---

## 1. Goals and success criteria

Build ECHO as a real, native iOS game that runs on Lazar's iPhone via free sideload — a calm, turn-based, black-and-white puzzle whose only verb is recording yourself and replaying it as a ghost. There is no commercial goal; the bar is simply **a fun, good-looking game Lazar enjoys playing.**

"Launched" means all three Parts are complete and the finished game is installed on the iPhone and keeping itself alive (see §15 for the hard checklist).

---

## 2. About the project

A personal passion project, owned and played by Lazar. Offline, single-player, no accounts, no internet, no monetization. The experience: a monochrome grid; the fold/echo mechanic; a finite hand-crafted Campaign with a clear ending; and an endless Echo Run arcade mode. The signature reward is that a solved room turns into a loop of percussion generated from the player's own moves.

**The core relationship that makes it original:** your past selves are at once the *tools* that solve a room and the *hazards* you must avoid — and because they replay deterministically, every self you add constrains every future self.

---

## 3. Information architecture (app structure)

This is an app, not a website — the "IA" is a screen flow, not a URL map:

```
Title
 └─ Main Menu
     ├─ Campaign ──► Level Select ──► Room (core gameplay) ──► Win overlay
     ├─ Echo Run ──► Arcade board ──► Game-over overlay
     └─ Settings
```

---

## 4. Pages (screens) at launch

1. **Title** — game name; one tap to enter.
2. **Main Menu** — Campaign / Echo Run / Settings.
3. **Level Select** — a grid of rooms; solved ones marked.
4. **Room** — the core gameplay screen: the grid, the player square, echoes, and the controls (move, fold, reset run, step back).
5. **Win overlay** — a gentle "solved" moment with a next-room button.
6. **Echo Run** — the bounded arcade survival board.
7. **Echo Run game-over** — score plus an instant retry.
8. **Settings** — invert mode, sound toggle, haptics toggle, echo-trail aid toggle.

---

## 5. Design system (locked direction; finalized in Part 2 Phase 2.01)

**One ink, one paper.** A soft, slightly warm off-white background. **You** are a solid black rounded square — maximum contrast, always the clearest thing on screen. **Echoes** are the same shape in translucent grey with a thin outline, so a crowded board still reads as "one black me, several grey thems." Walls are solid black; the exit is a hollow ring; switches are small open circles that fill when held; doors are simple lines that retract when held.

**Accent.** Black/white/grey only, plus **one optional muted accent color** used *solely* for the single thing the player must reach right now (active exit, or the switch currently keeping them alive). The accent is a bonus signal layered on top of shape, position, and motion — **never the only cue**, since meaning must never live in color alone.

**Motion targets.** Each step is an ease-in-out slide of ~120 ms with a slight squash-and-stretch and a soft snap on arrival. The fold is a brief, weighty event (a short hit-pause of a few frames, a quiet ripple, the grey echo peeling off your path). Death is a calm few-frame freeze then a soft particle fizz, with an instant restart.

**Typography.** A single clean system font (Apple's SF). Minimal, legible, never decorative.

**Modes.** An **invert mode** (white-on-black) ships for preference and accessibility. An optional **echo-trail aid** shows each echo's upcoming path as a faint dotted line.

**Off the table:** color-coded meaning, busy/cluttered UI, skeuomorphism, dark patterns, retention loops.

---

## 6. Tech stack (locked)

| Layer | Choice | Why it fits ECHO |
|---|---|---|
| Language | Swift 6.4 | The native iOS language; bundled with Xcode 27. |
| UI foundation | SwiftUI | The board is a grid of cells driven by state — SwiftUI's exact model — and it animates ease-in-out slides, squash-and-stretch, and snaps natively. |
| Build tool / IDE | Xcode 27 | Compiles and packages the app; required to install onto an iOS 27 device. Needs macOS 26.4+ on Apple silicon. |
| Dependencies | Swift Package Manager | Built-in; v1 likely needs **zero** external packages (a feature — fewer things to break). |
| Animation | SwiftUI built-in | Spring, easing, transitions — no third-party animation library. |
| Particles | SwiftUI Canvas first; thin SpriteKit layer only if Canvas can't manage | The death fizz and fold ripple. A Part 2 polish layer, never the foundation. |
| Audio | AVAudioEngine | Plays each move's tick with precise timing so stacked echoes layer into a rhythm locked to the turn counter — the signature feature. |
| Haptics | Core Haptics + UIFeedbackGenerator | Selection / impact / error / success taps, pre-warmed, paired with a visual change, mapped only to meaningful moments. |
| Level data | Plain JSON files in `Levels/` | Each room (walls, switches, doors, exit, echo budget) is a small hand-editable, version-controlled file. |
| Save data | UserDefaults | Tracks solved levels and the Echo Run high score. No database. |
| Tests | XCTest | The core is pure deterministic logic (replay, "same tile on the same turn = collision," win detection) — highly testable. |
| Source control + backup | Git + GitHub (`DinovLazar/echo`, public) | Where code and docs live and back up. Single branch `main`. |
| Distribution | Free Apple ID signing + SideStore | A real app at $0; SideStore auto-refreshes the 7-day certificate. |

**Total cost: $0.** The only paid option anywhere near the project — the $99/yr Apple Developer Program — is deliberately not used (see D-001).

---

## 7. File and folder structure

Top level of `/Users/lazar/Projects/ECHO`:

```
ECHO/
├── ECHO.xcodeproj              ← the Xcode project
├── ECHO/                       ← Swift source code
│   ├── App/                    ← app entry point, root views
│   ├── Models/                 ← grid, turn engine, echo/replay logic, win checks
│   ├── Views/                  ← SwiftUI screens and the board
│   ├── Audio/                  ← generative percussion (Part 2)
│   ├── Haptics/                ← Core Haptics mapping (Part 2)
│   └── Resources/              ← assets, fonts
├── Levels/                     ← hand-authored room JSON files
├── ECHOTests/                  ← XCTest unit tests
├── docs/
│   └── design-handovers/       ← RESERVED: Design phases save handovers here
└── _project-state/             ← RESERVED: live project-state docs
    ├── current-state.md
    ├── file-map.md
    ├── 00_stack-and-config.md
    └── completions/            ← one completion report per phase
```

> **Adapted convention (D-007):** the base playbook assumed a Windows web project with a `src/_project-state/` path. iOS apps have no `src/` folder, so project-state lives at `_project-state/` at the repo root, and completion reports go in `_project-state/completions/`. `docs/design-handovers/` is unchanged.

---

## 8. Integrations

**None.** ECHO is offline and single-player. No email, CRM, booking, payments, analytics, or third-party services.

## 9. SEO and schema strategy

**N/A** — not a website.

## 10. Bilingual / multi-language approach

**N/A** — English only, and the game is nearly text-free by design.

## 11. Lead-capture mechanics

**N/A** — nothing to capture; no marketing surface.

## 12. AI features specification

**None in the game.** (Claude Code building the app is tooling, not an in-game feature.)

## 13. Automation specification

**None.**

---

## 14. The Echo mechanic (the spec that drives the build)

1. Each level gives a goal (reach the exit) and a small **echo budget** — e.g. "solve this using at most 3 selves." That budget is the puzzle's currency.
2. You walk a run. When you **fold** it, time rewinds to turn zero and that run becomes a grey echo replaying in sync with a single shared **turn counter**. The world only advances when you take a step; every echo takes its next recorded step at the same time.
3. Echoes change the world: standing on a switch holds a door open; their body blocks a moving hazard or a sliding block; being on the right tile on the right turn trips a timed mechanism.
4. **Touching an echo dissolves you** and restarts the *current* run (existing echoes persist). This is the one hard constraint — it turns each room into a spatial-timing problem.
5. You win the instant present-you reaches the exit, which usually means your echoes are, at that moment, holding open everything that needs holding.

**Supporting controls:** **reset run** (scrap the current run without folding it; existing echoes stay) and **step back** (undo a single move; quality-of-life). A new player only needs *move* and *fold* to understand the game.

**Two modes from one verb:**
- **Campaign** — finite, hand-crafted rooms with a clear ending. Deterministic puzzles solved in N selves. The heart of the game.
- **Echo Run** — a bounded board where, every few turns, a new echo of your *entire* movement history spawns and retraces your path. You survive an ever-thickening crowd of your own past for distance/score. Same controls and look, opposite pressure.

---

## 15. Acceptance criteria — what "launched" means

- [ ] App builds in Xcode and installs on the iPhone via SideStore; auto-refresh keeps it alive past 7 days.
- [ ] All four controls work: move, fold, reset run, step back.
- [ ] Folding records a run and replays it as a grey echo locked to the shared turn counter.
- [ ] Touching an echo dissolves you and restarts the run; existing echoes persist.
- [ ] Reaching the exit wins the room; the full Campaign room set is solvable with a clear ending.
- [ ] Feel is in: ease-in-out motion, death fizz, fold ripple, the generative move-music, and mapped haptics.
- [ ] Echo Run is playable with a saved high score.
- [ ] Settings work: invert mode, sound/haptics toggles, echo-trail aid.
- [ ] Input-to-response under ~100 ms; restarts instant and blame-free; target 60fps; no crashes in a normal play session.

---

## 16. Pre-build parallel-track tasks (Cowork-led where possible)

- Create the GitHub repo `DinovLazar/echo` (public). *(Cowork.)*
- Install Xcode 27 on the Mac from the App Store. *(Lazar, guided.)*
- One-time SideStore setup on the iPhone with the Mac. *(Lazar, guided — needs his Apple ID; likely sequenced right after the first build in Phase 1.02.)*
- Decide on the optional accent color and rough muted tone. *(Lazar + Design, settled in Phase 2.01.)*

---

## 17. Phase breakdown

The full phase list lives in `ECHO-Phase-Plan.md`. Summary of the three parts:

- **Part 1 — Foundation + core mechanic (grey boxes).** Scaffold → first device install → grid + move → fold (record/replay) → collision + restart → win + level data → reset + step back → first ~10 rooms. *Milestone: core proven fun in grey boxes, on the real phone.*
- **Part 2 — The juice.** Visual design pass (Design) → motion → particles → generative audio → haptics → Settings screen. *Milestone: the game feels right.*
- **Part 3 — Content + arcade + workflow.** Full campaign → Echo Run mode → menus + polish → final feel/performance → sideload/refresh workflow. *Milestone: launched.*
