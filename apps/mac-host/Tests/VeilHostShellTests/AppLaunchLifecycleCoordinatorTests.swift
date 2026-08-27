import Testing
import VeilHostCore
@testable import VeilHostShell

struct AppLaunchLifecycleCoordinatorTests {
    @Test("requests the selected app when nothing is queued")
    func requestsLaunch() {
        #expect(step(queued: false) == .requestLaunch)
    }

    @Test("fulfills a queued app as soon as the live agent can launch it")
    func fulfillsQueuedLaunch() {
        #expect(step(canFulfill: true, live: true, state: .running) == .fulfillQueuedLaunch)
    }

    @Test("starts or resumes Windows for a queued app")
    func startsWindows() {
        #expect(step(state: .suspended, canStart: true) == .startOrResumeWindows)
    }

    @Test("waits for the guest agent while Windows is opening")
    func waitsForAgent() {
        #expect(step(state: .starting) == .waitForGuestAgent)
    }

    @Test("blocks before retrying an unavailable provider endpoint")
    func blocksUnavailableEndpoint() {
        #expect(step(state: .running, endpointAvailable: false) == .blockedGuestAgentEndpoint)
    }

    @Test("keeps setup blockers distinct from agent waiting")
    func blocksRuntimeSetup() {
        #expect(step(state: .notConfigured, canStart: false) == .blockedRuntimeSetup)
    }

    @Test("does not start a stopped runtime while setup is unavailable")
    func blocksStoppedRuntimeWithoutStartCapability() {
        #expect(step(state: .stopped, canStart: false) == .blockedRuntimeSetup)
    }

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

    private func step(
        queued: Bool = true,
        canFulfill: Bool = false,
        live: Bool = false,
        state: VMRuntimeState? = .stopped,
        canStart: Bool = true,
        endpointAvailable: Bool = true
    ) -> AppLaunchLifecycleStep {
        AppLaunchLifecycleCoordinator.nextStep(
            hasQueuedLaunch: queued,
            canFulfillQueuedLaunch: canFulfill,
            hasLiveAgentConnection: live,
            runtimeState: state,
            canStartOrResume: canStart,
            guestAgentEndpointAvailable: endpointAvailable
        )
    }

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
}
