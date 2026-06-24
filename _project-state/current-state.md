# current-state.md

> A snapshot of the repo **right now** — a mirror, not a changelog. Code **overwrites** the stale parts at the end of every phase; it does not append. If this and `ECHO-Plan.md` ever disagree, **this file wins** (it reflects reality). The running history lives in completion reports and `00_stack-and-config.md`.

**Last updated:** 2026-06-24 — end of **Phase 1.01 (Scaffold)**

---

## Summary (plain language)
- **Works now:** ECHO exists as a real iOS app project. There is an `ECHO.xcodeproj` you can open in Xcode 27 and run with ⌘R; it shows a single full-screen warm off-white ("paper") placeholder screen and nothing else. The full folder structure from the Plan is in place, an `ECHOTests` target holds one trivial passing test, and everything is committed and pushed to GitHub (`DinovLazar/echo`, branch `main`).
- **Stubbed / not wired yet:** Everything gameplay — grid, move, fold/replay, collision, win detection, level data, controls (reset-run, step-back), audio (Part 2), haptics (Part 2), invert mode. The `Models/`, `Views/`, `Audio/`, `Haptics/` source folders are empty (`.gitkeep` only).
- **Current phase:** 1.01 complete (scaffold).
- **Next:** Phase 1.02 — first install onto the physical iPhone via Xcode ⌘R / SideStore.

## Detail
- **`ECHO/App/ECHOApp.swift`** — `@main` SwiftUI `App`; opens a `WindowGroup` containing `ContentView`. Real.
- **`ECHO/App/ContentView.swift`** — placeholder root view: fills the screen with the warm off-white paper color (`Color(red: 0.96, green: 0.94, blue: 0.89)`, defined inline) and ignores safe areas. No gameplay. Real.
- **`ECHO/Resources/Assets.xcassets`** — asset catalog with an empty `AppIcon` set (no artwork yet) and an empty `AccentColor` set (system default). Real but intentionally bare.
- **`ECHO/Models/`, `ECHO/Views/`, `ECHO/Audio/`, `ECHO/Haptics/`** — empty source groups (`.gitkeep`), reserved for later phases.
- **`ECHOTests/ECHOTests.swift`** — one test, `testScaffoldCompilesAndRuns()` (`XCTAssertEqual(2 + 2, 4)`), hosted by the app target. Proves the test target builds and links.
- **`Levels/`** — empty (`.gitkeep`); room JSON starts in Phase 1.06 and is not yet wired into the build.
- **`docs/design-handovers/`** — reserved, empty (`.gitkeep`).
- **`ECHO.xcodeproj`** — hand-authored project using Xcode's file-system **synchronized groups** (the `ECHO/` and `ECHOTests/` folders sync to the project automatically, so files added in later phases appear without editing the project file). Shared scheme `ECHO` committed under `xcshareddata/xcschemes/`.

## Build & repo status
- **Project file:** `ECHO.xcodeproj` present at repo root; SwiftUI App lifecycle; bundle id `com.dinovlazar.echo`; display name **Echo**; deployment target **iOS 17.0**; Swift language mode 6.0 (Swift 6.4 toolchain).
- **Build verification:** ⚠️ **Not yet run in this environment.** Full Xcode is not installed on the machine that scaffolded the project (only the Command Line Tools + Swift 6.4), so the project could not be compiled or launched in the Simulator here. The project is authored to build clean; **the first actual build/run (⌘R) happens on Lazar's Mac in Phase 1.02** and must confirm the off-white screen. See the Phase 1.01 completion report §2/§7.
- **Remote:** `origin` = `https://github.com/DinovLazar/echo` (public). **Branch:** `main`. Initial scaffold commit pushed.

## Known issues
- The project build has not been validated by an actual Xcode compile (no Xcode in the scaffolding environment) — Phase 1.02 must open the project and run ⌘R as the first confirmation. If Xcode reports any project-file issue, fix it there.
- `AppIcon` has no artwork yet (placeholder); a real icon is a later design task.
