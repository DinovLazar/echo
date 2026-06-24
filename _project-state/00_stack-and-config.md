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

