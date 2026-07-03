import Foundation
import Testing

@testable import VeilHostCore

@Suite("Veil host client")
struct VeilHostClientTests {
    @Test("loads agent health without launching an app")
    func loadsAgentHealthOnly() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#
        ])
        let client = VeilHostClient(transport: transport)

        let health = try await client.loadHealth()

        #expect(transport.sentTypes == ["agent.health.request"])
        #expect(transport.expectedReplyCounts == [1])
        #expect(health.agentVersion == "0.1.0")
        #expect(health.os == "windows-arm64")
    }

    @Test("diagnoses connected Windows agent")
    func diagnosesConnectedAgent() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#
        ])
        let client = VeilHostClient(transport: transport)

        let diagnostic = await client.diagnoseAgentConnection(endpoint: "ws://127.0.0.1:18444")

        #expect(diagnostic.status == .connected)
        #expect(diagnostic.endpoint == "ws://127.0.0.1:18444")
        #expect(diagnostic.health?.agentVersion == "0.1.0")
        #expect(diagnostic.errorMessage == nil)
        #expect(diagnostic.nextActions.contains("Run veil-host-probe --launch-notepad-frame to verify HWND launch, tracking, and first frame capture."))
        #expect(transport.sentTypes == ["agent.health.request"])
    }

    @Test("diagnoses unavailable Windows agent with recovery actions")
    func diagnosesUnavailableAgentWithRecoveryActions() async throws {
        let transport = FailingTransport(error: DiagnosticTransportError.connectionRefused)
        let client = VeilHostClient(transport: transport)

        let diagnostic = await client.diagnoseAgentConnection(endpoint: "ws://127.0.0.1:18444")

        #expect(diagnostic.status == .unavailable)
        #expect(diagnostic.endpoint == "ws://127.0.0.1:18444")
        #expect(diagnostic.health == nil)
        #expect(diagnostic.errorMessage == "Connection refused.")
        #expect(diagnostic.nextActions.contains("Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd."))
        #expect(diagnostic.nextActions.contains("If the agent still does not connect, run Veil Shared\\Veil Guest Agent\\Collect Veil Agent Diagnostics.cmd and inspect the desktop ZIP."))
    }

    @Test("diagnoses stalled Windows agent with bounded timeout")
    func diagnosesStalledAgentWithBoundedTimeout() async throws {
        let client = VeilHostClient(transport: HangingTransport())

        let diagnostic = await client.diagnoseAgentConnection(
            endpoint: "ws://127.0.0.1:18444",
            timeoutNanoseconds: 1_000_000
        )

        #expect(diagnostic.status == .unavailable)
        #expect(diagnostic.errorMessage == "Timed out waiting for Windows agent health.")
        #expect(diagnostic.nextActions.contains("Confirm the Windows 11 Arm VM is running and has reached the desktop."))
    }

    @Test("runs the Notepad launch flow in protocol order")
    func runsNotepadLaunchFlow() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let result = try await client.launchNotepad()

        #expect(transport.sentTypes == [
            "agent.health.request",
            "app.list.request",
            "app.launch.request"
        ])
        #expect(result.health.agentVersion == "0.1.0")
        #expect(result.apps.map(\.id) == ["winapp_notepad"])
        #expect(result.launch.processId == 4912)
        #expect(result.window.windowId == "hwnd:0003029A")
    }

    @Test("launches a selected Windows app id")
    func launchesSelectedWindowsAppId() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_calculator","name":"Calculator","exePath":"calc.exe","publisher":"Microsoft","iconId":"icon_calculator"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_winapp_calculator","accepted":true,"processId":5010}"#,
            #"{"type":"window.created","windowId":"hwnd:0003030B","processId":5010,"appId":"winapp_calculator","title":"Calculator","bounds":{"x":10,"y":10,"width":520,"height":720},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let result = try await client.launchApp(appId: "winapp_calculator")

        #expect(transport.sentAppIds == ["winapp_calculator"])
        #expect(result.window.appId == "winapp_calculator")
        #expect(result.window.title == "Calculator")
    }

    @Test("fails when Notepad is missing from the app list")
    func failsWhenNotepadIsMissing() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[]}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.self) {
            _ = try await client.launchNotepad()
        }
    }

    @Test("rejects Notepad launch when the HWND event does not match the launched process")
    func rejectsMismatchedNotepadWindowEvent() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":9001,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.appWindowMismatch("winapp_notepad")) {
            _ = try await client.launchNotepad()
        }
    }

    @Test("sends a window close request to the agent")
    func sendsWindowCloseRequest() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"window.close.response","requestId":"req_close_notepad","windowId":"hwnd:0003029A","accepted":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let response = try await client.closeWindow(windowId: "hwnd:0003029A")

        #expect(transport.sentTypes == ["window.close.request"])
        #expect(response.type == .windowCloseResponse)
        #expect(response.requestId == "req_close_notepad")
        #expect(response.windowId == "hwnd:0003029A")
        #expect(response.accepted)
    }

    @Test("sends mouse input without waiting for a reply")
    func sendsMouseInputWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.sendMouseInput(
            InputMouseEvent(windowId: "hwnd:0003029A", event: "leftDown", x: 240, y: 130)
        )

        #expect(transport.sentTypes == ["input.mouse"])
        #expect(transport.expectedReplyCounts == [0])
    }

    @Test("sends key input without waiting for a reply")
    func sendsKeyInputWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.sendKeyInput(
            InputKeyEvent(
                windowId: "hwnd:0003029A",
                event: "keyDown",
                key: "c",
                windowsVirtualKey: 67,
                modifiers: ["ctrl"]
            )
        )

        #expect(transport.sentTypes == ["input.key"])
        #expect(transport.expectedReplyCounts == [0])
    }

    @Test("sends host clipboard text without waiting for a reply")
    func sendsHostClipboardTextWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.sendClipboardText(
            ClipboardTextSet(requestId: "req_clipboard_1", origin: "host", sequence: 1, text: "hello from macOS")
        )

        #expect(transport.sentTypes == ["clipboard.text.set"])
        #expect(transport.expectedReplyCounts == [0])
    }

    @Test("sends frame stream subscribe and unsubscribe without waiting for replies")
    func sendsFrameStreamControlWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.subscribeWindowFrames(windowId: "hwnd:0003029A")
        try await client.unsubscribeWindowFrames(windowId: "hwnd:0003029A")

        #expect(transport.sentTypes == [
            "window.frame.subscribe",
            "window.frame.unsubscribe"
        ])
        #expect(transport.expectedReplyCounts == [0, 0])
    }
}

private final class RecordingTransport: HostTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var sentTypes: [String] = []
    private(set) var sentAppIds: [String] = []
    private(set) var expectedReplyCounts: [Int] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
        sentTypes.append(object?["type"] as? String ?? "")
        if let appId = object?["appId"] as? String {
            sentAppIds.append(appId)
        }
        expectedReplyCounts.append(expectedReplies)

        let replyStrings = Array(responses.prefix(expectedReplies))
        responses.removeFirst(expectedReplies)
        return replyStrings.map { Data($0.utf8) }
    }
}

private enum DiagnosticTransportError: Error, LocalizedError {
    case connectionRefused

    var errorDescription: String? {
        switch self {
        case .connectionRefused:
            "Connection refused."
        }
    }
}

private struct FailingTransport: HostTransport {
    var error: any Error

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        throw error
    }
}

private struct HangingTransport: HostTransport {
    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return []
    }
}
