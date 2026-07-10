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
            overview.agentDiagnostic = AgentConnectionDiagnostic.unavailable(
                endpoint: primaryEndpointDescription,
                errorMessage: errorMessage(for: error)
            )
            return overview
        }
    }

    public func launchApp(appId: String) async throws -> WindowsAppLaunchResult {
        try await primary.launchApp(appId: appId)
    }

    public func restoreApp(appId: String) async throws -> WindowsAppLaunchResult {
        try await primary.restoreApp(appId: appId)
    }

    public func launchNotepad() async throws -> NotepadLaunchResult {
        try await launchApp(appId: "winapp_notepad")
    }

    public func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult {
        try await primary.openFile(appId: appId, fileName: fileName, contentBase64: contentBase64)
    }

    public func focusWindow(windowId: String) async throws -> WindowFocusResponse {
        try await primary.focusWindow(windowId: windowId)
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

    public func sendClipboardText(_ clipboard: ClipboardTextSet) async throws {
        try await primary.sendClipboardText(clipboard)
    }

    public func subscribeWindowFrames(windowId: String) async throws {
        try await primary.subscribeWindowFrames(windowId: windowId)
    }

    public func unsubscribeWindowFrames(windowId: String) async throws {
        try await primary.unsubscribeWindowFrames(windowId: windowId)
    }

    public func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport {
        await primary.waitForAgentConnection(endpoint: endpoint, timeoutSeconds: timeoutSeconds)
    }

    private var fallbackDetail: String {
        "No Windows agent reachable at \(primaryEndpointDescription). Showing built-in demo data."
    }

    private func errorMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
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

    public func launchApp(appId: String) async throws -> WindowsAppLaunchResult {
        let app = try Self.demoApp(for: appId)
        return WindowsAppLaunchResult(
            health: .demo,
            apps: Self.demoApps,
            launch: .demo(app: app),
            window: .demo(app: app),
            connectionMode: .demo
        )
    }

    public func launchNotepad() async throws -> NotepadLaunchResult {
        try await launchApp(appId: "winapp_notepad")
    }

    public func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult {
        let app = try Self.demoApp(for: appId)
        return WindowsAppLaunchResult(
            health: .demo,
            apps: Self.demoApps,
            launch: .demo(app: app),
            window: .demo(app: app),
            connectionMode: .demo
        )
    }

    public func focusWindow(windowId: String) async throws -> WindowFocusResponse {
        WindowFocusResponse(
            type: .windowFocusResponse,
            requestId: "demo_focus_window",
            windowId: windowId,
            accepted: true
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

    public func sendClipboardText(_ clipboard: ClipboardTextSet) async throws {}

    public func subscribeWindowFrames(windowId: String) async throws {}

    public func unsubscribeWindowFrames(windowId: String) async throws {}

    public func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport {
        let diagnostic = AgentConnectionDiagnostic.unavailable(
            endpoint: endpoint,
            errorMessage: "Demo mode cannot prove a live Windows guest agent connection."
        )
        return AgentConnectionWaitReport(
            endpoint: endpoint,
            status: .unavailable,
            waitedSeconds: min(max(timeoutSeconds, 0), 300),
            attempts: 1,
            diagnostic: diagnostic,
            nextActions: diagnostic.nextActions
        )
    }

    private static var demoApps: [WindowsApp] {
        [.demoNotepad, .demoCalculator, .demoPaint]
    }

    private static func demoApp(for appId: String) throws -> WindowsApp {
        guard let app = demoApps.first(where: { $0.id == appId }) else {
            throw VeilHostError.appMissing(appId)
        }

        return app
    }
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

    static var demoPaint: WindowsApp {
        WindowsApp(
            id: "winapp_paint",
            name: "Paint",
            exePath: "C:\\Windows\\System32\\mspaint.exe",
            publisher: "Microsoft",
            iconId: "icon_paint"
        )
    }
}

private extension AppLaunchResponse {
    static func demo(app: WindowsApp) -> AppLaunchResponse {
        AppLaunchResponse(
            type: .appLaunchResponse,
            requestId: "demo_launch_\(app.id)",
            accepted: true,
            processId: Self.demoProcessId(for: app.id)
        )
    }

    private static func demoProcessId(for appId: String) -> Int {
        switch appId {
        case "winapp_calculator":
            return 5010
        case "winapp_paint":
            return 5020
        default:
            return 4912
        }
    }
}

private extension WindowCreatedEvent {
    static func demo(app: WindowsApp) -> WindowCreatedEvent {
        WindowCreatedEvent(
            type: .windowCreated,
            windowId: demoWindowId(for: app.id),
            processId: AppLaunchResponse.demo(app: app).processId,
            appId: app.id,
            title: demoTitle(for: app),
            bounds: WindowBounds(x: 10, y: 10, width: app.id == "winapp_calculator" ? 520 : 1280, height: app.id == "winapp_calculator" ? 720 : 800),
            state: "normal",
            focused: true
        )
    }

    private static func demoWindowId(for appId: String) -> String {
        switch appId {
        case "winapp_calculator":
            return "hwnd:0003030B"
        case "winapp_paint":
            return "hwnd:0003040C"
        default:
            return "hwnd:0003029A"
        }
    }

    private static func demoTitle(for app: WindowsApp) -> String {
        switch app.id {
        case "winapp_notepad":
            return "Untitled - Notepad"
        default:
            return app.name
        }
    }
}
