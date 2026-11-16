import Foundation
import Testing
@testable import VeilHostCore

@Suite("Desktop size handed to the GPU runtime over VNC")
struct RFBDesktopSizeForwarderTests {
    @Test("QEMU's answer to the request is told apart from its initial size report")
    func returnsTheAnswerToTheRequest() throws {
        var server = Self.handshake(width: 1024, height: 768)
        server.append(Self.desktopSizeUpdate(reason: 0, result: 0, width: 1024, height: 768))
        server.append(Self.desktopSizeUpdate(reason: 1, result: 4, width: 1024, height: 768))
        let stream = ScriptedRFBStream(inbound: server)

        let response = try #require(try RFBDesktopSizeForwarder.forward(width: 2048, height: 1280, over: stream))

        #expect(response.isForwardedToGuest)
        #expect(response.reasonCode == 1)
        #expect(stream.writes.contains(RFBClientMessageBuilder.setDesktopSize(width: 2048, height: 1280)))
        // Only one-pixel updates are asked for: the forwarder never reads a whole framebuffer.
        let onePixel = RFBClientMessageBuilder.framebufferUpdateRequest(incremental: false, x: 0, y: 0, width: 1, height: 1)
        #expect(stream.writes.filter { $0.first == 3 }.allSatisfy { $0 == onePixel })
    }

    @Test("A QEMU that closes the connection gives no answer rather than a wrong one")
    func closedConnection() {
        var server = Self.handshake(width: 1024, height: 768)
        server.append(Self.desktopSizeUpdate(reason: 0, result: 0, width: 1024, height: 768))
        let stream = ScriptedRFBStream(inbound: server)

        #expect(throws: (any Error).self) {
            try RFBDesktopSizeForwarder.forward(width: 2048, height: 1280, over: stream)
        }
    }

    @Test("A missing socket answers nil at once")
    func missingSocket() {
        #expect(RFBDesktopSizeForwarder.forward(width: 2048, height: 1280, unixSocketPath: "/tmp/veil-no-such-vnc.sock") == nil)
    }

    private static func handshake(width: UInt16, height: UInt16) -> Data {
        var data = Data("RFB 003.008\n".utf8)
        data.append(contentsOf: [1, 1, 0, 0, 0, 0])
        data.append(contentsOf: Self.bigEndian(width) + Self.bigEndian(height))
        data.append(contentsOf: [32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 4] + Array("QEMU".utf8))
        return data
    }

    /// One FramebufferUpdate holding a single ExtendedDesktopSize rectangle with one screen.
    private static func desktopSizeUpdate(reason: UInt16, result: UInt16, width: UInt16, height: UInt16) -> Data {
        var data = Data([0, 0, 0, 1])
        data.append(contentsOf: Self.bigEndian(reason) + Self.bigEndian(result) + Self.bigEndian(width) + Self.bigEndian(height))
        data.append(contentsOf: [0xFF, 0xFF, 0xFE, 0xCC]) // -308
        data.append(contentsOf: [1, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0] + Self.bigEndian(width) + Self.bigEndian(height) + [0, 0, 0, 0])
        return data
    }

    private static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }
}

private final class ScriptedRFBStream: RFBByteStream {
    private let inbound: Data
    private var offset = 0
    private(set) var writes: [Data] = []

    init(inbound: Data) {
        self.inbound = inbound
    }

    func readExactly(_ byteCount: Int) throws -> Data {
        guard inbound.count >= offset + byteCount else {
            throw RFBLoopbackSocketError.connectionClosed
        }
        defer { offset += byteCount }
        return inbound.subdata(in: offset..<(offset + byteCount))
    }

    func write(_ data: Data) throws {
        writes.append(data)
    }

    func close() {}
}
