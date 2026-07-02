# ECHO — Phase Plan

> The living index of every phase. One phase = one completion report = one git commit. Phase numbering: `1.01`, `1.02`, … then `2.01`, etc. As phases complete, note status here. Scope is 1–3 sentences; the full brief lives in each `Part-X-Phase-YY-<Role>.md` file when the phase is opened.

---

## Part 1 — Foundation + core mechanic (grey boxes)

| # | Phase | Type | Scope |
|---|---|---|---|
| 1.01 | Scaffold | Code (+ Cowork for repo) | Create the Xcode project, the `DinovLazar/echo` repo, the folder structure, both reserved folders (`docs/design-handovers/`, `_project-state/`), and seed the project-state docs. |
| 1.02 | First device install | Code + Lazar | Build a bare "hello grid" and sideload it to the iPhone via SideStore, proving the whole build-and-install pipeline before any real gameplay work. |
| 1.03 | Grid + move | Code | Render the grid; move the black square one tile per tap/swipe; turn-based stepping (the world advances only on a move). |
| 1.04 | Fold (record & replay) | Code | Record a run, fold it, and replay it as a grey echo locked to the shared turn counter. **The keystone.** |
| 1.05 | Collision + restart | Code | Touching an echo dissolves you and restarts the current run; existing echoes persist. |
| 1.06 | Win + level data | Code | Exit detection; the JSON room format (walls, switches, doors, exit, echo budget); load a room from a file. |
| 1.07 | Reset + step back | Code | The two supporting controls — reset run (no fold) and single-move undo. |
| 1.08 | First ~10 rooms | Code (+ Chat on design) | Hand-author the teaching rooms in plain grey boxes: move → one self → don't-touch → block/time. |

**Part 1 milestone:** the core is proven fun in grey boxes, on the real phone, before any polish.

---

## Part 2 — The juice (feel)

| # | Phase | Type | Scope |
|---|---|---|---|
| 2.01 | Visual design pass | **Design** | Lock the monochrome look, the accent, invert mode, exact shapes, and motion specs. Outputs a handover. *(Starts with an in-chat visual-direction sketch Lazar approves before the prompt is written.)* |
| 2.02 | Motion | Code | Ease-in-out slides (~120 ms), squash-and-stretch, soft snap, and the fold ripple. Reads the 2.01 handover. |
| 2.03 | Particles | Code | The death fizz and fold ripple via SwiftUI Canvas (thin SpriteKit layer only if Canvas can't manage it). |
| 2.04 | Generative audio | Code | Per-move ticks that layer into a rhythm as echoes stack, via AVAudioEngine. **The signature feature.** |
| 2.05 | Haptics | Code | Core Haptics mapping (selection / impact / error / success), pre-warmed, each paired with a visual change. |
| 2.06 | Settings screen | Code (+ Design input) | Invert mode, sound toggle, haptics toggle, echo-trail aid toggle. |
| 2.07 | In-room HUD & solid walls | Code | Promote the throwaway debug strip into the real in-room HUD: a top strip (Settings gear · centred level number · turn/echoes readout) and a bottom row of real action buttons in one reusable `ButtonStyle`; *Next* turns green on solve; walls render as a flat solid fill. Presentation only — the layout becomes the spec Part 3's real menu reuses. |

**Part 2 milestone:** the game feels the way the design intends.

---

## Part 3 — Content + arcade + workflow

| # | Phase | Type | Scope |
|---|---|---|---|
| 3.01 | Full campaign | Code (+ Chat on design) | Expand from ~10 rooms to the full hand-crafted set with a real difficulty curve and a clear ending. |
| 3.02 | Echo Run mode | Code | Bounded board; periodic spawning of your full movement history; survival, distance/score, high-score save. |
| 3.03 | Menus + polish screens | Code (+ Design) | Title, main menu, level select, win/over overlays. |
| 3.04 | Final feel + performance | Code | 60fps pass, no jank, every action has feedback, instant blame-free restarts verified. |
| 3.05 | Sideload/refresh workflow | Cowork/Chat + Lazar | A clean, repeatable guide for rebuilding ECHO and keeping it alive on the phone; SideStore auto-refresh dialed in. |

**Part 3 milestone:** ECHO is "launched" — fully playable on the iPhone and refreshing itself.

---

## Part 4 — Post-launch campaign expansion (20 → 36 rooms across three new mechanics, D-065)

> Each new mechanic ships as its own engine phase and is **proven before** the rooms that use it. Bands: 21–25 strategic/relocating echoes (wait); 26–30 teleport; 31–35 mirror; 36 a bonus finale stacking mirror **and** teleport. Rooms 25 / 30 / 35 are oversized hard capstones; **room 35 becomes the campaign finale**, 36 a bonus beyond it.

| # | Phase | Type | Scope | Status |
|---|---|---|---|---|
| 4.01 | The wait action | Code | `Direction.stay` + `GameState.wait()` (a pass-the-turn move; a wait can be fatal) + the explicit **Wait** HUD control + first-pass wait feedback (pulse / calm tick / haptic). The primitive every "strategic echo" room needs (D-066–D-068). | **Done** |
| 4.02 | Rooms 21–25 | Code (+ Chat on design) | The "strategic / relocating echo" band: 21 "Relay" (b1), 22 "Two Relays" (b2), 23 "Patrol & Relay" (b2, enemy enters), 24 "Hold & Hand-off" (b2, AND-door + relocate), 25 "Clockwork" (b3, two enemies — the band capstone). Each with a solvability test; rooms 23 & 25 with a negative (D-069). | **Done** |
| 4.03 | Teleport engine | Code | The two-region teleport pad mechanic (linked pad pairs, auto-on-step), proven headlessly before any room uses it: `Portal` + level-format-v2 `portals`, the shared `resolveLanding` resolver, pad-aware move/stepBack/echo-position/isCellHeld/collision, a first-pass pad glyph (D-070–D-072). | **Done** |
| 4.04 | Rooms 26–30 | Code (+ Chat on design) | The teleport band: 26 "Threshold" (b1), 27 "Two Rooms" (b2), 28 "Portal & Patrol" (b2, enemy), 29 "Relay Across" (b2, wait+teleport), 30 "Junction" (b3, two enemies — the oversized capstone, 3 pad pairs + AND-door across regions). Each with a solvability test; rooms 28 & 30 with a negative (D-073). | **Done** |
| 4.05 | Mirror engine | Code | The "you exist in both halves at once" mirror mechanic, proven headlessly before any room uses it: the additive level-format `mirror` block, the separate two-body `MirrorGameState` (reflected controls, partial movement/desync, cross-half switches/AND-doors, per-half death, both-home win), the `MirrorBoardView`/`MirrorRoomView` render path beside the untouched single-body UI, full `MirrorTests` (D-074–D-076). | **Done** |
| 4.06 | Rooms 31–35 | Code (+ Chat on design) | The mirror band: 31 "Symmetry" (b1, lockstep), 32 "Break Symmetry" (b1, desync), 33 "Cross-Half Hold" (b2, AND across the divide), 34 "Mirror & Patrol" (b2, two enemies — recordings timed), 35 "Reflection" (b3, two enemies — the oversized capstone and **the campaign finale**, D-065). Each with a mirror solvability test; rooms 34 & 35 with negatives (D-077). | **Done** |
| 4.07 | Mirror × teleport interaction | Code (+ Chat) | Define + prove what happens when a two-bodied mirrored entity hits a teleport pad — the rules-sketch + engine phase gating room 36. | Planned |
| 4.08 | Room 36 | Code (+ Chat on design) | The bonus finale: three connected maps (two mirrored halves + a teleport-only third), four echoes, six+ teleport pads, two enemies — the hardest room in the game. | Planned |

**Part 4 milestone:** the campaign is 36 rooms deep across three new mechanics, each proven on the phone as it lands.

---

## Critical path & dependencies

- **1.01 → 1.02** proves the build-and-install pipeline *before* any mechanic work, so device problems surface early.
- **1.04 (fold/replay) is the keystone.** 1.05, 1.06, and everything in Parts 2–3 depend on it. If 1.04 isn't solid, nothing downstream is.
- **Part 2 cannot start until the Part 1 milestone is met** — the core must be proven fun in grey boxes first (juice can't rescue a weak core).
- **Within Part 2, the 2.01 design handover gates the visual code phases** (2.02, 2.03, 2.06). Code reads the handover before writing UI.
- **Part 3 depends on the Part 2 milestone.** Echo Run (3.02) reuses the same move/replay engine from Part 1, so it carries no new core mechanics.
- **3.05 (workflow)** can be drafted any time after 1.02 but is finalized last, once the finished app is what's being refreshed.
