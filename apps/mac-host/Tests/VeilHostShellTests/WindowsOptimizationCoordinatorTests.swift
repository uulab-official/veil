import Foundation
import Testing
@testable import VeilHostShell

@MainActor
struct WindowsOptimizationCoordinatorTests {
    @Test("runs every optimization step in order and completes only after agent connection")
    func runsEveryStepInOrderAndCompletesAfterAgentConnection() async {
        let service = RecordingWindowsOptimizationService()
        let coordinator = WindowsOptimizationCoordinator(service: service)

        await coordinator.begin()

        #expect(service.calls == [
            "prepareMedia",
            "restartWithPreparedMedia",
            "waitForDesktop",
            "dispatchOptimization",
            "waitForAgent"
        ])
        #expect(coordinator.phase == .complete(displayOptimized: false))
    }

    @Test("media download failure stops before runtime mutation")
    func mediaDownloadFailureStopsBeforeRuntimeMutation() async {
        let service = RecordingWindowsOptimizationService(failureStep: "prepareMedia")
        let coordinator = WindowsOptimizationCoordinator(service: service)

        await coordinator.begin()

        #expect(service.calls == ["prepareMedia"])
        #expect(coordinator.status.primaryButtonTitle == "Try Again")
    }

    @Test("desktop timeout never dispatches the installer")
    func desktopTimeoutNeverDispatchesTheInstaller() async {
        let service = RecordingWindowsOptimizationService(failureStep: "waitForDesktop")
        let coordinator = WindowsOptimizationCoordinator(service: service)

        await coordinator.begin()

        #expect(service.calls == ["prepareMedia", "restartWithPreparedMedia", "waitForDesktop"])
        #expect(coordinator.phase == .failed("waitForDesktop failed"))
    }

    @Test("agent timeout produces retryable failure instead of completion")
    func agentTimeoutProducesRetryableFailure() async {
        let service = RecordingWindowsOptimizationService(agentConnected: false)
        let coordinator = WindowsOptimizationCoordinator(service: service)

        await coordinator.begin()

        #expect(service.calls.last == "waitForAgent")
        #expect(coordinator.status.primaryButtonTitle == "Try Again")
        #expect(coordinator.status.isRunning == false)
    }

    @Test("cancel works before command dispatch")
    func cancelWorksBeforeCommandDispatch() async {
        let service = RecordingWindowsOptimizationService(pausesMediaPreparation: true)
        let coordinator = WindowsOptimizationCoordinator(service: service)
        let task = Task { @MainActor in
            await coordinator.begin()
        }

        while service.calls.isEmpty {
            await Task.yield()
        }
        coordinator.cancel()
        service.pausesMediaPreparation = false
        await task.value

        #expect(service.calls == ["prepareMedia"])
        #expect(coordinator.phase == .cancelled)
    }

    @Test("retry restarts from a fresh media evidence check")
    func retryRestartsFromFreshMediaEvidenceCheck() async {
        let service = RecordingWindowsOptimizationService(failureStep: "prepareMedia")
        let coordinator = WindowsOptimizationCoordinator(service: service)
        await coordinator.begin()
        service.failureStep = nil

        await coordinator.retry()

        #expect(service.calls.filter { $0 == "prepareMedia" }.count == 2)
        #expect(coordinator.phase == .complete(displayOptimized: false))
    }

    @Test("larger live framebuffer upgrades agent-connected completion")
    func largerLiveFramebufferUpgradesAgentConnectedCompletion() async {
        let service = RecordingWindowsOptimizationService()
        let coordinator = WindowsOptimizationCoordinator(service: service)
        await coordinator.begin()

        coordinator.recordDisplaySize(width: 800, height: 600)
        #expect(coordinator.phase == .complete(displayOptimized: false))
        coordinator.recordDisplaySize(width: 1_440, height: 900)
        #expect(coordinator.phase == .complete(displayOptimized: true))
    }
}

@MainActor
private final class RecordingWindowsOptimizationService: WindowsOptimizationServicing {
    var calls: [String] = []
    var failureStep: String?
    var agentConnected: Bool
    var pausesMediaPreparation: Bool

    init(
        failureStep: String? = nil,
        agentConnected: Bool = true,
        pausesMediaPreparation: Bool = false
    ) {
        self.failureStep = failureStep
        self.agentConnected = agentConnected
        self.pausesMediaPreparation = pausesMediaPreparation
    }

    func prepareMedia() async throws {
        calls.append("prepareMedia")
        while pausesMediaPreparation {
            await Task.yield()
        }
        try failIfNeeded("prepareMedia")
    }

    func restartWithPreparedMedia() async throws {
        calls.append("restartWithPreparedMedia")
        try failIfNeeded("restartWithPreparedMedia")
    }

    func waitForDesktop(timeoutSeconds: Int) async throws {
        calls.append("waitForDesktop")
        try failIfNeeded("waitForDesktop")
    }

    func dispatchOptimization() async throws {
        calls.append("dispatchOptimization")
        try failIfNeeded("dispatchOptimization")
    }

    func waitForAgent(timeoutSeconds: Int) async throws -> Bool {
        calls.append("waitForAgent")
        try failIfNeeded("waitForAgent")
        return agentConnected
    }

    private func failIfNeeded(_ step: String) throws {
        guard failureStep == step else {
            return
        }
        throw RecordingOptimizationError(step: step)
    }
}

private struct RecordingOptimizationError: LocalizedError {
    var step: String

    var errorDescription: String? {
        "\(step) failed"
    }
}
