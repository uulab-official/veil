import Darwin
import Foundation
import Testing

@testable import VeilHostCore

@Suite("QEMU tablet position sync")
struct QEMUTabletPositionSyncTests {
    @Test("sends each move on its own QMP connection and lets the next client in")
    func releasesTheQMPSocketAfterEachMove() async throws {
        let path = NSTemporaryDirectory() + "veil-qmp-\(UUID().uuidString.prefix(8)).sock"
        let server = try FakeQMPServer(path: path)
        defer { server.stop() }

        QEMUTabletPositionSync.send(#"{"execute":"input-send-event","n":1}"#, toSocketAt: path)
        QEMUTabletPositionSync.send(#"{"execute":"input-send-event","n":2}"#, toSocketAt: path)

        // QMP serves one client at a time; both moves landing proves the first connection was closed.
        let connections = server.waitForConnections(2)
        #expect(connections.count == 2)
        #expect(connections.allSatisfy { $0.contains("qmp_capabilities") })
        #expect(connections.first?.contains(#""n":1"#) == true)
        #expect(connections.last?.contains(#""n":2"#) == true)
    }
}

/// A one-client-at-a-time QMP stand-in that greets, answers each line with a return, and records what
/// every connection sent.
private final class FakeQMPServer: @unchecked Sendable {
    private let descriptor: Int32
    private let path: String
    private let lock = NSLock()
    private var received: [String] = []
    private var stopped = false

    init(path: String) throws {
        self.path = path
        unlink(path)
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            throw POSIXError(.EADDRINUSE)
        }
        let listener = descriptor
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                self?.serve(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        _ = #"{"QMP": {"version": {}}}"#.withCString { write(client, $0, strlen($0)) }
        var text = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            let chunk = String(decoding: buffer[0..<count], as: UTF8.self)
            text += chunk
            for _ in 0..<chunk.filter({ $0 == "\n" }).count {
                _ = "{\"return\": {}}\n".withCString { write(client, $0, strlen($0)) }
            }
        }
        close(client)
        lock.lock()
        received.append(text)
        lock.unlock()
    }

    func waitForConnections(_ count: Int) -> [String] {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            lock.lock()
            let snapshot = received
            lock.unlock()
            if snapshot.count >= count {
                return snapshot
            }
            usleep(10_000)
        }
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func stop() {
        close(descriptor)
        unlink(path)
    }
}
