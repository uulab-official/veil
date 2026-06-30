import Testing

@testable import VeilHostCore

@Suite("Host dashboard model")
struct HostDashboardModelTests {
    @Test("loads agent overview into dashboard state")
    @MainActor
    func loadsAgentOverview() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .connected)
        #expect(model.health?.agentVersion == "0.1.0")
        #expect(model.apps.map(\.id) == ["winapp_notepad"])
        #expect(model.statusText == "Connected to Windows agent 0.1.0")
        #expect(model.errorMessage == nil)
    }

    @Test("stores Notepad launch result")
    @MainActor
    func storesNotepadLaunchResult() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()

        #expect(model.phase == .connected)
        #expect(model.lastLaunch?.launch.processId == 4912)
        #expect(model.lastLaunch?.window.windowId == "hwnd:0003029A")
        #expect(model.statusText == "Launched Untitled - Notepad")
    }

    @Test("stores service failures as user visible errors")
    @MainActor
    func storesServiceFailures() async throws {
        let service = FakeDashboardService(error: VeilHostError.notepadMissing)
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "notepadMissing")
    }
}

private struct FakeDashboardService: HostDashboardService {
    var error: (any Error)?

    func loadOverview() async throws -> HostOverview {
        if let error {
            throw error
        }

        return HostOverview(
            health: .fixture,
            apps: [.notepad]
        )
    }

    func launchNotepad() async throws -> NotepadLaunchResult {
        if let error {
            throw error
        }

        return NotepadLaunchResult(
            health: .fixture,
            apps: [.notepad],
            launch: .fixture,
            window: .notepad
        )
    }
}

private extension AgentHealthResponse {
    static var fixture: AgentHealthResponse {
        AgentHealthResponse(
            type: .agentHealthResponse,
            requestId: "req_health",
            protocolVersion: 1,
            agentVersion: "0.1.0",
            os: "windows-arm64",
            session: AgentSession(interactive: true, user: "veil-user"),
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
    static var notepad: WindowsApp {
        WindowsApp(
            id: "winapp_notepad",
            name: "Notepad",
            exePath: "C:\\Windows\\System32\\notepad.exe",
            publisher: "Microsoft",
            iconId: "icon_notepad"
        )
    }
}

private extension AppLaunchResponse {
    static var fixture: AppLaunchResponse {
        AppLaunchResponse(
            type: .appLaunchResponse,
            requestId: "req_launch_notepad",
            accepted: true,
            processId: 4912
        )
    }
}

private extension WindowCreatedEvent {
    static var notepad: WindowCreatedEvent {
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
