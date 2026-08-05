# One-Click Windows Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one installed-Windows action that downloads and attaches official Guest Tools, installs display integration and the Veil guest agent, restarts Windows, and verifies the agent connection without replacing the Windows disk.

**Architecture:** Extend the existing read-only `VEIL_AUTO` media with an idempotent `Optimize.cmd` entrypoint and invoke it through the existing QMP Run-dialog automation. A focused `WindowsOptimizationCoordinator` owns the bounded workflow and exposes one state object to SwiftUI; an app service adapts the existing VM runtime, downloader, booter, and guest-agent models.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Observation, QEMU QMP, Windows batch/PowerShell, Swift Testing, Node lifecycle contracts.

## Global Constraints

- Preserve the Windows virtual disk and user data; never recreate, format, or replace the system disk.
- Require one explicit combined terms confirmation before installing official UTM Guest Tools and the Veil guest agent.
- Keep Guest Tools media read-only and outside the repository.
- Treat command dispatch as incomplete until the Windows guest agent reconnects.
- Report unchanged fallback resolution as partial display integration, not full success.
- Never commit Windows images, product keys, proprietary SDKs, UTM binaries, or Guest Tools media.

---

### Task 1: Build the idempotent Windows optimization media entrypoint

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUWindowsBootPlan.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`

**Interfaces:**
- Produces: `QEMUWindowsOptimizationKeySequence.commandText: String`
- Produces: `QEMUWindowsOptimizationKeySequence.steps: [QEMUKeySequenceStep]`
- Produces: generated `Veil Guest Agent/Optimize.cmd` inside `VeilAutoInstall.iso`
- Consumes: existing `QEMUQMPKeyboardCommandBuilder.keySequence(forText:)` and `Repair Veil Agent Connectivity.cmd`

- [ ] **Step 1: Write failing command and media tests**

Add tests asserting that `QEMUWindowsOptimizationKeySequence.commandText` invokes only the short `Optimize.cmd` path, stays below 200 QMP key steps, and ends with Return. Extend the prepared-media test to load `Veil Guest Agent/Optimize.cmd` and assert it contains all of these exact safety/behavior contracts:

```swift
#expect(script.contains("utm-guest-tools-*.exe"))
#expect(script.contains("start /wait \"\" \"%VEIL_GUEST_TOOLS%\" /S"))
#expect(script.contains("Repair Veil Agent Connectivity.cmd"))
#expect(script.contains("shutdown.exe /r /t 5"))
#expect(!script.localizedCaseInsensitiveContains("format "))
#expect(!script.localizedCaseInsensitiveContains("diskpart"))
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run:

```bash
swift test --package-path apps/mac-host --filter QEMUWindowsBootPlanTests
swift test --package-path apps/mac-host --filter VMProfileStoreTests
```

Expected: failure because the key-sequence type and `Optimize.cmd` do not exist.

- [ ] **Step 3: Add the short QMP sequence and generated script**

Add `QEMUWindowsOptimizationKeySequence` beside the existing guest-agent sequence. Its Run command scans `D:` through `Z:` for `Veil Guest Agent\Optimize.cmd`, and its steps reuse the existing start-button, Run-dialog, and UAC coordinates.

Add `windowsOptimizationCommandText` in `LocalVMRuntimeService` with this behavior:

```bat
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "VEIL_GUEST_TOOLS="
for %%D in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  for %%I in ("%%D:\utm-guest-tools-*.exe") do if exist "%%~fI" set "VEIL_GUEST_TOOLS=%%~fI"
)
if not defined VEIL_GUEST_TOOLS exit /b 10
start /wait "" "%VEIL_GUEST_TOOLS%" /S
if errorlevel 1 exit /b %errorlevel%
call "%~dp0Repair Veil Agent Connectivity.cmd"
if errorlevel 1 exit /b %errorlevel%
shutdown.exe /r /t 5 /c "Veil finished Windows optimization"
exit /b 0
```

Write it as `Optimize.cmd` while preparing the agent bundle. Do not alter partition, activation, or installer-media paths.

- [ ] **Step 4: Run focused tests and confirm pass**

Run the two commands from Step 2. Expected: both suites pass.

- [ ] **Step 5: Commit the media contract**

```bash
git add apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift apps/mac-host/Sources/VeilHostCore/QEMUWindowsBootPlan.swift apps/mac-host/Tests/VeilHostCoreTests/VMProfileStoreTests.swift apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift
git commit -m "feat(mac-host): add Windows optimization media"
```

### Task 2: Add a complete QMP installer dispatch path

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUVMRuntimeBooter.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/App/AppRuntimeBooter.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/AppRuntimeBooterTests.swift`

**Interfaces:**
- Produces: `QEMUVMRuntimeBooter.optimizeWindowsFromAttachedMedia() async throws -> QEMUKeySendRecord`
- Produces: `QEMUVMRuntimeBooter.requestGracefulShutdown(timeoutSeconds: Int) async throws`
- Produces: `AppRuntimeBooter.optimizeWindowsFromAttachedMedia() async throws -> QEMUKeySendRecord`
- Produces: `AppRuntimeBooter.requestGracefulShutdown(timeoutSeconds: Int) async throws`
- Consumes: `QEMUWindowsOptimizationKeySequence.steps`, `.stepsAfterRunOpened`, and `.uacApproveKeySteps`

- [ ] **Step 1: Write failing dispatch tests**

Add a QEMU sequence assertion that the optimization path includes command confirmation and UAC approval, plus a QMP control assertion for `system_powerdown`:

```swift
#expect(QEMUWindowsOptimizationKeySequence.commandConfirmationSteps.map(\.key) == ["ret"])
#expect(QEMUWindowsOptimizationKeySequence.uacApproveKeySteps.map(\.key) == ["left", "ret"])
#expect(try QEMUQMPControlCommandBuilder.powerDownCommand().contains("system_powerdown"))
```

Add an `AppRuntimeBooterTests` case proving Apple Virtualization throws `qemuGuestAutomationUnavailable` while QEMU exposes the optimization method.

- [ ] **Step 2: Run tests and confirm failure**

```bash
swift test --package-path apps/mac-host --filter QEMUWindowsBootPlanTests
swift test --package-path apps/mac-host --filter AppRuntimeBooterTests
```

Expected: failure because the optimization dispatch methods are absent.

- [ ] **Step 3: Implement bounded dispatch**

Refactor `sendAttachedMediaCommand` to accept explicit confirmation and post-confirmation steps:

```swift
private func sendAttachedMediaCommand(
    startButtonTapNormalizedX: Double,
    startButtonTapNormalizedY: Double,
    steps: @autoclosure () throws -> [QEMUKeySequenceStep],
    stepsAfterRunOpened: @autoclosure () throws -> [QEMUKeySequenceStep],
    commandConfirmationSteps: [QEMUKeySequenceStep] = [],
    postConfirmationSteps: [QEMUKeySequenceStep] = []
) async throws -> QEMUKeySendRecord
```

For optimization, send Return, wait three seconds for elevation, then send the existing left/Return approval sequence. Keep the old guest-agent and sparse-package behavior unchanged.

Add `requestGracefulShutdown(timeoutSeconds:)`: send `QEMUQMPControlCommandBuilder.powerDownCommand()` through the active QMP socket, poll the owned QEMU process until it exits, and throw a timeout error without calling `terminate()` when Windows does not shut down in time. Forward both new methods through `AppRuntimeBooter`; reject them for Apple Virtualization with the existing typed automation error.

- [ ] **Step 4: Run focused tests and confirm pass**

Run the two commands from Step 2. Expected: pass.

- [ ] **Step 5: Commit the dispatch path**

```bash
git add apps/mac-host/Sources/VeilHostCore/QEMUVMRuntimeBooter.swift apps/mac-host/Sources/VeilHostShell/App/AppRuntimeBooter.swift apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift apps/mac-host/Tests/VeilHostShellTests/AppRuntimeBooterTests.swift
git commit -m "feat(mac-host): dispatch one-click Windows optimization"
```

### Task 3: Implement the bounded optimization coordinator

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsOptimizationCoordinatorTests.swift`

**Interfaces:**
- Produces: `enum WindowsOptimizationPhase: Equatable`
- Produces: `struct WindowsOptimizationStatus: Equatable`
- Produces: `@MainActor protocol WindowsOptimizationServicing`
- Produces: `@MainActor @Observable final class WindowsOptimizationCoordinator`
- Service methods:

```swift
func prepareMedia() async throws
func restartWithPreparedMedia() async throws
func waitForDesktop(timeoutSeconds: Int) async throws
func dispatchOptimization() async throws
func waitForAgent(timeoutSeconds: Int) async throws -> Bool
```

- [ ] **Step 1: Write coordinator tests with a recording fake**

Cover these exact cases:

```swift
@Test func runsEveryStepInOrderAndCompletesAfterAgentConnection()
@Test func downloadFailureStopsBeforeRuntimeMutation()
@Test func desktopTimeoutNeverDispatchesTheInstaller()
@Test func agentTimeoutProducesRetryableFailure()
@Test func cancelWorksBeforeDispatchAndIsIgnoredAfterDispatch()
@Test func retryRestartsFromMediaEvidenceCheck()
```

The success test must assert this call order:

```swift
["prepareMedia", "restartWithPreparedMedia", "waitForDesktop", "dispatchOptimization", "waitForAgent"]
```

- [ ] **Step 2: Run the coordinator test and confirm failure**

```bash
swift test --package-path apps/mac-host --filter WindowsOptimizationCoordinatorTests
```

Expected: compile failure because the coordinator types do not exist.

- [ ] **Step 3: Implement phases, status copy, and coordinator**

Use these phases:

```swift
enum WindowsOptimizationPhase: Equatable {
    case idle
    case preparingMedia
    case restartingForMedia
    case waitingForDesktop
    case installing
    case restartingWindows
    case verifying
    case complete(displayOptimized: Bool)
    case failed(String)
    case cancelled
}
```

`WindowsOptimizationStatus` provides `title`, `detail`, `progress`, `isRunning`, `canCancel`, `primaryButtonTitle`, and `showsOptimizationCard`. The coordinator must set `installerDispatched = true` immediately before dispatch so cancellation cannot interrupt an unknown in-guest installation state. Completion requires `waitForAgent` to return true. Initially pass `displayOptimized: false`; Task 5 updates this with observed framebuffer evidence.

Also expose `recordDisplaySize(width: Int, height: Int)`. It stores only positive dimensions and upgrades a completed state to `complete(displayOptimized: true)` when either dimension exceeds the `800×600` fallback while preserving agent-connected completion.

- [ ] **Step 4: Run tests and confirm pass**

Run the command from Step 2. Expected: all coordinator tests pass.

- [ ] **Step 5: Commit the coordinator**

```bash
git add apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift apps/mac-host/Tests/VeilHostShellTests/WindowsOptimizationCoordinatorTests.swift
git commit -m "feat(mac-host): orchestrate Windows optimization"
```

### Task 4: Adapt the live app models to the coordinator

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsOptimizationCoordinatorTests.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/VMRuntimeModelTests.swift`

**Interfaces:**
- Produces: `@MainActor final class AppWindowsOptimizationService: WindowsOptimizationServicing`
- Consumes: `UTMGuestToolsDownloader.downloadIfNeeded()`, `VMRuntimeModel.updateProfilePaths`, `VMRuntimeModel.prepareDefaultVM`, `VMRuntimeModel.start`, `AppRuntimeBooter.requestGracefulShutdown`, `AppRuntimeBooter.optimizeWindowsFromAttachedMedia`, and `HostDashboardModel.waitForLiveAgentConnection`

- [ ] **Step 1: Add failing service-boundary tests**

Add a `VMRuntimeModel` test for a new result-returning helper:

```swift
let prepared = await model.prepareWindowsOptimization(driverMediaPath: "/tmp/utm.iso")
#expect(prepared)
#expect(service.updatedDriverMediaPath == "/tmp/utm.iso")
#expect(service.prepareDefaultVMCallCount == 1)
```

Add coordinator service tests that prove a running VM receives `system_powerdown` before media rebuild/start, while a stopped VM rebuilds media and starts once. A graceful-shutdown timeout must stop before rebuilding the ISO and must never call the force-stop path.

- [ ] **Step 2: Run tests and confirm failure**

```bash
swift test --package-path apps/mac-host --filter VMRuntimeModelTests
swift test --package-path apps/mac-host --filter WindowsOptimizationCoordinatorTests
```

- [ ] **Step 3: Add the model helper and app service**

Add:

```swift
@discardableResult
public func prepareWindowsOptimization(driverMediaPath: String) async -> Bool
```

It must preserve `installerMediaPath` and `virtualDiskPath`, update only the driver path, call `prepareDefaultVM()` to rebuild `VEIL_AUTO`, and return true only when the profile remains installed and startable.

`AppWindowsOptimizationService.prepareMedia()` only downloads and validates the ISO, retaining its path in memory without mutating a running VM. `restartWithPreparedMedia()` requests ACPI shutdown when running, waits for `.stopped`, calls `prepareWindowsOptimization(driverMediaPath:)` to rebuild and attach media, starts once, and fails on `.failed`. It never calls `VMRuntimeModel.stop()` or another force-stop path. `waitForDesktop` polls fresh console evidence at one-second intervals for at most 60 seconds. `waitForAgent` uses the host model's bounded connection wait, records guest-agent evidence, and refreshes both models.

Instantiate one coordinator in `VeilHostShellApp`, cancel competing quiet-runtime/repair tasks before starting, and expose `begin`, `retry`, and `cancel` actions to the view hierarchy.

- [ ] **Step 4: Run focused tests and confirm pass**

Run the commands from Step 2. Expected: pass.

- [ ] **Step 5: Commit live orchestration**

```bash
git add apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift apps/mac-host/Sources/VeilHostCore/VMRuntimeModel.swift apps/mac-host/Tests/VeilHostShellTests/WindowsOptimizationCoordinatorTests.swift apps/mac-host/Tests/VeilHostCoreTests/VMRuntimeModelTests.swift
git commit -m "feat(mac-host): connect optimization to the live runtime"
```

### Task 5: Replace manual repair choices with one installed-home action

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/ContentView.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/InstalledAppHomePresentationTests.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/RFBEmbeddedDisplayWorkerTests.swift`
- Test: `harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs`

**Interfaces:**
- Consumes: `WindowsOptimizationStatus`
- Produces view inputs: `optimizationStatus`, `optimizeWindowsAction`, `retryOptimizationAction`, `cancelOptimizationAction`, `displaySizeChangedAction`
- Produces: `WindowsOptimizationConsentPolicy.title`, `.message`, `.acceptButtonTitle`

- [ ] **Step 1: Write failing presentation contracts**

Assert that installed Windows with missing guest-agent evidence shows exactly one card with:

```swift
#expect(policy.title == "Finish Windows Optimization")
#expect(policy.detail.contains("Windows will restart once"))
#expect(policy.primaryButtonTitle == "Optimize Windows")
```

Add a lifecycle source contract that matches `Optimize Windows`, `Try Again`, the combined terms alert, and the absence of a primary `Repair App Connection` button when the optimization card is eligible.

Add an RFB model test that receiving a frame publishes its pixel dimensions only when width or height changes.

- [ ] **Step 2: Run tests and confirm failure**

```bash
swift test --package-path apps/mac-host --filter InstalledAppHomePresentationTests
swift test --package-path apps/mac-host --filter RFBEmbeddedDisplayWorkerTests
node --test harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs
```

- [ ] **Step 3: Implement the single-card UI and consent**

Show the optimization card only when `snapshot.windowsInstalled`, the provider is QEMU, and guest-agent integration is not healthy. Use this copy:

- `Finish Windows Optimization`
- `Install display integration and Veil app support automatically. Windows will restart once.`
- `Optimize Windows`
- `Try Again`
- `Keep Veil open while Windows finishes and restarts.`

The alert must open both Microsoft terms and UTM Guest Tools information and offer `I Agree and Optimize`. While running, replace the button with a determinate stage indicator. Permit cancel only before dispatch. Move legacy repair/check actions under Diagnostics/More so they cannot compete with the primary flow.

Publish RFB frame size changes to the coordinator. On agent-connected completion, classify dimensions larger than `800×600` as `displayOptimized: true`; otherwise show `Windows apps are connected. Display optimization still needs attention.` without failing the app connection.

- [ ] **Step 4: Run presentation tests and confirm pass**

Run all commands from Step 2. Expected: pass.

- [ ] **Step 5: Commit the product UI**

```bash
git add apps/mac-host/Sources/VeilHostShell/Views/ContentView.swift apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift apps/mac-host/Tests/VeilHostShellTests/InstalledAppHomePresentationTests.swift apps/mac-host/Tests/VeilHostShellTests/RFBEmbeddedDisplayWorkerTests.swift harness/macos-app-lifecycle/test/macos-app-lifecycle.test.mjs
git commit -m "feat(mac-host): add one-click Windows optimization UI"
```

### Task 6: Verify, document, install, and integrate

**Files:**
- Modify: `docs/checklists/2026-08-04-built-app-live-install-pass.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes all prior tasks.
- Produces regression and live acceptance evidence.

- [ ] **Step 1: Run focused static checks**

```bash
git diff --check
swift test --package-path apps/mac-host
```

Expected: 0 failures.

- [ ] **Step 2: Run the complete repository gate**

```bash
env PATH='/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8:/Users/uulab/.local/bin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin:/pkg/env/global/bin' DOTNET_CLI_TELEMETRY_OPTOUT=1 ./script/test_all.sh
```

Expected: Swift host, .NET Windows agent, 25 Node harness packages, signed app launch, and install/uninstall lifecycle all pass.

- [ ] **Step 3: Install and launch the built app**

```bash
./script/install_macos.sh --source dist/Veil.app --destination /Applications/Veil.app --replace
codesign --verify --deep --strict --verbose=2 /Applications/Veil.app
open -n /Applications/Veil.app
```

Expected: valid signature and a live `/Applications/Veil.app/Contents/MacOS/veil-host-shell` process.

- [ ] **Step 4: Run the existing-VM acceptance pass**

In the app, confirm the combined terms once and observe media preparation, one restart, guest-agent connection, and post-reboot framebuffer dimensions. Do not claim completion for any observation that does not occur. Record exact results and remaining blockers in the checklist.

- [ ] **Step 5: Commit evidence and push the feature branch**

```bash
git add docs/checklists/2026-08-04-built-app-live-install-pass.md docs/roadmap.md
git commit -m "docs: record one-click optimization verification"
git push -u origin codex/one-click-windows-optimization
```

- [ ] **Step 6: Merge verified work into develop**

```bash
git fetch origin
git switch develop
git pull --ff-only origin develop
git merge --no-ff codex/one-click-windows-optimization -m "merge: one-click Windows optimization"
```

Run `./script/test_all.sh` again on the merged tree. Push `develop` only after exit code 0:

```bash
git push origin develop
```
