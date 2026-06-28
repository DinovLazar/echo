# ECHO — Action → Feedback audit

**Phase 3.04 (final feel + performance — device-gated groundwork).** Last updated 2026-06-28.

This is the row-by-row checklist the owner verifies during the owed **on-device** session.
It turns "does it feel right?" into a concrete map: for **every player-facing action in
both modes**, what feedback each of the three channels — **visual / audio / haptic** —
should produce, and whether that path is **WIRED in code** (the call exists; verified by
reading the source this phase) or has **no hookup** (a gap, flagged below).

> **Read this first — what "WIRED" does and does not mean.** WIRED means the code path
> that produces the feedback exists and was verified by source inspection. It does **not**
> mean the feedback was *seen, heard, or felt* — none of that is observable under Command
> Line Tools (no device, no Simulator, no audio, no Taptic Engine). **Every WIRED audio,
> haptic, and on-screen-motion sensation is still OWED on device** (see the bottom list).
> This audit proves the wiring is present; the device session proves the *feel*.

Legend: **WIRED** = code path verified present · **— none** = no feedback on this channel
(see Gaps if one is expected) · spec refs are to the Part-2-Phase-01 handover (§) and
`ECHO-Decisions.md` (D-).

---

## Gaps found (missing or absent hookups)

Each gap below is **documented, not "fixed."** Per this phase's scope (presentation/tooling
only; the feel values themselves are not re-tuned or invented here — they can't be judged
without a device), none of these were a *trivial, safe, existing-call-simply-not-invoked*
wiring with a clear visual sibling — every one implies a **feel or design decision** that
belongs to the on-device pass or a later decision. So all are listed, none added.

| # | Action | What is missing | Why not fixed here |
|---|--------|-----------------|--------------------|
| **G1** | **Campaign — blocked move** (into a wall / closed door / off-grid): a no-op | **No feedback on any channel** — visual, audio, haptic all absent. `Motion.denyShake` (260 ms `decayShake`, handover §6a) is **defined in the token layer but never wired** (verified: only appears in `Motion.swift`). | Whether a refused move should deny-shake is a **feel decision**. The curve exists in the spec, but 2.02/2.03 deliberately left it unwired; wiring a shake is new presentation behaviour that can only be judged on device. Documented for the device pass. |
| **G2** | **Campaign — refused fold** (empty run, or echo budget reached; D-015/D-027) | **No feedback on any channel.** The fold choreography (sound + medium haptic + §6c peel) fires only from `onChange(of: state.echoes.count)` when the count *rises*; a refused `fold()` doesn't change the count, so it is silent. | Same `denyShake` family as G1 — a **feel decision**, not a missing-call. Not invented. |
| **G3** | **Campaign — reset run** and **step back** (the two control buttons) | **No audio, no haptic.** Visual = an instant board snap (no animation — handover §6d "restart = 0 ms"). | Plausibly intentional (a reset should feel instant and "your fault"). Whether a light tactile confirm is wanted is a **feel question** for the device pass. Not changed. |
| **G4** | **Echo Run — shadow spawn** (a new delayed shadow every 8 turns, D-057) | **No distinct cue** on any channel — the shadow simply appears at the start tile on the spawn turn. | Whether a spawn deserves its own cue (so the player *notices* a new pursuer) is a **design question** D-057 didn't settle. Inventing a cue is out of scope. Flagged for a later decision. |
| **G5** | **Echo Run — stall** (an edge swipe; D-057) | The stall fires `haptics.step()` (the same light tick as a real step) and plays only the *echoes'* ticks (no player tick, since the player didn't move). So on the **haptic** channel a stall is **indistinguishable from a step**. | Existing 3.02 behaviour. Whether a held edge should feel different from a step is a **feel question**; changing it is re-tuning feel (out of scope). Recorded, not changed. |
| **G6** | **Menu / Level-Select / Retry / back-chevron taps** | **No audio, no haptic** — only the visual route fade (~200 ms). | Haptics are deliberately scoped to the four *game* events (D-049); menu haptics are outside that scope. A **design decision**, not a missing-call. Not invented. |
| **G7** | **Echo Run — game-over reveal** | The panel is revealed **instantly** (`finishDeath()` sets `showGameOver = true` with no pre-delay/fade), unlike the campaign win overlay, which now gets a short pre-delay (D-064). | Not silent — the death sound + `.error` haptic already fired a beat earlier. The campaign win pre-delay was the *flagged* artifact (D-064); the Echo Run game-over was not. A possible **parity tweak** for the device pass; left as an observation, not changed this phase. |

> Note: G7's *sibling* on the campaign side **was** in scope and **is** addressed this phase —
> the win overlay now has a named pre-delay and the room→room advance no longer flashes the
> incoming board behind the outgoing scrim (D-064). See the campaign **win/solve** and
> **navigation** rows.

---

## Campaign (the 20-room mode)

| Action | Visual | Audio | Haptic | Spec / decision |
|--------|--------|-------|--------|-----------------|
| **Move / step** (swipe or tap an adjacent cell) | **WIRED** — 120 ms `curve.standard` slide + departure squash (94/106 %) + soft-snap settle; echoes glide in lockstep, hazards on the heavier 140 ms slide | **WIRED** — `audio.playStep(directions:)` at commit: one pentatonic tick per moving entity (player + each stepping echo), fired as one chord | **WIRED** — `haptics.step()` (light selection tick) on the committed step | §6b; D-045/D-046; D-049 |
| **Blocked move** (wall / closed door / off-grid) | **— none** (G1) | **— none** (G1) | **— none** (G1) | §6a `denyShake` *defined, unwired* |
| **Fold** (the *Fold* button; a run was recorded) | **WIRED** — §6c choreography: 50 ms hit-pause → grid ripple (220 ms) → new echo peels off the player, ink→echo grey, 32→28 pt (180 ms) | **WIRED** — `audio.playFold()` on the hit-pause onset (warm two-note settle) | **WIRED** — `haptics.fold()` (medium impact) on the same onset | §6c; D-044; D-049 |
| **Refused fold** (empty run / budget reached) | **— none** (G2) | **— none** (G2) | **— none** (G2) | D-015/D-027 |
| **Reset run** (the *Reset run* button) | **WIRED** — instant board snap to start (no animation, 0 ms) | **— none** (G3) | **— none** (G3) | §6d restart |
| **Step back** (the *Step back* button; no-op at turn 0) | **WIRED** — instant one-step snap (no animation) | **— none** (G3) | **— none** (G3) | §6d |
| **Collision / death** (touch an echo or hazard → restart the run) | **WIRED** — §6d: fatal glide onto contact → 66 ms freeze → 320 ms particle fizz → ~200 ms red vignette (+ one enemy-glow pulse for a hazard kill) | **WIRED** — `audio.playDeath()`, offset to swell on the fizz (`step + deathFreeze` later) | **WIRED** — `haptics.collision()` (`.error`) at the instant of contact, a beat before the sound | §6d; D-043; D-049; D-052 |
| **Death caption** ("you got eaten") | **WIRED** — `guidance.showEaten()` fades the recurring red-note caption in over the freeze (linger 1600 ms) | — (caption is visual) | — | §6/§8.2; D-052 |
| **Win / solve** (reach the exit alive) | **WIRED** — `hasWon` flips → room marked solved → **short pre-delay (≈0.45 s, D-064)** so the solved board reads → win overlay fades in; *Next room* in success-green (D-055) | **WIRED** — `audio.playSolve()`, offset one step so the figure resolves on arrival | **WIRED** — `haptics.win()` (`.success`) at the winning commit | §6; D-055; D-049; **D-064** |
| **Advance** ("Next room") | **WIRED** — opaque paper cover veils the solved board **before** the room swaps, so the incoming board never shows behind the outgoing scrim (D-064 artifact 1), then the root ~200 ms crossfade | — | — | **D-064**; D-059 |
| **One-time guidance hints** (rooms 01 / 03 / 06) | **WIRED** — `guidance.enterRoom` shows the room's hint once-ever (linger 2200 ms, seen-once persisted) | **— none** (by design — hints are quiet text) | **— none** (by design) | §6; D-042/D-052; D-033 |
| **Navigation transitions** (title→menu→level-select→room) | **WIRED** — ~200 ms `Motion.guidanceIn` opacity fade, owned by the root `.animation(value: route)` | **— none** (by design) | **— none** (by design) | D-059 |
| **Level-Select tile tap** | **WIRED** — opens the room via the same ~200 ms route fade | **— none** (G6) | **— none** (G6) | D-059/D-060 |

---

## Echo Run (the arcade survival mode)

| Action | Visual | Audio | Haptic | Spec / decision |
|--------|--------|-------|--------|-----------------|
| **Move / step** (swipe or tap an adjacent cell) | **WIRED** — same 120 ms slide + squash as the campaign; shadows glide in lockstep | **WIRED** — `audio.playStep(directions:)`: the player's tick + one per stepping shadow | **WIRED** — `haptics.step()` on the committed step | §6b; D-046; D-049; D-058 |
| **Edge-swipe stall** (a swipe that would leave the grid; D-057) | **WIRED** — player holds; turn advances; shadows glide (no player squash — `stepTick` not bumped) | **WIRED** — `audio.playStep` plays **only the echoes' ticks** (no player tick, since the player didn't move) — silent if no shadow is stepping yet | **WIRED** — `haptics.step()` fires (same tick as a real step → **G5**: tactilely identical to a step) | D-057; **G5** |
| **Shadow spawn** (every 8 turns; D-057) | **WIRED-ish** — the new shadow simply appears at the start tile next render; **no distinct spawn cue** (**G4**) | **— none** (G4) | **— none** (G4) | D-057; **G4** |
| **Stacked-shadow audio chord** (the signature "your past selves make the rhythm") | — (the chord *is* the audio) | **WIRED** — one `audio.playStep` call per turn voices the player + every stepping shadow at one audio time, so a busy board layers into a chord; a recorded path re-voices as a loop | **WIRED** — one `haptics.step()` per turn (a single tick, not one per shadow) | §14 "signature feature"; D-046 |
| **Collision / death** (touch any shadow → run over) | **WIRED** — same §6d freeze → fizz dissolve over the frozen board (no hazard, so no enemy-glow pulse) | **WIRED** — `audio.playDeath()` swelling on the fizz | **WIRED** — `haptics.collision()` (`.error`) at contact | §6d; D-043; D-049; D-057 |
| **Game-over reveal** | **WIRED** — score panel; "best N" / "new best!" in success-green (D-055). **Revealed instantly — no pre-delay/fade (G7)** | **— none on the reveal** (the death sound already fired) | **— none on the reveal** (the `.error` already fired) | D-055; D-059; **G7** |
| **Retry** (the *Retry* button) | **WIRED** — `state.reset()` snaps the board to a fresh run (instant) | **— none** (G6) | **— none** (G6) | D-058; **G6** |
| **Main menu / back chevron** | **WIRED** — ~200 ms route fade | **— none** (G6) | **— none** (G6) | D-059; **G6** |

---

## Cross-reference key

- **§6a** named easing curves · **§6b** step glide + squash + soft-snap · **§6c** fold
  choreography · **§6d** death dissolve · **§6 / §8** guidance microcopy — Part-2-Phase-01 handover.
- **D-033** the teaching arc (which room teaches which hint) · **D-041** two board accents,
  never colour-alone · **D-042 / D-052** guidance strings + timing · **D-043** death
  choreography (glide→freeze→fizz) · **D-044** fold peel · **D-045 / D-046** audio
  architecture + move-tick voicing · **D-049** the four haptic mappings · **D-055** the
  green solved/best chrome cue · **D-057** the Echo Run mechanic (stall / spawn / death) ·
  **D-058** Echo Run as a separate engine · **D-059** the navigation model + ~200 ms fades ·
  **D-064** (this phase) the win-overlay pre-delay + room→room scrim sequencing.

---

## OWED on device (checked only after the on-device session — NOT this phase)

Every WIRED row above proves the *call exists*; the **sensation** is unverifiable under
Command Line Tools and remains owed:

- [ ] **Audio heard** — the per-move pentatonic tick; the stacked-shadow **chord** layering
      in Echo Run; fold / death / solve event sounds; that they land *on the beat* they
      target (commit / hit-pause / fizz / arrival).
- [ ] **Haptics felt** — step / fold / collision (`.error`) / win (`.success`) on the real
      Taptic Engine; that the lead-vs-sound timing reads right for collision and win.
- [ ] **Motion seen on device** — step glide + squash; fold §6c; death §6d freeze→fizz;
      the navigation fades; and the two **D-064** transition fixes confirmed visually
      (the win pre-delay reads, and the "Next room" advance shows **no** incoming-board
      flash behind the outgoing scrim) — then their constants tuned to taste.
- [ ] **60 fps / no jank** — judged with the developer performance overlay (D-063) across
      busy campaign rooms and a long Echo Run (stacked shadows = worst case).
- [ ] **Gap decisions** — G1–G7 reviewed on device (deny-shake? spawn cue? stall vs step?
      menu haptics? game-over parity?), each ratified or deferred.
