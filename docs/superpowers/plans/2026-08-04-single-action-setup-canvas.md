# Single-Action Windows Setup Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Veil's checklist-heavy first-run screen with one edge-to-edge Windows setup canvas that presents one contextual primary action.

**Architecture:** Add a pure value-type presentation resolver for setup states, render that result in a focused SwiftUI canvas, and keep all VM operations in the existing `WindowsSetupDisplayPanel` closures. The live Windows display and installed app launcher retain their current runtime behavior.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Node.js built-in test runner

## Global Constraints

- The content below the persistent window header is one edge-to-edge setup canvas.
- Do not change VM preparation, ISO download, boot, guest-agent, or app-launch behavior.
- Do not show a second card frame, modal-like panel, duplicate bottom control bar, permanent setup checklist, or multiple equally prominent buttons.
- Keep `Use Existing ISO` directly discoverable only while installer media or renewed file access is needed.
- Support the existing `820 x 560` minimum window size without clipping text or controls.
- Keep raw provider, QEMU, path, and protocol details out of the main canvas.
- Preserve the existing Windows ISO and application-support data during lifecycle verification.

---

### Task 1: Resolve Setup Presentation as Testable State

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/App/WindowsSetupCanvasPresentation.swift`
- Modify: `apps/mac-host/Tests/VeilHostShellTests/AppRuntimeDockMenuTests.swift`

**Interfaces:**
- Consumes: `VMRuntimeState` from `VeilHostCore` and product-facing primary action strings already resolved by `WindowsSetupDisplayPanel`.
- Produces: `WindowsSetupCanvasPresentation.resolve(...) -> WindowsSetupCanvasPresentation`, `WindowsSetupCanvasPhase`, and `WindowsSetupCanvasPrimaryRoute` for Task 2.

- [ ] **Step 1: Write failing presentation-state tests**

Add tests that call this exact interface:

```swift
let presentation = WindowsSetupCanvasPresentation.resolve(
    runtimeState: .stopped,
    windowsInstalled: false,
    hasInstaller: false,
    requiresInstallerAccess: false,
    installerName: nil,
    bootReady: false,
    isBusy: false,
    integrationReady: false,
    errorMessage: nil,
    primaryTitle: "Download Windows 11",
    primarySymbolName: "arrow.down.circle",
    primaryHelp: "Download Windows",
    primaryDisabled: false,
    hasDiagnostics: false
)

#expect(presentation.phase == .needsInstaller)
#expect(presentation.title == "Get Windows 11")
#expect(presentation.showsExistingISOAction)
#expect(presentation.primaryRoute == .effectiveAction)
```

Cover `.needsInstaller`, `.needsPreparation`, `.readyToInstall`, `.inProgress`, `.needsIntegration`, and `.failure`. Also verify that renewed ISO access uses `.existingISO`, a disabled failure falls back to `.settings`, and failure detail contains none of `QEMU`, `VM`, `protocol`, or a local path.

- [ ] **Step 2: Run the tests and confirm the new type is missing**

Run:

```bash
swift test --package-path apps/mac-host --filter AppRuntimeDockMenuTests
```

Expected: compilation fails because `WindowsSetupCanvasPresentation` is not defined.

- [ ] **Step 3: Implement the pure presentation resolver**

Create the following value types and exact resolver signature:

```swift
import VeilHostCore

enum WindowsSetupCanvasPhase: Equatable {
    case needsInstaller
    case needsPreparation
    case readyToInstall
    case inProgress
    case needsIntegration
    case ready
    case failure
}

enum WindowsSetupCanvasPrimaryRoute: Equatable {
    case effectiveAction
    case existingISO
    case settings
}

struct WindowsSetupCanvasPresentation: Equatable {
    let phase: WindowsSetupCanvasPhase
    let title: String
    let detail: String
    let symbolName: String
    let primaryTitle: String
    let primarySymbolName: String
    let primaryHelp: String
    let primaryDisabled: Bool
    let primaryRoute: WindowsSetupCanvasPrimaryRoute
    let showsProgress: Bool
    let showsExistingISOAction: Bool
    let showsSettingsAction: Bool
    let showsDiagnosticsAction: Bool

    static func resolve(
        runtimeState: VMRuntimeState,
        windowsInstalled: Bool,
        hasInstaller: Bool,
        requiresInstallerAccess: Bool,
        installerName: String?,
        bootReady: Bool,
        isBusy: Bool,
        integrationReady: Bool,
        errorMessage: String?,
        primaryTitle: String,
        primarySymbolName: String,
        primaryHelp: String,
        primaryDisabled: Bool,
        hasDiagnostics: Bool
    ) -> Self
}
```

Resolve in this precedence order: failure/unsupported, busy/starting, missing or inaccessible installer, preparation, ready to install, integration, ready. Use fixed product copy for failure detail instead of interpolating `errorMessage`; the error's presence selects the state while diagnostics retains technical detail. When `requiresInstallerAccess` is true, use `Use an Existing ISO` with route `.existingISO`. When a failure's effective action is disabled, use `Open Settings` with route `.settings`.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --package-path apps/mac-host --filter AppRuntimeDockMenuTests
```

Expected: all existing tests plus the new presentation tests pass.

- [ ] **Step 5: Commit the state resolver**

```bash
git add apps/mac-host/Sources/VeilHostShell/App/WindowsSetupCanvasPresentation.swift \
  apps/mac-host/Tests/VeilHostShellTests/AppRuntimeDockMenuTests.swift
git commit -m "Model the focused Windows setup canvas"
```

---

### Task 2: Build the Edge-to-Edge Setup Canvas

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/Views/WindowsSetupCanvas.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift:1623-1973`

**Interfaces:**
- Consumes: `WindowsSetupCanvasPresentation` from Task 1 and existing `WindowsLogoMark` from `VMRuntimeView.swift`.
- Produces: `WindowsSetupCanvas`, initialized with presentation, progress, and four existing action closures.

- [ ] **Step 1: Add a failing lifecycle source contract**

Replace the old permanent three-step journey assertions in `harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs` with assertions for the new component:

```javascript
const canvas = await readRootFile(
  "apps/mac-host/Sources/VeilHostShell/Views/WindowsSetupCanvas.swift",
);

assert.match(runtime, /WindowsSetupCanvas\(/);
assert.match(canvas, /struct WindowsSetupCanvas: View/);
assert.match(canvas, /GeometryReader/);
assert.match(canvas, /\.accessibilityAddTraits\(\.isHeader\)/);
assert.match(canvas, /ProgressView\(value: progress\)/);
assert.match(canvas, /Label\("Use an Existing ISO", systemImage: "folder"\)/);
assert.match(canvas, /\.accessibilityLabel\("Settings"\)/);
assert.doesNotMatch(runtime, /SetupJourneyStep\(/);
assert.doesNotMatch(runtime, /FirstRunTrustItem\(/);
```

- [ ] **Step 2: Run the lifecycle test and confirm it fails**

Run:

```bash
node --test harness/macos-app-lifecycle/test/*.test.mjs
```

Expected: the first-run canvas contract fails because `WindowsSetupCanvas.swift` does not exist.

- [ ] **Step 3: Implement the focused SwiftUI canvas**

Create this interface:

```swift
import SwiftUI

struct WindowsSetupCanvas: View {
    let presentation: WindowsSetupCanvasPresentation
    let progress: Double
    let primaryAction: () -> Void
    let existingISOAction: () -> Void
    let settingsAction: () -> Void
    let diagnosticsAction: () -> Void
}
```

Use `GeometryReader` and `let compact = proxy.size.height < 600 || proxy.size.width < 900`. Render an edge-to-edge gradient, a `WindowsLogoMark` sized `compact ? 58 : 76`, title with `.accessibilityAddTraits(.isHeader)`, one detail paragraph with maximum width 560, and a stable 240-by-48 primary region. In progress state render `ProgressView(value: progress)` plus `Preparing Windows…`; otherwise render one prominent button and dispatch its action by `primaryRoute`.

Place `Use an Existing ISO` below the primary region only when `showsExistingISOAction` is true. Put Settings and Diagnostics as quiet icon actions in the top-right corner, each with `.help(...)` and explicit accessibility labels. Use `.contentTransition(.opacity)` and a 0.2-second ease transition keyed by `presentation.phase`; do not add an infinite animation.

- [ ] **Step 4: Connect the canvas without changing runtime operations**

In `WindowsSetupDisplayPanel`, add:

```swift
private var setupCanvasPresentation: WindowsSetupCanvasPresentation {
    .resolve(
        runtimeState: snapshot.state,
        windowsInstalled: effectiveInstallEvidence.isInstalled,
        hasInstaller: selectedInstallerName != nil,
        requiresInstallerAccess: installerNeedsFilePickerAccess,
        installerName: selectedInstallerName,
        bootReady: snapshot.bootReady,
        isBusy: isLoading || installSimulation.phase == .running,
        integrationReady: effectiveInstallEvidence.kind == .guestAgent,
        errorMessage: errorMessage,
        primaryTitle: effectivePrimaryTitle,
        primarySymbolName: effectivePrimarySymbol,
        primaryHelp: effectivePrimaryHelp,
        primaryDisabled: effectivePrimaryDisabled,
        hasDiagnostics: diagnosticsURL != nil || agentDiagnostic != nil
    )
}
```

When no live desktop surface exists, render `WindowsSetupCanvas` directly. Pass `runEffectivePrimaryAction`, `selectInstallerAction`, `detailsAction`, and a diagnostics closure that opens `diagnosticsURL` with `NSWorkspace.shared.open`. Keep `installDisplaySurface` and `installControlBar` only for an actual embedded Windows surface. Remove `firstRunSetupContent`, `firstRunPrimaryButton`, `firstRunExistingISOButton`, `firstRunTrustItems`, `firstRunCurrentStep`, `SetupJourneyStep`, `SetupJourneyConnector`, `SetupJourneyStageState`, and `FirstRunTrustItem` after callers are gone.

- [ ] **Step 5: Run focused Swift and lifecycle tests**

Run:

```bash
swift test --package-path apps/mac-host --filter AppRuntimeDockMenuTests
node --test harness/macos-app-lifecycle/test/*.test.mjs
```

Expected: both commands pass with no source-contract regressions.

- [ ] **Step 6: Commit the canvas integration**

```bash
git add apps/mac-host/Sources/VeilHostShell/Views/WindowsSetupCanvas.swift \
  apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift \
  harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs
git commit -m "Focus the Windows setup experience"
```

---

### Task 3: Verify Responsive, Accessible, and Lifecycle Behavior

**Files:**
- Create: `docs/checklists/2026-08-04-single-action-setup-canvas.md`
- Modify only if verification exposes a defect: the files from Tasks 1 and 2 and their tests.

**Interfaces:**
- Consumes: the completed setup canvas and repository lifecycle scripts.
- Produces: a completed verification checklist and an installed `/Applications/Veil.app`.

- [ ] **Step 1: Create the verification checklist**

Record checkboxes for six presentation phases, exactly one prominent action, existing-ISO discoverability, settings/diagnostics accessibility, `820 x 560` layout, regular layout, keyboard activation, full regression, install/replace/uninstall/data preservation/reinstall, code signing, and ISO size/mtime preservation.

- [ ] **Step 2: Run the full regression gate**

Run:

```bash
PATH=/Users/uulab/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH \
  script/test_all.sh --skip-windows-agent
```

Expected: every requested Veil regression gate passes, including the macOS install lifecycle.

- [ ] **Step 3: Build and install the app**

Run:

```bash
script/build_and_run.sh --verify
script/install_macos.sh --source dist/Veil.app --destination /Applications/Veil.app --replace
codesign --verify --deep --strict /Applications/Veil.app
```

Expected: bundle verification, guarded replacement, and strict code-sign verification succeed.

- [ ] **Step 4: Inspect the installed app at two sizes**

Launch `/Applications/Veil.app`, confirm the setup canvas fills the area below the header, and verify one primary action at the normal window size. Resize to `820 x 560` and confirm the logo, heading, detail, primary action, existing ISO action, and settings control remain visible without overlap. Use the accessibility tree to verify `Settings`, `Use an Existing ISO`, the contextual primary label, and progress status.

- [ ] **Step 5: Verify the existing ISO is unchanged**

Run:

```bash
stat -f 'ISO_SIZE=%z ISO_MODIFIED=%Sm' -t '%Y-%m-%d %H:%M:%S %z' \
  "/Users/uulab/Library/Application Support/Veil/Downloads/Win11_25H2_Korean_Arm64_v2.iso"
```

Expected: `ISO_SIZE=7951140864` and modification time `2026-08-03 21:57:17 +0900`.

- [ ] **Step 6: Fix only verification defects and rerun the narrowest failed gate**

For a layout or accessibility defect, change `WindowsSetupCanvas.swift` and rerun focused Swift plus lifecycle tests. For a state-selection defect, change `WindowsSetupCanvasPresentation.swift` and rerun `AppRuntimeDockMenuTests`. Do not change VM runtime behavior to satisfy UI checks.

- [ ] **Step 7: Commit verification evidence**

```bash
git add docs/checklists/2026-08-04-single-action-setup-canvas.md \
  apps/mac-host/Sources/VeilHostShell/App/WindowsSetupCanvasPresentation.swift \
  apps/mac-host/Sources/VeilHostShell/Views/WindowsSetupCanvas.swift \
  apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift \
  apps/mac-host/Tests/VeilHostShellTests/AppRuntimeDockMenuTests.swift \
  harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs
git commit -m "Verify the focused Windows setup canvas"
```

---

### Task 4: Publish and Merge

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: clean, verified `codex/setup-focus-ux-v9` history.
- Produces: matching remote feature branch and `origin/develop` merge commit.

- [ ] **Step 1: Confirm the feature branch is clean**

```bash
git diff --check
git status --short --branch
git log --oneline --decorate -5
```

Expected: no unstaged or untracked files and at least the design, model, canvas, and verification commits.

- [ ] **Step 2: Push the feature branch**

```bash
git push -u origin codex/setup-focus-ux-v9
```

- [ ] **Step 3: Merge from a clean develop worktree**

```bash
git fetch origin
git pull --ff-only origin develop
git merge --no-ff codex/setup-focus-ux-v9 -m "Merge focused Windows setup canvas"
git push origin develop
```

- [ ] **Step 4: Verify remote commit equality**

```bash
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/develop)"
```

Expected: exit code 0.
