# App-First Windows Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the installed-Windows VM dashboard with a responsive Windows application home that opens apps as native macOS windows and shows the full Windows desktop only after explicit selection.

**Architecture:** Add a pure installed-home presentation resolver and a dedicated SwiftUI home canvas. Feed the existing app catalog, pending launch, mirrored-window counts, runtime state, and executable action closures through `VMRuntimeView`; do not change protocol or VM behavior. Remove the old centered machine hero, permanent progress strip, and duplicate bottom quick-launch dock after the new canvas owns those interactions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Node.js built-in test runner, Bash macOS lifecycle harness

## Global Constraints

- The normal path is “open a Windows app,” not “open a VM.”
- Default `showsWindowsDesktop` to `false`; never switch it to `true` because the runtime or display becomes available.
- Keep the real native or captured Windows desktop behind an explicit `Windows Desktop` action.
- Do not change VM boot, guest-agent discovery, protocol messages, mirrored HWND presentation, Windows installation, download behavior, or settings operations.
- Do not fabricate an app catalog or readiness when discovery has not succeeded.
- Do not expose executable paths, HWND values, provider names, protocol data, or raw QEMU errors on the app home.
- Keep one edge-to-edge home canvas without a nested monitor, centered Windows 11 hero, permanent progress-card strip, or duplicate bottom dock.
- Support the existing `820 x 560` minimum without clipping; scroll only the app region when needed.
- Preserve `/Users/uulab/Library/Application Support/Veil/Downloads/Win11_25H2_Korean_Arm64_v2.iso` and all Veil application-support data during lifecycle verification.

---

### Task 1: Model Installed-Home and Tile States

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/App/InstalledAppHomePresentation.swift`
- Create: `apps/mac-host/Tests/VeilHostShellTests/InstalledAppHomePresentationTests.swift`

**Interfaces:**
- Consumes: `VMRuntimeState`, `HostDashboardPhase`, app count, pending app ID, open-window count, live-agent evidence, and user-visible error presence.
- Produces: `InstalledAppHomePresentation.resolve(...)`, `InstalledAppTilePresentation.resolve(...)`, `InstalledAppHomePhase`, `InstalledAppHomeTone`, and `InstalledAppHomeRecoveryRoute` for Tasks 2 and 3.

- [ ] **Step 1: Write failing presentation tests**

Create `InstalledAppHomePresentationTests.swift` with these imports and representative assertions:

```swift
import Testing
import VeilHostCore
@testable import VeilHostShell

struct InstalledAppHomePresentationTests {
    @Test("ready Windows shows an interactive app home")
    func readyHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .running,
            dashboardPhase: .connected,
            hasLiveAgentConnection: true,
            appCount: 3,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .ready)
        #expect(result.title == "Windows Apps")
        #expect(result.detail == "Choose an app to open it in its own Mac window.")
        #expect(result.isGridEnabled)
        #expect(result.recoveryRoute == nil)
    }

    @Test("stopped Windows keeps app tiles available")
    func stoppedHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .stopped,
            dashboardPhase: .idle,
            hasLiveAgentConnection: false,
            appCount: 3,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .stopped)
        #expect(result.isGridEnabled)
        #expect(result.detail == "Windows starts automatically when you open an app.")
    }

    @Test("queued app shows one opening state")
    func queuedHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .starting,
            dashboardPhase: .launching,
            hasLiveAgentConnection: false,
            appCount: 3,
            pendingAppId: "winapp_notepad",
            errorMessage: nil
        )
        let tile = InstalledAppTilePresentation.resolve(
            appId: "winapp_notepad",
            pendingAppId: "winapp_notepad",
            openWindowCount: 0,
            dashboardPhase: .launching
        )

        #expect(result.phase == .starting)
        #expect(!result.isGridEnabled)
        #expect(tile.statusText == "Opening…")
        #expect(tile.showsProgress)
        #expect(tile.accessibilityValue == "Opening")
    }

    @Test("missing catalog offers refresh without invented apps")
    func missingCatalog() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .running,
            dashboardPhase: .connected,
            hasLiveAgentConnection: true,
            appCount: 0,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .catalogUnavailable)
        #expect(result.recoveryRoute == .refresh)
        #expect(result.recoveryTitle == "Check Again")
    }

    @Test("technical failures use safe product copy")
    func safeFailureCopy() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .failed,
            dashboardPhase: .failed,
            hasLiveAgentConnection: false,
            appCount: 3,
            pendingAppId: nil,
            errorMessage: "QEMU failed at /Users/test/vm.img"
        )

        #expect(result.phase == .failure)
        #expect(result.recoveryRoute == .effectiveAction)
        #expect(!result.detail.contains("QEMU"))
        #expect(!result.detail.contains("/Users"))
    }
}
```

Add cases in the same file for `.reconnecting`, `.loading`, `.suspended`, an unqueued tile with two open windows, and a queued tile that already has an open window.

- [ ] **Step 2: Run the focused tests and observe the missing types**

Run:

```bash
swift test --package-path apps/mac-host --filter InstalledAppHomePresentationTests
```

Expected: compilation fails because `InstalledAppHomePresentation` and `InstalledAppTilePresentation` do not exist.

- [ ] **Step 3: Implement the pure resolver**

Create `InstalledAppHomePresentation.swift` with this public-to-module interface:

```swift
import VeilHostCore

enum InstalledAppHomePhase: Equatable {
    case ready
    case stopped
    case starting
    case reconnecting
    case loading
    case catalogUnavailable
    case failure
}

enum InstalledAppHomeTone: Equatable {
    case neutral
    case progress
    case warning
}

enum InstalledAppHomeRecoveryRoute: Equatable {
    case effectiveAction
    case refresh
}

struct InstalledAppHomePresentation: Equatable {
    let phase: InstalledAppHomePhase
    let title: String
    let detail: String
    let tone: InstalledAppHomeTone
    let isGridEnabled: Bool
    let recoveryTitle: String?
    let recoverySymbolName: String?
    let recoveryRoute: InstalledAppHomeRecoveryRoute?

    static func resolve(
        runtimeState: VMRuntimeState,
        dashboardPhase: HostDashboardPhase,
        hasLiveAgentConnection: Bool,
        appCount: Int,
        pendingAppId: String?,
        errorMessage: String?
    ) -> Self
}

struct InstalledAppTilePresentation: Equatable {
    let statusText: String?
    let showsProgress: Bool
    let accessibilityValue: String

    static func resolve(
        appId: String,
        pendingAppId: String?,
        openWindowCount: Int,
        dashboardPhase: HostDashboardPhase
    ) -> Self
}
```

Implement `InstalledAppHomePresentation.resolve` with this precedence and fixed copy:

```swift
if errorMessage != nil
    || dashboardPhase == .failed
    || runtimeState == .failed
    || runtimeState == .unsupported
    || runtimeState == .notConfigured {
    return .init(
        phase: .failure,
        title: "Windows needs attention",
        detail: "Veil could not make Windows apps available. Try the recovery action or open Settings for details.",
        tone: .warning,
        isGridEnabled: false,
        recoveryTitle: "Try Again",
        recoverySymbolName: "arrow.clockwise",
        recoveryRoute: .effectiveAction
    )
}

if appCount == 0 {
    if dashboardPhase == .loading || runtimeState == .starting {
        return .init(
            phase: .loading,
            title: "Windows Apps",
            detail: "Loading your Windows apps…",
            tone: .progress,
            isGridEnabled: false,
            recoveryTitle: nil,
            recoverySymbolName: nil,
            recoveryRoute: nil
        )
    }

    return .init(
        phase: .catalogUnavailable,
        title: "Windows Apps",
        detail: "Veil could not load the Windows app list.",
        tone: .warning,
        isGridEnabled: false,
        recoveryTitle: "Check Again",
        recoverySymbolName: "arrow.clockwise",
        recoveryRoute: .refresh
    )
}

if dashboardPhase == .reconnecting
    || (runtimeState == .running && !hasLiveAgentConnection) {
    return .init(
        phase: .reconnecting,
        title: "Windows Apps",
        detail: pendingAppId == nil
            ? "Reconnecting to Windows apps…"
            : "Reconnecting so your selected app can open…",
        tone: .progress,
        isGridEnabled: false,
        recoveryTitle: "Reconnect",
        recoverySymbolName: "bolt.horizontal.circle",
        recoveryRoute: .effectiveAction
    )
}

if dashboardPhase == .loading {
    return .init(
        phase: .loading,
        title: "Windows Apps",
        detail: "Checking Windows apps…",
        tone: .progress,
        isGridEnabled: false,
        recoveryTitle: nil,
        recoverySymbolName: nil,
        recoveryRoute: nil
    )
}

if runtimeState == .starting || dashboardPhase == .launching {
    return .init(
        phase: .starting,
        title: "Windows Apps",
        detail: pendingAppId == nil ? "Starting Windows…" : "Opening your selected app…",
        tone: .progress,
        isGridEnabled: false,
        recoveryTitle: nil,
        recoverySymbolName: nil,
        recoveryRoute: nil
    )
}

if runtimeState == .stopped || runtimeState == .suspended {
    return .init(
        phase: .stopped,
        title: "Windows Apps",
        detail: "Windows starts automatically when you open an app.",
        tone: .neutral,
        isGridEnabled: true,
        recoveryTitle: nil,
        recoverySymbolName: nil,
        recoveryRoute: nil
    )
}

return .init(
    phase: .ready,
    title: "Windows Apps",
    detail: "Choose an app to open it in its own Mac window.",
    tone: .neutral,
    isGridEnabled: true,
    recoveryTitle: nil,
    recoverySymbolName: nil,
    recoveryRoute: nil
)
```

Implement tile resolution so the matching pending ID returns `Opening…`, `showsProgress: true`, and accessibility value `Opening`; otherwise return `1 window` or `N windows` when `openWindowCount > 0`, and `Ready` with no visible status when the count is zero. Never interpolate `errorMessage`.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --package-path apps/mac-host --filter InstalledAppHomePresentationTests
```

Expected: all installed-home presentation tests pass.

- [ ] **Step 5: Commit the state model**

```bash
git add apps/mac-host/Sources/VeilHostShell/App/InstalledAppHomePresentation.swift \
  apps/mac-host/Tests/VeilHostShellTests/InstalledAppHomePresentationTests.swift
git commit -m "Model the installed Windows app home"
```

---

### Task 2: Build the Responsive Windows App Home

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/Views/InstalledWindowsAppHome.swift`
- Modify: `harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs`

**Interfaces:**
- Consumes: `InstalledAppHomePresentation`, `[WindowsApp]`, selected and pending app IDs, `[String: Int]` open-window counts, and existing action closures.
- Produces: `InstalledWindowsAppHome` for Task 3.

- [ ] **Step 1: Add a failing source contract**

Add this test to `macos-app-lifecycle.test.mjs`:

```javascript
test("installed Windows presents one responsive app-first home", async () => {
  const home = await readRootFile(
    "apps/mac-host/Sources/VeilHostShell/Views/InstalledWindowsAppHome.swift",
  );

  assert.match(home, /struct InstalledWindowsAppHome: View/);
  assert.match(home, /GeometryReader/);
  assert.match(home, /LazyVGrid/);
  assert.match(home, /GridItem\(\.adaptive/);
  assert.match(home, /Text\(presentation\.title\)/);
  assert.match(home, /Label\("Windows Desktop", systemImage: "display"\)/);
  assert.match(home, /\.accessibilityAddTraits\(\.isHeader\)/);
  assert.match(home, /\.accessibilityValue\(tilePresentation\.accessibilityValue\)/);
  assert.match(home, /Data\(base64Encoded:/);
  assert.doesNotMatch(home, /exePath|HWND|QEMU|protocol/);
});
```

- [ ] **Step 2: Run the lifecycle source contract and observe the missing file**

Run:

```bash
node --test harness/macos-app-lifecycle/test/*.test.mjs
```

Expected: the new test fails because `InstalledWindowsAppHome.swift` does not exist.

- [ ] **Step 3: Implement the home canvas and adaptive grid**

Create this exact initializer surface:

```swift
import AppKit
import SwiftUI
import VeilHostCore

struct InstalledWindowsAppHome: View {
    let presentation: InstalledAppHomePresentation
    let apps: [WindowsApp]
    @Binding var selectedAppId: String?
    let pendingAppId: String?
    let openWindowCounts: [String: Int]
    let canShowDesktop: Bool
    let launchAction: () -> Void
    let showDesktopAction: () -> Void
    let settingsAction: () -> Void
    let effectiveRecoveryAction: () -> Void
    let refreshAction: () -> Void
}
```

Use `GeometryReader` and `let compact = proxy.size.width < 900 || proxy.size.height < 600`. Render a full-canvas blue-to-charcoal gradient, a stable top row, and a `ScrollView` containing:

```swift
LazyVGrid(
    columns: [
        GridItem(
            .adaptive(minimum: compact ? 112 : 148, maximum: compact ? 150 : 188),
            spacing: compact ? 12 : 18
        )
    ],
    spacing: compact ? 12 : 18
)
```

Render each application as one plain button. Decode `app.iconPngBase64` with `Data(base64Encoded:)` and `NSImage(data:)`; use `note.text`, `plus.forwardslash.minus`, `paintpalette`, or `app.window` fallbacks by app ID. On activation set `selectedAppId = app.id` before calling `launchAction()`.

The tile must display `InstalledAppTilePresentation.resolve(...)`, an inline `ProgressView()` for the pending tile, and a subdued open-window count. Disable tiles when `presentation.isGridEnabled` is false. Add `.help("Open \(app.name) as a Mac window")`, `.accessibilityLabel("Open \(app.name)")`, and `.accessibilityValue(tilePresentation.accessibilityValue)`.

The top-right action row contains a bordered `Label("Windows Desktop", systemImage: "display")` only when `canShowDesktop`, and icon-only settings with `.accessibilityLabel("Settings")`. Render one recovery button only when `recoveryTitle`, `recoverySymbolName`, and `recoveryRoute` exist; dispatch `.effectiveAction` to `effectiveRecoveryAction` and `.refresh` to `refreshAction`.

Use only a 0.2-second state transition, disabled when `accessibilityReduceMotion` is true. Do not add continuous decorative animation or a card around the entire canvas.

- [ ] **Step 4: Run the focused state and source-contract tests**

Run:

```bash
swift test --package-path apps/mac-host --filter InstalledAppHomePresentationTests
node --test harness/macos-app-lifecycle/test/*.test.mjs
```

Expected: both commands pass.

- [ ] **Step 5: Commit the app home**

```bash
git add apps/mac-host/Sources/VeilHostShell/Views/InstalledWindowsAppHome.swift \
  harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs
git commit -m "Build the app-first Windows home"
```

---

### Task 3: Integrate the Home and Make Desktop Explicit

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift:26-310`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift:4-240,1530-1940,2605-2760,3038-3103`
- Modify: `apps/mac-host/Tests/VeilHostShellTests/RuntimeDisplaySelectionTests.swift`
- Modify: `harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs`

**Interfaces:**
- Consumes: `InstalledWindowsAppHome` and the Task 1 presentation types.
- Produces: one installed home inside `WindowsSetupDisplayPanel`, with explicit desktop entry and the existing app-launch/settings/recovery actions.

- [ ] **Step 1: Replace dock-policy tests with explicit-desktop policy tests**

Replace `RuntimeWorkspacePresentationPolicyTests` with:

```swift
struct InstalledWorkspacePresentationPolicyTests {
    @Test("installed workspace defaults to the app home")
    func defaultsToAppHome() {
        #expect(!InstalledWorkspacePresentationPolicy.initiallyShowsDesktop)
    }

    @Test("desktop closes when its display is unavailable")
    func closesUnavailableDesktop() {
        #expect(
            !InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
                requested: true,
                runtimeState: .stopped,
                hasDesktopDisplay: true
            )
        )
        #expect(
            !InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
                requested: true,
                runtimeState: .running,
                hasDesktopDisplay: false
            )
        )
    }

    @Test("desktop remains visible only after a valid request")
    func keepsValidDesktopRequest() {
        #expect(
            InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
                requested: true,
                runtimeState: .running,
                hasDesktopDisplay: true
            )
        )
    }
}
```

- [ ] **Step 2: Add a failing integration source contract**

Add this test to `macos-app-lifecycle.test.mjs`:

```javascript
test("installed workspace does not auto-open or duplicate the Windows desktop", async () => {
  const detail = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift");
  const runtime = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(detail, /showsWindowsDesktop = InstalledWorkspacePresentationPolicy\.initiallyShowsDesktop/);
  assert.match(runtime, /InstalledWindowsAppHome\(/);
  assert.match(runtime, /Label\("Show Apps", systemImage: "macwindow"\)/);
  assert.doesNotMatch(detail, /WindowsQuickLaunchPanel|WindowsQuickLaunchTile/);
  assert.doesNotMatch(runtime, /installedMachineContent|AppRuntimeProgressStrip|appOpenFlowItems/);
  assert.doesNotMatch(runtime, /showsFullDesktop = newState == \.running/);
  assert.doesNotMatch(runtime, /!hadDesktopDisplay[\s\S]*showsFullDesktop = true/);
});
```

- [ ] **Step 3: Route app data into the runtime view**

In `VMRuntimeView`, add these stored inputs:

```swift
var apps: [WindowsApp]
var mirrorSessions: [WindowMirrorSession]
@Binding var selectedWindowsAppId: String?
var dashboardPhase: HostDashboardPhase
var hasLiveAgentConnection: Bool
```

Pass them from `DetailView` as `model.apps`, `model.mirrorSessions`, `$model.selectedAppId`, `model.phase`, and `model.hasLiveAgentConnection`. Forward the same values into `WindowsSetupDisplayPanel`.

Replace the `DetailView` root `ZStack` with the single `VMRuntimeView`, delete `shouldShowAppDock`, `RuntimeWorkspacePresentationPolicy`, `WindowsQuickLaunchPanel`, and `WindowsQuickLaunchTile`, and initialize desktop state with:

```swift
@State private var showsWindowsDesktop = InstalledWorkspacePresentationPolicy.initiallyShowsDesktop
```

- [ ] **Step 4: Implement explicit desktop policy and installed-stage composition**

Add this policy next to the existing runtime display policy:

```swift
enum InstalledWorkspacePresentationPolicy {
    static let initiallyShowsDesktop = false

    static func shouldKeepDesktopVisible(
        requested: Bool,
        runtimeState: VMRuntimeState,
        hasDesktopDisplay: Bool
    ) -> Bool {
        requested && runtimeState == .running && hasDesktopDisplay
    }
}
```

In `WindowsSetupDisplayPanel`, replace automatic desktop handoff with one-way invalidation:

```swift
.onAppear {
    showsFullDesktop = InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
        requested: showsFullDesktop,
        runtimeState: snapshot.state,
        hasDesktopDisplay: hasDesktopDisplay
    )
}
.onChange(of: snapshot.state) { _, newState in
    showsFullDesktop = InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
        requested: showsFullDesktop,
        runtimeState: newState,
        hasDesktopDisplay: hasDesktopDisplay
    )
}
.onChange(of: hasDesktopDisplay) { _, newValue in
    showsFullDesktop = InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
        requested: showsFullDesktop,
        runtimeState: snapshot.state,
        hasDesktopDisplay: newValue
    )
}
```

When `showsFullDesktop && hasDesktopDisplay`, render the existing real display surface and one floating `Show Apps` button. Otherwise render `InstalledWindowsAppHome` with:

```swift
InstalledWindowsAppHome(
    presentation: installedHomePresentation,
    apps: apps,
    selectedAppId: $selectedWindowsAppId,
    pendingAppId: pendingLaunch.appId,
    openWindowCounts: Dictionary(grouping: mirrorSessions, by: { $0.window.appId }).mapValues(\.count),
    canShowDesktop: snapshot.state == .running && hasDesktopDisplay,
    launchAction: launchWindowsAppAction,
    showDesktopAction: { showsFullDesktop = true },
    settingsAction: detailsAction,
    effectiveRecoveryAction: runEffectivePrimaryAction,
    refreshAction: refreshAction
)
```

Derive `installedHomePresentation` through `InstalledAppHomePresentation.resolve(...)`. Delete `installedMachineContent`, `horizontalActions`, `AppRuntimeProgressStrip`, `appOpenFlowItems`, and the installed-progress-only helper properties. Keep `InstallFlowItem` and `flowItems` because first-run setup still uses them. Simplify `progressFraction` to calculate only from `flowItems` when install simulation is idle.

- [ ] **Step 5: Run focused tests and fix only integration errors**

Run:

```bash
swift test --package-path apps/mac-host --filter InstalledAppHomePresentationTests
swift test --package-path apps/mac-host --filter RuntimeDisplaySelectionTests
node --test harness/macos-app-lifecycle/test/*.test.mjs
```

Expected: presentation, desktop-policy, display-selection, and source-contract tests pass.

- [ ] **Step 6: Commit the integrated installed home**

```bash
git add apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift \
  apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift \
  apps/mac-host/Tests/VeilHostShellTests/RuntimeDisplaySelectionTests.swift \
  harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs
git commit -m "Make Windows apps the default workspace"
```

---

### Task 4: Regression, Lifecycle, Installed-App, and Visual Verification

**Files:**
- Create: `docs/checklists/2026-08-04-app-first-windows-home.md`
- Modify only if a verification failure exposes a defect: files already listed in Tasks 1-3

**Interfaces:**
- Consumes: the completed installed-home implementation and existing build/install/uninstall scripts.
- Produces: passing regression evidence, a replaced `/Applications/Veil.app`, preserved Windows media and support data, and a completed verification checklist.

- [ ] **Step 1: Record immutable Windows ISO evidence before lifecycle tests**

Run:

```bash
ISO_PATH="/Users/uulab/Library/Application Support/Veil/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
stat -f '%z %m' "$ISO_PATH"
```

Expected: size `7951140864`; retain the reported modification epoch for the final comparison.

- [ ] **Step 2: Run full automated verification**

Run:

```bash
swift test --package-path apps/mac-host
node --test harness/macos-app-lifecycle/test/*.test.mjs
./script/build_and_run.sh --verify
./script/test_macos_lifecycle.sh --skip-build
```

Expected: all Swift tests, lifecycle source contracts, app-bundle verification, guarded replace, quarantine cleanup, uninstall, support-data preservation, reinstall, and launch verification pass.

- [ ] **Step 3: Replace the installed application and verify signing**

Run:

```bash
./script/install_macos.sh --replace
codesign --verify --deep --strict /Applications/Veil.app
open -n /Applications/Veil.app
```

Expected: `/Applications/Veil.app` is the newly built bundle, passes strict deep code-sign verification, and launches without a damaged-app warning.

- [ ] **Step 4: Perform installed-app visual and input checks**

Check the installed app at regular size and `820 x 560`:

- default installed state is `Windows Apps`, not the Windows desktop;
- no nested monitor frame, Windows 11 hero, bottom dock, or progress-card strip appears;
- discovered icons or deterministic fallbacks render cleanly;
- long names truncate without overlapping status;
- tile hover, pressed, keyboard focus, Return/Space activation, queued progress, and window counts are legible;
- `Windows Desktop` appears only when a real display is available;
- `Windows Desktop` opens the real VM surface and `Show Apps` returns to the home;
- loading, reconnecting, empty catalog, and safe failure states show one contextual message and no raw technical detail.

- [ ] **Step 5: Exercise real uninstall and reinstall without deleting user data**

Run:

```bash
./script/uninstall_macos.sh
test ! -e /Applications/Veil.app
test -f "$ISO_PATH"
./script/install_macos.sh
codesign --verify --deep --strict /Applications/Veil.app
open -n /Applications/Veil.app
stat -f '%z %m' "$ISO_PATH"
```

Expected: the app moves to Trash, the ISO remains present with the exact size and modification epoch from Step 1, reinstall succeeds, and the app launches again.

- [ ] **Step 6: Write and complete the verification checklist**

Create `docs/checklists/2026-08-04-app-first-windows-home.md` with sections for presentation states, interaction/accessibility, automated verification, installed-app visual checks, and distribution safety. Mark only checks with direct evidence as complete; leave unavailable live Windows guest-agent checks unchecked with the reason and exact next action.

- [ ] **Step 7: Commit verification evidence and push the feature branch**

```bash
git add docs/checklists/2026-08-04-app-first-windows-home.md
git commit -m "Verify the app-first Windows home"
git push origin codex/app-first-home-v10
```

Expected: the remote feature branch contains the design, implementation plan, implementation commits, and verification evidence.
