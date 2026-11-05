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
        to continuation: AsyncThrowingStream<Data, any Error>.Continuation
    ) -> Bool {
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

    public func eventMessages() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream(
            Data.self,
            bufferingPolicy: .bufferingNewest(Self.eventBufferMessageCount)
        ) { continuation in
            let task = session.webSocketTask(with: url)
            task.maximumMessageSize = Self.maximumMessageByteCount
            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel(with: .normalClosure, reason: nil)
            }

            Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .data(let data):
                            guard Self.yieldEventMessage(data, to: continuation) else { return }
                        case .string(let text):
                            guard Self.yieldEventMessage(Data(text.utf8), to: continuation) else { return }
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
