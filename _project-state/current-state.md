# current-state.md

> A snapshot of the repo **right now** — a mirror, not a changelog. Code **overwrites** the stale parts at the end of every phase; it does not append. If this and `ECHO-Plan.md` ever disagree, **this file wins** (it reflects reality). The running history lives in completion reports and `00_stack-and-config.md`.

**Last updated:** 2026-06-24 — end of **Phase 1.02 (First device install — Code track)**

---

## Summary (plain language)
- **Works now:** ECHO is a real iOS app project. There is an `ECHO.xcodeproj` you open in Xcode 27 and run with ⌘R; it shows the warm off-white ("paper") background full-bleed with a static, non-interactive **5×5 grid of grey square cells** centered on it ("hello grid"). The grid sits within the safe area (never clipped by the notch or home indicator) and stays square by sizing from the smaller screen dimension. Everything is committed and pushed to GitHub (`DinovLazar/echo`, branch `main`).
- **Stubbed / not wired yet:** Everything gameplay — the grid is a throwaway placeholder with no state behind it. No player square, no move/tap/swipe, no fold/replay, no collision, no win detection, no level data, no controls (reset-run, step-back), no audio (Part 2), no haptics (Part 2), no invert mode. The `Models/`, `Audio/`, `Haptics/` source folders are still empty (`.gitkeep` only). `Levels/` is still empty.
- **Current phase:** 1.02 — **Code track complete; not yet fully closed.** The hello-grid is written and type-checks clean; the **iOS Simulator build, on-device run, and a real Simulator/device screenshot remain pending on Lazar's Mac** (full Xcode is not installed in the Code environment — see Build & repo status).
- **Next:** Lazar opens `ECHO.xcodeproj` in Xcode 27, runs ⌘R on the Simulator (and his iPhone), confirms the grid renders, then the orchestrator closes 1.02 → Phase 1.03 (the real state-driven grid that replaces this placeholder).

## Detail
- **`ECHO/App/ECHOApp.swift`** — `@main` SwiftUI `App`; opens a `WindowGroup` containing `ContentView`. Real, unchanged this phase.
- **`ECHO/App/ContentView.swift`** — root view: a `ZStack` of the warm off-white paper (`Color(red: 0.96, green: 0.94, blue: 0.89)`, defined inline) with `.ignoresSafeArea()` (full-bleed) behind `HelloGridView()` (which is inset to the safe area). No gameplay. Real.
- **`ECHO/Views/HelloGridView.swift`** — the static "hello grid": a `GeometryReader` sizes a square board to 82% of the smaller available dimension and draws a 5×5 lattice of `Rectangle`s with thin grey borders (`Color(white: 0.7)`, 1 pt), centered. Non-interactive, no state, no animation — a throwaway placeholder Phase 1.03 replaces. Real.
- **`ECHO/Resources/Assets.xcassets`** — asset catalog with an empty `AppIcon` set (no artwork yet) and an empty `AccentColor` set (system default). Real but intentionally bare, unchanged this phase.
- **`ECHO/Models/`, `ECHO/Audio/`, `ECHO/Haptics/`** — empty source groups (`.gitkeep`), reserved for later phases. `ECHO/Views/` now holds `HelloGridView.swift`.
- **`ECHOTests/ECHOTests.swift`** — one test, `testScaffoldCompilesAndRuns()` (`XCTAssertEqual(2 + 2, 4)`), hosted by the app target. Unchanged this phase (execution still pending a real Xcode test run on Lazar's Mac).
- **`Levels/`** — empty (`.gitkeep`); room JSON starts in Phase 1.06 and is not yet wired into the build.
- **`docs/design-handovers/`** — reserved, empty (`.gitkeep`). No design handover exists for this phase by design (deliberately pre-design "grey boxes").
- **`ECHO.xcodeproj`** — hand-authored project using Xcode's file-system **synchronized groups** (the `ECHO/` and `ECHOTests/` folders sync to the project automatically, so `HelloGridView.swift` is picked up without editing the project file). Shared scheme `ECHO` committed under `xcshareddata/xcschemes/`.

## Build & repo status
- **Project file:** `ECHO.xcodeproj` present at repo root; SwiftUI App lifecycle; bundle id `com.dinovlazar.echo`; display name **Echo**; deployment target **iOS 17.0** (unchanged); Swift language mode 6.0 (Swift 6.4 toolchain); iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).
- **Signing:** "Automatically manage signing" is on for **both** targets (`CODE_SIGN_STYLE = Automatic` on `ECHO` and `ECHOTests`). **No `DEVELOPMENT_TEAM` is set** — Lazar selects his personal Apple ID team during his device-install step. (Simulator builds don't sign, so this doesn't block Simulator verification.)
- **Build verification:** ⚠️ **Partial.** Full Xcode is **not installed** in the Code environment (only Command Line Tools + Swift 6.4; `xcodebuild`/`simctl` unavailable), so the project could **not** be compiled or launched in the iOS Simulator here, and a real Simulator screenshot could not be captured. What **was** verified: the new view code type-checks clean against the macOS SDK (`swiftc -typecheck -parse-as-library`, exit 0, with the `#Preview` macro — which needs full Xcode — set aside). A deterministic layout reference matching the code is committed at `_project-state/completions/Part-1-Phase-02-grid-layout-reference.svg` (a reference, **not** a Simulator capture). **Pending on Lazar's Mac:** open in Xcode 27, ⌘R on an iOS 17+ Simulator and on the iPhone, confirm the centered grid renders, run ⌘U (the one test), and pin exact Xcode/SDK build numbers in `00_stack-and-config.md`.
- **Remote:** `origin` = `https://github.com/DinovLazar/echo` (public). **Branch:** `main`.

## Known issues
- The build has not been validated by an actual Xcode compile / Simulator run (no full Xcode in the Code environment). Lazar's ⌘R is the first real confirmation; if Xcode reports any project-file or code issue, fix it there and note it.
- `AppIcon` has no artwork yet (placeholder); a real icon is a later design task.
- The hello-grid is intentionally throwaway. Phase 1.03 replaces it with the real, state-driven grid — do not build gameplay on top of `HelloGridView`.
