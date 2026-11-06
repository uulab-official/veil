import Foundation

/// Receives window frames as raw binary on a dedicated connection.
///
/// Separate from `HostEventSource` on purpose. Frames are large and frequent; sharing a TCP stream with
/// control messages puts a frame in front of the next `input.key`, which is precisely the delay a user
/// perceives as sluggish. A dedicated connection lets input overtake a frame in flight.
/// A decoded frame update plus what it cost to deliver.
///
/// The wire size is carried alongside rather than on `WindowFrameTile` itself, so the tile stays a pure
/// description of pixels while throughput measurement still has the number it needs.
public struct WindowFrameChannelMessage: Equatable, Sendable {
    public var tile: WindowFrameTile
    /// Size of the full encoded message including its header, which is what actually crossed the wire.
    public var wireByteCount: Int

    public init(tile: WindowFrameTile, wireByteCount: Int) {
        self.tile = tile
        self.wireByteCount = wireByteCount
    }
}

public protocol HostFrameChannel: Sendable {
    /// Yields frame updates, which may be key frames or dirty-rect tiles. Callers must route these through
    /// a `WindowFrameCompositor` rather than treating a tile as a displayable frame.
    func frames() -> AsyncThrowingStream<WindowFrameChannelMessage, any Error>
}

public enum HostFrameChannelError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedEndpoint(String)
    case tooManyMalformedFrames(Int)
    case bufferOverflow(windowId: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedEndpoint(let endpoint):
            "Cannot derive a binary frame channel endpoint from '\(endpoint)'."
        case .tooManyMalformedFrames(let count):
            "The Windows agent sent \(count) consecutive undecodable frames on the binary frame channel."
        case .bufferOverflow(let windowId):
            "The binary frame channel could not keep up with updates for \(windowId); the window needs a fresh key frame."
        }
    }
}

public struct URLSessionFrameChannel: HostFrameChannel {
    /// Path the guest routes to its send-only binary frame channel.
    public static let path = "/frames"

    /// Consecutive undecodable messages tolerated before giving up.
    ///
    /// One corrupt frame should not freeze a mirrored window, but a persistent framing disagreement
    /// between host and guest has to surface rather than silently producing a window that never updates.
    public static let malformedFrameTolerance = 8

    private let url: URL
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// Derives the frame channel endpoint from the agent control endpoint.
    ///
    /// Returns `nil` for anything that is not a WebSocket URL, so a misconfigured endpoint fails closed
    /// onto the JSON frame path instead of opening a connection to somewhere unexpected.
    public static func frameChannelURL(agentEndpoint: String) -> URL? {
        let trimmed = agentEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// How many undelivered frame messages the channel will hold.
    ///
    /// The default `AsyncThrowingStream` buffering policy is `.unbounded`, which is a memory leak waiting for
    /// a fast guest. The consumer is `@MainActor` and rebuilds an `NSHostingView` per frame, so it is
    /// comfortably slower than a loopback socket — the buffer grows monotonically, each element retaining its
    /// PNG payload, and display latency grows with it. No malformed data needed; a merely busy guest does it.
    ///
    /// Bounded generously rather than tightly, because frame tiles are **incremental**: dropping one leaves
    /// its rectangle stale until the next key frame. Overflow is therefore treated as a recoverable stream
    /// fault rather than a routine throttle: the caller receives `bufferOverflow`, resets that window's
    /// subscription, and lets the guest establish a new key frame.
    public static let frameBufferMessageCount = 256

    /// Enqueues one decoded message and turns a dropped incremental update into a scoped recovery error.
    /// Kept separate from the URLSession receive loop so the overflow contract is deterministic to test.
    static func yieldFrameMessage(
        _ message: WindowFrameChannelMessage,
        to continuation: AsyncThrowingStream<WindowFrameChannelMessage, any Error>.Continuation
    ) -> Bool {
        switch continuation.yield(message) {
        case .enqueued:
            return true
        case .dropped(let dropped):
            continuation.finish(
                throwing: HostFrameChannelError.bufferOverflow(windowId: dropped.tile.windowId)
            )
            return false
        case .terminated:
            return false
        @unknown default:
            continuation.finish(
                throwing: HostFrameChannelError.bufferOverflow(windowId: message.tile.windowId)
            )
            return false
        }
    }

    public func frames() -> AsyncThrowingStream<WindowFrameChannelMessage, any Error> {
        AsyncThrowingStream(
            WindowFrameChannelMessage.self,
            bufferingPolicy: .bufferingNewest(Self.frameBufferMessageCount)
        ) { continuation in
            let task = session.webSocketTask(with: url)
            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel(with: .normalClosure, reason: nil)
            }

            Task {
                var consecutiveMalformedFrames = 0
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard case .data(let data) = message else {
                            // The frame channel is binary only. A text message means the guest is sending
                            // something this channel was not designed for; ignore it rather than trying to
                            // interpret it as an image.
                            continue
                        }

                        do {
                            let message = WindowFrameChannelMessage(
                                tile: try VeilFrameChannelCodec.decode(data),
                                wireByteCount: data.count
                            )
                            guard Self.yieldFrameMessage(message, to: continuation) else {
                                return
                            }
                            consecutiveMalformedFrames = 0
                        } catch {
                            consecutiveMalformedFrames += 1
                            VeilLog.agent.error(
                                "Discarding an undecodable binary frame: \(String(describing: error))"
                            )
                            if consecutiveMalformedFrames >= Self.malformedFrameTolerance {
                                continuation.finish(
                                    throwing: HostFrameChannelError.tooManyMalformedFrames(consecutiveMalformedFrames)
                                )
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
