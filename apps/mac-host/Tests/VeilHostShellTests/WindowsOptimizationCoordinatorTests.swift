import Foundation
import AppKit
import Testing
import VeilHostCore
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
            "waitForAgent",
            "waitForDesktop"
        ])
        #expect(coordinator.phase == .complete(displayOptimized: false))
    }

    @Test("does not complete until the post-restart Windows desktop is visible")
    func doesNotCompleteUntilPostRestartDesktopIsVisible() async {
        let service = RecordingWindowsOptimizationService(failureStep: "waitForDesktop#2")
        let coordinator = WindowsOptimizationCoordinator(service: service)

        await coordinator.begin()

        #expect(service.calls == [
            "prepareMedia",
            "restartWithPreparedMedia",
            "waitForDesktop",
            "dispatchOptimization",
            "waitForAgent",
            "waitForDesktop"
        ])
        #expect(coordinator.status.primaryButtonTitle == "Try Again")
        #expect(coordinator.status.isRunning == false)
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

    @Test("keeps the restarting status while waiting for the guest agent to return")
    func keepsRestartingStatusDuringAgentReconnect() async {
        let service = RecordingWindowsOptimizationService(pausesAgentWait: true)
        let coordinator = WindowsOptimizationCoordinator(service: service)
        let task = Task { @MainActor in
            await coordinator.begin()
        }

        while !service.calls.contains("waitForAgent") {
            await Task.yield()
        }

        #expect(coordinator.phase == .restartingWindows)

        service.pausesAgentWait = false
        await task.value
        #expect(coordinator.phase == .complete(displayOptimized: false))
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
        #expect(coordinator.status.observedDisplaySize == WindowsObservedDisplaySize(width: 800, height: 600))
        coordinator.recordDisplaySize(width: 1_024, height: 768)
        #expect(coordinator.phase == .complete(displayOptimized: false))
        #expect(coordinator.status.observedDisplaySize == WindowsObservedDisplaySize(width: 1_024, height: 768))
        coordinator.recordDisplaySize(width: 1_280, height: 720)
        #expect(coordinator.phase == .complete(displayOptimized: false))
        coordinator.recordDisplaySize(width: 1_440, height: 900)
        #expect(coordinator.phase == .complete(displayOptimized: true))
    }

    @Test("downgrades display optimization when a later framebuffer is below target")
    func downgradesDisplayOptimizationWhenLaterFramebufferIsBelowTarget() async {
        let service = RecordingWindowsOptimizationService()
        let coordinator = WindowsOptimizationCoordinator(service: service)
        await coordinator.begin()

        coordinator.recordDisplaySize(width: 1_440, height: 900)
        #expect(coordinator.phase == .complete(displayOptimized: true))

        coordinator.recordDisplaySize(width: 1_024, height: 768)

        #expect(coordinator.phase == .complete(displayOptimized: false))
        #expect(coordinator.status.detail.contains("1024×768"))
        #expect(coordinator.status.detail.contains("1440×900"))
    }

    @Test("requires the configured display target instead of a smaller widescreen frame")
    func requiresConfiguredDisplayTarget() {
        #expect(WindowsDisplayOptimizationPolicy.isOptimized(width: 1_280, height: 720) == false)
        #expect(WindowsDisplayOptimizationPolicy.isOptimized(width: 1_440, height: 900))
    }

    @Test("running Windows shuts down normally before rebuilding attached media")
    func runningWindowsShutsDownNormallyBeforeRebuildingAttachedMedia() async throws {
        let calls = OptimizationCallLog()
        let model = RecordingOptimizationVMModel(state: .running, calls: calls)
        let service = AppWindowsOptimizationService(
            vmModel: model,
            dependencies: .init(
                downloadGuestTools: {
                    calls.values.append("download")
                    return URL(fileURLWithPath: "/tmp/utm.iso")
                },
                requestGracefulShutdown: { _ in
                    calls.values.append("powerdown")
                    model.snapshot?.state = .stopped
                },
                dispatchOptimization: {},
                waitForAgent: { _ in true },
                sleep: { _ in }
            )
        )

        try await service.prepareMedia()
        try await service.restartWithPreparedMedia()

        #expect(calls.values == ["download", "powerdown", "refresh", "prepare", "start"])
    }

    @Test("stopped Windows rebuilds attached media without a redundant powerdown")
    func stoppedWindowsRebuildsAttachedMediaWithoutPowerdown() async throws {
        let calls = OptimizationCallLog()
        let model = RecordingOptimizationVMModel(state: .stopped, calls: calls)
        let service = AppWindowsOptimizationService(
            vmModel: model,
            dependencies: .init(
                downloadGuestTools: {
                    calls.values.append("download")
                    return URL(fileURLWithPath: "/tmp/utm.iso")
                },
                requestGracefulShutdown: { _ in
                    calls.values.append("powerdown")
                },
                dispatchOptimization: {},
                waitForAgent: { _ in true },
                sleep: { _ in }
            )
        )

        try await service.prepareMedia()
        try await service.restartWithPreparedMedia()

        #expect(calls.values == ["download", "prepare", "start"])
    }

    @Test("fresh but black console capture does not count as a ready Windows desktop")
    func freshButBlackConsoleCaptureDoesNotCountAsReadyDesktop() async throws {
        let screenshotURL = try makeBlackConsoleScreenshot()
        defer { try? FileManager.default.removeItem(at: screenshotURL) }
        let calls = OptimizationCallLog()
        let model = RecordingOptimizationVMModel(state: .running, calls: calls)
        model.snapshot?.latestConsoleLaunch = VMConsoleLaunchEvidence(
            provider: "QEMU/HVF",
            pid: 123,
            processLogPath: "/tmp/qemu.log",
            monitorSocketPath: "/tmp/missing-monitor.sock",
            consoleScreenshotPath: screenshotURL.path,
            previewStatus: .fresh,
            startedAt: Date()
        )
        let service = AppWindowsOptimizationService(
            vmModel: model,
            dependencies: .init(
                downloadGuestTools: { URL(fileURLWithPath: "/tmp/utm.iso") },
                requestGracefulShutdown: { _ in },
                dispatchOptimization: {},
                waitForAgent: { _ in true },
                sleep: { _ in }
            )
        )

        await #expect(throws: (any Error).self) {
            try await service.waitForDesktop(timeoutSeconds: 0)
        }
    }

    private func makeBlackConsoleScreenshot() throws -> URL {
        let screenshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-black-console-\(UUID().uuidString).png")
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let byteCount = representation.bytesPerRow * representation.pixelsHigh
        let bitmap = try #require(representation.bitmapData)
        bitmap.initialize(repeating: 0, count: byteCount)
        for offset in stride(from: 3, to: byteCount, by: 4) {
            bitmap[offset] = 255
        }
        let data = try #require(representation.representation(using: .png, properties: [:]))
        try data.write(to: screenshotURL, options: .atomic)
        return screenshotURL
    }
}

@MainActor
private final class OptimizationCallLog {
    var values: [String] = []
}

@MainActor
private final class RecordingOptimizationVMModel: WindowsOptimizationVMModeling {
    var snapshot: VMRuntimeSnapshot?
    var errorMessage: String?
    private let calls: OptimizationCallLog

    init(state: VMRuntimeState, calls: OptimizationCallLog) {
        self.calls = calls
        snapshot = VMRuntimeSnapshot(
            state: state,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            driverMediaPath: nil,
            virtualDiskPath: "/tmp/Windows.img",
            bootReady: true,
            windowsInstalled: true,
            detail: "Windows test runtime"
        )
    }

    func prepareWindowsOptimization(driverMediaPath: String) async -> Bool {
        calls.values.append("prepare")
        snapshot?.driverMediaPath = driverMediaPath
        return true
    }

    func refreshRuntimeEvidence() async {
        calls.values.append("refresh")
    }

    func start() async {
        calls.values.append("start")
        snapshot?.state = .running
    }
}

@MainActor
private final class RecordingWindowsOptimizationService: WindowsOptimizationServicing {
    var calls: [String] = []
    var failureStep: String?
    var agentConnected: Bool
    var pausesMediaPreparation: Bool
    var pausesAgentWait: Bool

    init(
        failureStep: String? = nil,
        agentConnected: Bool = true,
        pausesMediaPreparation: Bool = false,
        pausesAgentWait: Bool = false
    ) {
        self.failureStep = failureStep
        self.agentConnected = agentConnected
        self.pausesMediaPreparation = pausesMediaPreparation
        self.pausesAgentWait = pausesAgentWait
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
        let occurrence = calls.filter { $0 == "waitForDesktop" }.count
        try failIfNeeded("waitForDesktop#\(occurrence)")
        try failIfNeeded("waitForDesktop")
    }

    func dispatchOptimization() async throws {
        calls.append("dispatchOptimization")
        try failIfNeeded("dispatchOptimization")
    }

    func waitForAgent(timeoutSeconds: Int) async throws -> Bool {
        calls.append("waitForAgent")
        while pausesAgentWait {
            await Task.yield()
        }
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
