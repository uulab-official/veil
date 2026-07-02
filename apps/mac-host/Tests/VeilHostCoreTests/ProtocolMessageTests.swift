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
}

private func decodeFixture<T: Decodable>(_ name: String) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    let data = try Data(contentsOf: url)
    return try JSONDecoder.veilProtocol.decode(T.self, from: data)
}
