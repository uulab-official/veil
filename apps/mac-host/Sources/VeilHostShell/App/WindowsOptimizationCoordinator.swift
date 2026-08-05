import Foundation
import Observation
import VeilHostCore

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

struct WindowsOptimizationStatus: Equatable {
    var phase: WindowsOptimizationPhase

    var title: String {
        switch phase {
        case .idle:
            "Finish Windows Optimization"
        case .preparingMedia:
            "Preparing Windows integration"
        case .restartingForMedia:
            "Restarting Windows safely"
        case .waitingForDesktop:
            "Waiting for the Windows desktop"
        case .installing:
            "Installing display and app support"
        case .restartingWindows:
            "Windows is restarting"
        case .verifying:
            "Checking Windows integration"
        case .complete(let displayOptimized):
            displayOptimized ? "Windows is optimized" : "Windows apps are connected"
        case .failed:
            "Windows optimization needs attention"
        case .cancelled:
            "Windows optimization cancelled"
        }
    }

    var detail: String {
        switch phase {
        case .idle:
            "Install display integration and Veil app support automatically. Windows will restart once."
        case .preparingMedia:
            "Downloading and validating official Guest Tools."
        case .restartingForMedia:
            "Veil is attaching the prepared integration media without changing your Windows disk."
        case .waitingForDesktop:
            "Keep Veil open while Windows reaches the desktop."
        case .installing:
            "Keep Veil open while Windows installs display integration and Veil app support."
        case .restartingWindows:
            "Windows will return automatically after one normal restart."
        case .verifying:
            "Veil is waiting for the Windows app connection to return."
        case .complete(let displayOptimized):
            displayOptimized
                ? "Display integration and Windows app support are ready."
                : "Windows apps are connected. Display optimization still needs attention."
        case .failed(let message):
            message
        case .cancelled:
            "No installer command was sent. You can restart optimization when ready."
        }
    }

    var progress: Double {
        switch phase {
        case .idle, .cancelled, .failed:
            0
        case .preparingMedia:
            0.15
        case .restartingForMedia:
            0.35
        case .waitingForDesktop:
            0.5
        case .installing:
            0.65
        case .restartingWindows:
            0.75
        case .verifying:
            0.9
        case .complete:
            1
        }
    }

    var isRunning: Bool {
        switch phase {
        case .preparingMedia, .restartingForMedia, .waitingForDesktop,
             .installing, .restartingWindows, .verifying:
            true
        case .idle, .complete, .failed, .cancelled:
            false
        }
    }

    var canCancel: Bool {
        switch phase {
        case .preparingMedia, .restartingForMedia, .waitingForDesktop:
            true
        case .idle, .installing, .restartingWindows, .verifying,
             .complete, .failed, .cancelled:
            false
        }
    }

    var primaryButtonTitle: String {
        switch phase {
        case .failed, .cancelled:
            "Try Again"
        case .idle:
            "Optimize Windows"
        case .complete:
            "Done"
        case .preparingMedia, .restartingForMedia, .waitingForDesktop,
             .installing, .restartingWindows, .verifying:
            "Optimizing..."
        }
    }

    var showsOptimizationCard: Bool {
        if case .complete(displayOptimized: true) = phase {
            return false
        }
        return true
    }
}

@MainActor
protocol WindowsOptimizationServicing: AnyObject {
    func prepareMedia() async throws
    func restartWithPreparedMedia() async throws
    func waitForDesktop(timeoutSeconds: Int) async throws
    func dispatchOptimization() async throws
    func waitForAgent(timeoutSeconds: Int) async throws -> Bool
}

enum WindowsOptimizationCoordinatorError: LocalizedError {
    case agentDidNotReconnect

    var errorDescription: String? {
        switch self {
        case .agentDidNotReconnect:
            "Windows restarted, but the Veil app connection did not return."
        }
    }
}

@MainActor
@Observable
final class WindowsOptimizationCoordinator {
    private(set) var phase: WindowsOptimizationPhase = .idle

    var status: WindowsOptimizationStatus {
        WindowsOptimizationStatus(phase: phase)
    }

    private let service: any WindowsOptimizationServicing
    private var cancellationRequested = false
    private var installerDispatched = false
    private var displayOptimized = false

    init(service: any WindowsOptimizationServicing) {
        self.service = service
    }

    func begin() async {
        guard !status.isRunning else {
            return
        }

        cancellationRequested = false
        installerDispatched = false

        do {
            phase = .preparingMedia
            try await service.prepareMedia()
            try checkCancellation()

            phase = .restartingForMedia
            try await service.restartWithPreparedMedia()
            try checkCancellation()

            phase = .waitingForDesktop
            try await service.waitForDesktop(timeoutSeconds: 60)
            try checkCancellation()

            phase = .installing
            installerDispatched = true
            try await service.dispatchOptimization()

            phase = .restartingWindows
            phase = .verifying
            guard try await service.waitForAgent(timeoutSeconds: 180) else {
                throw WindowsOptimizationCoordinatorError.agentDidNotReconnect
            }

            phase = .complete(displayOptimized: displayOptimized)
        } catch is WindowsOptimizationCancellation {
            phase = .cancelled
        } catch {
            if cancellationRequested, !installerDispatched {
                phase = .cancelled
            } else {
                phase = .failed(userMessage(for: error))
            }
        }
    }

    func retry() async {
        await begin()
    }

    func cancel() {
        guard status.canCancel, !installerDispatched else {
            return
        }
        cancellationRequested = true
    }

    func recordDisplaySize(width: Int, height: Int) {
        guard width > 0, height > 0 else {
            return
        }

        if width > 800 || height > 600 {
            displayOptimized = true
            if case .complete = phase {
                phase = .complete(displayOptimized: true)
            }
        }
    }

    private func checkCancellation() throws {
        if cancellationRequested, !installerDispatched {
            throw WindowsOptimizationCancellation()
        }
    }

    private func userMessage(for error: any Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private struct WindowsOptimizationCancellation: Error {}

@MainActor
protocol WindowsOptimizationVMModeling: AnyObject {
    var snapshot: VMRuntimeSnapshot? { get }
    var errorMessage: String? { get }
    func prepareWindowsOptimization(driverMediaPath: String) async -> Bool
    func refreshRuntimeEvidence() async
    func start() async
}

extension VMRuntimeModel: WindowsOptimizationVMModeling {}

enum AppWindowsOptimizationServiceError: LocalizedError {
    case mediaNotPrepared
    case gracefulShutdownIncomplete
    case mediaPreparationFailed(String)
    case windowsStartFailed(String)
    case desktopTimedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .mediaNotPrepared:
            "Guest Tools media was not prepared."
        case .gracefulShutdownIncomplete:
            "Windows did not finish shutting down normally."
        case .mediaPreparationFailed(let message):
            "Veil could not attach Windows integration media. \(message)"
        case .windowsStartFailed(let message):
            "Windows could not restart for optimization. \(message)"
        case .desktopTimedOut(let seconds):
            "The Windows desktop did not become ready within \(seconds) seconds."
        }
    }
}

@MainActor
final class AppWindowsOptimizationService: WindowsOptimizationServicing {
    struct Dependencies {
        var downloadGuestTools: () async throws -> URL
        var requestGracefulShutdown: (Int) async throws -> Void
        var dispatchOptimization: () async throws -> Void
        var waitForAgent: (Int) async throws -> Bool
        var sleep: (Int) async -> Void
    }

    private let vmModel: any WindowsOptimizationVMModeling
    private let dependencies: Dependencies
    private var preparedGuestToolsURL: URL?

    init(
        vmModel: any WindowsOptimizationVMModeling,
        dependencies: Dependencies
    ) {
        self.vmModel = vmModel
        self.dependencies = dependencies
    }

    func prepareMedia() async throws {
        preparedGuestToolsURL = try await dependencies.downloadGuestTools()
    }

    func restartWithPreparedMedia() async throws {
        guard let preparedGuestToolsURL else {
            throw AppWindowsOptimizationServiceError.mediaNotPrepared
        }

        if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
            try await dependencies.requestGracefulShutdown(30)
            await vmModel.refreshRuntimeEvidence()
            guard vmModel.snapshot?.state == .stopped else {
                throw AppWindowsOptimizationServiceError.gracefulShutdownIncomplete
            }
        }

        guard await vmModel.prepareWindowsOptimization(
            driverMediaPath: preparedGuestToolsURL.path
        ) else {
            throw AppWindowsOptimizationServiceError.mediaPreparationFailed(
                vmModel.errorMessage ?? "Check Windows settings and try again."
            )
        }

        await vmModel.start()
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            throw AppWindowsOptimizationServiceError.windowsStartFailed(
                vmModel.errorMessage ?? "Check Windows diagnostics and try again."
            )
        }
    }

    func waitForDesktop(timeoutSeconds: Int) async throws {
        let boundedTimeout = max(timeoutSeconds, 0)
        for elapsed in 0...boundedTimeout {
            await vmModel.refreshRuntimeEvidence()
            if vmModel.snapshot?.state == .running,
               let console = vmModel.snapshot?.latestConsoleLaunch,
               let screenshotPath = console.consoleScreenshotPath {
                let screenshotURL = URL(fileURLWithPath: screenshotPath)
                if let qmpSocketPath = console.qmpSocketPath,
                   FileManager.default.fileExists(atPath: qmpSocketPath) {
                    let qmpSocketURL = URL(fileURLWithPath: qmpSocketPath)
                    await Task.detached {
                        QEMUVMRuntimeBooter.captureConsoleScreenshot(
                            qmpSocketURL: qmpSocketURL,
                            imageURL: screenshotURL
                        )
                    }.value
                } else {
                    let monitorURL = URL(fileURLWithPath: console.monitorSocketPath)
                    if FileManager.default.fileExists(atPath: monitorURL.path) {
                        await Task.detached {
                            QEMUVMRuntimeBooter.captureConsoleScreenshot(
                                monitorSocketURL: monitorURL,
                                imageURL: screenshotURL
                            )
                        }.value
                    }
                }
                if QEMUConsoleScreenshotReadiness.isDesktopVisible(at: screenshotURL) {
                    return
                }
            }
            if elapsed < boundedTimeout {
                await dependencies.sleep(1)
            }
        }
        throw AppWindowsOptimizationServiceError.desktopTimedOut(seconds: boundedTimeout)
    }

    func dispatchOptimization() async throws {
        try await dependencies.dispatchOptimization()
    }

    func waitForAgent(timeoutSeconds: Int) async throws -> Bool {
        try await dependencies.waitForAgent(timeoutSeconds)
    }
}

extension AppWindowsOptimizationService.Dependencies {
    @MainActor
    static func live(
        runtimeBooter: AppRuntimeBooter,
        hostModel: HostDashboardModel,
        vmModel: VMRuntimeModel,
        agentEndpoint: String
    ) -> Self {
        Self(
            downloadGuestTools: {
                try await UTMGuestToolsDownloader.downloadIfNeeded()
            },
            requestGracefulShutdown: { timeoutSeconds in
                try await runtimeBooter.requestGracefulShutdown(
                    timeoutSeconds: timeoutSeconds
                )
            },
            dispatchOptimization: {
                _ = try await runtimeBooter.optimizeWindowsFromAttachedMedia()
            },
            waitForAgent: { timeoutSeconds in
                let report = await hostModel.waitForLiveAgentConnection(
                    endpoint: agentEndpoint,
                    timeoutSeconds: timeoutSeconds
                )
                if report.status == .connected,
                   let agentVersion = report.diagnostic.health?.agentVersion {
                    await vmModel.markGuestAgentConnected(agentVersion: agentVersion)
                }
                await hostModel.load()
                await vmModel.refreshRuntimeEvidence()
                return report.status == .connected
            },
            sleep: { seconds in
                try? await Task.sleep(for: .seconds(seconds))
            }
        )
    }
}
