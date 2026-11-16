import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

private func readyFrameDriverValues() -> (
    readiness: (String) -> OneClickAppFrameReadiness,
    wait: (String, Int) async -> OneClickAppFrameReadiness,
    restart: (String) async -> Bool,
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

@MainActor
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

struct OneClickAppLaunchCoordinatorTests {
    @Test("stopping Windows cancels the shared launch and permits a later retry")
    @MainActor
    func cancelsSharedLaunchBeforeRetry() async {
        let gate = OneClickAppLaunchTaskGate<Bool>()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        var iterator = started.stream.makeAsyncIterator()
        let caller = Task { @MainActor in
            await gate.run {
                started.continuation.yield()
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
                return Task.isCancelled
            }
        }
        _ = await iterator.next()
        gate.cancel()
        release.continuation.yield()
        #expect(await caller.value)
        #expect(await gate.run { !Task.isCancelled })
    }

    @Test("cancellation during first-frame waiting never restarts capture or opens a window")
    @MainActor
    func cancellationStopsFrameRecovery() async {
        var restarts = 0
        var stages: [OneClickAppLaunchStage] = []
        let outcome = await Task { @MainActor in
            let driver = connectedDriver(
                waitForFirstFrame: { _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .waiting
                },
                frameReadiness: { _ in .waiting },
                restartFrameStream: { _ in restarts += 1; return true },
                reportStage: { stages.append($0) }
            )
            return await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        }.value
        #expect(restarts == 0)
        #expect(!stages.contains(.restartingFrameStream))
        if case .opened = outcome { Issue.record("Cancelled launch must not open") }
    }

    @Test("a ready frame arriving with cancellation cannot report a successful launch")
    @MainActor
    func cancellationWinsOverReadyFrame() async {
        var readyReported = false
        let outcome = await Task { @MainActor in
            let driver = connectedDriver(
                waitForFirstFrame: { _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .ready
                },
                frameReadiness: { _ in .ready },
                restartFrameStream: { _ in false },
                reportStage: { if $0 == .ready { readyReported = true } }
            )
            return await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        }.value
        #expect(!readyReported)
        if case .opened = outcome { Issue.record("Cancelled ready launch must not present") }
    }

    @Test("a cancelled launch cannot send a guest launch command")
    @MainActor
    func cancellationBeforeLaunchHasNoSideEffects() async {
        var launches = 0
        _ = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            var driver = connectedDriver(
                waitForFirstFrame: { _, _ in .ready },
                frameReadiness: { _ in .ready },
                restartFrameStream: { _ in false }
            )
            driver.fulfillLaunch = { launches += 1; return "hwnd:cancelled" }
            return await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        }.value
        #expect(launches == 0)
    }

    @Test("one click queues, starts, connects, and opens the selected app")
    @MainActor
    func opensFromStoppedVM() async {
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
            },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(
            appId: "winapp_notepad",
            driver: driver
        )

        #expect(events == [
            "request:winapp_notepad",
            "start-or-resume",
            "wait-agent:90",
            "fulfill"
        ])
        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected the app launch to open a window")
            return
        }
        #expect(windowId == "hwnd:0001")
    }

    @Test("an already connected guest fulfills without starting Windows")
    @MainActor
    func fulfillsAlreadyConnectedLaunch() async {
        var starts = 0
        let driver = OneClickAppLaunchDriver<String>(
            context: {
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
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: {
                starts += 1
                return true
            },
            waitForGuestAgent: { _ in true },
            repairGuestAgent: {},
            fulfillLaunch: { "hwnd:0002" },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected the connected app launch to open a window")
            return
        }
        #expect(windowId == "hwnd:0002")
        #expect(starts == 0)
    }

    @Test("one agent wait timeout triggers repair and then fulfills")
    @MainActor
    func repairsAfterAgentTimeout() async {
        var connected = false
        var repairCount = 0
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: true,
                    canFulfillQueuedLaunch: connected,
                    hasLiveAgentConnection: connected,
                    runtimeState: .running,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0
                )
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: { true },
            waitForGuestAgent: { _ in false },
            repairGuestAgent: {
                repairCount += 1
                connected = true
            },
            fulfillLaunch: { "hwnd:0003" },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected repair to recover the app launch")
            return
        }
        #expect(windowId == "hwnd:0003")
        #expect(repairCount == 1)
    }

    @Test("one click waits through a blank Windows boot before repairing the agent")
    @MainActor
    func waitsThroughBlankBootBeforeRepair() async {
        var connected = false
        var waitCount = 0
        var events: [String] = []
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: true,
                    canFulfillQueuedLaunch: connected,
                    hasLiveAgentConnection: connected,
                    runtimeState: .running,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0,
                    isConsoleStillBooting: waitCount < 2
                )
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: { true },
            waitForGuestAgent: { seconds in
                events.append("wait-agent:\(seconds)")
                waitCount += 1
                return false
            },
            repairGuestAgent: {
                events.append("repair-agent")
                connected = true
            },
            fulfillLaunch: {
                events.append("fulfill")
                return "hwnd:boot-grace"
            },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(events == ["wait-agent:90", "wait-agent:90", "repair-agent", "fulfill"])
        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected the app launch to wait for boot before repairing")
            return
        }
        #expect(windowId == "hwnd:boot-grace")
    }

    @Test("a failed agent wait refreshes VM evidence before choosing repair")
    @MainActor
    func refreshesEvidenceAfterAgentTimeout() async {
        var connected = false
        var refreshCount = 0
        var events: [String] = []
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: true,
                    canFulfillQueuedLaunch: connected,
                    hasLiveAgentConnection: connected,
                    runtimeState: .running,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0,
                    isConsoleStillBooting: refreshCount == 1
                )
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: { true },
            waitForGuestAgent: { seconds in
                events.append("wait-agent:\(seconds)")
                return false
            },
            refreshRuntimeEvidence: {
                refreshCount += 1
                events.append("refresh-evidence")
            },
            repairGuestAgent: {
                events.append("repair-agent")
                connected = true
            },
            fulfillLaunch: {
                events.append("fulfill")
                return "hwnd:refreshed-evidence"
            },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(events == [
            "wait-agent:90", "refresh-evidence", "wait-agent:90", "refresh-evidence", "repair-agent", "fulfill"
        ])
        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected refreshed boot evidence to delay repair")
            return
        }
        #expect(windowId == "hwnd:refreshed-evidence")
    }

    @Test("a known QEMU session recovers its transport before reinstalling the agent")
    @MainActor
    func recoversStalledRuntimeBeforeAgentRepair() async {
        var connected = false
        var runtimeRecoveryAttempted = false
        var waitCount = 0
        var events: [String] = []

        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: true,
                    canFulfillQueuedLaunch: connected,
                    hasLiveAgentConnection: connected,
                    runtimeState: .running,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0,
                    canRecoverStalledRuntime: true,
                    hasAttemptedRuntimeRecovery: runtimeRecoveryAttempted
                )
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: { true },
            waitForGuestAgent: { seconds in
                events.append("wait-agent:\(seconds)")
                waitCount += 1
                if waitCount == 2 {
                    connected = true
                }
                return connected
            },
            recoverStalledRuntime: {
                events.append("recover-runtime")
                runtimeRecoveryAttempted = true
                return true
            },
            repairGuestAgent: {
                events.append("repair-agent")
            },
            fulfillLaunch: {
                events.append("fulfill")
                return "hwnd:0004"
            },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(events == ["wait-agent:90", "recover-runtime", "wait-agent:90", "fulfill"])
        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected the recovered runtime to open the queued app")
            return
        }
        #expect(windowId == "hwnd:0004")
    }

    @Test("two failed repairs produce a bounded recovery failure")
    @MainActor
    func stopsAfterTwoFailedRepairs() async {
        var repairCount = 0
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: true,
                    canFulfillQueuedLaunch: false,
                    hasLiveAgentConnection: false,
                    runtimeState: .running,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0
                )
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: { true },
            waitForGuestAgent: { _ in false },
            repairGuestAgent: {
                repairCount += 1
                throw NSError(domain: "test", code: repairCount)
            },
            fulfillLaunch: { "unreachable" },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(repairCount == 2)
        guard case .blocked(.guestAgentRecoveryExhausted) = outcome else {
            Issue.record("Expected the repair budget to stop the launch")
            return
        }
    }

    @Test("an unavailable endpoint blocks without starting the runtime")
    @MainActor
    func blocksUnavailableEndpoint() async {
        var starts = 0
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: true,
                    canFulfillQueuedLaunch: false,
                    hasLiveAgentConnection: false,
                    runtimeState: .stopped,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: false,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0
                )
            },
            requestLaunch: { _ in nil },
            startOrResumeWindows: {
                starts += 1
                return true
            },
            waitForGuestAgent: { _ in true },
            repairGuestAgent: {},
            fulfillLaunch: { "unreachable" },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(starts == 0)
        guard case .blocked(.guestAgentEndpointUnavailable) = outcome else {
            Issue.record("Expected the unavailable endpoint to block the launch")
            return
        }
    }

    @Test("a stuck state stops at the transition budget")
    @MainActor
    func stopsAtTransitionBudget() async {
        var requestCount = 0
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: false,
                    canFulfillQueuedLaunch: false,
                    hasLiveAgentConnection: false,
                    runtimeState: .stopped,
                    canStartOrResume: false,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0
                )
            },
            requestLaunch: { _ in
                requestCount += 1
                return nil
            },
            startOrResumeWindows: { true },
            waitForGuestAgent: { _ in true },
            repairGuestAgent: {},
            fulfillLaunch: { "unreachable" },
            frameReadiness: readyFrameDriverValues().readiness,
            waitForFirstFrame: readyFrameDriverValues().wait,
            restartFrameStream: readyFrameDriverValues().restart,
            reportStage: readyFrameDriverValues().progress
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(requestCount == 12)
        guard case .blocked(.transitionBudgetExceeded) = outcome else {
            Issue.record("Expected a stuck launch to hit the transition budget")
            return
        }
    }

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

    @Test("an immediate app launch reports opening before requesting it")
    @MainActor
    func reportsOpeningBeforeImmediateLaunch() async {
        var stages: [OneClickAppLaunchStage] = []
        let driver = OneClickAppLaunchDriver<String>(
            context: {
                AppLaunchLifecycleContext(
                    hasQueuedLaunch: false,
                    canFulfillQueuedLaunch: false,
                    hasLiveAgentConnection: false,
                    runtimeState: .running,
                    canStartOrResume: true,
                    guestAgentEndpointAvailable: true,
                    agentWaitTimedOut: false,
                    repairAttemptCount: 0
                )
            },
            requestLaunch: { _ in "hwnd:immediate" },
            startOrResumeWindows: { true },
            waitForGuestAgent: { _ in true },
            recoverStalledRuntime: { false },
            repairGuestAgent: {},
            fulfillLaunch: { nil },
            frameReadiness: { _ in .ready },
            waitForFirstFrame: { _, _ in .ready },
            restartFrameStream: { _ in false },
            reportStage: { stages.append($0) }
        )

        _ = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        #expect(stages == [.preparingApp, .openingApp, .waitingForFirstFrame, .ready])
    }

    @Test("one first-frame timeout restarts the stream and then opens")
    @MainActor
    func recoversFirstFrameOnce() async {
        var waits: [OneClickAppFrameReadiness] = [.waiting, .ready]
        var restartCount = 0
        let driver = connectedDriver(
            waitForFirstFrame: { _, _ in waits.removeFirst() },
            frameReadiness: { _ in .waiting },
            restartFrameStream: { _ in restartCount += 1; return true }
        )
        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        #expect(restartCount == 1)
        guard case .opened = outcome else { Issue.record("Expected frame restart to recover the launch"); return }
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
        guard case .blocked(.firstFrameRecoveryExhausted) = outcome else { Issue.record("Expected bounded first-frame failure"); return }
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

    @Test("capture unavailable blocks without a blank host window")
    @MainActor
    func blocksUnavailableCapture() async {
        let driver = connectedDriver(waitForFirstFrame: { _, _ in .unavailable }, frameReadiness: { _ in .unavailable }, restartFrameStream: { _ in false })
        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        guard case .blocked(.captureUnavailable) = outcome else { Issue.record("Expected capture-unavailable failure"); return }
    }

    @Test("a failed frame restart reports its own failure")
    @MainActor
    func reportsFrameRestartFailure() async {
        let driver = connectedDriver(waitForFirstFrame: { _, _ in .waiting }, frameReadiness: { _ in .waiting }, restartFrameStream: { _ in false })
        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        guard case .blocked(.firstFrameRecoveryFailed) = outcome else { Issue.record("Expected frame-restart failure"); return }
    }

    @Test("a delayed frame prevents an unnecessary restart")
    @MainActor
    func rechecksBeforeRestarting() async {
        var restartCount = 0
        let driver = connectedDriver(waitForFirstFrame: { _, _ in .waiting }, frameReadiness: { _ in .ready }, restartFrameStream: { _ in restartCount += 1; return true })
        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)
        #expect(restartCount == 0)
        guard case .opened = outcome else { Issue.record("Expected delayed readiness to finish the launch"); return }
    }

    @Test("duplicate clicks coalesce until first-frame readiness completes")
    @MainActor
    func coalescesDuplicateClicksUntilFirstFrameReadinessCompletes() async {
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

    @Test("a click coalescing during task retirement cannot strand fresh launch ownership")
    @MainActor
    func coalescingDuringRetirementDoesNotStrandOwnership() async {
        let taskGate = OneClickAppLaunchTaskGate<String>()
        let presentationGate = OneClickAppWindowPresentationGate()
        let mutationGate = OneClickAppFrameMutationGate()
        var firstRuns = 0
        var coalescedRuns = 0
        var laterRuns = 0
        var cleanupObservedContinuation: AsyncStream<Void>.Continuation!
        var releaseRetirementContinuation: AsyncStream<Void>.Continuation!
        let cleanupObserved = AsyncStream<Void> { cleanupObservedContinuation = $0 }
        let releaseRetirement = AsyncStream<Void> { releaseRetirementContinuation = $0 }
        var cleanupObservedIterator = cleanupObserved.makeAsyncIterator()

        let first = Task { @MainActor in
            await taskGate.run {
                let value = await OneClickAppLaunchOwnership.run(
                    requestedAppId: "winapp_notepad",
                    pendingAppId: nil,
                    presentationGate: presentationGate,
                    mutationGate: mutationGate,
                    operation: {
                        firstRuns += 1
                        presentationGate.bindLaunchResult(
                            appId: "winapp_notepad",
                            windowId: "hwnd:first"
                        )
                        return "first"
                    },
                    finalize: { _ in
                        _ = presentationGate.authorizeLaunchPresentation(
                            appId: "winapp_notepad",
                            windowId: "hwnd:first",
                            decision: .ready
                        )
                    }
                )
                cleanupObservedContinuation.yield()
                var releaseIterator = releaseRetirement.makeAsyncIterator()
                _ = await releaseIterator.next()
                return value ?? "missing-first"
            }
        }
        _ = await cleanupObservedIterator.next()

        #expect(!presentationGate.keepsLauncherVisible)
        #expect(await mutationGate.runAutomaticMaintenance {} == true)

        let second = Task { @MainActor in
            await taskGate.run {
                coalescedRuns += 1
                return await OneClickAppLaunchOwnership.run(
                    requestedAppId: "winapp_calculator",
                    pendingAppId: nil,
                    presentationGate: presentationGate,
                    mutationGate: mutationGate,
                    operation: { "second" },
                    finalize: { _ in }
                ) ?? "missing-second"
            }
        }
        await Task.yield()

        #expect(firstRuns == 1)
        #expect(coalescedRuns == 0)
        #expect(!presentationGate.keepsLauncherVisible)
        #expect(await mutationGate.runAutomaticMaintenance {} == true)

        releaseRetirementContinuation.yield()
        #expect(await first.value == "first")
        #expect(await second.value == "first")

        let third = await taskGate.run {
            laterRuns += 1
            return await OneClickAppLaunchOwnership.run(
                requestedAppId: "winapp_calculator",
                pendingAppId: nil,
                presentationGate: presentationGate,
                mutationGate: mutationGate,
                operation: {
                    presentationGate.bindLaunchResult(
                        appId: "winapp_calculator",
                        windowId: "hwnd:later"
                    )
                    return "later"
                },
                finalize: { _ in
                    _ = presentationGate.authorizeLaunchPresentation(
                        appId: "winapp_calculator",
                        windowId: "hwnd:later",
                        decision: .ready
                    )
                }
            ) ?? "missing-later"
        }

        #expect(third == "later")
        #expect(laterRuns == 1)
        #expect(!presentationGate.keepsLauncherVisible)
        #expect(await mutationGate.runAutomaticMaintenance {} == true)
    }
}

@MainActor
struct OneClickAppWindowPresentationGateTests {
    @Test("a queued app owns early events when a different app was clicked")
    func queuedAppOwnsEarlyEvents() {
        let gate = OneClickAppWindowPresentationGate()
        let began = gate.begin(
            requestedAppId: "winapp_calculator",
            pendingAppId: "winapp_notepad"
        )
        #expect(began)

        #expect(!gate.allowsEventDrivenPresentation(appId: "winapp_notepad", windowId: "hwnd:early"))
        #expect(gate.allowsEventDrivenPresentation(appId: "winapp_calculator", windowId: "hwnd:other"))

        gate.bindLaunchResult(appId: "winapp_notepad", windowId: "hwnd:ready")

        #expect(!gate.allowsEventDrivenPresentation(appId: "winapp_notepad", windowId: "hwnd:ready"))
    }

    @Test("events for other apps remain presentable while one app waits for its first frame")
    func allowsUnrelatedAppEvents() {
        let gate = OneClickAppWindowPresentationGate()
        let began = gate.begin(requestedAppId: "winapp_notepad", pendingAppId: nil)
        #expect(began)

        #expect(gate.allowsEventDrivenPresentation(appId: "winapp_calculator", windowId: "hwnd:other"))
    }

    @Test("only the exact ready launch session releases the active gate")
    func releasesExactReadyLaunchSession() {
        let gate = OneClickAppWindowPresentationGate()
        let began = gate.begin(requestedAppId: "winapp_notepad", pendingAppId: nil)
        #expect(began)
        gate.bindLaunchResult(appId: "winapp_notepad", windowId: "hwnd:ready")

        let rejectedOtherWindow = gate.authorizeLaunchPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:other",
            decision: .ready
        )
        #expect(!rejectedOtherWindow)
        let authorizedReadyWindow = gate.authorizeLaunchPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:ready",
            decision: .ready
        )
        #expect(authorizedReadyWindow)

        #expect(gate.allowsEventDrivenPresentation(appId: "winapp_notepad", windowId: "hwnd:ready"))
    }

    @Test("a blocked logical app remains suppressed when reconnect assigns a replacement HWND")
    func suppressesReplacementWindowForFailedApp() {
        let gate = OneClickAppWindowPresentationGate()
        let began = gate.begin(requestedAppId: "winapp_notepad", pendingAppId: nil)
        #expect(began)
        gate.bindLaunchResult(appId: "winapp_notepad", windowId: "hwnd:failed")
        gate.finishBlockedLaunch()

        #expect(!gate.allowsEventDrivenPresentation(appId: "winapp_notepad", windowId: "hwnd:failed"))
        #expect(!gate.allowsEventDrivenPresentation(appId: "winapp_notepad", windowId: "hwnd:replacement"))
    }

    @Test("manual recovery acknowledgement does not release suppression before a new frame")
    func manualRecoveryWaitsForNewFrame() {
        let gate = OneClickAppWindowPresentationGate()
        let began = gate.begin(requestedAppId: "winapp_notepad", pendingAppId: nil)
        #expect(began)
        gate.bindLaunchResult(appId: "winapp_notepad", windowId: "hwnd:failed")
        gate.finishBlockedLaunch()

        let blockedBeforeFrame = gate.authorizeUserPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:replacement",
            decision: .blocked(.firstFramePending)
        )
        #expect(!blockedBeforeFrame)
        #expect(!gate.allowsEventDrivenPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:replacement"
        ))

        let authorizedAfterFrame = gate.authorizeUserPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:replacement",
            decision: .ready
        )
        #expect(authorizedAfterFrame)
        #expect(gate.allowsEventDrivenPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:replacement"
        ))
    }

    @Test("already-visible frame refresh remains allowed without releasing launch ownership")
    func allowsVisibleRefreshDuringLaunch() {
        let gate = OneClickAppWindowPresentationGate()
        let began = gate.begin(requestedAppId: "winapp_notepad", pendingAppId: nil)
        #expect(began)

        #expect(gate.allowsEventDrivenPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:visible",
            isAlreadyVisible: true
        ))
        #expect(!gate.allowsEventDrivenPresentation(
            appId: "winapp_notepad",
            windowId: "hwnd:new",
            isAlreadyVisible: false
        ))
    }
}

@MainActor
struct OneClickAppFrameMutationGateTests {
    @Test("manual recovery excludes repeated clicks and automatic maintenance until its frame arrives")
    func serializesManualRecoveryThroughPresentation() async {
        let gate = OneClickAppFrameMutationGate()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        var iterator = started.stream.makeAsyncIterator()
        let recovery = Task { @MainActor in
            await gate.runManualRecovery {
                started.continuation.yield()
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
        }
        _ = await iterator.next()
        #expect(await gate.runManualRecovery { Issue.record("Repeated recovery must not run") } == false)
        #expect(await gate.runAutomaticMaintenance { Issue.record("Automatic recovery must not overlap") } == false)
        #expect(gate.reserveLaunch())
        var launchRan = false
        let launch = Task { @MainActor in
            await gate.runReservedLaunch { launchRan = true }
        }
        await Task.yield()
        #expect(!launchRan)
        release.continuation.yield()
        #expect(await recovery.value)
        await launch.value
        #expect(launchRan)
        #expect(await gate.runAutomaticMaintenance {})
    }

    @Test("a failed ownership reservation leaves the current mutation owner protected")
    func preservesMutationOwnerAfterReserveFailure() async {
        let presentationGate = OneClickAppWindowPresentationGate()
        let mutationGate = OneClickAppFrameMutationGate()
        #expect(mutationGate.reserveLaunch())

        let result = await OneClickAppLaunchOwnership.run(
            requestedAppId: "winapp_notepad",
            pendingAppId: nil,
            presentationGate: presentationGate,
            mutationGate: mutationGate,
            operation: { "unexpected" },
            finalize: { _ in }
        )

        #expect(result == nil)
        #expect(!presentationGate.keepsLauncherVisible)
        #expect(await mutationGate.runAutomaticMaintenance {} == false)
        mutationGate.abandonLaunchReservation()
        #expect(await mutationGate.runAutomaticMaintenance {} == true)
    }

    @Test("a competing launch cannot clear another app's presentation ownership")
    func preservesPresentationOwnerAfterBeginFailure() async {
        let presentationGate = OneClickAppWindowPresentationGate()
        let mutationGate = OneClickAppFrameMutationGate()
        #expect(presentationGate.begin(requestedAppId: "winapp_notepad", pendingAppId: nil))
        #expect(mutationGate.reserveLaunch())
        let result = await OneClickAppLaunchOwnership.run(
            requestedAppId: "winapp_paint", pendingAppId: nil,
            presentationGate: presentationGate, mutationGate: mutationGate,
            operation: { "unexpected" }, finalize: { _ in }
        )
        #expect(result == nil)
        #expect(!presentationGate.allowsEventDrivenPresentation(appId: "winapp_notepad", windowId: "hwnd:pending"))
        #expect(await mutationGate.runAutomaticMaintenance {} == false)
        presentationGate.abandonActiveLaunch()
        mutationGate.abandonLaunchReservation()
    }

    @Test("a launch waits for an in-flight automatic sweep and excludes new sweeps")
    func serializesLaunchAgainstAutomaticMaintenance() async {
        let gate = OneClickAppFrameMutationGate()
        var events: [String] = []
        var automaticStartedContinuation: AsyncStream<Void>.Continuation!
        var releaseAutomaticContinuation: AsyncStream<Void>.Continuation!
        var launchStartedContinuation: AsyncStream<Void>.Continuation!
        var releaseLaunchContinuation: AsyncStream<Void>.Continuation!
        let automaticStarted = AsyncStream<Void> { automaticStartedContinuation = $0 }
        let releaseAutomatic = AsyncStream<Void> { releaseAutomaticContinuation = $0 }
        let launchStarted = AsyncStream<Void> { launchStartedContinuation = $0 }
        let releaseLaunch = AsyncStream<Void> { releaseLaunchContinuation = $0 }
        var automaticStartedIterator = automaticStarted.makeAsyncIterator()
        var launchStartedIterator = launchStarted.makeAsyncIterator()

        let automatic = Task { @MainActor in
            await gate.runAutomaticMaintenance {
                events.append("automatic-start")
                automaticStartedContinuation.yield()
                var iterator = releaseAutomatic.makeAsyncIterator()
                _ = await iterator.next()
                events.append("automatic-end")
            }
        }
        _ = await automaticStartedIterator.next()

        #expect(gate.reserveLaunch())
        let launch = Task { @MainActor in
            await gate.runReservedLaunch {
                events.append("launch-start")
                launchStartedContinuation.yield()
                var iterator = releaseLaunch.makeAsyncIterator()
                _ = await iterator.next()
                events.append("launch-end")
            }
        }
        await Task.yield()
        #expect(events == ["automatic-start"])
        #expect(await gate.runAutomaticMaintenance { events.append("unexpected-automatic") } == false)

        releaseAutomaticContinuation.yield()
        _ = await launchStartedIterator.next()
        #expect(events == ["automatic-start", "automatic-end", "launch-start"])
        #expect(await gate.runAutomaticMaintenance { events.append("unexpected-during-launch") } == false)

        releaseLaunchContinuation.yield()
        await launch.value
        _ = await automatic.value
        #expect(await gate.runAutomaticMaintenance { events.append("automatic-after") })
        #expect(events == [
            "automatic-start", "automatic-end", "launch-start", "launch-end", "automatic-after"
        ])
    }
}
