# Part X · Phase YY · <Role> — Completion Report
**Date:** YYYY-MM-DD · **Outcome (one line):** <what now exists that didn't>

> Template. **Copy** this file to `_project-state/completions/Part-X-Phase-YY-Completion.md` (e.g. `Part-1-Phase-01-Code.md`) and fill it in. One phase = one completion report = one git commit. Keep it factual and plain — no marketing language. Write so a non-developer owner understands it. Filing this report **and** syncing `current-state.md` is what *closes* the phase. Don't edit a filed report later; note any correction in the next phase's report.

## 1. What shipped (plain language)
2–3 sentences a non-technical owner can read. What is now possible that wasn't before.

## 2. Definition of Done
Restate each DoD item from the phase prompt and mark it, with the **evidence** next to it (command output, file path, screenshot reference). Do not write a checkmark from memory — verify each item against the actual result.
- ✅ <item> — evidence: <proof>
- ⚠️ <item> — done except <gap>, because <reason>
- ❌ <item> — not done, because <reason>

## 3. Decisions I made during this phase
Anything I chose that the phase prompt or spec did **not** spell out — an off-spec change, a small redesign, a library/version pick, a scope cut, a workaround. For each: what I decided · why · the alternative I rejected · does it need a `ECHO-Decisions.md` entry (YES/NO)?
*(If there were none, write "None." Never leave this section blank — silent decisions are the main failure mode this report prevents.)*

## 4. Deviations from the brief / spec
Anything in the prompt I did not do, deferred, or changed — and why. "None" if none.

## 5. Changed files / deliverables
- **Code:** new / edited / deleted files (short list), and the commit hash / branch.
- **Design:** the handover file path (`docs/design-handovers/Part-X-Phase-YY-Handover.md`) and what it contains.
- **Ops / manual:** what was created or configured, and **where** it lives. Never paste secrets — say where they were placed instead. (The repo is public; treat every secret as off-limits in this report.)

## 6. State updates done (code phases)
Confirm the live state files now match reality:
- [ ] `current-state.md` overwritten to reflect what actually shipped
- [ ] `file-map.md` updated for every add/rename/delete
- [ ] `00_stack-and-config.md` appended if any dependency/tool/version changed
*(If any box is unchecked, the phase is **not** closed.)*

## 7. Risks, follow-ups, what the next phase needs to know
New blockers, anything that surprised you, anything the next agent must be aware of.

## 8. What's now possible that wasn't before
One forward-looking line.
