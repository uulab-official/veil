import Foundation

public enum URLSessionWebSocketTransportError: Error, LocalizedError, Equatable, Sendable {
    /// The bounded control-event queue dropped a lifecycle/clipboard/notification message. Reconnect so
    /// the host can resume from a fresh event channel; silently continuing would leave a closed HWND or
    /// a guest notification permanently out of sync.
    case eventBufferOverflow

    public var errorDescription: String? {
        switch self {
        case .eventBufferOverflow:
            "The Windows agent sent control events faster than the host could process them; reconnecting the event channel."
        }
    }
}

public struct URLSessionWebSocketTransport: HostTransport, HostEventSource {
    private let url: URL
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public init(url: URL, requestTimeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        self.url = url
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        try await send(message, expectedReplies: expectedReplies, replyTimeout: nil)
    }

    /// Sends one message and reads up to `expectedReplies` frames.
    ///
    /// When `replyTimeout` is set, one deadline bounds the whole reply phase, including
    /// unsolicited events. The caller decides whether incomplete replies prove delivery.
    public func send(
        _ message: Data,
        expectedReplies: Int,
        replyTimeout: TimeInterval?
    ) async throws -> [Data] {
        if let replyTimeout, !replyTimeout.isFinite || replyTimeout < 0 {
            throw VeilHostError.missingReply("reply timeout must be finite and nonnegative")
        }
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = Self.maximumMessageByteCount
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            task.resume()
            defer {
                task.cancel(with: .normalClosure, reason: nil)
            }

            try await task.send(.data(message))
            let deadline = replyTimeout.map { ContinuousClock.now + .seconds($0) }

            var replies: [Data] = []
            var ignoredEventCount = 0
            while replies.count < expectedReplies {
                let reply: Data
                if let deadline {
                    let remaining = ContinuousClock.now.duration(to: deadline).components
                    let remainingSeconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
                    guard remainingSeconds > 0 else { return replies }
                    guard let boundedReply = try await Self.receiveWithTimeout(
                        task,
                        timeoutSeconds: remainingSeconds
                    ) else {
                        return replies
                    }
                    reply = boundedReply
                } else {
                    switch try await task.receive() {
                    case .data(let data):
                        reply = data
                    case .string(let text):
                        reply = Data(text.utf8)
                    @unknown default:
                        throw VeilHostError.missingReply("unsupported websocket message type")
                    }
                }

                if Self.isUnsolicitedEvent(reply) {
                    ignoredEventCount += 1
                    if ignoredEventCount > 64 {
                        throw VeilHostError.missingReply("too many unsolicited websocket events while waiting for replies")
                    }
                    continue
                }

                replies.append(reply)
                if Self.isProtocolError(reply) {
                    break
                }
            }

            return replies
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Races one receive against a timeout. Returns the frame, or nil when the timeout expired
    /// first. Losing the race cancels the receive task, which is safe because the caller closes
    /// the socket right after.
    private static func receiveWithTimeout(
        _ task: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> Data? {
        try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    switch try await task.receive() {
                    case .data(let data):
                        return data
                    case .string(let text):
                        return Data(text.utf8)
                    @unknown default:
                        throw VeilHostError.missingReply("unsupported websocket message type")
                    }
                } onCancel: {
                    // A task group waits for cancelled children. Close the socket to unblock
                    // a receive that is still suspended when the deadline wins.
                    task.cancel(with: .goingAway, reason: nil)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }

            defer { group.cancelAll() }
            let first = try await group.next() ?? nil
            try Task.checkCancellation()
            return first
        }
    }

    private static func isProtocolError(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return false
        }
        return type == MessageType.error.rawValue
    }

    private static func isUnsolicitedEvent(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return false
        }

        // Every guest-initiated event that can arrive on a request/response connection has to be
        // listed here, otherwise it gets consumed as the reply to the in-flight request and the
        // caller decodes the wrong message. `notification.listener.response` is deliberately absent
        // because it *is* a reply.
        return type == MessageType.windowFrame.rawValue
            || type == MessageType.windowUpdated.rawValue
            || type == MessageType.windowClosed.rawValue
            || type == MessageType.clipboardTextSet.rawValue
            || type == MessageType.clipboardImageSet.rawValue
            || type == MessageType.notificationReceived.rawValue
            || type == MessageType.windowFrameUnchanged.rawValue
            || type == MessageType.windowLayout.rawValue
    }

    /// How many undelivered control messages the event stream will hold.
    ///
    /// The default policy is `.unbounded`. Control messages are low volume in normal use — window lifecycle,
    /// clipboard, notifications — so this bound is never reached by a working guest. It exists so a guest
    /// flooding the connection cannot grow host memory without limit.
    ///
    /// Dropping is genuinely lossy here, unlike frames: a discarded `window.closed` leaves a mirrored window
    /// the guest has already forgotten. There is no policy that avoids that under a flood, so the choice is
    /// which failure to take, and losing events beats exhausting memory.
    public static let eventBufferMessageCount = 1_024

    /// Bytes of events received and not yet taken by the consumer. The count bound alone let 1,024
    /// messages of up to 32 MiB each wait in memory, 32 GiB, while the app was busy; a working guest stays
    /// far below this, since a large clipboard image is one message of about 11 MB.
    public static let eventBufferByteBudget = 96 * 1_024 * 1_024

    /// Largest single message either socket will receive. URLSession's default is 1 MiB, and a guest
    /// clipboard image of up to 8 MiB arrives as about 11.2 MB of base64 JSON; at the default the receive
    /// fails and the event stream would reconnect on every large copy instead of delivering it.
    public static let maximumMessageByteCount = 32 * 1_024 * 1_024

    /// Enqueues one control event and turns a lossy buffer eviction into a reconnectable stream error.
    /// The event stream carries lifecycle messages, so silently dropping one is worse than reconnecting:
    /// a lost `window.closed` would leave a macOS window for an HWND the guest has already forgotten.
    /// Kept separate from the URLSession receive loop so the overflow contract is deterministic to test.
    static func yieldEventMessage(
        _ message: Data,
        to continuation: AsyncThrowingStream<Data, any Error>.Continuation,
        budget: EventByteBudget? = nil
    ) -> Bool {
        if let budget, !budget.reserve(message.count) {
            continuation.finish(throwing: URLSessionWebSocketTransportError.eventBufferOverflow)
            return false
        }
        switch continuation.yield(message) {
        case .enqueued:
            return true
        case .dropped:
            continuation.finish(throwing: URLSessionWebSocketTransportError.eventBufferOverflow)
            return false
        case .terminated:
            return false
        @unknown default:
            continuation.finish(throwing: URLSessionWebSocketTransportError.eventBufferOverflow)
            return false
        }
    }

    static let windowListRequestText = #"{"type":"window.list.request","requestId":"events"}"#

    /// How long the guest has to answer the window list before its connection is given up.
    static let windowListTimeout: Duration = .seconds(15)

    public func eventMessages() -> AsyncThrowingStream<Data, any Error> {
        let budget = EventByteBudget(limit: Self.eventBufferByteBudget)
        return EventByteBudget.releasing(receivedEventMessages(budget: budget), into: budget)
    }

    private func receivedEventMessages(budget: EventByteBudget) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream(
            Data.self,
            bufferingPolicy: .bufferingNewest(Self.eventBufferMessageCount)
        ) { continuation in
            // This connection only listens. The agent stops sending events to a connection once that
            // connection has sent a request, so nothing may be sent on it.
            let task = session.webSocketTask(with: url)
            task.maximumMessageSize = Self.maximumMessageByteCount
            task.resume()
            // Asks for the windows already open in Windows, on a connection of its own. The answers are
            // passed into this stream as the `window.created` events they are, so they are handled like any
            // window that opens later. When the request went out on the listening connection, every event
            // after the answer was lost: layouts, new and closed windows, the clipboard, notifications.
            let listTask = session.webSocketTask(with: url)
            listTask.maximumMessageSize = Self.maximumMessageByteCount
            listTask.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel(with: .normalClosure, reason: nil)
                listTask.cancel(with: .normalClosure, reason: nil)
            }

            let listTimeout = Task {
                try? await Task.sleep(for: Self.windowListTimeout)
                listTask.cancel(with: .normalClosure, reason: nil)
            }
            Task {
                defer {
                    listTimeout.cancel()
                    listTask.cancel(with: .normalClosure, reason: nil)
                }
                // Best effort: without the list, windows still arrive as the guest reports them.
                guard (try? await listTask.send(.string(Self.windowListRequestText))) != nil else {
                    return
                }
                var reader = WindowListReplyReader()
                while !Task.isCancelled, let message = try? await listTask.receive() {
                    let data: Data
                    switch message {
                    case .data(let received): data = received
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: return
                    }
                    let step = reader.accept(data)
                    if step.forward, !Self.yieldEventMessage(data, to: continuation, budget: budget) {
                        return
                    }
                    if step.done {
                        return
                    }
                }
            }

            Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .data(let data):
                            guard Self.yieldEventMessage(data, to: continuation, budget: budget) else { return }
                        case .string(let text):
                            guard Self.yieldEventMessage(Data(text.utf8), to: continuation, budget: budget) else { return }
                        @unknown default:
                            continuation.finish(throwing: VeilHostError.missingReply("unsupported websocket message type"))
                            return
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Counts the bytes of events waiting between the socket and the consumer.
final class EventByteBudget: @unchecked Sendable {
    let limit: Int
    private let lock = NSLock()
    private var buffered = 0

    init(limit: Int) {
        self.limit = limit
    }

    var bufferedBytes: Int {
        lock.withLock { buffered }
    }

    /// False when the message would take the waiting bytes past the limit. A single message larger than the
    /// limit still passes when nothing else waits, so one large clipboard copy is never refused.
    func reserve(_ byteCount: Int) -> Bool {
        lock.withLock {
            guard buffered == 0 || buffered + byteCount <= limit else {
                return false
            }
            buffered += byteCount
            return true
        }
    }

    func release(_ byteCount: Int) {
        lock.withLock {
            buffered = max(0, buffered - byteCount)
        }
    }

    /// The same messages, giving their bytes back to the budget as the consumer takes each one.
    static func releasing(
        _ stream: AsyncThrowingStream<Data, any Error>,
        into budget: EventByteBudget
    ) -> AsyncThrowingStream<Data, any Error> {
        let source = IteratorBox(stream.makeAsyncIterator(), budget: budget)
        return AsyncThrowingStream(unfolding: { try await source.next() })
    }

    private final class IteratorBox: @unchecked Sendable {
        private var iterator: AsyncThrowingStream<Data, any Error>.AsyncIterator
        private let budget: EventByteBudget

        init(_ iterator: AsyncThrowingStream<Data, any Error>.AsyncIterator, budget: EventByteBudget) {
            self.iterator = iterator
            self.budget = budget
        }

        /// Called by one consumer at a time, as an async sequence's iterator is.
        func next() async throws -> Data? {
            let message = try await iterator.next()
            if let message {
                budget.release(message.count)
            }
            return message
        }
    }
}

/// Picks the answer to `window.list.request` out of what arrives on the connection that asked: the
/// `window.list.response` and the one `window.created` per window that follows it. Anything else there is
/// an event the listening connection also receives, and is left to it.
struct WindowListReplyReader {
    /// `window.created` messages still to come, or nil before the response.
    private var remaining: Int?

    /// Whether to pass the message on as an event, and whether the answer is complete.
    mutating func accept(_ message: Data) -> (forward: Bool, done: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
              let type = object["type"] as? String else {
            return (false, false)
        }

        guard let remaining else {
            switch type {
            case MessageType.windowListResponse.rawValue:
                let count = (object["windowIds"] as? [Any])?.count ?? 0
                self.remaining = count
                return (true, count == 0)
            case MessageType.error.rawValue:
                // An agent without `capabilities.desktopWindows` does not know the request.
                return (false, true)
            default:
                return (false, false)
            }
        }

        guard type == MessageType.windowCreated.rawValue else {
            return (false, false)
        }
        self.remaining = remaining - 1
        return (true, remaining <= 1)
    }
}
