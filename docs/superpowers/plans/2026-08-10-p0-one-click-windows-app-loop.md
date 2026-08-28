# P0 One-Click Windows App Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one Notepad tile click start or resume Windows, connect or repair the guest agent, launch Notepad, receive its first frame, and present one independent macOS window without exposing the Windows desktop during normal use.

**Architecture:** Keep VM lifecycle in `VMRuntimeModel`, guest operations in `HostDashboardModel`, and AppKit presentation in `WindowsAppWindowPresenter`. Add one testable shell coordinator that sequences those existing boundaries with a fixed transition budget and two guest-agent repair attempts, while a pure workspace policy makes the full Windows display setup/recovery-only.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, QEMU/HVF, C#/.NET 8 guest agent, Node.js harness validators.

## Global Constraints

- Host platform remains macOS 15+ on Apple Silicon; guest remains Windows 11 Arm.
- Do not commit Windows media, product keys, signing secrets, user documents, or Parallels assets.
- Preserve all pre-existing dirty working-tree changes. Use `git add -p` for every tracked file that was already modified before this plan.
- Do not force-stop QEMU or delete guest state without explicit user approval after graceful shutdown fails.
- The normal app path must not show a nested Windows desktop; Setup and explicit recovery may show it.
- Automatic guest-agent repair is bounded to two attempts and the total lifecycle is bounded to twelve transitions.
- Protocol shapes do not change in this P0 slice. If implementation proves a wire change is necessary, stop this plan and write a separate protocol spec and plan.
- A deterministic test makes a feature `implemented`; a real Windows evidence pass makes it `verified`.
- Run Swift tests with `--disable-sandbox`.
- Use `/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet` when `dotnet` is not on `PATH`.

## File Map

- Modify `apps/mac-host/Sources/VeilHostShell/App/AppLaunchLifecycleCoordinator.swift`: pure transition context and typed lifecycle failures.
- Create `apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift`: bounded asynchronous sequencing over injected host-shell operations.
- Modify `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`: make a selected-app request return its immediate live launch result while preserving offline queueing.
- Modify `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`: route tile, menu, and queued-launch actions through one coordinator task.
- Modify `apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift`: own setup/recovery-versus-app-launcher presentation policy and return to apps on first frame.
- Modify `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`: stop automatically forcing the full desktop on every running-state transition.
- Modify `apps/mac-host/Sources/VeilHostShell/App/WindowsAppWindowPresenter.swift`: only if the live stability test exposes a frame-preservation defect; otherwise tests document the existing invariant.
- Modify `apps/mac-host/Tests/VeilHostShellTests/AppLaunchLifecycleCoordinatorTests.swift`: transition and recovery-budget tests.
- Create `apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift`: end-to-end sequencing tests with injected fakes.
- Modify `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`: immediate-result and offline-queue request tests.
- Modify `apps/mac-host/Tests/VeilHostShellTests/RuntimeDisplaySelectionTests.swift`: setup/recovery-only desktop tests.
- Modify `apps/mac-host/Tests/VeilHostShellTests/WindowsAppWindowPresenterTests.swift`: repeated-frame sizing and focus invariants.
- Create `docs/checklists/2026-08-10-p0-one-click-runtime-proof.md`: exact deterministic and live acceptance record.

---

### Task 1: Make the Windows Desktop Setup/Recovery-Only

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/RuntimeDisplaySelectionTests.swift`

**Interfaces:**
- Consumes: `VMRuntimeState`, `VMRuntimeSnapshot.installEvidence`, `WindowMirrorSession.latestFrame`.
- Produces: `RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(windowsInstalled:runtimeState:hasDesktopDisplay:) -> Bool` and `RuntimeWorkspacePresentationPolicy.shouldReturnToApps(windowsInstalled:hasFirstAppFrame:) -> Bool`.

- [x] **Step 1: Add failing workspace-policy tests**

```swift
@Test("installed Windows defaults to the app launcher even when a desktop display exists")
func installedWindowsDefaultsToLauncher() {
    #expect(
        RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
            windowsInstalled: true,
            runtimeState: .running,
            hasDesktopDisplay: true
        ) == false
    )
}

@Test("Windows Setup keeps the recovery display visible")
func setupKeepsDesktopVisible() {
    #expect(
        RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
            windowsInstalled: false,
            runtimeState: .running,
            hasDesktopDisplay: true
        )
    )
}

@Test("the first app frame returns the workspace to apps")
func firstFrameReturnsToApps() {
    #expect(
        RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
            windowsInstalled: true,
            hasFirstAppFrame: true
        )
    )
}
```

- [x] **Step 2: Run the focused tests and verify the new API is missing**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter RuntimeWorkspacePresentationPolicyTests
```

Expected: FAIL because `defaultShowsFullDesktop` and `shouldReturnToApps` do not exist.

- [x] **Step 3: Implement the pure presentation policy**

Add to `RuntimeWorkspacePresentationPolicy` in `DetailView.swift`:

```swift
static func defaultShowsFullDesktop(
    windowsInstalled: Bool,
    runtimeState: VMRuntimeState?,
    hasDesktopDisplay: Bool
) -> Bool {
    !windowsInstalled && runtimeState == .running && hasDesktopDisplay
}

static func shouldReturnToApps(
    windowsInstalled: Bool,
    hasFirstAppFrame: Bool
) -> Bool {
    windowsInstalled && hasFirstAppFrame
}
```

In `DetailView`, derive `windowsInstalled` from the same profile/guest evidence used by `shouldShowAppDock`, initialize `showsWindowsDesktop` through `defaultShowsFullDesktop`, and set it to `false` when `activeMirrorSession?.latestFrame` becomes non-`nil`.

Remove the three automatic assignments in `WindowsSetupDisplayPanel.body` that currently set `showsFullDesktop = true` whenever the VM becomes running or a desktop surface appears. Preserve the explicit “Show Desktop” button as the recovery/user-requested path.

- [x] **Step 4: Run display and shell tests**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter RuntimeDisplaySelectionTests
swift test --disable-sandbox --package-path apps/mac-host --filter RuntimeWorkspacePresentationPolicyTests
```

Expected: PASS; installed Windows starts on the app launcher while uninstalled Windows Setup keeps the display visible.

- [x] **Step 5: Commit only this task's hunks**

```bash
git add -p apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift
git add -p apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift
git add -p apps/mac-host/Tests/VeilHostShellTests/RuntimeDisplaySelectionTests.swift
git diff --cached --check
git commit -m "fix(ui): keep Windows desktop recovery-only"
```

### Task 2: Define Typed, Bounded Launch Transitions

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/AppLaunchLifecycleCoordinator.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/AppLaunchLifecycleCoordinatorTests.swift`

**Interfaces:**
- Consumes: current VM, agent, queue, and recovery state.
- Produces: `AppLaunchLifecycleContext`, `AppLaunchLifecycleFailure`, and `AppLaunchLifecycleCoordinator.nextStep(context:)`.

- [x] **Step 1: Add failing tests for repair exhaustion and terminal blockers**

```swift
@Test("a timed out running guest requests bounded agent repair")
func requestsAgentRepair() {
    #expect(
        AppLaunchLifecycleCoordinator.nextStep(
            context: context(
                state: .running,
                agentWaitTimedOut: true,
                repairAttemptCount: 0
            )
        ) == .repairGuestAgent
    )
}

@Test("agent repair stops after two attempts")
func stopsAfterRepairBudget() {
    #expect(
        AppLaunchLifecycleCoordinator.nextStep(
            context: context(
                state: .running,
                agentWaitTimedOut: true,
                repairAttemptCount: 2
            )
        ) == .blockedGuestAgentRecovery
    )
}
```

Use this test helper:

```swift
private func context(
    state: VMRuntimeState? = .stopped,
    agentWaitTimedOut: Bool = false,
    repairAttemptCount: Int = 0
) -> AppLaunchLifecycleContext {
    AppLaunchLifecycleContext(
        hasQueuedLaunch: true,
        canFulfillQueuedLaunch: false,
        hasLiveAgentConnection: false,
        runtimeState: state,
        canStartOrResume: true,
        guestAgentEndpointAvailable: true,
        agentWaitTimedOut: agentWaitTimedOut,
        repairAttemptCount: repairAttemptCount
    )
}
```

- [x] **Step 2: Run the focused test and verify failure**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter AppLaunchLifecycleCoordinatorTests
```

Expected: FAIL because the context API and repair steps do not exist.

- [x] **Step 3: Add the context and terminal failures**

```swift
struct AppLaunchLifecycleContext: Equatable {
    var hasQueuedLaunch: Bool
    var canFulfillQueuedLaunch: Bool
    var hasLiveAgentConnection: Bool
    var runtimeState: VMRuntimeState?
    var canStartOrResume: Bool
    var guestAgentEndpointAvailable: Bool
    var agentWaitTimedOut: Bool
    var repairAttemptCount: Int
}

enum AppLaunchLifecycleFailure: Error, Equatable {
    case guestAgentEndpointUnavailable
    case runtimeSetupIncomplete
    case runtimeStartFailed
    case guestAgentRecoveryExhausted
    case launchRejected
    case transitionBudgetExceeded
}
```

Extend `AppLaunchLifecycleStep` with `.repairGuestAgent` and `.blockedGuestAgentRecovery`. Implement `nextStep(context:)` so a running/starting guest waits before timeout, repairs after timeout while `repairAttemptCount < 2`, and blocks after two attempts. Keep the old parameter-list overload as a compatibility wrapper until Task 4 removes its final call sites.

Define `AppLaunchLifecycleCoordinator.maximumRepairAttempts = 2` and compare `repairAttemptCount` to that constant rather than repeating the literal in transition logic.

Add an exhaustive product message on `AppLaunchLifecycleFailure`:

```swift
var userMessage: String {
    switch self {
    case .guestAgentEndpointUnavailable:
        return "This Windows runtime has no available app connection. Open Windows Settings to choose the supported QEMU/HVF runtime."
    case .runtimeSetupIncomplete:
        return "Finish Windows setup before opening this app."
    case .runtimeStartFailed:
        return "Windows could not start or resume. Open the recovery display for the exact boot error."
    case .guestAgentRecoveryExhausted:
        return "Windows is running, but the app connection did not recover after two attempts. Open recovery to repair Veil Agent."
    case .launchRejected:
        return "Windows connected, but the selected app did not open. Refresh the app list and try once more."
    case .transitionBudgetExceeded:
        return "Veil stopped the app launch because its state did not settle. Refresh Windows status before retrying."
    }
}
```

- [x] **Step 4: Run transition tests**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter AppLaunchLifecycleCoordinatorTests
```

Expected: PASS for request, start/resume, wait, repair, fulfillment, endpoint blocker, setup blocker, and repair exhaustion.

- [x] **Step 5: Commit the transition contract**

```bash
git add -p apps/mac-host/Sources/VeilHostShell/App/AppLaunchLifecycleCoordinator.swift
git add -p apps/mac-host/Tests/VeilHostShellTests/AppLaunchLifecycleCoordinatorTests.swift
git diff --cached --check
git commit -m "feat(shell): define bounded app launch lifecycle"
```

### Task 3: Execute the One-Click Lifecycle Through Injected Boundaries

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift`
- Create: `apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AppLaunchLifecycleContext` and generic closures that the shell later backs with `HostDashboardModel`, `VMRuntimeModel`, and `AppRuntimeBooter`.
- Produces: `OneClickAppLaunchDriver`, `OneClickAppLaunchOutcome`, and `OneClickAppLaunchCoordinator.run(appId:driver:)`.

- [x] **Step 1: Write a failing stopped-VM sequence test**

```swift
@Test("one click queues, starts, connects, and opens the selected app")
@MainActor
func opensFromStoppedVM() async throws {
    var runtimeState: VMRuntimeState? = .stopped
    var connected = false
    var queued = false
    var events: [String] = []

    let driver = OneClickAppLaunchDriver<String>(
        context: {
            AppLaunchLifecycleContext(
                hasQueuedLaunch: queued,
                canFulfillQueuedLaunch: queued && connected,
                hasLiveAgentConnection: connected,
                runtimeState: runtimeState,
                canStartOrResume: true,
                guestAgentEndpointAvailable: true,
                agentWaitTimedOut: false,
                repairAttemptCount: 0
            )
        },
        requestLaunch: { appId in
            events.append("request:\(appId)")
            queued = true
            return nil
        },
        startOrResumeWindows: {
            events.append("start-or-resume")
            runtimeState = .running
            return true
        },
        waitForGuestAgent: { seconds in
            events.append("wait-agent:\(seconds)")
            connected = true
            return true
        },
        repairGuestAgent: {
            events.append("repair-agent")
        },
        fulfillLaunch: {
            events.append("fulfill")
            queued = false
            return "hwnd:0001"
        }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(
        appId: "winapp_notepad",
        driver: driver
    )

    #expect(events == [
        "request:winapp_notepad",
        "start-or-resume",
        "wait-agent:30",
        "fulfill"
    ])
    guard case .opened(let windowId) = outcome else {
        Issue.record("Expected the app launch to open a window")
        return
    }
    #expect(windowId == "hwnd:0001")
}
```

Add tests for: already-connected direct fulfillment, one wait timeout followed by repair and success, two failed repairs producing `.guestAgentRecoveryExhausted`, unavailable endpoint producing no start attempt, and twelve transitions producing `.transitionBudgetExceeded`.

- [x] **Step 2: Run the new test and verify missing types**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
```

Expected: FAIL because the coordinator file does not exist.

- [x] **Step 3: Implement the injected driver and bounded runner**

```swift
@MainActor
struct OneClickAppLaunchDriver<LaunchResult> {
    var context: () -> AppLaunchLifecycleContext
    var requestLaunch: (String) async -> LaunchResult?
    var startOrResumeWindows: () async -> Bool
    var waitForGuestAgent: (Int) async -> Bool
    var repairGuestAgent: () async throws -> Void
    var fulfillLaunch: () async -> LaunchResult?
}

enum OneClickAppLaunchOutcome<LaunchResult> {
    case opened(LaunchResult)
    case blocked(AppLaunchLifecycleFailure)
}

@MainActor
struct OneClickAppLaunchCoordinator {
    static let maximumTransitions = 12
    static let agentWaitSeconds = 30

    func run<LaunchResult>(
        appId: String,
        driver: OneClickAppLaunchDriver<LaunchResult>
    ) async -> OneClickAppLaunchOutcome<LaunchResult> {
        var repairAttemptCount = 0
        var agentWaitTimedOut = false

        for _ in 0..<Self.maximumTransitions {
            var context = driver.context()
            context.repairAttemptCount = repairAttemptCount
            context.agentWaitTimedOut = agentWaitTimedOut

            switch AppLaunchLifecycleCoordinator.nextStep(context: context) {
            case .requestLaunch:
                if let immediateResult = await driver.requestLaunch(appId) {
                    return .opened(immediateResult)
                }
            case .startOrResumeWindows:
                guard await driver.startOrResumeWindows() else {
                    return .blocked(.runtimeStartFailed)
                }
                agentWaitTimedOut = false
            case .waitForGuestAgent:
                agentWaitTimedOut = !(await driver.waitForGuestAgent(Self.agentWaitSeconds))
            case .repairGuestAgent:
                do {
                    try await driver.repairGuestAgent()
                    repairAttemptCount += 1
                    agentWaitTimedOut = false
                } catch {
                    repairAttemptCount += 1
                    agentWaitTimedOut = true
                }
            case .fulfillQueuedLaunch:
                guard let result = await driver.fulfillLaunch() else {
                    return .blocked(.launchRejected)
                }
                return .opened(result)
            case .blockedGuestAgentEndpoint:
                return .blocked(.guestAgentEndpointUnavailable)
            case .blockedRuntimeSetup:
                return .blocked(.runtimeSetupIncomplete)
            case .blockedGuestAgentRecovery:
                return .blocked(.guestAgentRecoveryExhausted)
            }
        }

        return .blocked(.transitionBudgetExceeded)
    }
}
```

The remaining tests use the same closure pattern and mutate only local queue, runtime, connection, and repair-count state; they do not open sockets or launch QEMU.

- [x] **Step 4: Run coordinator tests**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
```

Expected: PASS with no sleeps, network access, or VM process.

- [x] **Step 5: Commit the coordinator**

```bash
git add apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift
git add apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift
git diff --cached --check
git commit -m "feat(shell): orchestrate one-click Windows app launch"
```

### Task 4: Route Every Product Launch Entry Through the Coordinator

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`
- Test: `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`
- Modify: `apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift`

**Interfaces:**
- Consumes: `OneClickAppLaunchCoordinator.run(appId:driver:)`.
- Produces: one in-flight `oneClickAppLaunchTask` for tile, main button, Dock/menu, and queued-launch fulfillment.

- [x] **Step 1: Make selected-app requests return an immediate live result**

Extend the existing `launchesSelectedWindowsApp` and `queuesNotepadLaunchUntilLiveAgentConnects` tests:

```swift
let liveResult = await model.launchSelectedApp()
#expect(liveResult?.window.appId == "winapp_calculator")

let queuedResult = await offlineModel.launchSelectedApp()
#expect(queuedResult == nil)
#expect(offlineModel.pendingLaunchAppId == "winapp_notepad")
```

Change `HostDashboardModel.launchSelectedApp()` to `@discardableResult public func launchSelectedApp() async -> WindowsAppLaunchResult?`. Return `nil` for selection, offline queue, and availability failures; return `await launchApp(appId:)` for a live launch. Existing callers may ignore the result.

- [x] **Step 2: Add a failing duplicate-request test**

Add a small `OneClickAppLaunchTaskGate` to the coordinator file and test it directly:

```swift
@Test("a second click joins the active app launch instead of starting another")
@MainActor
func coalescesDuplicateClicks() async {
    let gate = OneClickAppLaunchTaskGate<String>()
    var starts = 0
    var startedContinuation: AsyncStream<Void>.Continuation!
    var releaseContinuation: AsyncStream<Void>.Continuation!
    let started = AsyncStream<Void> { startedContinuation = $0 }
    let release = AsyncStream<Void> { releaseContinuation = $0 }
    var startedIterator = started.makeAsyncIterator()

    let first = Task { @MainActor in
        await gate.run {
            starts += 1
            startedContinuation.yield()
            var releaseIterator = release.makeAsyncIterator()
            _ = await releaseIterator.next()
            return "hwnd:0001"
        }
    }
    _ = await startedIterator.next()

    let second = Task { @MainActor in
        await gate.run {
            starts += 1
            return "hwnd:0002"
        }
    }
    await Task.yield()
    releaseContinuation.yield()

    #expect(await first.value == "hwnd:0001")
    #expect(await second.value == "hwnd:0001")
    #expect(starts == 1)
}
```

- [x] **Step 3: Run the focused tests and verify failure**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
swift test --disable-sandbox --package-path apps/mac-host --filter HostDashboardModelTests
```

Expected: FAIL because `OneClickAppLaunchTaskGate` is missing.

- [x] **Step 4: Implement one task gate and shell driver**

Add the gate:

```swift
@MainActor
final class OneClickAppLaunchTaskGate<Value> {
    private var task: Task<Value, Never>?

    func run(_ operation: @escaping @MainActor () async -> Value) async -> Value {
        if let task { return await task.value }
        let newTask = Task { @MainActor in await operation() }
        task = newTask
        let value = await newTask.value
        task = nil
        return value
    }
}
```

In `VeilHostShellApp`, create `@State private var oneClickAppLaunchGate = OneClickAppLaunchTaskGate<OneClickAppLaunchOutcome<WindowsAppLaunchResult>>()`. Replace direct tile/menu launch branching with `runOneClickAppLaunch(appId:)`.

Define the shell context exactly once:

```swift
private func currentAppLaunchContext() -> AppLaunchLifecycleContext {
    AppLaunchLifecycleContext(
        hasQueuedLaunch: model.pendingLaunchAppId != nil,
        canFulfillQueuedLaunch: model.canFulfillPendingLaunch,
        hasLiveAgentConnection: model.hasLiveAgentConnection,
        runtimeState: vmModel.snapshot?.state,
        canStartOrResume: vmModel.canStart || vmModel.canResume,
        guestAgentEndpointAvailable: agentConnectionPlan.isAvailable,
        agentWaitTimedOut: false,
        repairAttemptCount: 0
    )
}
```

The driver must use the existing boundaries:

```swift
let driver = OneClickAppLaunchDriver(
    context: { currentAppLaunchContext() },
    requestLaunch: { requestedAppId in
        model.selectedAppId = requestedAppId
        return await model.launchSelectedApp()
    },
    startOrResumeWindows: {
        await startOrResumeWindows()
        return vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    },
    waitForGuestAgent: { seconds in
        let report = await model.waitForLiveAgentConnection(
            endpoint: agentURLString,
            timeoutSeconds: seconds
        )
        return report.status == .connected
    },
    repairGuestAgent: {
        _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
        await vmModel.refreshRuntimeEvidence()
    },
    fulfillLaunch: { await model.fulfillPendingLaunch() }
)
```

On `.opened`, call `showWindowsAppWindow(for:)`, set product-facing success copy, and synchronize launcher visibility. On `.blocked(let failure)`, set `displayMessage = failure.userMessage`. Do not also schedule the old automatic recovery task for the same pending launch; retain the reconnect poller for passive reconnection and restore only.

- [x] **Step 5: Run all lifecycle and shell tests**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter AppLaunchLifecycleCoordinatorTests
swift test --disable-sandbox --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
swift test --disable-sandbox --package-path apps/mac-host --filter AppGuestAgentConnectionTests
swift test --disable-sandbox --package-path apps/mac-host --filter AppRuntimeBooterTests
```

Expected: PASS; duplicate clicks share one task and agent repair never exceeds two attempts.

- [x] **Step 6: Commit shell wiring only**

```bash
git add -p apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift
git add -p apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift
git add -p apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift
git add -p apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift
git add -p apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift
git diff --cached --check
git commit -m "feat(app): route launches through one-click lifecycle"
```

### Task 5: Lock Window Handoff Against Size and Focus Oscillation

**Files:**
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsAppWindowPresenterTests.swift`
- Modify if the test fails: `apps/mac-host/Sources/VeilHostShell/App/WindowsAppWindowPresenter.swift`

**Interfaces:**
- Consumes: `WindowsAppWindowPresenter.showWindow(for:bringToFront:)`.
- Produces: the invariant that frame/window-update refreshes preserve host frame and foreground order.

- [x] **Step 1: Add a repeated-update regression test**

```swift
@Test("repeated frame updates never resize or re-center an existing app window")
func repeatedFrameUpdatesPreserveWindowGeometry() throws {
    _ = NSApplication.shared
    let presenter = WindowsAppWindowPresenter()
    defer { presenter.closeAll() }

    let id = "hwnd:stable"
    presenter.showWindow(for: session(windowId: id, appId: "winapp_notepad", title: "Notepad"))
    let window = try #require(mirroredWindow(withId: id))
    let userFrame = NSRect(x: 96, y: 112, width: 960, height: 600)
    window.setFrame(userFrame, display: false)

    for sequence in 1...30 {
        presenter.showWindow(
            for: session(windowId: id, appId: "winapp_notepad", title: "Notepad \(sequence)"),
            bringToFront: false
        )
        #expect(NSEqualRects(window.frame, userFrame))
    }
}
```

Extend the existing background-focus test to alternate 30 updates between two HWNDs and assert the foreground window never changes.

- [x] **Step 2: Run presenter tests**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter WindowsAppWindowPresenterTests
```

Expected: PASS with the current preservation path. If it fails, the failure reproduces the reported center-small-to-large oscillation.

- [x] **Step 3: Apply the minimal fix only if Step 2 fails**

Keep `updateExistingWindow` content replacement in place, but prevent `configure` from applying a new initial frame to an existing HWND. Restore `preservedFrame` after constraints and content replacement, and never call `present` unless `bringToFront` is true. Do not weaken the guest aspect-ratio constraint.

- [x] **Step 4: Re-run placement and presenter tests**

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter WindowsAppWindowPlacementTests
swift test --disable-sandbox --package-path apps/mac-host --filter WindowsAppWindowPresenterTests
```

Expected: PASS with stable geometry, preserved aspect ratio, and no background focus stealing.

- [x] **Step 5: Commit the regression evidence**

```bash
git add -p apps/mac-host/Tests/VeilHostShellTests/WindowsAppWindowPresenterTests.swift
git add -p apps/mac-host/Sources/VeilHostShell/App/WindowsAppWindowPresenter.swift
git diff --cached --check
git commit -m "test(ui): lock app window handoff stability"
```

If no source fix was necessary, omit the source file from staging.

### Task 6: Run Deterministic Production Gates

**Files:**
- Create: `docs/checklists/2026-08-10-p0-one-click-runtime-proof.md`

**Interfaces:**
- Consumes: the completed P0 implementation and existing `script/test_all.sh`.
- Produces: a dated deterministic verification record with exact command results.

- [x] **Step 1: Run Swift host tests**

```bash
swift test --disable-sandbox --package-path apps/mac-host
```

Expected: all Swift suites pass.

- [x] **Step 2: Run Windows agent tests with the managed SDK**

```bash
"/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" test \
  apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --no-restore
```

Expected: all Windows agent tests pass.

- [x] **Step 3: Run the complete repository gate**

```bash
PATH="/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8:$PATH" ./script/test_all.sh
```

Expected: Swift host, Windows agent, all Node packages, app bundle contract, and install/uninstall lifecycle pass.

- [x] **Step 4: Record exact deterministic results**

Create `docs/checklists/2026-08-10-p0-one-click-runtime-proof.md` with:

```markdown
# P0 One-Click Runtime Proof — 2026-08-10

## Deterministic gates

- [x] Swift host: record the exact test and suite counts printed by the successful run.
- [x] Windows agent: record the exact passing test count printed by `dotnet test`.
- [x] Node harness: record the exact package count printed by `script/test_all.sh`.
- [x] macOS bundle and launch contract.
- [x] install, guarded replace, uninstall, preservation, and reinstall lifecycle.

## Live Windows gates

- [x] Fresh boot-safe QEMU launch.
- [x] Guest-agent health through `ws://127.0.0.1:18444`.
- [x] One Notepad tile click opens one macOS window.
- [x] Initial and post-input frames prove mouse, keyboard, and clipboard.
- [x] Normal app path never shows the nested Windows desktop.
```

Replace each “record the exact” instruction with the observed numeric output before committing; an unobserved count is a plan failure.

- [x] **Step 5: Commit deterministic evidence**

```bash
git add docs/checklists/2026-08-10-p0-one-click-runtime-proof.md
git diff --cached --check
git commit -m "docs: record P0 deterministic gates"
```

### Task 7: Prove the Real Windows Loop Safely

**Files:**
- Modify: `docs/checklists/2026-08-10-p0-one-click-runtime-proof.md`
- Evidence outside git: `/Users/uulab/Library/Application Support/Veil/Diagnostics/P0 Proof/`

**Interfaces:**
- Consumes: `veil-vmctl qemu-install-status`, `qemu-powerdown`, `qemu-plan`, `qemu-start`, `qemu-capture`, `guest-agent-wait`, and `mvp-proof`.
- Produces: a real Windows proof tied to `git rev-parse HEAD` and fixed screenshot/report names.

- [x] **Step 1: Record the tested identity and inspect the running VM**

```bash
git rev-parse HEAD
apps/mac-host/.build/debug/veil-vmctl qemu-install-status --json
apps/mac-host/.build/debug/veil-vmctl qemu-capture --json
```

Expected: commit identity is recorded; current VM state and console evidence are captured before mutation.

- [x] **Step 2: Request graceful shutdown**

```bash
apps/mac-host/.build/debug/veil-vmctl qemu-powerdown --json --wait-seconds 30
```

Expected: QEMU exits. If it does not, stop here and request explicit user approval before any `qemu-force-stop --i-understand-data-loss` command.

- [x] **Step 3: Verify and start the boot-safe plan**

```bash
apps/mac-host/.build/debug/veil-vmctl qemu-plan --json
apps/mac-host/.build/debug/veil-vmctl qemu-start --json
```

Expected: `networkAdapter` is `usb-net`, the process starts under QEMU/HVF, and the display endpoint is loopback-only.

- [x] **Step 4: Capture Windows and prove the agent**

```bash
apps/mac-host/.build/debug/veil-vmctl qemu-capture --json
apps/mac-host/.build/debug/veil-vmctl guest-agent-wait --json --wait-seconds 120
```

Expected: the screenshot is Windows Setup or the Windows desktop rather than UEFI `Start boot option`; guest-agent wait reaches `connected` before app proof.

If the screenshot remains UEFI or the agent remains unavailable, retain logs and screenshots, do not mark the gate complete, and switch to `superpowers:systematic-debugging` before changing boot or agent code.

- [x] **Step 5: Exercise the installed app path**

```bash
./script/build_and_run.sh --build-only
./script/install_macos.sh \
  --source "/Users/uulab/Documents/workspace/uulab/veil/dist/Veil.app" \
  --destination "/Applications/Veil.app" \
  --replace
/usr/bin/open -na "/Applications/Veil.app"
```

Click the Notepad tile once. Confirm one Notepad macOS window appears, the launcher hides, no nested desktop remains visible, and repeated frames do not resize or re-center the window.

- [x] **Step 6: Save real input and clipboard proof**

```bash
mkdir -p "/Users/uulab/Library/Application Support/Veil/Diagnostics/P0 Proof"
apps/mac-host/.build/debug/veil-vmctl mvp-proof \
  --json \
  --app-id winapp_notepad \
  --wait-seconds 120 \
  --require-proved \
  --output "/Users/uulab/Library/Application Support/Veil/Diagnostics/P0 Proof/mvp-proof.json"
```

Expected: `status=proved`, connected wait evidence, matching HWND/process identity, initial frame, mouse and keyboard input, clipboard evidence, and a newer post-input frame.

- [x] **Step 7: Update and commit live evidence metadata**

Mark only observed live gates complete in the checklist. Record the tested commit, macOS version, Mac model, Windows build, QEMU version, evidence directory name, and measured first/post-input frame latency. Do not commit screenshots, Windows media, clipboard content, or absolute user-document paths.

```bash
git add -p docs/checklists/2026-08-10-p0-one-click-runtime-proof.md
git diff --cached --check
git commit -m "docs: verify P0 one-click Windows app loop"
git push origin HEAD
```

### Task 8: Final P0 Review Gate

**Files:**
- Review only: all files changed in Tasks 1–7.

**Interfaces:**
- Consumes: deterministic and live evidence.
- Produces: an honest P0 completion decision.

- [x] **Step 1: Inspect commit separation and remaining dirty state**

```bash
git log --oneline -8
git status --short --branch
git diff --check
```

Expected: P0 commits are coherent and pushed; unrelated user changes remain preserved and unstaged.

- [x] **Step 2: Re-run the full gate at the final commit**

```bash
PATH="/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8:$PATH" ./script/test_all.sh
```

Expected: `All requested Veil regression gates passed.`

- [x] **Step 3: Apply completion vocabulary**

Mark P0 `implemented` if deterministic gates pass but any live gate is open. Mark it `verified` only when the live evidence checklist is complete. Do not mark Veil `production-ready`; P1–P4 and the notarized clean-Mac release gate remain separate plans.

- [x] **Step 4: Commit any evidence-only correction and push**

```bash
git add -p docs/checklists/2026-08-10-p0-one-click-runtime-proof.md
git diff --cached --check
git commit -m "docs: finalize P0 verification status"
git push origin HEAD
```

Skip this commit when Step 3 requires no document correction.
