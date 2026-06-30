import Foundation

public struct URLSessionWebSocketTransport: HostTransport {
    private let url: URL
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
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
}
