import Foundation
import Testing

@testable import VeilHostCore

@Suite("WebSocket event transport")
struct WebSocketTransportTests {
    @Test("control event buffer overflow ends the stream for reconnect instead of dropping silently")
    func controlEventBufferOverflowEndsStream() async throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let stream = AsyncThrowingStream<Data, any Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            #expect(URLSessionWebSocketTransport.yieldEventMessage(first, to: continuation))
            // `.bufferingNewest(1)` evicts `first` when `second` arrives. The transport turns that
            // lossy result into a typed stream failure so the caller reconnects the control channel.
            #expect(!URLSessionWebSocketTransport.yieldEventMessage(second, to: continuation))
        }

        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == second)

        do {
            _ = try await iterator.next()
            Issue.record("Expected the event stream to fail after its bounded buffer overflowed.")
        } catch let error as URLSessionWebSocketTransportError {
            #expect(error == .eventBufferOverflow)
        }
    }
}
