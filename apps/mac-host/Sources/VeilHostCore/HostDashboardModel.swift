import Foundation
import Observation

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchNotepad() async throws -> NotepadLaunchResult
}

public struct HostOverview: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]
    public var connectionMode: HostConnectionMode

    public init(
        health: AgentHealthResponse,
        apps: [WindowsApp],
        connectionMode: HostConnectionMode = .agent
    ) {
        self.health = health
        self.apps = apps
        self.connectionMode = connectionMode
    }
}

public enum HostConnectionMode: String, Codable, Equatable, Sendable {
    case agent
    case demo
}

public enum HostDashboardPhase: Equatable, Sendable {
    case idle
    case loading
    case connected
    case launching
    case failed
}

@MainActor
@Observable
public final class HostDashboardModel {
    public private(set) var phase: HostDashboardPhase = .idle
    public private(set) var health: AgentHealthResponse?
    public private(set) var apps: [WindowsApp] = []
    public private(set) var lastLaunch: NotepadLaunchResult?
    public private(set) var errorMessage: String?
    public private(set) var connectionMode: HostConnectionMode = .agent
    public var selectedAppId: String?

    private let service: any HostDashboardService

    public init(service: any HostDashboardService) {
        self.service = service
    }

    public var statusText: String {
        switch phase {
        case .idle:
            "Ready to connect"
        case .loading:
            "Connecting to Windows agent"
        case .connected:
            if let lastLaunch {
                connectionMode == .demo
                    ? "Demo launched \(lastLaunch.window.title)"
                    : "Launched \(lastLaunch.window.title)"
            } else if let health {
                connectionMode == .demo
                    ? "Demo mode: Windows agent unavailable"
                    : "Connected to Windows agent \(health.agentVersion)"
            } else {
                "Connected"
            }
        case .launching:
            "Launching Notepad"
        case .failed:
            errorMessage ?? "Connection failed"
        }
    }

    public var selectedApp: WindowsApp? {
        guard let selectedAppId else {
            return nil
        }

        return apps.first { $0.id == selectedAppId }
    }

    public var canLaunchSelectedApp: Bool {
        selectedApp?.id == "winapp_notepad" && phase != .loading && phase != .launching
    }

    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            let overview = try await service.loadOverview()
            health = overview.health
            apps = overview.apps
            connectionMode = overview.connectionMode
            selectDefaultAppIfNeeded()
            phase = .connected
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func launchSelectedApp() async {
        guard selectedApp != nil else {
            errorMessage = "Select an app before launching."
            phase = .failed
            return
        }

        guard canLaunchSelectedApp else {
            errorMessage = userMessage(for: VeilHostError.unsupportedHarnessApp)
            phase = .failed
            return
        }

        await launchNotepad()
    }

    public func launchNotepad() async {
        phase = .launching
        errorMessage = nil

        do {
            let result = try await service.launchNotepad()
            health = result.health
            apps = result.apps
            connectionMode = result.connectionMode
            selectedAppId = result.window.appId
            lastLaunch = result
            phase = .connected
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    private func selectDefaultAppIfNeeded() {
        if let selectedAppId, apps.contains(where: { $0.id == selectedAppId }) {
            return
        }

        selectedAppId = apps.first?.id
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
