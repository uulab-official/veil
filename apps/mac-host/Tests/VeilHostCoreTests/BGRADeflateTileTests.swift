import Compression
import CoreGraphics
import Foundation
import Testing

@testable import VeilHostCore

@Suite("BGRA deflate frame tiles")
struct BGRADeflateTileTests {
    /// Raw deflate, as the guest's DeflateStream produces.
    private static func deflate(_ bytes: [UInt8]) -> Data {
        var output = [UInt8](repeating: 0, count: bytes.count + 1024)
        let written = compression_encode_buffer(&output, output.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
        return Data(output.prefix(written))
    }

    @Test("decodes a deflated BGRA tile into an image of the tile's size")
    func decodesDeflatedBGRA() throws {
        // 2x1: one blue pixel, one red pixel, in BGRA byte order.
        let payload = Self.deflate([255, 0, 0, 255, 0, 0, 255, 255])

        let image = try #require(WindowFrameCompositor.decodeBGRADeflate(payload, width: 2, height: 1))

        #expect(image.width == 2)
        #expect(image.height == 1)
    }

    @Test("rejects a payload that does not inflate to the tile's pixel count")
    func rejectsShortPayload() {
        let payload = Self.deflate([1, 2, 3, 4])

        #expect(WindowFrameCompositor.decodeBGRADeflate(payload, width: 2, height: 1) == nil)
    }

    @Test("composites a deflated tile through the compositor")
    func compositesDeflatedTile() {
        let compositor = WindowFrameCompositor()
        let tile = WindowFrameTile(
            windowId: "hwnd:1",
            sequence: 1,
            surfaceWidth: 2,
            surfaceHeight: 1,
            scale: 1,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: 2, height: 1),
            payload: Self.deflate([255, 0, 0, 255, 0, 0, 255, 255]),
            payloadFormat: VeilFrameChannelCodec.bgraDeflateFormat
        )

        guard case .composited = compositor.apply(tile) else {
            Issue.record("A valid deflated key frame should composite.")
            return
        }
    }

    @Test("asks the agent for deflated tiles when subscribing")
    func subscribeRequestsDeflatedTiles() throws {
        let request = WindowFrameSubscribeRequest(requestId: "r", windowId: "hwnd:1", tileFormat: VeilFrameChannelCodec.bgraDeflateFormatName)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)

        #expect(json.contains(#""tileFormat":"bgra-deflate""#))
    }
}
