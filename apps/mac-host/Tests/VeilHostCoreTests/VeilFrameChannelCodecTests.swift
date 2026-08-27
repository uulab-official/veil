import Foundation
import Testing

@testable import VeilHostCore

@Suite("Binary frame channel codec")
struct VeilFrameChannelCodecTests {
    private static let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])

    private static func tile(
        windowId: String = "hwnd:0003029A",
        sequence: Int = 7,
        surfaceWidth: Int = 1_280,
        surfaceHeight: Int = 800,
        scale: Double = 2,
        isKeyFrame: Bool = false,
        rect: WindowFrameTileRect = WindowFrameTileRect(x: 16, y: 32, width: 64, height: 48),
        payload: Data = VeilFrameChannelCodecTests.payload
    ) -> WindowFrameTile {
        WindowFrameTile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            scale: scale,
            isKeyFrame: isKeyFrame,
            rect: rect,
            payload: payload
        )
    }

    private static func keyFrame(
        surfaceWidth: Int = 1_280,
        surfaceHeight: Int = 800
    ) -> WindowFrameTile {
        tile(
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: surfaceWidth, height: surfaceHeight)
        )
    }

    @Test("round-trips a dirty-rect tile")
    func roundTripsTile() throws {
        let original = Self.tile()
        let decoded = try VeilFrameChannelCodec.decode(try VeilFrameChannelCodec.encode(original))

        #expect(decoded == original)
        #expect(!decoded.isKeyFrame)
        #expect(decoded.rect == WindowFrameTileRect(x: 16, y: 32, width: 64, height: 48))
    }

    @Test("round-trips a key frame")
    func roundTripsKeyFrame() throws {
        let decoded = try VeilFrameChannelCodec.decode(try VeilFrameChannelCodec.encode(Self.keyFrame()))

        #expect(decoded.isKeyFrame)
        #expect(decoded.rect.covers(surfaceWidth: 1_280, surfaceHeight: 800))
    }

    @Test("carries the payload as raw bytes rather than an inflated string")
    func carriesRawPayloadBytes() throws {
        let message = try VeilFrameChannelCodec.encode(Self.tile())
        let expectedSize = VeilFrameChannelCodec.headerByteCountWithoutWindowIdV2
            + "hwnd:0003029A".utf8.count
            + Self.payload.count

        #expect(message.count == expectedSize)
        #expect(message.suffix(Self.payload.count) == Self.payload)
        #expect(message.prefix(4) == VeilFrameChannelCodec.magicV2)
    }

    @Test("decodes a version 1 message as a full-surface key frame")
    func decodesVersion1AsKeyFrame() throws {
        // An agent caught mid-upgrade must degrade to full frames, not fail outright.
        var v1 = Data()
        v1.append(VeilFrameChannelCodec.magicV1)
        v1.append(VeilFrameChannelCodec.pngFormat)
        let windowIdBytes = Data("hwnd:0003029A".utf8)
        v1.append(Data([0x00, UInt8(windowIdBytes.count)]))
        v1.append(windowIdBytes)
        v1.append(Data([0, 0, 0, 9]))          // sequence
        v1.append(Data([0, 0, 2, 0]))          // width 512
        v1.append(Data([0, 0, 1, 0]))          // height 256
        v1.append(Data([0, 0, 0x03, 0xE8]))    // scale 1000
        v1.append(Data([0, 0, 0, UInt8(Self.payload.count)]))
        v1.append(Self.payload)

        let decoded = try VeilFrameChannelCodec.decode(v1)

        #expect(decoded.isKeyFrame)
        #expect(decoded.sequence == 9)
        #expect(decoded.surfaceWidth == 512)
        #expect(decoded.surfaceHeight == 256)
        #expect(decoded.scale == 1)
        #expect(decoded.rect == WindowFrameTileRect(x: 0, y: 0, width: 512, height: 256))
    }

    @Test("round-trips a non-ASCII window id")
    func roundTripsNonASCIIWindowId() throws {
        // The window id length is a byte count, not a character count. Getting that wrong would misplace
        // every field after it.
        let decoded = try VeilFrameChannelCodec.decode(
            try VeilFrameChannelCodec.encode(Self.tile(windowId: "hwnd:창-0003029A"))
        )

        #expect(decoded.windowId == "hwnd:창-0003029A")
        #expect(decoded.rect.width == 64)
    }

    @Test("decodes correctly from a slice of a larger receive buffer")
    func decodesFromSliceOfLargerBuffer() throws {
        // A `Data` slice keeps the parent's start index. Assuming zero would read the wrong bytes, so this
        // guards the exact mistake that produces silently corrupt frames.
        let message = try VeilFrameChannelCodec.encode(Self.tile())
        let slice = (Data(repeating: 0xFF, count: 16) + message)[16...]

        #expect(try VeilFrameChannelCodec.decode(slice).windowId == "hwnd:0003029A")
    }

    @Test("preserves fractional DPI scale through the integer encoding")
    func preservesFractionalScale() throws {
        for scale in [1.0, 1.25, 1.5, 2.0, 3.0] {
            let decoded = try VeilFrameChannelCodec.decode(
                try VeilFrameChannelCodec.encode(Self.tile(scale: scale))
            )
            #expect(decoded.scale == scale, "\(scale)")
        }
    }

    @Test("treats a zero scale as 100 percent rather than an unusable window")
    func treatsZeroScaleAsHundredPercent() throws {
        #expect(
            try VeilFrameChannelCodec.decode(
                try VeilFrameChannelCodec.encode(Self.tile(scale: 0))
            ).scale == 1
        )
    }

    @Test("rejects a message that does not start with a recognized magic")
    func rejectsBadMagic() throws {
        var message = [UInt8](try VeilFrameChannelCodec.encode(Self.tile()))
        message[3] = 0x39

        #expect(throws: VeilFrameChannelCodec.CodecError.badMagic) {
            _ = try VeilFrameChannelCodec.decode(Data(message))
        }
    }

    @Test("rejects an unsupported payload format")
    func rejectsUnsupportedFormat() throws {
        var message = [UInt8](try VeilFrameChannelCodec.encode(Self.tile()))
        message[4] = 0x09

        #expect(throws: VeilFrameChannelCodec.CodecError.unsupportedFormat(0x09)) {
            _ = try VeilFrameChannelCodec.decode(Data(message))
        }
    }

    @Test("rejects a truncated message")
    func rejectsTruncatedMessage() throws {
        let message = try VeilFrameChannelCodec.encode(Self.tile())

        for prefixLength in [0, 3, 12, VeilFrameChannelCodec.headerByteCountWithoutWindowIdV2 - 1] {
            #expect(throws: (any Error).self) {
                _ = try VeilFrameChannelCodec.decode(message.prefix(prefixLength))
            }
        }
    }

    @Test("rejects a declared payload length that disagrees with the buffer")
    func rejectsPayloadLengthMismatch() throws {
        let message = try VeilFrameChannelCodec.encode(Self.tile())

        // Silently accepting a short declared length would hide a framing disagreement between the host
        // and the guest, which is exactly how corrupt frames become mysterious rendering bugs.
        #expect(throws: (any Error).self) {
            _ = try VeilFrameChannelCodec.decode(message.dropLast(3))
        }
        #expect(throws: (any Error).self) {
            _ = try VeilFrameChannelCodec.decode(message + Data([0x00]))
        }
    }

    @Test("refuses a tile that falls outside its declared surface")
    func refusesTileOutsideSurface() {
        for rect in [
            WindowFrameTileRect(x: 1_270, y: 0, width: 64, height: 48),
            WindowFrameTileRect(x: 0, y: 790, width: 64, height: 48),
            WindowFrameTileRect(x: -1, y: 0, width: 64, height: 48),
            WindowFrameTileRect(x: 0, y: 0, width: 0, height: 48)
        ] {
            #expect(throws: (any Error).self) {
                _ = try VeilFrameChannelCodec.encode(Self.tile(rect: rect))
            }
        }
    }

    @Test("refuses a key frame that does not cover its surface")
    func refusesPartialKeyFrame() {
        // The compositor has nothing to composite onto until a key frame arrives, so a partial one would
        // leave undefined pixels with no way to detect it.
        #expect(throws: (any Error).self) {
            _ = try VeilFrameChannelCodec.encode(
                Self.tile(isKeyFrame: true, rect: WindowFrameTileRect(x: 0, y: 0, width: 64, height: 48))
            )
        }
    }

    @Test("refuses an implausible surface size")
    func refusesImplausibleSurface() {
        #expect(throws: (any Error).self) {
            _ = try VeilFrameChannelCodec.encode(Self.tile(surfaceWidth: 0))
        }
        #expect(throws: (any Error).self) {
            _ = try VeilFrameChannelCodec.encode(
                Self.tile(surfaceWidth: VeilFrameChannelCodec.maximumSurfaceDimension + 1)
            )
        }
    }

    @Test("refuses to encode an empty payload")
    func refusesEmptyPayload() {
        #expect(throws: VeilFrameChannelCodec.CodecError.emptyPayload) {
            _ = try VeilFrameChannelCodec.encode(Self.tile(payload: Data()))
        }
    }

    @Test("rectangle containment rejects overflowing coordinates instead of trapping")
    func rectangleContainmentRejectsOverflow() {
        let overflowing = WindowFrameTileRect(x: Int.max, y: 0, width: 2, height: 2)

        #expect(!overflowing.fits(surfaceWidth: 1_280, surfaceHeight: 800))
    }
}

@Suite("Binary frame channel endpoint")
struct HostFrameChannelEndpointTests {
    @Test("derives the frame endpoint from the agent control endpoint")
    func derivesFrameEndpoint() {
        #expect(
            URLSessionFrameChannel.frameChannelURL(agentEndpoint: "ws://127.0.0.1:18444")?.absoluteString
                == "ws://127.0.0.1:18444/frames"
        )
        #expect(
            URLSessionFrameChannel.frameChannelURL(agentEndpoint: "  wss://guest.local:9000  ")?.absoluteString
                == "wss://guest.local:9000/frames"
        )
    }

    @Test("replaces an existing path rather than appending to it")
    func replacesExistingPath() {
        #expect(
            URLSessionFrameChannel.frameChannelURL(agentEndpoint: "ws://127.0.0.1:18444/control?x=1")?.absoluteString
                == "ws://127.0.0.1:18444/frames"
        )
    }

    @Test("fails closed for anything that is not a WebSocket endpoint")
    func failsClosedForNonWebSocketEndpoints() {
        // Failing closed matters: the fallback is the working JSON frame path, whereas guessing a URL
        // could open a connection to somewhere unexpected.
        for endpoint in ["", "   ", "http://127.0.0.1:18444", "127.0.0.1:18444", "ws://"] {
            #expect(URLSessionFrameChannel.frameChannelURL(agentEndpoint: endpoint) == nil, "\(endpoint)")
        }
    }
}
