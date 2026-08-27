import Foundation
import VeilHostCore

enum AppGuestAgentTransport: String, Equatable {
    case qemuLoopback
    case explicitWebSocket
    case unavailable
}

struct AppGuestAgentConnectionPlan: Equatable {
    static let environmentKey = "VEIL_AGENT_URL"
    static let qemuLoopbackEndpoint = "ws://127.0.0.1:18444"

    var transport: AppGuestAgentTransport
    var endpoint: String
    var endpointURL: URL?
    var detail: String
    var nextActions: [String]

    var isAvailable: Bool {
        endpointURL != nil && transport != .unavailable
    }

    static func resolve(
        provider: AppRuntimeProviderSelection,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        if let explicitEndpoint = environment[environmentKey], !explicitEndpoint.isEmpty {
            guard let url = webSocketURL(explicitEndpoint) else {
                return unavailable(
                    endpoint: explicitEndpoint,
                    detail: "VEIL_AGENT_URL must be a valid ws:// or wss:// endpoint with a host.",
                    nextActions: [
                        "Correct VEIL_AGENT_URL, then restart Veil.",
                        "Use \(qemuLoopbackEndpoint) for the standard QEMU/HVF guest-agent forward."
                    ]
                )
            }

            return AppGuestAgentConnectionPlan(
                transport: .explicitWebSocket,
                endpoint: explicitEndpoint,
                endpointURL: url,
                detail: "Using the explicitly configured Windows guest-agent endpoint.",
                nextActions: []
            )
        }

        switch provider {
        case .qemu:
            return AppGuestAgentConnectionPlan(
                transport: .qemuLoopback,
                endpoint: qemuLoopbackEndpoint,
                endpointURL: URL(string: qemuLoopbackEndpoint),
                detail: "QEMU forwards the Windows guest agent to a loopback-only macOS endpoint.",
                nextActions: []
            )
        case .appleVirtualization:
            return unavailable(
                endpoint: "unavailable://apple-virtualization/guest-agent",
                detail: "Apple Virtualization can show the Windows console, but Veil has not configured a routable guest-agent endpoint for app windows yet.",
                nextActions: [
                    "Use the Windows console for installation and recovery only.",
                    "Install the QEMU/HVF runtime to use Veil's proved loopback guest-agent path.",
                    "For development, set VEIL_AGENT_URL to a reachable ws:// or wss:// guest endpoint after configuring that transport yourself."
                ]
            )
        }
    }

    private static func unavailable(
        endpoint: String,
        detail: String,
        nextActions: [String]
    ) -> Self {
        AppGuestAgentConnectionPlan(
            transport: .unavailable,
            endpoint: endpoint,
            endpointURL: nil,
            detail: detail,
            nextActions: nextActions
        )
    }

    private static func webSocketURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

struct UnavailableGuestAgentService: HostDashboardService {
    let plan: AppGuestAgentConnectionPlan

    func loadOverview() async throws -> HostOverview { try failure() }
    func launchApp(appId: String) async throws -> WindowsAppLaunchResult { try failure() }
    func launchNotepad() async throws -> NotepadLaunchResult { try failure() }
    func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult { try failure() }
    func focusWindow(windowId: String) async throws -> WindowFocusResponse { try failure() }
    func closeWindow(windowId: String) async throws -> WindowCloseResponse { try failure() }
    func sendMouseInput(_ input: InputMouseEvent) async throws { try failure() }
    func sendKeyInput(_ input: InputKeyEvent) async throws { try failure() }
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws { try failure() }
    func subscribeWindowFrames(windowId: String) async throws { try failure() }
    func unsubscribeWindowFrames(windowId: String) async throws { try failure() }

    func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport {
        let diagnostic = diagnostic
        return AgentConnectionWaitReport(
            endpoint: plan.endpoint,
            status: .unavailable,
            waitedSeconds: 0,
            attempts: 0,
            diagnostic: diagnostic,
            nextActions: diagnostic.nextActions
        )
    }

    private var diagnostic: AgentConnectionDiagnostic {
        AgentConnectionDiagnostic(
            status: .unavailable,
            endpoint: plan.endpoint,
            errorMessage: plan.detail,
            nextActions: plan.nextActions
        )
    }

    private func failure() throws -> Never {
        throw HostDashboardServiceError.agentEndpointUnavailable(
            endpoint: plan.endpoint,
            detail: plan.detail,
            nextActions: plan.nextActions
        )
    }
}
