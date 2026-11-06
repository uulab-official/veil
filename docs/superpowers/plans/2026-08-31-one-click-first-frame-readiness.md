# One-Click First-Frame Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a one-click Windows app launch succeed only after Veil has a renderable first frame, with one bounded frame-stream recovery and visible stage progress.

**Architecture:** Extend the existing generic one-click coordinator with frame-readiness and progress callbacks, then provide a small AppKit-aware readiness policy in the host shell. Wire the callbacks in `VeilHostShellApp` so the launcher stays visible until the first frame is renderable and background maintenance cannot race the gated launch.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, VeilHostCore

**Spec:** `docs/superpowers/specs/2026-08-31-one-click-first-frame-readiness-design.md`

## Global Constraints

- macOS host support remains macOS 15+ on Apple Silicon.
- Do not change protocol messages, the Windows agent, harness fixtures, or VM boot behavior.
- Do not modify or overwrite the user's in-progress protocol acknowledgement files.
- Reuse the existing eight-second first-frame timeout.
- Permit at most one launch-time frame-subscription restart.
- Do not present a macOS app window until the first frame is renderable.
- Keep the launcher visible after capture or first-frame failure.
- Use product copy that avoids QEMU, HWND, and protocol terminology on the primary launcher surface.

## File Structure

- Modify `apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift`: launch stages, first-frame driver contract, typed failures, and bounded completion gate.
- Modify `apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift`: coordinator ordering, timeout, recovery, failure, progress, and duplicate-click tests.
- Create `apps/mac-host/Sources/VeilHostShell/App/WindowsAppFirstFrameReadiness.swift`: AppKit-aware renderability policy, bounded polling, and product-facing progress copy.
- Create `apps/mac-host/Tests/VeilHostShellTests/WindowsAppFirstFrameReadinessTests.swift`: PNG, composited, unavailable, missing, and polling decisions.
- Modify `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`: real model/compositor driver callbacks, progress messages, and launch/maintenance coordination.
- Modify `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`: show the existing `displayMessage` on the installed launcher surface.

---

### Task 1: Extend The One-Click Coordinator Through First-Frame Readiness

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift`
- Modify: `apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift`

**Interfaces:**
- Consumes: existing `AppLaunchLifecycleCoordinator`, `OneClickAppLaunchTaskGate`, and generic `LaunchResult`.
- Produces: `OneClickAppFrameReadiness`, `OneClickAppLaunchStage`, three new `AppLaunchLifecycleFailure` cases, and required readiness/recovery/progress closures on `OneClickAppLaunchDriver`.

- [ ] **Step 1: Add failing tests for waiting, recovery, and progress order**

Add test-local helpers so every driver explicitly supplies the new contract:

```swift
private func readyFrameDriverValues<Result: Sendable>() -> (
    readiness: (Result) -> OneClickAppFrameReadiness,
    wait: (Result, Int) async -> OneClickAppFrameReadiness,
    restart: (Result) async -> Bool,
    progress: (OneClickAppLaunchStage) -> Void
) {
    (
        readiness: { _ in .ready },
        wait: { _, _ in .ready },
        restart: { _ in false },
        progress: { _ in }
    )
}

private func connectedQueuedContext() -> AppLaunchLifecycleContext {
    AppLaunchLifecycleContext(
        hasQueuedLaunch: true,
        canFulfillQueuedLaunch: true,
        hasLiveAgentConnection: true,
        runtimeState: .running,
        canStartOrResume: true,
        guestAgentEndpointAvailable: true,
        agentWaitTimedOut: false,
        repairAttemptCount: 0
    )
}

private func connectedDriver(
    waitForFirstFrame: @escaping (String, Int) async -> OneClickAppFrameReadiness,
    frameReadiness: @escaping (String) -> OneClickAppFrameReadiness,
    restartFrameStream: @escaping (String) async -> Bool,
    reportStage: @escaping (OneClickAppLaunchStage) -> Void = { _ in }
) -> OneClickAppLaunchDriver<String> {
    OneClickAppLaunchDriver(
        context: { connectedQueuedContext() },
        requestLaunch: { _ in nil },
        startOrResumeWindows: { true },
        waitForGuestAgent: { _ in true },
        recoverStalledRuntime: { false },
        repairGuestAgent: {},
        fulfillLaunch: { "hwnd:frame" },
        frameReadiness: frameReadiness,
        waitForFirstFrame: waitForFirstFrame,
        restartFrameStream: restartFrameStream,
        reportStage: reportStage
    )
}
```

Update the existing driver constructions to pass `frameReadiness`, `waitForFirstFrame`, `restartFrameStream`, and `reportStage`. Then add these focused tests:

```swift
@Test("an already connected launch waits for a renderable first frame")
@MainActor
func waitsForFirstFrameBeforeOpening() async {
    var waitCount = 0
    let driver = OneClickAppLaunchDriver<String>(
        context: { connectedQueuedContext() },
        requestLaunch: { _ in nil },
        startOrResumeWindows: { true },
        waitForGuestAgent: { _ in true },
        recoverStalledRuntime: { false },
        repairGuestAgent: {},
        fulfillLaunch: { "hwnd:frame" },
        frameReadiness: { _ in .waiting },
        waitForFirstFrame: { result, seconds in
            #expect(result == "hwnd:frame")
            #expect(seconds == OneClickAppLaunchCoordinator.firstFrameWaitSeconds)
            waitCount += 1
            return .ready
        },
        restartFrameStream: { _ in false },
        reportStage: { _ in }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

    #expect(waitCount == 1)
    guard case .opened("hwnd:frame") = outcome else {
        Issue.record("Expected opening only after first-frame readiness")
        return
    }
}

@Test("one first-frame timeout restarts the stream and then opens")
@MainActor
func recoversFirstFrameOnce() async {
    var waits: [OneClickAppFrameReadiness] = [.waiting, .ready]
    var restartCount = 0
    let driver = connectedDriver(
        waitForFirstFrame: { _, _ in waits.removeFirst() },
        frameReadiness: { _ in .waiting },
        restartFrameStream: { _ in
            restartCount += 1
            return true
        }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

    #expect(restartCount == 1)
    guard case .opened = outcome else {
        Issue.record("Expected frame restart to recover the launch")
        return
    }
}

@Test("a second first-frame timeout returns a bounded failure")
@MainActor
func stopsAfterFirstFrameRecoveryBudget() async {
    let driver = connectedDriver(
        waitForFirstFrame: { _, _ in .waiting },
        frameReadiness: { _ in .waiting },
        restartFrameStream: { _ in true }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

    guard case .blocked(.firstFrameRecoveryExhausted) = outcome else {
        Issue.record("Expected bounded first-frame failure")
        return
    }
}

@Test("launch stages report the real recovery order")
@MainActor
func reportsFrameRecoveryStages() async {
    var stages: [OneClickAppLaunchStage] = []
    var waits: [OneClickAppFrameReadiness] = [.waiting, .ready]
    let driver = connectedDriver(
        waitForFirstFrame: { _, _ in waits.removeFirst() },
        frameReadiness: { _ in .waiting },
        restartFrameStream: { _ in true },
        reportStage: { stages.append($0) }
    )

    _ = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

    #expect(stages == [.preparingApp, .openingApp, .waitingForFirstFrame, .restartingFrameStream, .waitingForFirstFrame, .ready])
}
```

Add the remaining failure and delayed-success cases:

```swift
@Test("capture unavailable blocks without a blank host window")
@MainActor
func blocksUnavailableCapture() async {
    let driver = connectedDriver(
        waitForFirstFrame: { _, _ in .unavailable },
        frameReadiness: { _ in .unavailable },
        restartFrameStream: { _ in false }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
    guard case .blocked(.captureUnavailable) = outcome else {
        Issue.record("Expected capture-unavailable failure")
        return
    }
}

@Test("a failed frame restart reports its own failure")
@MainActor
func reportsFrameRestartFailure() async {
    let driver = connectedDriver(
        waitForFirstFrame: { _, _ in .waiting },
        frameReadiness: { _ in .waiting },
        restartFrameStream: { _ in false }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
    guard case .blocked(.firstFrameRecoveryFailed) = outcome else {
        Issue.record("Expected frame-restart failure")
        return
    }
}

@Test("a delayed frame prevents an unnecessary restart")
@MainActor
func rechecksBeforeRestarting() async {
    var restartCount = 0
    let driver = connectedDriver(
        waitForFirstFrame: { _, _ in .waiting },
        frameReadiness: { _ in .ready },
        restartFrameStream: { _ in
            restartCount += 1
            return true
        }
    )

    let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
    #expect(restartCount == 0)
    guard case .opened = outcome else {
        Issue.record("Expected delayed readiness to finish the launch")
        return
    }
}
```

Rename the existing task-gate test to `coalescesDuplicateClicksUntilFirstFrameReadinessCompletes`, keep its release continuation inside the gated operation, and assert both callers receive the same result only after the continuation is released. This models the full coordinator remaining inside the gate through first-frame readiness.

- [ ] **Step 2: Run the coordinator tests and confirm the new contract is missing**

Run:

```sh
swift test --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
```

Expected: compilation fails because `OneClickAppFrameReadiness`, `OneClickAppLaunchStage`, the driver fields, and first-frame failures do not exist.

- [ ] **Step 3: Implement the typed coordinator contract and bounded completion gate**

Add these types and required driver fields:

```swift
enum OneClickAppFrameReadiness: Equatable, Sendable {
    case ready
    case waiting
    case unavailable
}

enum OneClickAppLaunchStage: Equatable, Sendable {
    case preparingApp
    case startingOrResumingWindows
    case connectingAppBridge
    case recoveringRuntime
    case repairingAppBridge(attempt: Int)
    case openingApp
    case waitingForFirstFrame
    case restartingFrameStream
    case ready
}

@MainActor
struct OneClickAppLaunchDriver<LaunchResult: Sendable> {
    var context: () -> AppLaunchLifecycleContext
    var requestLaunch: (String) async -> LaunchResult?
    var startOrResumeWindows: () async -> Bool
    var waitForGuestAgent: (Int) async -> Bool
    var recoverStalledRuntime: () async -> Bool
    var repairGuestAgent: () async throws -> Void
    var fulfillLaunch: () async -> LaunchResult?
    var frameReadiness: (LaunchResult) -> OneClickAppFrameReadiness
    var waitForFirstFrame: (LaunchResult, Int) async -> OneClickAppFrameReadiness
    var restartFrameStream: (LaunchResult) async -> Bool
    var reportStage: (OneClickAppLaunchStage) -> Void
}
```

Add the failures to `AppLaunchLifecycleFailure` and give them product-facing `userMessage` values:

```swift
case captureUnavailable
case firstFrameRecoveryFailed
case firstFrameRecoveryExhausted
```

```swift
case .captureUnavailable:
    return "Windows opened the app, but app screen sharing is unavailable. Open recovery to check the Windows app connection."
case .firstFrameRecoveryFailed:
    return "Windows opened the app, but Veil could not restart its screen. Use Refresh App Screen and try again."
case .firstFrameRecoveryExhausted:
    return "Windows opened the app, but its screen did not arrive after one recovery attempt. Open recovery for the next safe action."
```

Set `static let firstFrameWaitSeconds = 8`. Report the matching stage before every existing driver action. Route every non-`nil` launch result through one helper:

```swift
private func finish<LaunchResult: Sendable>(
    _ result: LaunchResult,
    driver: OneClickAppLaunchDriver<LaunchResult>
) async -> OneClickAppLaunchOutcome<LaunchResult> {
    driver.reportStage(.waitingForFirstFrame)
    switch await driver.waitForFirstFrame(result, Self.firstFrameWaitSeconds) {
    case .ready:
        driver.reportStage(.ready)
        return .opened(result)
    case .unavailable:
        return .blocked(.captureUnavailable)
    case .waiting:
        break
    }

    switch driver.frameReadiness(result) {
    case .ready:
        driver.reportStage(.ready)
        return .opened(result)
    case .unavailable:
        return .blocked(.captureUnavailable)
    case .waiting:
        break
    }

    driver.reportStage(.restartingFrameStream)
    guard await driver.restartFrameStream(result) else {
        return .blocked(.firstFrameRecoveryFailed)
    }

    driver.reportStage(.waitingForFirstFrame)
    switch await driver.waitForFirstFrame(result, Self.firstFrameWaitSeconds) {
    case .ready:
        driver.reportStage(.ready)
        return .opened(result)
    case .unavailable:
        return .blocked(.captureUnavailable)
    case .waiting:
        return .blocked(.firstFrameRecoveryExhausted)
    }
}
```

- [ ] **Step 4: Run coordinator tests**

Run:

```sh
swift test --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
```

Expected: all coordinator and task-gate tests pass, including the existing runtime and agent recovery cases.

- [ ] **Step 5: Commit the coordinator boundary**

```sh
git add apps/mac-host/Sources/VeilHostShell/App/OneClickAppLaunchCoordinator.swift apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift
git commit -m "feat: gate app launch on first-frame readiness"
```

---

### Task 2: Add A Renderable First-Frame Policy

**Files:**
- Create: `apps/mac-host/Sources/VeilHostShell/App/WindowsAppFirstFrameReadiness.swift`
- Create: `apps/mac-host/Tests/VeilHostShellTests/WindowsAppFirstFrameReadinessTests.swift`

**Interfaces:**
- Consumes: `WindowMirrorSession`, `WindowFrameEvent.isCompositedSurface`, `WindowFrameEvent.encodedPayloadData`, and an optional compositor `CGImage`.
- Produces: `WindowsAppFirstFrameReadiness.resolve(session:compositedImage:)`, `WindowsAppFirstFrameReadiness.wait(timeoutSeconds:sessionProvider:compositedImageProvider:)`, and `OneClickAppLaunchStage.userMessage(appName:)`.

- [ ] **Step 1: Write failing policy tests**

Create tests that decode a real one-pixel PNG frame instead of depending on an inaccessible synthesized image initializer:

```swift
import CoreGraphics
import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct WindowsAppFirstFrameReadinessTests {
    @Test("a decodable PNG is renderable")
    func acceptsDecodablePNG() throws {
        let frame = try JSONDecoder().decode(WindowFrameEvent.self, from: Data(Self.pngFrameJSON.utf8))
        let session = Self.session(captureState: .streaming, frame: frame)

        #expect(WindowsAppFirstFrameReadiness.resolve(session: session, compositedImage: nil) == .ready)
    }

    @Test("a composited frame needs its compositor surface")
    func requiresCompositorSurface() throws {
        let frame = try JSONDecoder().decode(WindowFrameEvent.self, from: Data(Self.compositedFrameJSON.utf8))
        let session = Self.session(captureState: .streaming, frame: frame)

        #expect(WindowsAppFirstFrameReadiness.resolve(session: session, compositedImage: nil) == .waiting)
        #expect(WindowsAppFirstFrameReadiness.resolve(session: session, compositedImage: Self.pixelImage()) == .ready)
    }

    @Test("capture unavailable is a terminal readiness state")
    func reportsUnavailableCapture() {
        #expect(WindowsAppFirstFrameReadiness.resolve(session: Self.session(captureState: .unavailable), compositedImage: nil) == .unavailable)
    }

    @Test("missing or malformed frames keep waiting")
    func waitsForMissingOrMalformedFrame() throws {
        #expect(WindowsAppFirstFrameReadiness.resolve(session: nil, compositedImage: nil) == .waiting)
        #expect(WindowsAppFirstFrameReadiness.resolve(session: Self.session(captureState: .pending), compositedImage: nil) == .waiting)
    }
}
```

Use the fixture payload from `apps/mac-host/Tests/VeilHostCoreTests/Fixtures/window.frame.json` for `pngFrameJSON`. Define `compositedFrameJSON` with `format: "composited"` and empty `encodedData`. Create the compositor test image exactly as follows:

```swift
private static func pixelImage() -> CGImage {
    let data = Data([0xFF]) as CFData
    let provider = CGDataProvider(data: data)!
    return CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: 1,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
```

Add a polling test whose provider returns `.waiting` once and `.ready` on the next read, using `timeoutSeconds: 1` and a one-millisecond injected poll interval. Add exact copy assertions:

```swift
#expect(OneClickAppLaunchStage.startingOrResumingWindows.userMessage(appName: "Notepad") == "Starting Windows for Notepad.")
#expect(OneClickAppLaunchStage.waitingForFirstFrame.userMessage(appName: "Notepad") == "Opening Notepad screen.")
#expect(OneClickAppLaunchStage.restartingFrameStream.userMessage(appName: "Notepad") == "Refreshing Notepad screen once.")
```

- [ ] **Step 2: Run policy tests and verify the file is missing**

Run:

```sh
swift test --package-path apps/mac-host --filter WindowsAppFirstFrameReadinessTests
```

Expected: compilation fails because `WindowsAppFirstFrameReadiness` and the stage copy extension do not exist.

- [ ] **Step 3: Implement renderability, bounded polling, and stage copy**

Create the production file:

```swift
import AppKit
import VeilHostCore

@MainActor
enum WindowsAppFirstFrameReadiness {
    static let defaultPollInterval: Duration = .milliseconds(100)

    static func resolve(
        session: WindowMirrorSession?,
        compositedImage: CGImage?
    ) -> OneClickAppFrameReadiness {
        guard let session else {
            return .waiting
        }
        guard session.captureState != .unavailable else {
            return .unavailable
        }
        guard let frame = session.latestFrame else {
            return .waiting
        }
        if frame.isCompositedSurface {
            return compositedImage == nil ? .waiting : .ready
        }
        guard frame.format == "png",
              let payload = frame.encodedPayloadData,
              !payload.isEmpty,
              NSImage(data: payload) != nil else {
            return .waiting
        }
        return .ready
    }

    static func wait(
        timeoutSeconds: Int,
        pollInterval: Duration = defaultPollInterval,
        sessionProvider: () -> WindowMirrorSession?,
        compositedImageProvider: (String) -> CGImage?
    ) async -> OneClickAppFrameReadiness {
        let deadline = ContinuousClock.now + .seconds(max(0, timeoutSeconds))
        while true {
            let session = sessionProvider()
            let readiness = resolve(
                session: session,
                compositedImage: session.map { compositedImageProvider($0.id) } ?? nil
            )
            guard readiness == .waiting,
                  ContinuousClock.now < deadline,
                  !Task.isCancelled else {
                return readiness
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}
```

Add exact product copy for every stage:

```swift
extension OneClickAppLaunchStage {
    func userMessage(appName: String) -> String {
        switch self {
        case .preparingApp: "Preparing \(appName)."
        case .startingOrResumingWindows: "Starting Windows for \(appName)."
        case .connectingAppBridge: "Connecting Windows apps for \(appName)."
        case .recoveringRuntime: "Restoring the Windows connection for \(appName)."
        case .repairingAppBridge(let attempt): "Repairing the Windows app connection for \(appName) (\(attempt)/2)."
        case .openingApp: "Opening \(appName) in Windows."
        case .waitingForFirstFrame: "Opening \(appName) screen."
        case .restartingFrameStream: "Refreshing \(appName) screen once."
        case .ready: "\(appName) is ready."
        }
    }
}
```

- [ ] **Step 4: Run policy and coordinator tests**

Run:

```sh
swift test --package-path apps/mac-host --filter WindowsAppFirstFrameReadinessTests
swift test --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
```

Expected: both suites pass.

- [ ] **Step 5: Commit the readiness policy**

```sh
git add apps/mac-host/Sources/VeilHostShell/App/WindowsAppFirstFrameReadiness.swift apps/mac-host/Tests/VeilHostShellTests/WindowsAppFirstFrameReadinessTests.swift
git commit -m "feat: validate renderable Windows app frames"
```

---

### Task 3: Wire First-Frame Readiness Into The Host Shell

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift`
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/OneClickAppLaunchCoordinatorTests.swift`
- Test: `apps/mac-host/Tests/VeilHostShellTests/WindowsAppFirstFrameReadinessTests.swift`

**Interfaces:**
- Consumes: Task 1's driver callbacks and Task 2's readiness/polling/copy APIs.
- Produces: a real launch driver that waits on `HostDashboardModel.mirrorSessions` and `compositedFrameImage(for:)`, restarts the matching subscription once, and presents the AppKit window only after `.opened`.

- [ ] **Step 1: Add the active first-frame gate state and real driver callbacks**

Add host-shell state beside the existing one-click gate:

```swift
@State private var activeOneClickFrameWindowID: String?
```

Resolve the product app name before starting the gated task:

```swift
let appName = model.apps.first { $0.id == appId }?.name ?? "Windows app"
```

Inside `oneClickAppLaunchGate.run`, clear the active window with `defer`, then provide the callbacks:

```swift
defer { self.activeOneClickFrameWindowID = nil }

let driver = OneClickAppLaunchDriver<WindowsAppLaunchResult>(
    context: { self.currentAppLaunchContext() },
    requestLaunch: { requestedAppId in
        self.model.selectedAppId = requestedAppId
        return await self.model.launchSelectedApp()
    },
    startOrResumeWindows: {
        await self.startOrResumeWindows()
        return self.vmModel.snapshot?.state == .running || self.vmModel.snapshot?.state == .starting
    },
    waitForGuestAgent: { seconds in
        let report = await self.model.waitForLiveAgentConnection(endpoint: self.agentURLString, timeoutSeconds: seconds)
        return report.status == .connected
    },
    recoverStalledRuntime: {
        let result = await self.vmRuntimeBooter.recoverStalledRuntime()
        await self.vmModel.refreshRuntimeEvidence()
        switch result {
        case .recovered:
            return true
        case .notNeeded, .unsupported, .unavailable, .failed:
            return false
        }
    },
    repairGuestAgent: {
        _ = try await self.vmRuntimeBooter.installGuestAgentFromAttachedMedia()
        await self.vmModel.refreshRuntimeEvidence()
    },
    fulfillLaunch: { await self.model.fulfillPendingLaunch() },
    frameReadiness: { result in
        let windowId = result.window.windowId
        let session = self.model.mirrorSessions.first { $0.id == windowId }
        return WindowsAppFirstFrameReadiness.resolve(
            session: session,
            compositedImage: self.model.compositedFrameImage(for: windowId)
        )
    },
    waitForFirstFrame: { result, seconds in
        let windowId = result.window.windowId
        self.activeOneClickFrameWindowID = windowId
        return await WindowsAppFirstFrameReadiness.wait(
            timeoutSeconds: seconds,
            sessionProvider: { self.model.mirrorSessions.first { $0.id == windowId } },
            compositedImageProvider: { self.model.compositedFrameImage(for: $0) }
        )
    },
    restartFrameStream: { result in
        await self.model.restartFrameSubscription(windowId: result.window.windowId)
    },
    reportStage: { stage in
        self.displayMessage = stage.userMessage(appName: appName)
    }
)
```

Keep the existing `.opened` switch as the only call site that invokes `showWindowsAppWindow(for:)`. Keep the `.blocked` switch activating the launcher and rendering the typed failure message.

- [ ] **Step 2: Prevent automatic frame maintenance from racing the active gate**

At the top of `performFrameStreamMaintenance(automatic:)`, add:

```swift
if automatic, activeOneClickFrameWindowID != nil {
    return
}
```

This pauses only the two-second background maintenance loop for the bounded first-frame wait. Manual recovery and post-failure maintenance remain unchanged.

- [ ] **Step 3: Display the existing progress message on the installed launcher**

In `WindowsSetupDisplayPanel.machineDisplay`, place this beneath the machine title/subtitle and before the primary action:

```swift
if let displayMessage, !displayMessage.isEmpty {
    Label(displayMessage, systemImage: "info.circle.fill")
        .font(.callout.weight(.medium))
        .foregroundStyle(.white.opacity(0.84))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .accessibilityLabel(displayMessage)
}
```

Do not add another navigation surface, sheet, or diagnostic panel.

- [ ] **Step 4: Run narrow host-shell verification**

Run:

```sh
swift test --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
swift test --package-path apps/mac-host --filter WindowsAppFirstFrameReadinessTests
swift build --package-path apps/mac-host --product veil-host-shell
```

Expected: both focused suites pass and `veil-host-shell` builds.

- [ ] **Step 5: Run the full Swift verification and working-tree safety checks**

Run:

```sh
swift test --package-path apps/mac-host
git diff --check
git status --short
```

Expected: the full Swift suite passes; `git diff --check` is silent; user-owned protocol changes remain present and unstaged unless they were already staged by the user.

- [ ] **Step 6: Commit only the host-shell integration**

```sh
git add apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift
git commit -m "feat: present Windows apps after first frame"
```

Do not stage any file listed as a pre-existing user change.

---

### Task 4: Final Acceptance Verification

**Files:**
- Verify only; no source file is modified by this task.

**Interfaces:**
- Consumes: the completed coordinator, readiness policy, and host-shell integration.
- Produces: deterministic evidence that the slice satisfies the design without changing the protocol boundary.

- [ ] **Step 1: Verify the first-frame behavior is covered by named tests**

Run:

```sh
swift test --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
swift test --package-path apps/mac-host --filter WindowsAppFirstFrameReadinessTests
```

Expected: tests prove no `.opened` outcome occurs before `.ready`, only one restart occurs, unavailable capture is typed, progress order is stable, and duplicate clicks coalesce.

- [ ] **Step 2: Verify the complete macOS package**

Run:

```sh
swift test --package-path apps/mac-host
swift build --package-path apps/mac-host --product veil-host-shell
```

Expected: all tests and the product build pass.

- [ ] **Step 3: Confirm scope and repository hygiene**

Run:

```sh
git diff --check
git status --short
git log -4 --oneline --decorate
```

Expected: no whitespace errors; exactly the planned host-shell commits appear after the design and plan commits; the user's protocol acknowledgement changes are still preserved.
