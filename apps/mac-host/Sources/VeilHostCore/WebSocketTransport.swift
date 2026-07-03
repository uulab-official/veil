import Foundation

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
        let task = session.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        try await task.send(.data(message))

        var replies: [Data] = []
        for _ in 0..<expectedReplies {
            switch try await task.receive() {
            case .data(let data):
                replies.append(data)
            case .string(let text):
                replies.append(Data(text.utf8))
            @unknown default:
                throw VeilHostError.missingReply("unsupported websocket message type")
            }
        }

        return replies
    }

    public func eventMessages() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let task = session.webSocketTask(with: url)
            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel(with: .normalClosure, reason: nil)
            }

            Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .data(let data):
                            continuation.yield(data)
                        case .string(let text):
                            continuation.yield(Data(text.utf8))
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
