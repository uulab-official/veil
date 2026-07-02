import Foundation
import Testing

@testable import VeilHostCore

@Suite("Veil host client")
struct VeilHostClientTests {
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

        await #expect(throws: VeilHostError.notepadWindowMismatch) {
            _ = try await client.launchNotepad()
        }
    }
}

private final class RecordingTransport: HostTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var sentTypes: [String] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
        sentTypes.append(object?["type"] as? String ?? "")

        let replyStrings = Array(responses.prefix(expectedReplies))
        responses.removeFirst(expectedReplies)
        return replyStrings.map { Data($0.utf8) }
    }
}
