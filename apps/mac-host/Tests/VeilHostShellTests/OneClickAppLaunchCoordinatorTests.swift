import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

struct OneClickAppLaunchCoordinatorTests {
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
            fulfillLaunch: { "hwnd:0002" }
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
            fulfillLaunch: { "hwnd:0003" }
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        guard case .opened(let windowId) = outcome else {
            Issue.record("Expected repair to recover the app launch")
            return
        }
        #expect(windowId == "hwnd:0003")
        #expect(repairCount == 1)
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
            }
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(events == ["wait-agent:30", "recover-runtime", "wait-agent:30", "fulfill"])
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
            fulfillLaunch: { "unreachable" }
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
            fulfillLaunch: { "unreachable" }
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
            fulfillLaunch: { "unreachable" }
        )

        let outcome = await OneClickAppLaunchCoordinator().run(appId: "winapp_notepad", driver: driver)

        #expect(requestCount == 12)
        guard case .blocked(.transitionBudgetExceeded) = outcome else {
            Issue.record("Expected a stuck launch to hit the transition budget")
            return
        }
    }

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
}
