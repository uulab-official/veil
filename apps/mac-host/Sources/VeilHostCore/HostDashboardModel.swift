import Foundation
import Observation

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchNotepad() async throws -> NotepadLaunchResult
}

public struct HostOverview: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]

    public init(health: AgentHealthResponse, apps: [WindowsApp]) {
        self.health = health
        self.apps = apps
    }
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
                "Launched \(lastLaunch.window.title)"
            } else if let health {
                "Connected to Windows agent \(health.agentVersion)"
            } else {
                "Connected"
            }
        case .launching:
            "Launching Notepad"
        case .failed:
            errorMessage ?? "Connection failed"
        }
    }

    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            let overview = try await service.loadOverview()
            health = overview.health
            apps = overview.apps
            phase = .connected
        } catch {
            errorMessage = String(describing: error)
            phase = .failed
        }
    }

    public func launchNotepad() async {
        phase = .launching
        errorMessage = nil

        do {
            let result = try await service.launchNotepad()
            health = result.health
            apps = result.apps
            lastLaunch = result
            phase = .connected
        } catch {
            errorMessage = String(describing: error)
            phase = .failed
        }
    }
}
