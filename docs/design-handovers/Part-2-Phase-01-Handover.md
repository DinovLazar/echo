# ECHO · Part 2 · Phase 01 — Visual Design Handover

**Status:** Locked for implementation
**Implements in:** SwiftUI (Claude Code, later phases)
**Supersedes:** `ECHO-Plan.md` §5 (see *Decisions Embodied* at the end)

This document is the single source of truth for the board's visual design. Every value is
concrete and expressible in SwiftUI: colours as hex, sizes/radii in points, opacities as
fractions, motion as milliseconds + a named easing curve. Nothing is left "TBD".

> **How to read sizes.** Geometry is given against a reference **cell size `C = 44 pt`** (also
> the minimum hit target). Insets and diameters are stated in points *and* as a fraction of `C`
> so the board scales cleanly to any device cell size — multiply the fraction by the runtime `C`.

---

## 0. The colour-language rule (binding)

ECHO is a calm, tactile, lightly-coloured monochrome board. The base world is **paper** (warm
off-white), **ink** (near-black), and **echo grey** (translucent). On top of that there are
**exactly two meaning-colours**:

- **Red = danger.** Only the enemy is ever red.
- **Gold = your current goal.** Only the active exit, and a switch *while it is keeping you
  alive*, are ever gold.

**Meaning never lives in colour alone.** Each accent always rides on a distinct, already-readable
shape:

| Meaning | Shape that carries it | Colour is a *bonus* layer |
|---|---|---|
| Danger | spiky **diamond** with inner core | red |
| Goal | **ring** (exit) / **filled circle** (held switch) | gold |

If colour were removed entirely (grayscale, or full colour-blindness), every element is still
uniquely identifiable by shape, fill, opacity, and stroke. The grayscale sanity pass in §5
confirms this. Designers and Code must preserve this rule: **do not introduce a third accent
colour, and never let red or gold be the only differentiator between two states.**

---

## 1. Token table — colours, geometry, opacity, motion

### 1a. Colour tokens

Both modes are authoritative. Invert mode is a true white-on-black presentation, not a dimmed
copy; red and gold are re-tuned (not merely darkened) to stay legible and on-tone on a dark
surface — see §4 for the reasoning.

| Token | Role | Light value | Invert value |
|---|---|---|---|
| `paper.top` | Board background, top of gradient | `#F5EDDD` | `#1A1713` |
| `paper.bottom` | Board background, bottom of gradient | `#EADFCA` | `#0E0C0A` |
| `ink` | Player fill, primary marks | `#16130F` | `#F2EBDD` |
| `wall.top` | Wall tile, top-light | `#3B3731` | `#3A352E` |
| `wall.bottom` | Wall tile, bottom-dark | `#262320` | `#23201B` |
| `echo.base` | Echo fill/stroke base hue | `#4A453E` | `#C9C1B2` |
| `switch.ring` | Open switch ring | `#7A7163` | `#8A8275` |
| `danger.red` | Enemy fill | `#C0473B` | `#D85A4C` |
| `danger.outline` | Enemy outline | `#7E2A22` | `#F0A89E` |
| `danger.core` | Enemy inner core | `#7E2A22` | `#8E2C22` |
| `danger.glow` | Enemy soft glow | `#C0473B` @ 35% | `#D85A4C` @ 45% |
| `goal.gold` | Active exit / held switch | `#C99A3A` | `#E0B450` |
| `goal.glow` | Gold soft glow | `#C99A3A` @ 35% | `#E0B450` @ 45% |
| `text.guidance` | Guidance microcopy | `#5C5346` | `#9A8F7E` |
| `tile.hairline` | Grid tile hairlines | `#C7BAA3` | `#332E27` |

**Rationale (one line per group):**

- **paper.* / ink** — a warm off-white sheet with near-black marks; the gentle vertical gradient
  reads as soft top light without ever looking like a UI panel.
- **wall.*** — top-light / bottom-dark gradient gives walls just enough depth to read as solid
  matter, not as drawn outlines.
- **echo.base** — a single neutral-warm grey used at low opacity so past selves recede behind the
  present player.
- **switch.ring** — a muted brown-grey ring that is clearly mechanical and quiet when inactive.
- **danger.*** — one earthy, desaturated red (never fire-engine) plus a darker outline and core so
  the enemy reads as a deliberate, contained point of tension.
- **goal.*** — a warm muted gold that says "here / safe / your aim" without shouting.
- **text.guidance / tile.hairline** — deliberately the quietest values on screen; help that does
  not compete with the board.

### 1b. Geometry, stroke & opacity tokens

| Token | Value (light & invert identical unless noted) |
|---|---|
| `cell.size` | `C = 44 pt` reference (runtime-driven) |
| `radius.player` | `7 pt` (0.159·C) |
| `radius.echo` | `7 pt` (0.159·C) |
| `radius.wall` | `4 pt` (0.091·C) |
| `radius.doorBar` | `3 pt` |
| `radius.enemyCorner` | `3 pt` (deliberately small — "slightly sharp") |
| `stroke.echo` | `1.5 pt` |
| `stroke.switchRing` | `3 pt` |
| `stroke.exitRing` | `3 pt` |
| `stroke.enemyOutline` | `2 pt` |
| `stroke.hairline` | `0.5 pt` |
| `opacity.echoFill` | `0.24` |
| `opacity.echoStroke` | `0.55` |
| `opacity.doorOpenRemnant` | `0.22` |
| `opacity.trailDot` | `0.40` |
| `opacity.accentGlow` | `0.35` light / `0.45` invert |
| `shadow.player` | `y +2 pt, blur 6 pt, ink @ 0.22` (invert: `ink-on-dark @ 0.40`) |
| `glow.accent` | `blur 8 pt, spread 2 pt` around the shape, colour = `*.glow` token |

### 1c. Motion tokens

All durations in milliseconds; all curves named below in §6a and given as SwiftUI
`Animation.timingCurve` control points.

| Token | Duration | Curve |
|---|---|---|
| `motion.step` | `120 ms` | `curve.standard` |
| `motion.stepSnap` | `40 ms` settle | `curve.softSnap` |
| `motion.foldHitPause` | `50 ms` (3 frames @60fps) | hold |
| `motion.foldRipple` | `220 ms` | `curve.easeOut` |
| `motion.foldPeel` | `180 ms` | `curve.easeOut` |
| `motion.deathFreeze` | `66 ms` (4 frames @60fps) | hold |
| `motion.deathFizz` | `320 ms` | `curve.easeOut` |
| `motion.restart` | `0 ms` (next frame) | — |
| `motion.enemyStep` | `140 ms` | `curve.standard` |
| `motion.trailReveal` | `200 ms` (8 ms stagger/dot) | `curve.easeOut` |
| `motion.denyShake` | `260 ms` | `curve.decayShake` |
| `motion.guidanceIn` | `200 ms` | `curve.easeOut` |
| `motion.guidanceOut` | `350 ms` | `curve.easeIn` |
| `motion.guidanceLingerHint` | `2200 ms` | hold |
| `motion.guidanceLingerFeedback` | `1600 ms` | hold |

---

## 2. Component specs — every element, every state

Geometry below is anchored to the cell. "Centred" = centred in the cell. Shadows/glows render
*outside* the shape and must not be clipped by the cell bounds.

### 2.1 Player — "you, now" (must always be the clearest element)

- **Shape:** rounded square, centred.
- **Size:** `32 pt` (0.73·C) — inset `6 pt` per side.
- **Radius:** `radius.player` = `7 pt`.
- **Fill:** `ink`, fully opaque (`1.0`).
- **Stroke:** none.
- **Shadow:** `shadow.player` (`y +2, blur 6, ink @ 0.22`). This soft drop shadow is what lifts the
  player off the paper and reads as "the present." No other board element casts this shadow.
- **State:** single resting state; motion states defined in §6 (step, deny-shake, dissolve).

### 2.2 Echo — "a past you" (recedes behind the player)

- **Shape:** rounded square, centred.
- **Size:** `28 pt` (0.636·C) — inset `8 pt` per side (visibly smaller than the player).
- **Radius:** `radius.echo` = `7 pt`.
- **Fill:** `echo.base` @ `opacity.echoFill` (0.24).
- **Stroke:** `echo.base` @ `opacity.echoStroke` (0.55), `1.5 pt`.
- **Shadow:** none (echoes are flat — only the present casts a shadow).
- **Upcoming-path trail (resting attachment):** see §9. A faint dotted line projecting from the
  echo along the cells it is about to walk.

### 2.3 Wall — subtle-depth tile

- **Shape:** rounded square filling the cell with a `1 pt` inset (so adjacent walls read as
  separate tiles, not one mass).
- **Size:** `42 pt` (C − 2 pt).
- **Radius:** `radius.wall` = `4 pt`.
- **Fill:** vertical gradient `wall.top → wall.bottom`.
- **Stroke:** none; the gradient alone gives solidity. Optional `0.5 pt` `tile.hairline` only if
  two walls of identical height need separation (Code's discretion).
- **Depth cue:** top edge catches `wall.top`; bottom sits in `wall.bottom` — a consistent
  top-light read across the whole board.

### 2.4 Switch — open & held

- **Open (inactive):** empty ring, centred. Diameter `22 pt` (0.5·C), stroke
  `stroke.switchRing` = `3 pt`, colour `switch.ring`. No fill, no glow. Reads quiet/mechanical.
- **Held (keeping the player alive):** filled circle, centred. Diameter `20 pt`, fill `goal.gold`,
  `glow.accent` using `goal.glow`. The shift from hollow-ring to filled-gold-circle is the
  shape-change that carries the meaning; the gold is the bonus layer.

### 2.5 Door — closed & open (must differ at a glance)

- **Closed:** solid bar spanning the cell edge it blocks. Bar thickness `10 pt`, length = `C`,
  radius `radius.doorBar` = `3 pt`, fill `ink` @ `0.92`. Reads as a firm, present barrier.
- **Open:** recessed remnant — two short stub marks at the bar's ends (each `8 pt` long, same
  `10 pt` thickness, radius `3 pt`) drawn in `ink` @ `opacity.doorOpenRemnant` (0.22). The gap in
  the middle + the faded stubs read unmistakably as "this was a door, now passable."
- **At-a-glance distinction:** closed = one solid high-contrast bar; open = two faint short stubs
  with an empty centre. Solidity *and* completeness change, not just opacity.

### 2.6 Enemy — red diamond (menacing but tasteful)

- **Shape:** diamond (square rotated 45°), centred, with **small** corner radius
  `radius.enemyCorner` = `3 pt` so edges read as "slightly sharp," not razor-pointed.
- **Size:** `30 pt` point-to-point (0.68·C).
- **Fill:** `danger.red`.
- **Outline:** `stroke.enemyOutline` = `2 pt`, colour `danger.outline`.
- **Glow:** `glow.accent` using `danger.glow` — soft, contained; never a pulsing alarm at rest.
- **Inner core:** a small concentric diamond, `10 pt` point-to-point, fill `danger.core`,
  no stroke. Gives the enemy a focused "eye" so it reads as a creature/threat, not a token.
- **Movement feel:** §6d.

### 2.7 Exit — default & active-goal

- **Default (not yet the goal):** hollow ring, centred. Diameter `30 pt` (0.68·C), stroke
  `stroke.exitRing` = `3 pt`, colour `ink` @ `0.55`. No fill, no glow — a quiet destination.
- **Active-goal (this is where you must go now):** same ring geometry, stroke colour `goal.gold`,
  plus `glow.accent` using `goal.glow`. The ring shape is constant; gold + glow is the bonus layer
  announcing "your goal."

---

## 3. Hierarchy & legibility

**Hierarchy rule (binding):** reading priority on the board, brightest/sharpest to quietest, is:

1. **Player** — full-opacity ink + the only drop shadow → unmistakably "now."
2. **Enemy** — red + glow + sharp diamond → the one point of tension.
3. **Active goal** (gold exit / held switch) — gold + glow draws the eye to the aim.
4. **Walls & closed doors** — solid, present, but neutral.
5. **Echoes & their trails** — translucent, smaller, flat → clearly "the past," recede.
6. **Open-door remnants, hairlines, guidance text** — quietest; present but never competing.

The player must never be out-read by an echo: it is larger (32 vs 28 pt), fully opaque (1.0 vs
0.24), and the only shadow-casting piece.

### Grayscale / colour-blind sanity pass

With all colour removed, each element remains uniquely identifiable by **shape + opacity +
size**, never by hue:

| Element | Identifiable without colour by… |
|---|---|
| Player | largest solid square + drop shadow |
| Echo | smaller, translucent square, no shadow |
| Wall | full-cell solid tile with depth gradient |
| Closed door | single solid bar on a cell edge |
| Open door | two faint short stubs + central gap |
| Switch (open) | hollow ring |
| Switch (held) | filled solid circle (vs the hollow open ring) |
| Enemy | spiky diamond + inner core (only diamond on the board) |
| Exit (default) | hollow ring, thin |
| Exit (active goal) | same ring + soft glow halo (glow survives grayscale as a light bloom) |

Confirmed: removing red and gold changes *emphasis* but never *identity*. The colour-language rule
holds for monochrome and all colour-vision types.

---

## 4. Invert mode (white-on-black)

Invert mode flips the world to ink-on-dark while preserving every relationship. All token values
are in the §1a table; the design reasoning:

- **Surface & marks swap.** `paper.*` becomes a warm near-black gradient (`#1A1713 → #0E0C0A`);
  `ink` becomes warm off-white `#F2EBDD`. The warmth is kept on both ends so it never feels like a
  cold "dark theme."
- **Walls stay raised.** Wall gradient lightens to `#3A352E → #23201B` so walls sit *above* the
  dark paper (top-light read preserved, now as the lighter element).
- **Echoes invert to light grey.** `echo.base` → `#C9C1B2`, kept at low opacity (0.22 fill /
  0.50 stroke) so they still recede against the dark sheet.
- **Player shadow becomes a deeper ambient shadow** (`ink-on-dark @ 0.40`) so the off-white player
  still lifts off the dark paper.
- **Red is brightened, not just kept.** `#C0473B → #D85A4C` and the outline flips to a *light*
  halo `#F0A89E` (rather than the light-mode dark outline) so the diamond's edge stays crisp
  against black; glow opacity rises to 0.45. Net effect: same earthy danger-red identity, legible
  on a dark field without becoming neon.
- **Gold is brightened similarly.** `#C99A3A → #E0B450`, glow to 0.45. Gold stays warm and muted
  but gains the luminance it needs to read as "goal" on black.
- **Guidance text & hairlines** lift to `#9A8F7E` / `#332E27` — still the quietest things on
  screen, now as faint light marks.

Every element/state in §2 renders identically in geometry; only the token *values* change. No
element is unique to one mode.

---

## 5. Motion specs (plug-in values for SwiftUI)

### 6a. Named easing curves (SwiftUI `Animation.timingCurve(c1x, c1y, c2x, c2y, duration:)`)

| Curve name | Control points | Notes |
|---|---|---|
| `curve.standard` | `(0.42, 0.0, 0.58, 1.0)` | symmetric ease-in-out; the default board move |
| `curve.easeOut` | `(0.0, 0.0, 0.2, 1.0)` | decelerate-in; reveals, ripples, fizz |
| `curve.easeIn` | `(0.4, 0.0, 1.0, 1.0)` | accelerate-out; fade-outs |
| `curve.softSnap` | `(0.2, 0.9, 0.3, 1.06)` | tiny overshoot (>1) for the arrival settle |
| `curve.decayShake` | drive with `interpolatingSpring(stiffness: 320, damping: 14)` | damped oscillation for deny-shake |

> For `curve.decayShake`, prefer SwiftUI's `interpolatingSpring` (or a keyframe oscillation) over a
> bezier, since it is a decaying back-and-forth, not a monotonic ease.

### 6b. Step slide (`motion.step`)

- **Duration / curve:** `120 ms`, `curve.standard`.
- **Squash-and-stretch:** on departure, squash to `94%` along the travel axis / `106%` across it
  for the first `~40 ms`; return to `100%` by arrival.
- **Soft snap on arrival:** a `40 ms` `curve.softSnap` settle (`motion.stepSnap`) with the ~6%
  overshoot, so the player "lands" with a hair of weight rather than stopping dead.
- **Timing intent:** total perceived move ≤ ~160 ms keeps input-to-response well under the
  100 ms-feel target (the square starts moving on the same frame as input).

### 6c. The fold (the brief weighty event)

The signature beat — give it weight, keep it short:

1. **Hit-pause:** freeze the whole board for `50 ms` (`3 frames @60fps`, `motion.foldHitPause`) at
   the instant of the fold — the moment lands.
2. **Grid ripple:** a one-shot ripple radiating from the player's cell across the tile hairlines,
   `220 ms`, `curve.easeOut` (`motion.foldRipple`) — a subtle scale/opacity pulse on hairlines, no
   colour.
3. **Echo peel-off:** the new grey echo "peels" off the player's just-walked path over `180 ms`,
   `curve.easeOut` (`motion.foldPeel`) — fading from the player's ink toward `echo.base` @ 0.24 as
   it separates, so you *see* the present shed a past self.

Beats are spaced so audio/haptics can sit on: (a) the hit-pause onset, (b) the ripple crest
(~`+40 ms` into the ripple), (c) the peel completion.

### 6d. Death / dissolve (`motion.deathFreeze` → `motion.deathFizz` → `motion.restart`)

- **Calm freeze:** `66 ms` (`4 frames`) hold the instant of contact — no slow-mo drama.
- **Soft particle fizz:** the player square dissolves into ~`14` small ink particles drifting
  outward and fading to transparent over `320 ms`, `curve.easeOut`. Particles inherit `ink`
  (invert: off-white); they fizz, not explode.
- **Brief red note:** simultaneously, a faint full-board red vignette flash (`danger.red` @ `0.08`)
  rises and falls over `~200 ms`, and the enemy's glow pulses once — a quiet "it got you," not a
  jump-scare.
- **Restart:** `motion.restart` = `0 ms`. The board snaps back to the room's start on the next
  frame. Instant and clean so failure reads as "my fault, try again," never as punishment.

### 6e. Enemy movement feel (`motion.enemyStep`)

- **Duration / curve:** `140 ms`, `curve.standard` — deliberately ~20 ms slower than the player so
  it feels heavier and more deliberate.
- **Anticipation:** a `~30 ms` squash toward the travel direction before it sets off (lean-in),
  then settle with no overshoot — measured, predatory, not twitchy.

### 6f. Echo-trail reveal (`motion.trailReveal`)

- Dots appear from the echo outward, staggered `8 ms` per dot, each fading 0→`opacity.trailDot`
  over `200 ms`, `curve.easeOut`. The path "draws itself" toward where the echo is headed.
- On toggle-off, dots fade out over `150 ms`, `curve.easeIn`, then stop rendering.

---

## 6. Typography & the guidance-message system

**Family:** system font — **SF Pro** (SwiftUI `.system` / `Font.system`). No custom faces.

| Use | Font | Size | Weight | Tracking |
|---|---|---|---|---|
| Guidance microcopy (both categories) | SF Pro Text | `15 pt` | `.medium` | `+0.2 pt` |

There is no other on-board text. (Menus/title/level-select are Part 3, out of scope.)

### Microcopy treatment

- **Placement:** horizontally centred in the **lower third** of the board, above the home-indicator
  safe area (min `24 pt` from the bottom safe-area inset). Never overlaps the player or the enemy;
  if the action is happening in the lower third, Code may anchor to the **upper third** instead —
  same style.
- **Style (clearly *not* a board piece):** `text.guidance` colour only, no fill/box/card, no shadow,
  no border. Muted, flat, weightless — visibly UI, not a game object. Optional `≤4 pt` of breathing
  room is fine but **no pill, no panel.**
- **Fade behaviour:** fade-in `200 ms` `curve.easeOut` → **linger** → fade-out `350 ms`
  `curve.easeIn`. The message slides nowhere; opacity only.

### Two categories (same look, different timing)

- **One-time hints** — shown **once**, the first time the situation is relevant; linger
  `motion.guidanceLingerHint` = `2200 ms`. Strings (verbatim):
  - `swipe to move`
  - `fold to keep the door open`
  - `beware — it bites`
- **Recurring feedback** — shown **every time** it happens; linger
  `motion.guidanceLingerFeedback` = `1600 ms`. Strings (verbatim):
  - `you got eaten`
  - `you can't go there — your ghost is`

> The five strings above are final — reproduce verbatim, do not reword or re-case. Which room each
> *one-time hint* belongs to is wired by Code later; this phase fixes only the look and fade.

---

## 7. The two interaction-feedback visuals

> **Out of scope reminder:** *when* each of these fires (the "blocked move vs lethal collision"
> trigger rule) is a separate gameplay decision made later with the owner. This phase specifies the
> **visual states only** — both are fully specified so either can be wired without further design.

### 8.1 Denied / blocked move

The player tried to move into a cell its own ghost (echo) occupies and is refused.

- **Cue:** a gentle horizontal **nudge-shake** of the player square — amplitude `4 pt`, ~3 damped
  oscillations, `260 ms`, `curve.decayShake`. The player does **not** leave its cell; it bumps and
  settles. No colour change — the player stays `ink`.
- **Optional reinforcement:** the blocking echo gives a single faint flash (its stroke opacity
  rises `0.55 → 0.75` and back over `200 ms`) so you see *what* blocked you.
- **Paired message:** recurring-feedback string `you can't go there — your ghost is`.
- **Intent:** reads as "not allowed, no harm done" — instant, legible, your-fault-but-fine.

### 8.2 Eaten / dissolve death

The player was caught by the enemy.

- **Cue:** the death/dissolve sequence from §6d — `66 ms` calm freeze → `320 ms` soft ink particle
  fizz → instant restart — plus the brief red note (vignette flash `danger.red` @ `0.08` + one
  enemy-glow pulse).
- **Paired message:** recurring-feedback string `you got eaten`, fading in on the freeze frame.
- **Intent:** weighty enough to register, calm enough to stay on-tone; the instant restart keeps it
  "try again," not "game over."

---

## 8. Echo-trail aid (user-toggleable)

A faint dotted line showing each echo's **upcoming** path — an accessibility/clarity aid the user
can switch on or off.

- **Geometry:** dots of `3 pt` diameter, centre-spaced `8 pt`, running from the echo's current cell
  centre along the centres of the cells it is about to enter, for the full known upcoming path.
- **Colour / opacity:** `echo.base` @ `opacity.trailDot` (0.40). Invert: same token, same opacity.
- **On:** revealed with `motion.trailReveal` (§6f) — dots draw outward, `8 ms` stagger, `200 ms`
  `curve.easeOut` each.
- **Off (default state TBD by owner setting):** not rendered at all; toggling off fades existing
  dots over `150 ms` `curve.easeIn`. The aid never changes gameplay — purely a read of existing
  echo intent.

---

## 9. Decisions embodied (revisions to Plan §5 — log in `ECHO-Decisions.md`)

This phase intentionally revises the previously-locked §5. Where they differ, **this handover
wins.** Two decisions for the orchestrator to record:

1. **Two-accent danger/goal colour language supersedes the strict black-white-grey of Plan §5.**
   The board gains exactly two meaning-colours — **red = danger**, **gold = goal** — each always
   layered on a distinct shape and never the sole signal. The world is otherwise ink, paper, and
   grey. Rationale: a single point of tension and a clear aim are far more legible with one bonus
   hue each than with grey alone, without sacrificing the calm monochrome character.

2. **Light, one-time on-screen guidance microcopy supersedes the original "no on-screen text /
   tutorial-free" stance.** A muted, clearly-not-a-board-piece message system delivers three
   one-time hints and two recurring feedback lines. Rationale: a few quiet, well-timed words remove
   ambiguity (especially the fold mechanic) at near-zero cost to the diegetic feel, since the text
   is visibly UI and fades away.

---

*End of handover. Every colour, radius, stroke, opacity, duration, and curve above is concrete and
ready to implement in SwiftUI.*
