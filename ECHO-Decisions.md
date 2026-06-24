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

---

### Decision-log conventions
- **Append, never rewrite.** Past entries are frozen except their **Status** line.
- **One decision per entry.** Bundling several makes them impossible to supersede independently later.
- **Always include** an Alternative considered and a Consequence (the honest downside). An entry with neither is an assertion, not a decision.
- **Reversals:** mark the old entry `Superseded by D-0YY`, then add a new entry that links back to it.
- **IDs** are zero-padded and sequential (`D-001`, `D-002`, …), permanent, never reused.
