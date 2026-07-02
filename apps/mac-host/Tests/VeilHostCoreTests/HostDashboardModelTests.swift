import Foundation
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
        #expect(model.selectedAppId == "winapp_notepad")
        #expect(model.selectedApp?.name == "Notepad")
        #expect(model.canLaunchSelectedApp)
        #expect(model.statusText == "Connected to Windows agent 0.1.0")
        #expect(model.connectionMode == .agent)
        #expect(model.hasLiveAgentConnection)
        #expect(model.guestAgentInstallEvidence?.kind == .guestAgent)
        #expect(model.guestAgentInstallEvidence?.isInstalled == true)
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
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0003029A"])
        #expect(model.selectedAppId == "winapp_notepad")
        #expect(model.canLaunchSelectedApp)
        #expect(model.statusText == "Launched Untitled - Notepad")
    }

    @Test("updates active window sessions by HWND")
    @MainActor
    func updatesActiveWindowSessionsByHWND() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        await model.launchNotepad()

        #expect(model.activeWindows.count == 1)
        #expect(model.activeWindows.first?.windowId == "hwnd:0003029A")
        #expect(model.activeWindows.first?.title == "Untitled - Notepad")
        #expect(service.launchCount == 2)
    }

    @Test("stores service failures as user visible errors")
    @MainActor
    func storesServiceFailures() async throws {
        let service = FakeDashboardService(error: VeilHostError.notepadMissing)
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Notepad is not available from the Windows agent.")
        #expect(model.canLaunchSelectedApp == false)
    }

    @Test("does not launch when no app is selected")
    @MainActor
    func doesNotLaunchWithoutSelection() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.launchSelectedApp()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Select an app before launching.")
        #expect(service.launchCount == 0)
    }

    @Test("does not launch unsupported selected apps")
    @MainActor
    func doesNotLaunchUnsupportedSelectedApps() async throws {
        let service = FakeDashboardService(apps: [.calculator])
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.selectedAppId == "winapp_calculator")
        #expect(model.canLaunchSelectedApp == false)
        #expect(model.phase == .failed)
        #expect(model.errorMessage == "The current harness can only launch Notepad.")
        #expect(service.launchCount == 0)
    }

    @Test("loads demo overview when primary agent is unavailable")
    @MainActor
    func loadsDemoOverviewWhenPrimaryAgentIsUnavailable() async throws {
        let service = FallbackHostDashboardService(
            primary: FakeDashboardService(error: URLError(.cannotConnectToHost)),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .connected)
        #expect(model.errorMessage == nil)
        #expect(model.health?.agentVersion == "demo-0.1.0")
        #expect(model.connectionMode == .demo)
        #expect(model.hasLiveAgentConnection == false)
        #expect(model.guestAgentInstallEvidence == nil)
        #expect(model.statusText == "Demo mode: Windows agent unavailable")
        #expect(model.connectionDetail == "No Windows agent reachable at ws://127.0.0.1:18444. Showing built-in demo data.")
        #expect(model.apps.map(\.id).contains("winapp_notepad"))
        #expect(model.canLaunchSelectedApp)
    }

    @Test("launches demo Notepad when primary agent is unavailable")
    @MainActor
    func launchesDemoNotepadWhenPrimaryAgentIsUnavailable() async throws {
        let service = FallbackHostDashboardService(
            primary: FakeDashboardService(error: URLError(.cannotConnectToHost)),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.phase == .connected)
        #expect(model.errorMessage == nil)
        #expect(model.lastLaunch?.window.title == "Untitled - Notepad")
        #expect(model.connectionMode == .demo)
        #expect(model.connectionDetail == "No Windows agent reachable at ws://127.0.0.1:18444. Showing built-in demo data.")
        #expect(model.statusText == "Demo launched Untitled - Notepad")
    }

    @Test("does not hide primary agent protocol failures behind demo fallback")
    @MainActor
    func doesNotHidePrimaryAgentProtocolFailuresBehindDemoFallback() async throws {
        let service = FallbackHostDashboardService(
            primary: FakeDashboardService(error: VeilHostError.notepadMissing),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Notepad is not available from the Windows agent.")
        #expect(model.health == nil)
        #expect(model.apps.isEmpty)
    }
}

@MainActor
private final class FakeDashboardService: HostDashboardService {
    var error: (any Error)?
    var apps: [WindowsApp]
    private(set) var launchCount = 0

    init(error: (any Error)? = nil, apps: [WindowsApp] = [.notepad]) {
        self.error = error
        self.apps = apps
    }

    func loadOverview() async throws -> HostOverview {
        if let error {
            throw error
        }

        return HostOverview(
            health: .fixture,
            apps: apps
        )
    }

    func launchNotepad() async throws -> NotepadLaunchResult {
        if let error {
            throw error
        }

        launchCount += 1
        return NotepadLaunchResult(
            health: .fixture,
            apps: apps,
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

    static var calculator: WindowsApp {
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
