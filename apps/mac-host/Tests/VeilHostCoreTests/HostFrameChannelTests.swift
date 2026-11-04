import Foundation
import Testing

@testable import VeilHostCore

@Suite("Binary frame channel recovery")
struct HostFrameChannelTests {
    @Test("reports the window whose incremental tile was dropped")
    func reportsDroppedWindow() async throws {
        let stream = AsyncThrowingStream<WindowFrameChannelMessage, any Error>(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            let first = Self.message(windowId: "hwnd:1")
            let second = Self.message(windowId: "hwnd:2")

            #expect(URLSessionFrameChannel.yieldFrameMessage(first, to: continuation))
            #expect(!URLSessionFrameChannel.yieldFrameMessage(second, to: continuation))
        }
        var iterator = stream.makeAsyncIterator()

        // bufferingNewest keeps the newest element, so the second message remains available even though
        // the dropped first message identifies which HWND must be re-keyed.
        #expect(try await iterator.next()?.tile.windowId == "hwnd:2")
        await #expect(throws: HostFrameChannelError.bufferOverflow(windowId: "hwnd:1")) {
            _ = try await iterator.next()
        }
    }

    private static func message(windowId: String) -> WindowFrameChannelMessage {
        WindowFrameChannelMessage(
            tile: WindowFrameTile(
                windowId: windowId,
                sequence: 1,
                surfaceWidth: 1,
                surfaceHeight: 1,
                scale: 1,
                isKeyFrame: true,
                rect: WindowFrameTileRect(x: 0, y: 0, width: 1, height: 1),
                payload: Data([0x01])
            ),
            wireByteCount: 1
        )
    }
}
