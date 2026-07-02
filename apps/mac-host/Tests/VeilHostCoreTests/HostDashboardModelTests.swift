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
        #expect(service.frameSubscriptions == ["hwnd:0003029A"])
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

    @Test("consumes guest clipboard text from an event source once")
    @MainActor
    func consumesGuestClipboardTextFromEventSourceOnce() async throws {
        let service = FakeDashboardService(health: .clipboardReady)
        let model = HostDashboardModel(service: service)
        let source = StaticHostEventSource(messages: [
            Data(ClipboardTextSet.guestEventJSON.utf8),
            Data(ClipboardTextSet.guestEventJSON.utf8)
        ])
        var handledResults: [HostProtocolMessageResult] = []

        await model.load()
        await model.consumeProtocolMessages(from: source) { result in
            handledResults.append(result)
        }

        #expect(model.latestGuestClipboardText == "hello from Windows")
        #expect(model.lastGuestClipboardSequence == 43)
        #expect(handledResults == [
            .handledClipboardText(sequence: 43),
            .ignored
        ])
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

    @Test("closes mirrored Windows windows through the agent")
    @MainActor
    func closesMirroredWindowsThroughAgent() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        let response = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(response?.accepted == true)
        #expect(service.closedWindowIds == ["hwnd:0003029A"])
        #expect(model.activeWindows.isEmpty)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.lastLaunch == nil)
        #expect(model.phase == .connected)
        #expect(service.frameUnsubscriptions == ["hwnd:0003029A"])
    }

    @Test("keeps mirrored window state when the agent rejects close")
    @MainActor
    func keepsMirroredWindowWhenAgentRejectsClose() async throws {
        let service = FakeDashboardService(health: .captureReady, closeAccepted: false)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        let response = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(response?.accepted == false)
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(model.lastLaunch?.window.windowId == "hwnd:0003029A")
    }

    @Test("forwards mouse input for mirrored windows")
    @MainActor
    func forwardsMouseInputForMirroredWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        await model.sendMouseInput(windowId: "hwnd:0003029A", event: "leftDown", x: 240, y: 130)

        #expect(service.mouseInputs == [
            InputMouseEvent(windowId: "hwnd:0003029A", event: "leftDown", x: 240, y: 130)
        ])
        #expect(model.phase == .connected)
    }

    @Test("ignores mouse input for windows without a mirror session")
    @MainActor
    func ignoresMouseInputForUnknownWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.sendMouseInput(windowId: "hwnd:DEADBEEF", event: "leftDown", x: 20, y: 20)

        #expect(service.mouseInputs.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("forwards key input for mirrored windows")
    @MainActor
    func forwardsKeyInputForMirroredWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        await model.sendKeyInput(
            windowId: "hwnd:0003029A",
            event: "keyDown",
            key: "c",
            windowsVirtualKey: 67,
            modifiers: ["ctrl"]
        )

        #expect(service.keyInputs == [
            InputKeyEvent(
                windowId: "hwnd:0003029A",
                event: "keyDown",
                key: "c",
                windowsVirtualKey: 67,
                modifiers: ["ctrl"]
            )
        ])
        #expect(model.phase == .connected)
    }

    @Test("ignores key input for windows without a mirror session")
    @MainActor
    func ignoresKeyInputForUnknownWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.sendKeyInput(windowId: "hwnd:DEADBEEF", event: "keyDown", key: "c", windowsVirtualKey: 67)

        #expect(service.keyInputs.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("sends host clipboard text with increasing sequence")
    @MainActor
    func sendsHostClipboardTextWithIncreasingSequence() async throws {
        let service = FakeDashboardService(health: .clipboardReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.sendHostClipboardText("hello")
        await model.sendHostClipboardText("world")

        #expect(service.clipboardTexts.map(\.text) == ["hello", "world"])
        #expect(service.clipboardTexts.map(\.origin) == ["host", "host"])
        #expect(service.clipboardTexts.map(\.sequence) == [1, 2])
        #expect(model.clipboardSequence == 2)
        #expect(model.phase == .connected)
    }

    @Test("does not send host clipboard text without live clipboard support")
    @MainActor
    func doesNotSendClipboardTextWithoutLiveClipboardSupport() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.sendHostClipboardText("hello")

        #expect(service.clipboardTexts.isEmpty)
        #expect(model.clipboardSequence == 0)
        #expect(model.phase == .connected)
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
        _ = await model.refreshLiveAgentIfNeeded()

        #expect(model.phase == .connected)
        #expect(model.connectionMode == .agent)
        #expect(model.health?.agentVersion == "0.1.0")
        #expect(model.hasLiveAgentConnection)
        #expect(model.connectionDetail == nil)
        #expect(primary.loadCount == 2)
    }

    @Test("queues Notepad launch until live agent connects")
    @MainActor
    func queuesNotepadLaunchUntilLiveAgentConnects() async throws {
        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.phase == .connected)
        #expect(model.errorMessage == nil)
        #expect(model.lastLaunch == nil)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.pendingLaunchAppId == "winapp_notepad")
        #expect(model.connectionMode == .demo)
        #expect(model.connectionDetail == "No Windows agent reachable at ws://127.0.0.1:18444. Showing built-in demo data.")

        primary.error = nil
        let fulfilledLaunch = await model.refreshLiveAgentIfNeeded()

        #expect(model.connectionMode == .agent)
        #expect(model.pendingLaunchAppId == nil)
        #expect(model.lastLaunch?.window.title == "Untitled - Notepad")
        #expect(fulfilledLaunch?.window.title == "Untitled - Notepad")
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(primary.launchCount == 1)
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

    @Test("does not hide close failures behind demo fallback")
    @MainActor
    func doesNotHideCloseFailuresBehindDemoFallback() async throws {
        let primary = FakeDashboardService(health: .captureReady)
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        primary.error = URLError(.cannotConnectToHost)
        let response = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(response == nil)
        #expect(model.phase == .failed)
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
    }
}

@MainActor
private final class FakeDashboardService: HostDashboardService {
    var error: (any Error)?
    var health: AgentHealthResponse
    var apps: [WindowsApp]
    var closeAccepted: Bool
    private(set) var loadCount = 0
    private(set) var launchCount = 0
    private(set) var closedWindowIds: [String] = []
    private(set) var mouseInputs: [InputMouseEvent] = []
    private(set) var keyInputs: [InputKeyEvent] = []
    private(set) var clipboardTexts: [ClipboardTextSet] = []
    private(set) var frameSubscriptions: [String] = []
    private(set) var frameUnsubscriptions: [String] = []

    init(
        error: (any Error)? = nil,
        health: AgentHealthResponse = .fixture,
        apps: [WindowsApp] = [.notepad],
        closeAccepted: Bool = true
    ) {
        self.error = error
        self.health = health
        self.apps = apps
        self.closeAccepted = closeAccepted
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

    func closeWindow(windowId: String) async throws -> WindowCloseResponse {
        if let error {
            throw error
        }

        closedWindowIds.append(windowId)
        return WindowCloseResponse(
            type: .windowCloseResponse,
            requestId: "req_close_notepad",
            windowId: windowId,
            accepted: closeAccepted
        )
    }

    func sendMouseInput(_ input: InputMouseEvent) async throws {
        if let error {
            throw error
        }

        mouseInputs.append(input)
    }

    func sendKeyInput(_ input: InputKeyEvent) async throws {
        if let error {
            throw error
        }

        keyInputs.append(input)
    }

    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws {
        if let error {
            throw error
        }

        clipboardTexts.append(clipboard)
    }

    func subscribeWindowFrames(windowId: String) async throws {
        if let error {
            throw error
        }

        frameSubscriptions.append(windowId)
    }

    func unsubscribeWindowFrames(windowId: String) async throws {
        if let error {
            throw error
        }

        frameUnsubscriptions.append(windowId)
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

    static var inputReady: AgentHealthResponse {
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
                input: true,
                clipboardText: false
            )
        )
    }

    static var clipboardReady: AgentHealthResponse {
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
                input: true,
                clipboardText: true
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

private extension ClipboardTextSet {
    static var guestEventJSON: String {
        #"{"type":"clipboard.text.set","requestId":"evt_clipboard_43","origin":"guest","sequence":43,"text":"hello from Windows"}"#
    }
}
