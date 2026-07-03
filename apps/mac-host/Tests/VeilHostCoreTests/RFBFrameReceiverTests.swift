import Foundation
import Testing

@testable import VeilHostCore

@Suite("RFB frame receiver")
struct RFBFrameReceiverTests {
    @Test("builds client handshake and framebuffer request messages")
    func buildsClientMessages() {
        #expect(String(decoding: RFBClientMessageBuilder.clientProtocolVersion(), as: UTF8.self) == "RFB 003.008\n")
        #expect(RFBClientMessageBuilder.selectNoneSecurity() == Data([1]))
        #expect(RFBClientMessageBuilder.sharedClientInit() == Data([1]))
        #expect(RFBClientMessageBuilder.setRawEncoding() == Data([
            2, 0,
            0, 1,
            0, 0, 0, 0
        ]))

        let request = RFBClientMessageBuilder.framebufferUpdateRequest(
            incremental: true,
            x: 1,
            y: 2,
            width: 640,
            height: 480
        )

        #expect(request == Data([
            3, 1,
            0, 1,
            0, 2,
            2, 128,
            1, 224
        ]))
    }

    @Test("parses QEMU-style server init")
    func parsesServerInit() throws {
        let serverInit = try RFBFrameParser.parseServerInit(Self.serverInitData(
            width: 1_024,
            height: 768,
            desktopName: "QEMU"
        ))

        #expect(serverInit.width == 1_024)
        #expect(serverInit.height == 768)
        #expect(serverInit.desktopName == "QEMU")
        #expect(serverInit.pixelFormat.bitsPerPixel == 32)
        #expect(serverInit.pixelFormat.depth == 24)
        #expect(serverInit.pixelFormat.redShift == 16)
        #expect(serverInit.pixelFormat.greenShift == 8)
        #expect(serverInit.pixelFormat.blueShift == 0)
    }

    @Test("parses raw framebuffer update")
    func parsesRawFramebufferUpdate() throws {
        let pixelFormat = RFBPixelFormat(
            bitsPerPixel: 32,
            depth: 24,
            isBigEndian: false,
            isTrueColor: true,
            redMax: 255,
            greenMax: 255,
            blueMax: 255,
            redShift: 16,
            greenShift: 8,
            blueShift: 0
        )
        var update = Data([
            0, 0,
            0, 1,
            0, 1,
            0, 2,
            0, 2,
            0, 1
        ])
        update.append(contentsOf: [0, 0, 0, 0])
        update.append(contentsOf: [1, 2, 3, 4, 5, 6, 7, 8])

        let frame = try RFBFrameParser.parseFramebufferUpdate(update, pixelFormat: pixelFormat)

        #expect(frame.rectangles.count == 1)
        let rectangle = try #require(frame.rectangles.first)
        #expect(rectangle.x == 1)
        #expect(rectangle.y == 2)
        #expect(rectangle.width == 2)
        #expect(rectangle.height == 1)
        #expect(rectangle.pixels == Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    @Test("rejects unsupported rectangle encoding")
    func rejectsUnsupportedEncoding() {
        let pixelFormat = RFBPixelFormat(
            bitsPerPixel: 32,
            depth: 24,
            isBigEndian: false,
            isTrueColor: true,
            redMax: 255,
            greenMax: 255,
            blueMax: 255,
            redShift: 16,
            greenShift: 8,
            blueShift: 0
        )
        let update = Data([
            0, 0,
            0, 1,
            0, 0,
            0, 0,
            0, 1,
            0, 1,
            0, 0, 0, 5
        ])

        #expect(throws: RFBError.unsupportedEncoding(5)) {
            _ = try RFBFrameParser.parseFramebufferUpdate(update, pixelFormat: pixelFormat)
        }
    }

    @Test("rejects short protocol version")
    func rejectsShortProtocolVersion() {
        #expect(throws: RFBError.messageTooShort(expected: 12, actual: 3)) {
            _ = try RFBFrameParser.parseProtocolVersion(Data("RFB".utf8))
        }
    }

    @Test("stream client handshakes and reads a raw framebuffer update")
    func streamClientHandshakesAndReadsFrame() throws {
        let stream = FakeRFBByteStream(inbound: Self.serverStreamData())
        let client = RFBFrameStreamClient(stream: stream)

        let serverInit = try client.startSharedSession()
        try client.requestFramebufferUpdate(incremental: false)
        let update = try client.readFramebufferUpdate()

        #expect(serverInit.width == 2)
        #expect(serverInit.height == 1)
        #expect(serverInit.desktopName == "QEMU")
        #expect(stream.writes[0] == RFBClientMessageBuilder.clientProtocolVersion())
        #expect(stream.writes[1] == RFBClientMessageBuilder.selectNoneSecurity())
        #expect(stream.writes[2] == RFBClientMessageBuilder.sharedClientInit())
        #expect(stream.writes[3] == RFBClientMessageBuilder.setRawEncoding())
        #expect(stream.writes[4] == Data([
            3, 0,
            0, 0,
            0, 0,
            0, 2,
            0, 1
        ]))
        #expect(update.rectangles.count == 1)
        #expect(update.rectangles.first?.pixels == Data([
            0, 0, 255, 0,
            0, 255, 0, 0
        ]))
    }

    @Test("framebuffer renderer applies raw rectangles into RGBA pixels")
    func framebufferRendererAppliesRawRectangles() throws {
        let serverInit = try RFBFrameParser.parseServerInit(Self.serverInitData(
            width: 2,
            height: 1,
            desktopName: "QEMU"
        ))
        let renderer = try RFBFramebufferRenderer(serverInit: serverInit)
        let update = RFBFramebufferUpdate(rectangles: [
            RFBRawRectangle(
                x: 0,
                y: 0,
                width: 2,
                height: 1,
                pixels: Data([
                    0, 0, 255, 0,
                    0, 255, 0, 0
                ])
            )
        ])

        let frame = try renderer.apply(update)

        #expect(frame.width == 2)
        #expect(frame.height == 1)
        #expect(frame.sequence == 1)
        #expect(frame.rgbaPixels == Data([
            255, 0, 0, 255,
            0, 255, 0, 255
        ]))
    }

    @Test("framebuffer renderer rejects rectangles outside display bounds")
    func framebufferRendererRejectsOutOfBoundsRectangles() throws {
        let serverInit = try RFBFrameParser.parseServerInit(Self.serverInitData(
            width: 2,
            height: 1,
            desktopName: "QEMU"
        ))
        let renderer = try RFBFramebufferRenderer(serverInit: serverInit)
        let update = RFBFramebufferUpdate(rectangles: [
            RFBRawRectangle(
                x: 1,
                y: 0,
                width: 2,
                height: 1,
                pixels: Data(repeating: 0, count: 8)
            )
        ])

        #expect(throws: RFBError.invalidRectangleBounds) {
            _ = try renderer.apply(update)
        }
    }

    @Test("framebuffer renderer rejects short pixel buffers")
    func framebufferRendererRejectsShortPixelBuffers() throws {
        let serverInit = try RFBFrameParser.parseServerInit(Self.serverInitData(
            width: 2,
            height: 1,
            desktopName: "QEMU"
        ))
        let renderer = try RFBFramebufferRenderer(serverInit: serverInit)
        let update = RFBFramebufferUpdate(rectangles: [
            RFBRawRectangle(
                x: 0,
                y: 0,
                width: 2,
                height: 1,
                pixels: Data([0, 0, 255, 0])
            )
        ])

        #expect(throws: RFBError.messageTooShort(expected: 8, actual: 4)) {
            _ = try renderer.apply(update)
        }
    }

    private static func serverInitData(width: UInt16, height: UInt16, desktopName: String) -> Data {
        var data = Data()
        data.appendBigEndian(width)
        data.appendBigEndian(height)
        data.append(contentsOf: [
            32,
            24,
            0,
            1,
            0, 255,
            0, 255,
            0, 255,
            16,
            8,
            0,
            0, 0, 0
        ])
        let nameBytes = Array(desktopName.utf8)
        data.appendBigEndian(UInt32(nameBytes.count))
        data.append(contentsOf: nameBytes)
        return data
    }

    private static func serverStreamData() -> Data {
        var data = Data("RFB 003.008\n".utf8)
        data.append(contentsOf: [1, 1])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(serverInitData(width: 2, height: 1, desktopName: "QEMU"))
        data.append(contentsOf: [
            0, 0,
            0, 1,
            0, 0,
            0, 0,
            0, 2,
            0, 1,
            0, 0, 0, 0,
            0, 0, 255, 0,
            0, 255, 0, 0
        ])
        return data
    }
}

private final class FakeRFBByteStream: RFBByteStream {
    private var inbound: Data
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

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(contentsOf: [
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}
