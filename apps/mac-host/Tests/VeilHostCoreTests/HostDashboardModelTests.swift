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
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.first?.captureState == .unavailable)
        #expect(model.selectedAppId == "winapp_notepad")
        #expect(model.canLaunchSelectedApp)
        #expect(model.statusText == "Launched Untitled - Notepad")
    }

    @Test("stores a pending capture mirror session when the live agent supports capture")
    @MainActor
    func storesPendingCaptureMirrorSessionWhenAgentSupportsCapture() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()

        let session = try #require(model.mirrorSessions.first)
        #expect(session.id == "hwnd:0003029A")
        #expect(session.window.title == "Untitled - Notepad")
        #expect(session.connectionMode == .agent)
        #expect(session.captureState == .pending)
    }

    @Test("stores the latest frame on the matching mirror session")
    @MainActor
    func storesLatestFrameOnMatchingMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame)

        let session = try #require(model.mirrorSessions.first)
        #expect(session.captureState == .streaming)
        #expect(session.latestFrame?.windowId == "hwnd:0003029A")
        #expect(session.latestFrame?.frameId == "frame_000001")
        #expect(session.latestFrame?.sequence == 1)
        #expect(session.latestFrame?.format == "png")
        #expect(session.latestFrame?.encodedData.hasPrefix("iVBOR") == true)
    }

    @Test("routes a protocol frame message into the matching mirror session")
    @MainActor
    func routesProtocolFrameMessageIntoMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let message = Data(WindowFrameEvent.notepadFirstFrameJSON.utf8)

        await model.launchNotepad()
        let result = try model.receiveProtocolMessage(message)

        let session = try #require(model.mirrorSessions.first)
        #expect(result == .handledWindowFrame(windowId: "hwnd:0003029A"))
        #expect(session.captureState == .streaming)
        #expect(session.latestFrame?.frameId == "frame_000001")
    }

    @Test("consumes protocol frames from an event source")
    @MainActor
    func consumesProtocolFramesFromEventSource() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let source = StaticHostEventSource(messages: [
            Data(WindowFrameEvent.notepadFirstFrameJSON.utf8)
        ])
        var handledResults: [HostProtocolMessageResult] = []

        await model.launchNotepad()
        await model.consumeProtocolMessages(from: source) { result in
            handledResults.append(result)
        }

        let session = try #require(model.mirrorSessions.first)
        #expect(handledResults == [.handledWindowFrame(windowId: "hwnd:0003029A")])
        #expect(session.captureState == .streaming)
        #expect(session.latestFrame?.frameId == "frame_000001")
    }

    @Test("ignores frames for windows without a mirror session")
    @MainActor
    func ignoresFramesWithoutMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.orphanFrame)

        let session = try #require(model.mirrorSessions.first)
        #expect(session.captureState == .pending)
        #expect(session.latestFrame == nil)
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
        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let service = FallbackHostDashboardService(
            primary: primary,
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
        #expect(model.canLaunchSelectedApp == false)
    }

    @Test("refresh live agent retries after demo fallback")
    @MainActor
    func refreshLiveAgentRetriesAfterDemoFallback() async throws {
        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        primary.error = nil
        await model.refreshLiveAgentIfNeeded()

        #expect(model.phase == .connected)
        #expect(model.connectionMode == .agent)
        #expect(model.health?.agentVersion == "0.1.0")
        #expect(model.hasLiveAgentConnection)
        #expect(model.connectionDetail == nil)
        #expect(primary.loadCount == 2)
    }

    @Test("does not launch demo Notepad as a Mac window when primary agent is unavailable")
    @MainActor
    func doesNotLaunchDemoNotepadAsMacWindowWhenPrimaryAgentIsUnavailable() async throws {
        let service = FallbackHostDashboardService(
            primary: FakeDashboardService(error: URLError(.cannotConnectToHost)),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Connect the Windows guest agent before opening a Mac window.")
        #expect(model.lastLaunch == nil)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.connectionMode == .demo)
        #expect(model.connectionDetail == "No Windows agent reachable at ws://127.0.0.1:18444. Showing built-in demo data.")
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
    var health: AgentHealthResponse
    var apps: [WindowsApp]
    private(set) var loadCount = 0
    private(set) var launchCount = 0

    init(error: (any Error)? = nil, health: AgentHealthResponse = .fixture, apps: [WindowsApp] = [.notepad]) {
        self.error = error
        self.health = health
        self.apps = apps
    }

    func loadOverview() async throws -> HostOverview {
        loadCount += 1
        if let error {
            throw error
        }

        return HostOverview(
            health: health,
            apps: apps
        )
    }

    func launchNotepad() async throws -> NotepadLaunchResult {
        if let error {
            throw error
        }

        launchCount += 1
        return NotepadLaunchResult(
            health: health,
            apps: apps,
            launch: .fixture,
            window: .notepad
        )
    }
}

private struct StaticHostEventSource: HostEventSource {
    var messages: [Data]

    func eventMessages() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            for message in messages {
                continuation.yield(message)
            }
            continuation.finish()
        }
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

    static var captureReady: AgentHealthResponse {
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
                windowCapture: true,
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

private extension WindowFrameEvent {
    static var notepadFirstFrameJSON: String {
        #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_000001","sequence":1,"format":"png","width":1,"height":1,"scale":1,"encodedData":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="}"#
    }

    static var notepadFirstFrame: WindowFrameEvent {
        WindowFrameEvent(
            type: .windowFrame,
            windowId: "hwnd:0003029A",
            frameId: "frame_000001",
            sequence: 1,
            format: "png",
            width: 1,
            height: 1,
            scale: 1,
            encodedData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        )
    }

    static var orphanFrame: WindowFrameEvent {
        WindowFrameEvent(
            type: .windowFrame,
            windowId: "hwnd:DEADBEEF",
            frameId: "frame_orphan",
            sequence: 1,
            format: "png",
            width: 1,
            height: 1,
            scale: 1,
            encodedData: "iVBORw0KGgo="
        )
    }
}
