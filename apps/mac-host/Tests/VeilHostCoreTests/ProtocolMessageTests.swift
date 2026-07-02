import Foundation
import Testing

@testable import VeilHostCore

@Suite("Protocol messages")
struct ProtocolMessageTests {
    @Test("decodes agent health response")
    func decodesAgentHealthResponse() throws {
        let response: AgentHealthResponse = try decodeFixture("agent.health.response")

        #expect(response.type == .agentHealthResponse)
        #expect(response.requestId == "req_001")
        #expect(response.agentVersion == "0.1.0")
        #expect(response.session.interactive)
        #expect(response.capabilities.appLaunch)
        #expect(response.capabilities.windowCapture == false)
    }

    @Test("decodes app list response")
    func decodesAppListResponse() throws {
        let response: AppListResponse = try decodeFixture("app.list.response")

        #expect(response.type == .appListResponse)
        #expect(response.apps.count == 1)
        #expect(response.apps[0].id == "winapp_notepad")
        #expect(response.apps[0].name == "Notepad")
    }

    @Test("decodes window created event")
    func decodesWindowCreatedEvent() throws {
        let event: WindowCreatedEvent = try decodeFixture("window.created")

        #expect(event.type == .windowCreated)
        #expect(event.windowId == "hwnd:0003029A")
        #expect(event.bounds.width == 1280)
        #expect(event.focused)
    }

    @Test("decodes window frame event")
    func decodesWindowFrameEvent() throws {
        let event: WindowFrameEvent = try decodeFixture("window.frame")

        #expect(event.type == .windowFrame)
        #expect(event.windowId == "hwnd:0003029A")
        #expect(event.frameId == "frame_000001")
        #expect(event.format == "png")
        #expect(event.width == 1)
        #expect(event.height == 1)
        #expect(event.encodedData.hasPrefix("iVBOR"))
    }

    @Test("decodes window frame payload data")
    func decodesWindowFramePayloadData() throws {
        let event: WindowFrameEvent = try decodeFixture("window.frame")

        let payload = try #require(event.encodedPayloadData)
        #expect(payload.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("decodes window frame stream requests")
    func decodesWindowFrameStreamRequests() throws {
        let subscribe: WindowFrameSubscribeRequest = try decodeFixture("window.frame.subscribe")
        let unsubscribe: WindowFrameUnsubscribeRequest = try decodeFixture("window.frame.unsubscribe")

        #expect(subscribe.type == .windowFrameSubscribe)
        #expect(subscribe.requestId == "req_frame_subscribe_notepad")
        #expect(subscribe.windowId == "hwnd:0003029A")
        #expect(subscribe.format == "png")
        #expect(unsubscribe.type == .windowFrameUnsubscribe)
        #expect(unsubscribe.requestId == "req_frame_unsubscribe_notepad")
        #expect(unsubscribe.windowId == "hwnd:0003029A")
    }

    @Test("decodes window close request and response")
    func decodesWindowCloseRequestAndResponse() throws {
        let request: WindowCloseRequest = try decodeFixture("window.close.request")
        let response: WindowCloseResponse = try decodeFixture("window.close.response")

        #expect(request.type == .windowCloseRequest)
        #expect(request.requestId == "req_close_001")
        #expect(request.windowId == "hwnd:0003029A")
        #expect(response.type == .windowCloseResponse)
        #expect(response.requestId == request.requestId)
        #expect(response.windowId == request.windowId)
        #expect(response.accepted)
    }

    @Test("decodes mouse input event")
    func decodesMouseInputEvent() throws {
        let input: InputMouseEvent = try decodeFixture("input.mouse.left-down")

        #expect(input.type == .inputMouse)
        #expect(input.windowId == "hwnd:0003029A")
        #expect(input.event == "leftDown")
        #expect(input.x == 240)
        #expect(input.y == 130)
        #expect(input.modifiers == [])
    }

    @Test("decodes key input event")
    func decodesKeyInputEvent() throws {
        let input: InputKeyEvent = try decodeFixture("input.key.copy")

        #expect(input.type == .inputKey)
        #expect(input.windowId == "hwnd:0003029A")
        #expect(input.event == "keyDown")
        #expect(input.key == "c")
        #expect(input.windowsVirtualKey == 67)
        #expect(input.modifiers == ["ctrl"])
    }

    @Test("decodes host clipboard text event")
    func decodesHostClipboardTextEvent() throws {
        let clipboard: ClipboardTextSet = try decodeFixture("clipboard.text.set.host")

        #expect(clipboard.type == .clipboardTextSet)
        #expect(clipboard.requestId == "req_004")
        #expect(clipboard.origin == "host")
        #expect(clipboard.sequence == 42)
        #expect(clipboard.text == "hello from macOS")
    }

    @Test("decodes guest clipboard text event")
    func decodesGuestClipboardTextEvent() throws {
        let clipboard: ClipboardTextSet = try decodeFixture("clipboard.text.set.guest")

        #expect(clipboard.type == .clipboardTextSet)
        #expect(clipboard.requestId == "evt_clipboard_43")
        #expect(clipboard.origin == "guest")
        #expect(clipboard.sequence == 43)
        #expect(clipboard.text == "hello from Windows")
    }
}

private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    let data = try Data(contentsOf: url)
    return try JSONDecoder.veilProtocol.decode(T.self, from: data)
}
