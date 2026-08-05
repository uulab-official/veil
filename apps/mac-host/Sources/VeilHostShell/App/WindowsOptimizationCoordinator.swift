import Foundation
import Observation

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
