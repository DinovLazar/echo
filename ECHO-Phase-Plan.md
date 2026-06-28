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

## Critical path & dependencies

- **1.01 → 1.02** proves the build-and-install pipeline *before* any mechanic work, so device problems surface early.
- **1.04 (fold/replay) is the keystone.** 1.05, 1.06, and everything in Parts 2–3 depend on it. If 1.04 isn't solid, nothing downstream is.
- **Part 2 cannot start until the Part 1 milestone is met** — the core must be proven fun in grey boxes first (juice can't rescue a weak core).
- **Within Part 2, the 2.01 design handover gates the visual code phases** (2.02, 2.03, 2.06). Code reads the handover before writing UI.
- **Part 3 depends on the Part 2 milestone.** Echo Run (3.02) reuses the same move/replay engine from Part 1, so it carries no new core mechanics.
- **3.05 (workflow)** can be drafted any time after 1.02 but is finalized last, once the finished app is what's being refreshed.
