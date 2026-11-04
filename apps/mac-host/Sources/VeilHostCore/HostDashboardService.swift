import CoreGraphics
import Foundation
import Observation

public enum HostDashboardServiceError: Error, LocalizedError, Equatable, Sendable {
    case textInputUnsupported
    case agentEndpointUnavailable(endpoint: String, detail: String, nextActions: [String])

    public var errorDescription: String? {
        switch self {
        case .textInputUnsupported:
            "This Windows agent connection cannot accept committed text input."
        case .agentEndpointUnavailable(_, let detail, _):
            detail
        }
    }
}

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchApp(appId: String) async throws -> WindowsAppLaunchResult
    func restoreApp(appId: String) async throws -> WindowsAppLaunchResult
    func launchNotepad() async throws -> NotepadLaunchResult
    func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult
    func focusWindow(windowId: String) async throws -> WindowFocusResponse
    func closeWindow(windowId: String) async throws -> WindowCloseResponse
    func resizeWindow(windowId: String, width: Int, height: Int) async throws -> WindowResizeResponse
    func sendMouseInput(_ input: InputMouseEvent) async throws
    func sendKeyInput(_ input: InputKeyEvent) async throws
    func sendTextInput(_ input: InputTextEvent) async throws
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws
    func subscribeWindowFrames(windowId: String) async throws
    func unsubscribeWindowFrames(windowId: String) async throws
    func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport
}

public struct HostOverview: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]
    public var connectionMode: HostConnectionMode
    public var connectionDetail: String?
    public var agentDiagnostic: AgentConnectionDiagnostic?

    public init(
        health: AgentHealthResponse,
        apps: [WindowsApp],
        connectionMode: HostConnectionMode = .agent,
        connectionDetail: String? = nil,
        agentDiagnostic: AgentConnectionDiagnostic? = nil
    ) {
        self.health = health
        self.apps = apps
        self.connectionMode = connectionMode
        self.connectionDetail = connectionDetail
        self.agentDiagnostic = agentDiagnostic
    }
}

public enum HostConnectionMode: String, Codable, Equatable, Sendable {
    case agent
    case demo
}
