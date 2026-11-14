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

    @Test("Events past the byte budget end the stream; taken events give their bytes back")
    func byteBudgetEndsStream() async throws {
        let budget = EventByteBudget(limit: 10)
        let stream = AsyncThrowingStream<Data, any Error>(bufferingPolicy: .bufferingNewest(100)) { continuation in
            #expect(URLSessionWebSocketTransport.yieldEventMessage(Data(count: 6), to: continuation, budget: budget))
            #expect(URLSessionWebSocketTransport.yieldEventMessage(Data(count: 4), to: continuation, budget: budget))
            #expect(!URLSessionWebSocketTransport.yieldEventMessage(Data(count: 1), to: continuation, budget: budget))
        }
        var iterator = EventByteBudget.releasing(stream, into: budget).makeAsyncIterator()
        #expect(try await iterator.next()?.count == 6)
        #expect(budget.bufferedBytes == 4)
        #expect(try await iterator.next()?.count == 4)
        #expect(budget.bufferedBytes == 0)
        do {
            _ = try await iterator.next()
            Issue.record("Expected the event stream to fail past its byte budget.")
        } catch let error as URLSessionWebSocketTransportError {
            #expect(error == .eventBufferOverflow)
        }
    }

    @Test("One message larger than the budget passes when nothing else waits")
    func oversizedSingleMessagePasses() {
        let budget = EventByteBudget(limit: 10)
        #expect(budget.reserve(50))
        #expect(!budget.reserve(1))
        budget.release(50)
        #expect(budget.reserve(1))
    }

    @Test("Cancelling the consumer still ends the socket's stream")
    func cancellationReachesTheSocketStream() async throws {
        let terminated = AsyncStream<Void>.makeStream()
        let inner = AsyncThrowingStream<Data, any Error> { continuation in
            continuation.onTermination = { _ in terminated.continuation.yield() }
        }
        let outer = EventByteBudget.releasing(inner, into: EventByteBudget(limit: 10))
        let consumer = Task {
            for try await _ in outer {}
        }
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()
        var signals = terminated.stream.makeAsyncIterator()
        #expect(await signals.next() != nil)
    }
}
