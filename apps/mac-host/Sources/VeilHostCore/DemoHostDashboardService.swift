import Foundation

public struct FallbackHostDashboardService: HostDashboardService, Sendable {
    private let primary: any HostDashboardService
    private let fallback: any HostDashboardService
    private let primaryEndpointDescription: String

    public init(
        primary: any HostDashboardService,
        fallback: any HostDashboardService,
        primaryEndpointDescription: String = "configured Windows agent"
    ) {
        self.primary = primary
        self.fallback = fallback
        self.primaryEndpointDescription = primaryEndpointDescription
    }

    public func loadOverview() async throws -> HostOverview {
        do {
            return try await primary.loadOverview()
        } catch {
            guard shouldUseFallback(for: error) else {
                throw error
            }

            var overview = try await fallback.loadOverview()
            overview.connectionDetail = fallbackDetail
            return overview
        }
    }

    public func launchNotepad() async throws -> NotepadLaunchResult {
        do {
            return try await primary.launchNotepad()
        } catch {
            guard shouldUseFallback(for: error) else {
                throw error
            }

            var result = try await fallback.launchNotepad()
            result.connectionDetail = fallbackDetail
            return result
        }
    }

    public func closeWindow(windowId: String) async throws -> WindowCloseResponse {
        try await primary.closeWindow(windowId: windowId)
    }

    public func sendMouseInput(_ input: InputMouseEvent) async throws {
        try await primary.sendMouseInput(input)
    }

    public func sendKeyInput(_ input: InputKeyEvent) async throws {
        try await primary.sendKeyInput(input)
    }

    private var fallbackDetail: String {
        "No Windows agent reachable at \(primaryEndpointDescription). Showing built-in demo data."
    }

    private func shouldUseFallback(for error: any Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .cannotConnectToHost,
             .cannotFindHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut:
            return true
        default:
            return false
        }
    }
}

public struct DemoHostDashboardService: HostDashboardService, Sendable {
    public init() {}

    public func loadOverview() async throws -> HostOverview {
        HostOverview(
            health: .demo,
            apps: [.demoNotepad, .demoCalculator],
            connectionMode: .demo
        )
    }

    public func launchNotepad() async throws -> NotepadLaunchResult {
        NotepadLaunchResult(
            health: .demo,
            apps: [.demoNotepad, .demoCalculator],
            launch: .demoNotepad,
            window: .demoNotepad,
            connectionMode: .demo
        )
    }

    public func closeWindow(windowId: String) async throws -> WindowCloseResponse {
        WindowCloseResponse(
            type: .windowCloseResponse,
            requestId: "demo_close_window",
            windowId: windowId,
            accepted: true
        )
    }

    public func sendMouseInput(_ input: InputMouseEvent) async throws {}

    public func sendKeyInput(_ input: InputKeyEvent) async throws {}
}

private extension AgentHealthResponse {
    static var demo: AgentHealthResponse {
        AgentHealthResponse(
            type: .agentHealthResponse,
            requestId: "demo_health",
            protocolVersion: 1,
            agentVersion: "demo-0.1.0",
            os: "windows-arm64",
            session: AgentSession(interactive: true, user: "demo-user"),
            capabilities: AgentCapabilities(
                appList: true,
                appLaunch: true,
                windowTracking: true,
                windowCapture: false,
                input: false,
                clipboardText: false
            )
        )
    }
}

private extension WindowsApp {
    static var demoNotepad: WindowsApp {
        WindowsApp(
            id: "winapp_notepad",
            name: "Notepad",
            exePath: "C:\\Windows\\System32\\notepad.exe",
            publisher: "Microsoft",
            iconId: "icon_notepad"
        )
    }

    static var demoCalculator: WindowsApp {
        WindowsApp(
            id: "winapp_calculator",
            name: "Calculator",
            exePath: "C:\\Windows\\System32\\calc.exe",
            publisher: "Microsoft",
            iconId: "icon_calculator"
        )
    }
}

private extension AppLaunchResponse {
    static var demoNotepad: AppLaunchResponse {
        AppLaunchResponse(
            type: .appLaunchResponse,
            requestId: "demo_launch_notepad",
            accepted: true,
            processId: 4912
        )
    }
}

private extension WindowCreatedEvent {
    static var demoNotepad: WindowCreatedEvent {
        WindowCreatedEvent(
            type: .windowCreated,
            windowId: "hwnd:0003029A",
            processId: 4912,
            appId: "winapp_notepad",
            title: "Untitled - Notepad",
            bounds: WindowBounds(x: 10, y: 10, width: 1280, height: 800),
            state: "normal",
            focused: true
        )
    }
}
