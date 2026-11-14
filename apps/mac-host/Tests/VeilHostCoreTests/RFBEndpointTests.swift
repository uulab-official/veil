import Darwin
import Foundation
import Testing
@testable import VeilHostCore

@Suite("QEMU display endpoint")
struct RFBEndpointTests {
    @Test("Endpoints parse from text and from a launch record's fields")
    func parses() {
        #expect(RFBEndpoint("unix:/tmp/vq-1.vnc.sock") == .unix(path: "/tmp/vq-1.vnc.sock"))
        #expect(RFBEndpoint("127.0.0.1:5907") == .tcp(host: "127.0.0.1", port: 5_907))
        #expect(RFBEndpoint("unix:relative.sock") == nil)
        #expect(RFBEndpoint("127.0.0.1:0") == nil)
        #expect(RFBEndpoint("nonsense") == nil)
        #expect(RFBEndpoint("unix:/tmp/a.sock")?.description == "unix:/tmp/a.sock")

        #expect(RFBEndpoint(socketPath: "/tmp/a.sock", host: "127.0.0.1", port: 5_907) == .unix(path: "/tmp/a.sock"))
        #expect(RFBEndpoint(socketPath: nil, host: "127.0.0.1", port: 5_907) == .tcp(host: "127.0.0.1", port: 5_907))
        #expect(RFBEndpoint(socketPath: nil, host: " ", port: 5_907) == nil)
        #expect(RFBEndpoint(socketPath: nil, host: nil, port: nil) == nil)
    }

    @Test("Console evidence offers the socket as the live display")
    func evidenceUsesSocket() {
        let evidence = VMConsoleLaunchEvidence(
            provider: "QEMU/HVF",
            pid: 1,
            processLogPath: "/tmp/q.log",
            monitorSocketPath: "/tmp/m.sock",
            vncSocketPath: "/tmp/vq-1.vnc.sock",
            consoleScreenshotPath: nil,
            startedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(evidence.displaySurface.kind == .vncLoopback)
        #expect(evidence.displaySurface.endpoint == "unix:/tmp/vq-1.vnc.sock")
    }

    @Test("The display connection reads the server's greeting over a Unix socket")
    func connectsOverUnixSocket() throws {
        let path = "/tmp/vq-test-\(UUID().uuidString.prefix(8)).vnc.sock"
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(server >= 0)
        defer {
            close(server)
            unlink(path)
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        #expect(listen(server, 1) == 0)

        let greeting = Data("RFB 003.008\n".utf8)
        let accepted = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let connection = accept(server, nil, nil)
            greeting.withUnsafeBytes { _ = write(connection, $0.baseAddress, greeting.count) }
            accepted.wait()
            close(connection)
        }

        let client = try RFBLoopbackSocket(endpoint: .unix(path: path), timeoutSeconds: 2)
        #expect(try client.readExactly(12) == greeting)
        client.close()
        accepted.signal()
    }

    @Test("A missing socket fails to connect instead of hanging")
    func missingSocketFails() {
        #expect(throws: RFBLoopbackSocketError.self) {
            try RFBLoopbackSocket(endpoint: .unix(path: "/tmp/vq-missing-\(UUID().uuidString.prefix(8)).sock"), timeoutSeconds: 1)
        }
    }
}
