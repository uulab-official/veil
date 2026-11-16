import Foundation
import Testing
@testable import VeilHostCore

@Suite("Operation acknowledgement delivery")
struct OperationAcknowledgementTests {
    @Test("a negotiated clipboard acknowledgement must confirm the matching request", arguments: [
        "", "{}",
        #"{"type":"operation.ack","requestId":"wrong","accepted":true}"#,
        #"{"type":"operation.ack","requestId":"req_clipboard","accepted":false}"#,
        #"{"type":"window.created","requestId":"req_clipboard","accepted":true}"#
    ])
    func refusesUnconfirmedClipboard(reply: String) async throws {
        let client = VeilHostClient(transport: AckTransport(reply: reply))
        _ = try await client.loadHealth()
        await #expect(throws: (any Error).self) {
            try await client.sendClipboardText(Self.clipboard)
        }
    }

    @Test("a matching positive acknowledgement completes the clipboard write")
    func acceptsConfirmedClipboard() async throws {
        let client = VeilHostClient(transport: AckTransport(
            reply: #"{"type":"operation.ack","requestId":"req_clipboard","accepted":true}"#
        ))
        _ = try await client.loadHealth()
        try await client.sendClipboardText(Self.clipboard)
    }

    @Test("legacy guests do not wait for acknowledgements they never advertised")
    func preservesLegacyDelivery() async throws {
        let transport = AckTransport(reply: "", advertised: false)
        let client = VeilHostClient(transport: transport)
        _ = try await client.loadHealth()
        try await client.sendClipboardText(Self.clipboard)
        #expect(await transport.operationReplyCount == 0)
    }

    @Test("an explicit guest rejection keeps its actionable error")
    func propagatesGuestFailure() async throws {
        let client = VeilHostClient(transport: AckTransport(
            reply: #"{"type":"error","requestId":"req_clipboard","code":"clipboard_busy","message":"Clipboard is busy."}"#
        ))
        _ = try await client.loadHealth()
        await #expect(throws: VeilHostError.agentError(code: "clipboard_busy", message: "Clipboard is busy.")) {
            try await client.sendClipboardText(Self.clipboard)
        }
    }

    @Test("negotiated mouse, key, and Unicode input carry unique acknowledged request IDs")
    func acknowledgesEveryInputPath() async throws {
        let transport = AckTransport(reply: "echo")
        let client = VeilHostClient(transport: transport)
        _ = try await client.loadHealth()
        try await client.sendMouseInput(InputMouseEvent(windowId: "hwnd:1", event: "leftDown", x: 4, y: 8))
        try await client.sendKeyInput(InputKeyEvent(windowId: "hwnd:1", event: "keyDown", key: "a", windowsVirtualKey: 65))
        try await client.sendTextInput(InputTextEvent(windowId: "hwnd:1", text: "안녕하세요"))
        let ids = await transport.operationRequestIds
        #expect(ids.count == 3)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(Set(ids).count == 3)
        #expect(await transport.operationReplyCount == 1)
    }

    @Test("reads where the guest cursor went from a mouse acknowledgement")
    func readsReportedPointer() async throws {
        let client = VeilHostClient(transport: AckTransport(reply: "echo-pointer"))
        _ = try await client.loadHealth()

        let pointer = try await client.sendMouseInputReportingPointer(
            InputMouseEvent(windowId: "hwnd:1", event: "move", x: 4, y: 8)
        )

        #expect(pointer == GuestPointerPosition(x: 16384, y: 8192))
    }

    @Test("an acknowledgement without a pointer reports none")
    func reportsNoPointerFromOlderAgents() async throws {
        let client = VeilHostClient(transport: AckTransport(reply: "echo"))
        _ = try await client.loadHealth()

        let pointer = try await client.sendMouseInputReportingPointer(
            InputMouseEvent(windowId: "hwnd:1", event: "move", x: 4, y: 8)
        )

        #expect(pointer == nil)
    }

    @Test("serializes negotiated input operations so key order cannot overtake")
    func serializesInputOperations() async throws {
        let transport = AckTransport(reply: "echo", operationDelayNanoseconds: 50_000_000)
        let client = VeilHostClient(transport: transport)
        _ = try await client.loadHealth()

        let keyDown = Task {
            try await client.sendKeyInput(
                InputKeyEvent(windowId: "hwnd:1", event: "keyDown", key: "a", windowsVirtualKey: 65)
            )
        }
        await transport.waitForOperationCount(1)
        let keyUp = Task {
            try await client.sendKeyInput(
                InputKeyEvent(windowId: "hwnd:1", event: "keyUp", key: "a", windowsVirtualKey: 65)
            )
        }
        try await keyDown.value
        try await keyUp.value

        #expect(await transport.maxConcurrentOperationSends == 1)
        #expect(await transport.operationEvents == ["keyDown", "keyUp"])
    }

    @Test("keeps acknowledged input lanes independent across mirrored windows")
    func allowsIndependentWindowOperations() async throws {
        // The first send is held open until the second one arrives (or a bounded timeout), so the
        // overlap does not depend on scheduling under a loaded test run. If the lanes were wrongly
        // serialized, the second send could not start while the first is held and the max stays 1.
        let transport = AckTransport(reply: "echo", holdsFirstOperationUntilCount: 2)
        let client = VeilHostClient(transport: transport)
        _ = try await client.loadHealth()

        let firstWindow = Task {
            try await client.sendKeyInput(
                InputKeyEvent(windowId: "hwnd:1", event: "keyDown", key: "a", windowsVirtualKey: 65)
            )
        }
        await transport.waitForOperationCount(1)
        let secondWindow = Task {
            try await client.sendKeyInput(
                InputKeyEvent(windowId: "hwnd:2", event: "keyDown", key: "b", windowsVirtualKey: 66)
            )
        }

        try await firstWindow.value
        try await secondWindow.value

        #expect(await transport.maxConcurrentOperationSends == 2)
    }

    private static let clipboard = ClipboardTextSet(
        requestId: "req_clipboard", origin: "host", sequence: 1, text: "Current text"
    )
}

private actor AckTransport: HostTransport {
    let reply: String
    let advertised: Bool
    let operationDelayNanoseconds: UInt64
    let holdsFirstOperationUntilCount: Int?
    private(set) var operationReplyCount: Int?
    private(set) var operationRequestIds: [String] = []
    private(set) var operationEvents: [String] = []
    private(set) var maxConcurrentOperationSends = 0
    private var concurrentOperationSends = 0

    init(
        reply: String,
        advertised: Bool = true,
        operationDelayNanoseconds: UInt64 = 0,
        holdsFirstOperationUntilCount: Int? = nil
    ) {
        self.reply = reply
        self.advertised = advertised
        self.operationDelayNanoseconds = operationDelayNanoseconds
        self.holdsFirstOperationUntilCount = holdsFirstOperationUntilCount
    }

    func waitForOperationCount(_ count: Int) async {
        while operationEvents.count < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
        if object?["type"] as? String == "agent.health.request" {
            let health = #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"test"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true,"packageIdentity":false,"operationAcks":ADVERTISED}}"#
                .replacingOccurrences(of: "ADVERTISED", with: advertised ? "true" : "false")
            return [Data(health.utf8)]
        }
        operationReplyCount = expectedReplies
        if let requestId = object?["requestId"] as? String {
            operationRequestIds.append(requestId)
            if let event = object?["event"] as? String {
                operationEvents.append(event)
            }
            concurrentOperationSends += 1
            maxConcurrentOperationSends = max(maxConcurrentOperationSends, concurrentOperationSends)
            if operationDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: operationDelayNanoseconds)
            }
            if let holdCount = holdsFirstOperationUntilCount, operationEvents.count == 1 {
                let deadline = ContinuousClock.now + .seconds(2)
                while operationEvents.count < holdCount, ContinuousClock.now < deadline {
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
            concurrentOperationSends -= 1
            if reply == "echo" {
                return [try JSONSerialization.data(withJSONObject: [
                    "type": "operation.ack", "requestId": requestId, "accepted": true
                ])]
            }
            if reply == "echo-pointer" {
                return [try JSONSerialization.data(withJSONObject: [
                    "type": "operation.ack", "requestId": requestId, "accepted": true,
                    "pointer": ["x": 16384, "y": 8192]
                ])]
            }
        }
        return reply.isEmpty ? [] : [Data(reply.utf8)]
    }
}
