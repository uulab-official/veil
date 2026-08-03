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
}
