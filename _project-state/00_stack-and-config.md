# 00_stack-and-config.md  (append-only)

> A log of stack and config decisions with **exact pinned versions**. Append a dated entry whenever a dependency or tool is added or upgraded; never rewrite a past entry. This is what keeps the build reproducible. Pin exact versions (`x.y.z`), never "latest" or caret ranges — silent drift is undebuggable for a non-developer owner.

---

## 2026-06-24 — Planning lock (pre-scaffold)

The locked stack for ECHO, as decided during intake and planning. Versions reflect what's current as of this date; Code confirms and re-pins the exact installed versions during Phase 1.01 and appends a correction here if anything differs.

- **Language:** Swift 6.4 (bundled with Xcode 27)
- **Build tool / IDE:** Xcode 27 (currently the WWDC 2026 beta; public release expected ~Sept 2026)
- **Host OS to build on:** macOS 26.4+ (Tahoe) or macOS 27, Apple silicon only
- **UI foundation:** SwiftUI (system framework, tracks the SDK)
- **Deployment target (min OS):** iOS 17.0
- **Dependency manager:** Swift Package Manager (no external packages at v1 — target zero)
- **Animation:** SwiftUI built-in (system)
- **Particles:** SwiftUI Canvas (system); thin SpriteKit layer only if needed (system)
- **Audio:** AVAudioEngine (system)
- **Haptics:** Core Haptics + UIFeedbackGenerator (system)
- **Persistence:** UserDefaults (system) for solved-levels + Echo Run high score
- **Level data:** plain JSON files in `Levels/` (no library)
- **Tests:** XCTest (system)
- **Source control:** Git + GitHub `DinovLazar/echo` (public), single branch `main`
- **Distribution:** free Apple ID signing + SideStore (no paid Apple Developer Program)

**Notes:**
- "System" frameworks (SwiftUI, AVAudioEngine, Core Haptics, XCTest, etc.) are versioned by the iOS SDK / Xcode, not pinned separately. The number that matters is the **deployment target (iOS 17.0)** and the **Xcode/Swift version** above.
- No third-party packages are planned for v1. If one is ever added, append an entry here with its exact pinned version and the reason (and log the choice in `ECHO-Decisions.md`).
- Building on a beta toolchain is a known, accepted risk (D-009). If Xcode 27 / iOS 27 advances to a new beta or to public release, append the new versions here.

---

## 2026-06-24 — Phase 1.01 scaffold (confirm + pin)

The Xcode project was created during Phase 1.01. Confirmed/observed versions and config choices:

- **Swift toolchain (confirmed installed):** `Apple Swift version 6.4 (swiftlang-6.4.0.20.104 clang-2100.3.20.102)` — matches the planned Swift 6.4 lock.
- **Swift language mode (build setting `SWIFT_VERSION`):** `6.0` (the Swift 6 language mode), set at the project level for both Debug and Release. The trivial scaffold code (App + placeholder View + one test) has no concurrency surface, so Swift 6 mode is safe; flip to `5.0` only if a later phase hits strict-concurrency friction it can't resolve.
- **Deployment target:** `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (unchanged from plan).
- **Bundle id:** `com.dinovlazar.echo` · **Display name:** `Echo` (via `INFOPLIST_KEY_CFBundleDisplayName`; `GENERATE_INFOPLIST_FILE = YES`, no standalone Info.plist).
- **Project-file format:** `ECHO.xcodeproj/project.pbxproj` hand-authored using Xcode's **file-system synchronized groups** (`PBXFileSystemSynchronizedRootGroup`), `objectVersion = 77`. No project-generation tool (no XcodeGen) was added — the zero-package goal is intact and there is no build-time tool dependency.
- **Packages:** still **zero** Swift Package dependencies.
- **Source control:** Git initialised, single branch `main`, `origin = https://github.com/DinovLazar/echo` (public).

**Environment caveat (important for the next session):** the machine that scaffolded the project had **only the Xcode Command Line Tools installed, not full Xcode** (`xcodebuild`/`simctl` unavailable). The project therefore could **not** be compiled or run in the Simulator during Phase 1.01. Versions above are confirmed from the Swift CLI; the **Xcode 27 / iOS SDK build numbers must be pinned here by the first session that opens the project in full Xcode** (Phase 1.02), along with confirmation that ⌘R builds and runs.

---

## 2026-06-24 — Phase 1.02 first device install (Code track)

The hello-grid placeholder was added. No dependency, tool, or version change this phase — recording the config facts the brief asked to capture:

- **Toolchain (unchanged):** Swift 6.4 confirmed from the CLI (`swift --version` → `Apple Swift version 6.4 (swiftlang-6.4.0.23.5 clang-2100.3.23.3)`, target `arm64-apple-macosx27.0.0`). Deployment target unchanged at `IPHONEOS_DEPLOYMENT_TARGET = 17.0`. No Swift Package dependencies added (still zero).
- **Signing:** `CODE_SIGN_STYLE = Automatic` on **both** targets (`ECHO` and `ECHOTests`) — "Automatically manage signing" is on. **No `DEVELOPMENT_TEAM` is set** in `project.pbxproj` (left for Lazar to pick his personal Apple ID team at device-install time). Already true since 1.01; confirmed unchanged here.
- **Verification performed in this environment:** `swiftc -typecheck -parse-as-library` of `ContentView.swift` + `HelloGridView.swift` against the **macOS** SDK (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`) → **exit 0 / clean** (the `#Preview` macro is excluded because its plugin ships only with full Xcode, not CLT). This is a syntax/type smoke test, **not** an iOS Simulator build.
- **Still NOT verified here (no full Xcode — same caveat as 1.01):** the iOS Simulator build, the on-device ⌘R run, the `⌘U` test run, and a real Simulator/device screenshot. **Pinning still owed:** the exact **Xcode 27 / iOS SDK build numbers** must be appended by the first session that opens the project in full Xcode (Lazar's Mac).
- **Build-config fix during Lazar's first Xcode build (D-012):** the first compile failed with `Multiple commands produce …/ECHO.app/.gitkeep` (1 error + 2 "duplicate output file" warnings). **Cause:** Xcode's file-system synchronized groups (`PBXFileSystemSynchronizedRootGroup`) treat `.gitkeep` as a **bundle resource** and copy it — the three identically-named `ECHO/{Models,Audio,Haptics}/.gitkeep` files all map to `ECHO.app/.gitkeep` and collide. **Fix:** removed those three `.gitkeep` files (the empty folders are now untracked until a real source file lands; `.gitkeep` files **outside** any synchronized group — `Levels/`, `docs/design-handovers/` — are safe and were kept). **Rule for this repo:** never place a `.gitkeep` (or any duplicate-named throwaway file) inside `ECHO/` or `ECHOTests/`; to keep an in-target folder, add a real source file or exclude the keeper via a `PBXFileSystemSynchronizedBuildFileExceptionSet`. Corrects the Phase 1.01 report's incorrect assumption that synchronized groups ignore dotfiles.
- **First successful build verified (Lazar's Xcode 27):** after the D-012 fix, the project builds, installs, and launches on the **iOS 27.0 Simulator, iPhone 17 Pro**. This is the first confirmed compile of the project (Phase 1.01 shipped unbuilt). **Still owed:** the exact **Xcode 27 / iOS SDK build numbers** — capture `xcodebuild -version` on the build Mac and pin them here (the Code environment can only confirm Swift 6.4 from the CLI). Physical-device install and a `⌘U` test run are still pending.

---

## 2026-06-24 — Phase 1.03 grid + move (Code track)

The first real model code and tests were added. **No dependency, tool, or version change this phase** — still Swift 6.4, zero Swift Package dependencies, deployment target `IPHONEOS_DEPLOYMENT_TARGET = 17.0`. Recording the config-relevant facts and how they were verified:

- **Actor-isolation regime (existing build setting, now load-bearing):** the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (set since 1.01) makes unannotated declarations main-actor-isolated. Phase 1.03's model is written to that regime per **D-013**: `GameState` is `@MainActor @Observable`; the pure value types `GridCoordinate`/`Direction` are explicitly `nonisolated`/`Sendable`; the XCTest case is `@MainActor`. The **test target does not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` (so it defaults to nonisolated) — the explicit annotations make the model correct under both.
- **Verification performed in this environment (CLT only):**
  - Models type-check clean under the app regime (`swiftc -typecheck -parse-as-library -default-isolation MainActor -sdk <MacOSX.sdk>`) **and** under the test regime (no flag) → exit 0 each.
  - Views + models type-check clean under the app regime → exit 0, after a smoke-test substitution for the two SwiftUI macros that the **CLT lacks** (`@State` → plain property; `#Preview` stripped). The production files retain both and compile in real Xcode.
  - A standalone executable built from the real model sources runs every XCTest scenario → **18/18 PASS**.
- **`-default-isolation MainActor`** is the `swiftc` frontend flag corresponding to the `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting — recorded here for reproducible local type-checking in a no-Xcode environment.
- **Still NOT verified here (no full Xcode — same caveat as 1.01/1.02):** the iOS Simulator build, the on-device ⌘R run, and the **⌘U** XCTest run. **Pinning still owed:** the exact **Xcode 27 / iOS SDK build numbers** (paste `xcodebuild -version` on Lazar's Mac).

---

## 2026-06-24 — Phase 1.04 fold / record & replay (Code track)

The fold mechanic (`Echo` type, `GameState` record/fold/clear, echo rendering, debug bar) was added. **No dependency, tool, or version change this phase** — still Swift 6.4, **zero** Swift Package dependencies, deployment target `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, bundle id `com.dinovlazar.echo`, display name `Echo` all unchanged. Recording the config-relevant facts and how they were verified:

- **Concurrency regime unchanged (D-013, extended):** the new `Echo` value type follows the established discipline — `nonisolated struct Echo: Identifiable, Equatable, Sendable` (a `UUID` + `[Direction]`, both Sendable), so it is usable from any context like `GridCoordinate`/`Direction`. `GameState` stays `@MainActor @Observable`; the test case stays `@MainActor`. App target still sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the test target does not.
- **Toolchain caveat refined:** under this Swift 6.4 CLT, SwiftUI's **`@State` is now an attached macro** (`SwiftUIMacros.StateMacro`) whose plugin ships only with full Xcode — so, like `#Preview`, it can't be expanded here. For the views-type-check smoke test, `@State` is de-macroed to a plain property and `#Preview` is stripped in a throwaway copy; the production sources keep both and compile in real Xcode. `import XCTest` also does not resolve under CLT (confirmed `no such module 'XCTest'`).
- **Verification performed in this environment (CLT only):**
  - Model (`GridCoordinate` + `Direction` + `Echo` + `GameState`) type-checks clean under the app regime (`swiftc -typecheck -parse-as-library -default-isolation MainActor -sdk <MacOSX.sdk>`) **and** under the test regime (no flag) → exit 0 each.
  - Views + model type-check clean under the app regime → exit 0 (with the `@State`/`#Preview` macro substitution above).
  - The verbatim `ECHOTests.swift` (minus its two CLT-unresolvable imports) type-checks against the model API under the test regime via a minimal **XCTest shim** (`XCTestCase` + the `XCTAssert*` used) → exit 0.
  - A standalone executable built from the **real** model sources (`main.swift` driving `@MainActor GameState` via `MainActor.assumeIsolated`) runs every test scenario (all 1.03 move checks + all 1.04 fold/replay checks) → **39/39 PASS**.
- **Still NOT verified here (no full Xcode — same caveat as 1.01–1.03):** the iOS Simulator build, the on-device ⌘R run, and the **⌘U** XCTest run, plus a real screenshot. **Pinning still owed:** the exact **Xcode 27 / iOS SDK build numbers** (paste `xcodebuild -version` on Lazar's Mac).

---

## 2026-06-24 — Phase 1.05 collision + restart (Code track)

The collision rule and death restart (`GameState.playerCollides(...)`, `GameState.restartRun()`, `move(_:)` wiring) plus the collision test suite were added. **No dependency, tool, or version change this phase** — still Swift 6.4, **zero** Swift Package dependencies, deployment target `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, bundle id `com.dinovlazar.echo`, display name `Echo`, all unchanged. No `.pbxproj` edit (synchronized groups; no files added/renamed). Recording the config-relevant facts and how they were verified:

- **Concurrency regime unchanged (D-013):** the new collision predicate and `restartRun()` are plain methods on the `@MainActor @Observable GameState`; they read only `start`/`echoes` and the `nonisolated` value types, so nothing new crosses an isolation boundary. App target still sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the test target does not.
- **Toolchain still CLT-only (confirmed):** `xcodebuild -version` → `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`; `simctl` absent. So the exact **Xcode 27 / iOS SDK build numbers remain unpinned** — still owed from 1.02, to be captured on Lazar's Mac. Swift CLI confirms `Apple Swift version 6.4 (swiftlang-6.4.0.23.5 clang-2100.3.23.3)`, target `arm64-apple-macosx27.0.0`; macOS SDK present is `MacOSX27.0.sdk` (CLT).
- **Verification performed in this environment (CLT only):**
  - Model (`GridCoordinate` + `Direction` + `Echo` + `GameState`) type-checks clean under the app regime (`swiftc -typecheck -parse-as-library -default-isolation MainActor -sdk <MacOSX.sdk>`) **and** under the test regime (no flag) → exit 0 each.
  - Views + model type-check clean under the app regime → exit 0 (with the `@State`/`#Preview` macro substitution CLT requires).
  - The verbatim `ECHOTests.swift` (minus its two CLT-unresolvable imports) type-checks against the model API under the test regime via a minimal **XCTest shim** (confirms `playerCollides` and the new test methods compile) → exit 0.
  - A standalone executable built from the **real** model sources runs every test scenario (all 1.03 move checks + all 1.04 fold/replay checks + all 1.05 collision/restart checks) → **134/134 PASS**.
- **Still NOT verified here (no full Xcode — same caveat as 1.01–1.04):** the iOS Simulator build, the on-device ⌘R run, and the **⌘U** XCTest run, plus a real screenshot of the death snap-back. **Pinning still owed:** the exact **Xcode 27 / iOS SDK build numbers** (paste `xcodebuild -version` on Lazar's Mac).

---

## 2026-06-25 — Phase 1.06 room contents, level data & win (Code track)

The puzzle contents (walls/switches/doors/hazards/exit/win/budget), the `Level`/`Hazard` models + `LevelLoader`, the level JSON, and the rendering/debug-bar additions were added. **No dependency or external-package change this phase** — still Swift 6.4, **zero** Swift Package dependencies, deployment target `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, bundle id `com.dinovlazar.echo`, display name `Echo`, all unchanged.

- **One project-file change (`.pbxproj`) — Levels bundling (D-025):** a **third `PBXFileSystemSynchronizedRootGroup` (`Levels`, id `…B432`)** was added to the project's main group and to the **app target's `fileSystemSynchronizedGroups`**, so the repo-root `Levels/*.json` bundle as app resources (the same mechanism already used for the `ECHO` and `ECHOTests` source roots — `.json` files are auto-classified as bundle resources). The obsolete `Levels/.gitkeep` was removed (the folder now holds real files; it sits outside `ECHO/`, so no D-012 name-collision risk). **This edit was made blind — the CLT has no `xcodebuild` to validate it — and is flagged in `current-state.md` / the completion report for Lazar to confirm on first ⌘R** (the loader degrades to a bare board, not a crash, if bundling somehow fails).
- **Concurrency regime unchanged (D-013):** the new value types `Level`/`Switch`/`Door`/`Hazard` are all `nonisolated` + `Sendable` (+ `Decodable`), like `GridCoordinate`/`Direction`/`Echo`; `GridCoordinate` gained `Codable` and `Direction` gained a `String` raw value + `Codable`. `GameState`'s new members are plain methods/derivations on the existing `@MainActor @Observable` class. App target still sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the test target does not.
- **Toolchain still CLT-only (confirmed):** `Apple Swift version 6.4 (swiftlang-6.4.0.23.5 clang-2100.3.23.3)`, target `arm64-apple-macosx27.0.0`; `xcodebuild`/`simctl` absent. So the exact **Xcode 27 / iOS SDK build numbers remain unpinned** — still owed from 1.02, to be captured on Lazar's Mac. macOS SDK used for type-checks: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`.
- **Verification performed in this environment (CLT only):**
  - Full model (`GridCoordinate` + `Direction` + `Echo` + `Hazard` + `Level` + `GameState`) type-checks clean under the app regime (`-default-isolation MainActor`) **and** the test regime (no flag) → exit 0 each.
  - Views + model type-check clean under the app regime → exit 0 (with the `@State`/`#Preview` macro substitution CLT requires; `@State` swapped for a property wrapper with a `nonmutating set` to preserve SwiftUI's mutation semantics).
  - The verbatim `ECHOTests.swift` (its `import XCTest`/`@testable import ECHO` swapped for `import Foundation` + a minimal XCTest shim) type-checks against the model API under the test regime → exit 0.
  - A standalone executable built from the **real** model sources runs every test scenario (1.03 + 1.04 + 1.05 + all new 1.06: walls, switch/door, canonical solve, hazard land-on/swap/loop, win, collision-before-win, budget, JSON decode, level-load reset) **and** loads all three proof rooms from disk and plays their solutions (plus the naive-fail paths) → **172/172 PASS**.
- **Still NOT verified here (no full Xcode — same caveat as 1.01–1.05):** the iOS Simulator build, the on-device ⌘R run, the **⌘U** XCTest run, a real screenshot, and that the **`Levels/` bundling edit** copies the JSON into the app bundle at runtime. **Pinning still owed:** the exact **Xcode 27 / iOS SDK build numbers** (paste `xcodebuild -version` on Lazar's Mac).

---

## 2026-06-26 — Phase 2.02 board look + motion (Code track)

The real visual design and step motion were added: a `Theme` colour-token layer (`ECHO/Theme/Theme.swift`), the named easing curves (`ECHO/Theme/Motion.swift`), and a full rewrite of `BoardView` to render every element to spec with sliding/squash motion. **No dependency, tool, or external-package change this phase** — still Swift 6.4, **zero** Swift Package dependencies, deployment target `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, bundle id `com.dinovlazar.echo`, display name `Echo`, all unchanged. **No `.pbxproj` structural edit** — the two new files live under the existing `ECHO` file-system-synchronized root group and are picked up automatically (no target-membership edit needed).

- **System frameworks only (unchanged set):** SwiftUI, including `Animation.timingCurve` / `interpolatingSpring` for the curves and `keyframeAnimator(initialValue:trigger:content:keyframes:)` for the squash/anticipation. `keyframeAnimator` is iOS 17.0+ — within the deployment target, so no floor change. No new framework imports beyond `SwiftUI`.
- **Concurrency regime unchanged (D-013/D-040):** every new token type (`Theme`, `ThemeMode`, `BoardMetrics`, `Curve`, `Motion`, `ThemeEnvironmentKey`) is explicitly `nonisolated` (and `Sendable` where it holds state), and the `Color(hex:)` extension init is `nonisolated`, so the `EnvironmentKey`/`Color` conformances satisfy SwiftUI's `nonisolated` requirements under the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — the same rule D-040 set. App target still sets default-MainActor; the test target does not. **No engine/model/test file was touched.**
- **Toolchain still CLT-only (confirmed):** `Apple Swift version 6.4 (swiftlang-6.4.0.23.5 clang-2100.3.23.3)`, target `arm64-apple-macosx27.0.0`; `xcodebuild`/`simctl` absent. macOS SDK used for type-checks: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` (the SDK's `SwiftUI.framework` is present, so the view code type-checks).
- **Verification performed in this environment (CLT only):**
  - The token layer (`Theme.swift` + `Motion.swift`) type-checks clean under the app regime (`swiftc -typecheck -parse-as-library -swift-version 6 -default-isolation MainActor -sdk <MacOSX.sdk>`) → **exit 0** — this validates the `Color(hex:)` isolation, the `EnvironmentKey` conformance, and the curve/spring signatures.
  - The **real** model sources type-check clean under the app regime (incl. `@Observable` expansion) → exit 0 — confirms the engine is still well-formed and untouched.
  - The full app (models + theme + the real `BoardView.swift`/`ContentView.swift`/`ECHOApp.swift`) type-checks clean under the app regime with the **CLT-only macro substitution** the prior phases established (`@State` swapped for a property wrapper with a `nonmutating set`; `#Preview` stripped) → **exit 0, no warnings** — this validates the new SwiftUI API usage end-to-end: `keyframeAnimator` with two `KeyframeTrack`s over a `Squash` value, the `.transaction { … }` enemy-retiming, the `accentGlow` `View` extension, `scaleEffect(x:y:)`, and `commitMove`'s read-only prediction logic. The only constructs not exercised here are the `@State`/`#Preview` macros themselves (CLT lacks their plugins); they are standard and expand in real Xcode.
- **Still NOT verified here (no full Xcode — same caveat as 1.01–1.08 + hotfix):** the iOS Simulator build, the on-device ⌘R run (the real look + 60fps glide), the **⌘U** XCTest run (the green baseline + post-change re-run the brief asks for), a real screenshot, and the runtime `Levels/` bundling. **Pinning still owed (carried from 1.02):** the exact **Xcode 27 / iOS SDK build numbers** — this environment has no Xcode, so they cannot be captured here. Capture on Lazar's Mac with `xcodebuild -version` **and** `xcodebuild -version -sdk iphoneos ProductBuildVersion` (or Xcode → About Xcode), and pin them in a follow-up entry here.

