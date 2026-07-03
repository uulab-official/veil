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
