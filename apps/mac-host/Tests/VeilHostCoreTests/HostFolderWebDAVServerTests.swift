import Darwin
import Foundation
import Testing
@testable import VeilHostCore

/// Talks to the server over a raw loopback socket so the tests control exactly what goes on the wire: URL
/// loading systems normalise `..` away and add headers of their own.
@Suite("Host folder WebDAV server")
struct HostFolderWebDAVServerTests {
    private static let token = "t0k3n-ABC"

    struct Reply {
        let status: Int
        let headers: [String: String]
        let body: Data

        var text: String { String(decoding: body, as: UTF8.self) }
    }

    /// A shared folder and a running server, torn down together.
    final class Fixture {
        let base: URL
        let root: URL
        let server: HostFolderWebDAVServer
        let port: UInt16

        init(readOnly: Bool = false) throws {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("veil-webdav-\(UUID().uuidString)", isDirectory: true)
            root = base.appendingPathComponent("shared", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            server = HostFolderWebDAVServer(root: root, token: HostFolderWebDAVServerTests.token, readOnly: readOnly)
            port = try server.start()
        }

        deinit {
            server.stop()
            try? FileManager.default.removeItem(at: base)
        }

        func write(_ name: String, _ contents: String) throws {
            try Data(contents.utf8).write(to: root.appendingPathComponent(name))
        }

        /// Sends raw bytes and reads every response until the server closes the connection.
        func exchange(_ raw: Data) throws -> [Reply] {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            #expect(fd >= 0)
            defer { close(fd) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            try #require(connected == 0)
            try raw.withUnsafeBytes { bytes in
                var sent = 0
                while sent < bytes.count {
                    let n = Darwin.send(fd, bytes.baseAddress! + sent, bytes.count - sent, 0)
                    try #require(n > 0)
                    sent += n
                }
            }
            var received = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = recv(fd, &chunk, chunk.count, 0)
                if n <= 0 { break }
                received.append(contentsOf: chunk[0..<n])
            }
            return try Self.parse(received)
        }

        func request(
            _ method: String,
            _ path: String,
            headers: [String: String] = [:],
            body: Data = Data()
        ) throws -> Reply {
            var head = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n"
            for (name, value) in headers {
                head += "\(name): \(value)\r\n"
            }
            if !body.isEmpty || method == "PUT" {
                head += "Content-Length: \(body.count)\r\n"
            }
            head += "\r\n"
            let replies = try exchange(Data(head.utf8) + body)
            return try #require(replies.first)
        }

        static func parse(_ data: Data) throws -> [Reply] {
            var replies: [Reply] = []
            var rest = data
            let separator = Data("\r\n\r\n".utf8)
            while let end = rest.range(of: separator) {
                let head = String(decoding: rest[rest.startIndex..<end.lowerBound], as: UTF8.self)
                rest = Data(rest[end.upperBound...])
                let lines = head.components(separatedBy: "\r\n")
                let status = Int(lines[0].split(separator: " ")[1]) ?? 0
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                // HEAD replies carry a Content-Length but no body; none of the tests pipeline a HEAD.
                let length = Int(headers["content-length"] ?? "0") ?? 0
                try #require(rest.count >= length)
                replies.append(Reply(status: status, headers: headers, body: Data(rest.prefix(length))))
                rest = Data(rest.dropFirst(length))
            }
            return replies
        }
    }

    private static func hrefs(_ xml: String) -> [String] {
        xml.components(separatedBy: "<D:href>").dropFirst().compactMap { $0.components(separatedBy: "</D:href>").first }
    }

    @Test("skips a flood of blank lines before a request without recursing")
    func skipsBlankLinesBeforeARequest() throws {
        let fixture = try Fixture()
        try fixture.write("note.txt", "hello")
        // 100,000 blank lines, sent before any token is checked.
        var raw = Data(repeating: 0, count: 200_000)
        for index in stride(from: 0, to: raw.count, by: 2) {
            raw[index] = 0x0D
            raw[index + 1] = 0x0A
        }
        raw.append(Data("GET /\(Self.token)/note.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".utf8))

        let replies = try fixture.exchange(raw)

        #expect(replies.first?.status == 200)
        #expect(replies.first.map { String(decoding: $0.body, as: UTF8.self) } == "hello")
    }

    @Test("binds to loopback and returns a real port")
    func startsOnLoopback() throws {
        let fixture = try Fixture()
        #expect(fixture.port != 0)
        #expect(throws: HostFolderWebDAVServer.StartError.alreadyStarted) {
            try fixture.server.start()
        }
    }

    @Test("is not reachable through the Mac's other addresses")
    func notReachableOffLoopback() throws {
        let fixture = try Fixture()
        // Connecting to one of this Mac's own interface addresses never leaves the machine, but it is exactly
        // the path another device on the network would take.
        var list: UnsafeMutablePointer<ifaddrs>?
        try #require(getifaddrs(&list) == 0)
        defer { freeifaddrs(list) }
        var cursor = list
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            guard ipv4.sin_addr.s_addr != inet_addr("127.0.0.1") else { continue }
            ipv4.sin_port = fixture.port.bigEndian
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            let result = withUnsafePointer(to: &ipv4) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(fd)
            #expect(result != 0)
        }
    }

    @Test("refuses an unsafe token")
    func refusesUnsafeToken() throws {
        let server = HostFolderWebDAVServer(root: FileManager.default.temporaryDirectory, token: "a/b")
        #expect(throws: HostFolderWebDAVServer.StartError.invalidToken) {
            try server.start()
        }
    }

    @Test("a wrong or missing token is 404")
    func wrongToken() throws {
        let fixture = try Fixture()
        try fixture.write("a.txt", "hello")
        #expect(try fixture.request("GET", "/wrong/a.txt").status == 404)
        #expect(try fixture.request("GET", "/a.txt").status == 404)
        #expect(try fixture.request("PROPFIND", "/", headers: ["Depth": "1"]).status == 404)
        #expect(try fixture.request("PROPFIND", "/\(Self.token)x/", headers: ["Depth": "1"]).status == 404)
        #expect(try fixture.request("PUT", "/wrong/b.txt", body: Data("x".utf8)).status == 404)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("b.txt").path))
    }

    @Test("OPTIONS advertises WebDAV")
    func options() throws {
        let fixture = try Fixture()
        let reply = try fixture.request("OPTIONS", "/\(Self.token)/")
        #expect(reply.status == 200)
        #expect(reply.headers["dav"] == "1, 2")
        #expect(reply.headers["ms-author-via"] == "DAV")
        #expect(reply.headers["allow"]?.contains("PROPFIND") == true)
    }

    @Test("PROPFIND depth 1 lists children with their sizes")
    func propfindDepthOne() throws {
        let fixture = try Fixture()
        try fixture.write("a.txt", "hello")
        try fixture.write("b & <c>.bin", String(repeating: "x", count: 1234))
        try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("sub dir"), withIntermediateDirectories: false)

        let reply = try fixture.request("PROPFIND", "/\(Self.token)/", headers: ["Depth": "1"])
        #expect(reply.status == 207)
        let xml = reply.text
        #expect(Self.hrefs(xml) == [
            "/\(Self.token)/",
            "/\(Self.token)/a.txt",
            "/\(Self.token)/b%20%26%20%3Cc%3E.bin",
            "/\(Self.token)/sub%20dir/",
        ])
        #expect(xml.contains("<D:displayname>b &amp; &lt;c&gt;.bin</D:displayname>"))
        #expect(xml.contains("<D:getcontentlength>5</D:getcontentlength>"))
        #expect(xml.contains("<D:getcontentlength>1234</D:getcontentlength>"))
        #expect(xml.contains("<D:resourcetype><D:collection/></D:resourcetype>"))
        #expect(xml.contains("Win32FileAttributes"))
        #expect(xml.contains(" GMT</D:getlastmodified>"))
        #expect((try? XMLDocument(data: reply.body)) != nil)

        let depthZero = try fixture.request("PROPFIND", "/\(Self.token)", headers: ["Depth": "0"])
        #expect(Self.hrefs(depthZero.text) == ["/\(Self.token)/"])
        #expect(try fixture.request("PROPFIND", "/\(Self.token)/missing", headers: ["Depth": "0"]).status == 404)
    }

    @Test("PUT then GET returns the same bytes, chunked uploads included")
    func putGetRoundTrip() throws {
        let fixture = try Fixture()
        let payload = Data((0..<300_000).map { UInt8($0 % 251) })
        #expect(try fixture.request("PUT", "/\(Self.token)/data.bin", body: payload).status == 201)
        let get = try fixture.request("GET", "/\(Self.token)/data.bin")
        #expect(get.status == 200)
        #expect(get.body == payload)

        let head = "PUT /\(Self.token)/data.bin HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        let chunked = Data(head.utf8) + Data("5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\n\r\n".utf8)
        #expect(try fixture.exchange(chunked).first?.status == 204)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("data.bin"), encoding: .utf8) == "hello world")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        #expect(leftovers == ["data.bin"])
    }

    @Test("keeps the connection open across pipelined requests")
    func keepAlive() throws {
        let fixture = try Fixture()
        try fixture.write("a.txt", "one")
        let first = "GET /\(Self.token)/a.txt HTTP/1.1\r\nHost: x\r\n\r\n"
        let second = "PROPFIND /\(Self.token)/a.txt HTTP/1.1\r\nHost: x\r\nDepth: 0\r\nConnection: close\r\n\r\n"
        let replies = try fixture.exchange(Data((first + second).utf8))
        #expect(replies.map(\.status) == [200, 207])
        #expect(replies.first?.text == "one")
        #expect(replies.first?.headers["connection"] == "keep-alive")
    }

    @Test("MKCOL, MOVE and DELETE")
    func mkcolMoveDelete() throws {
        let fixture = try Fixture()
        try fixture.write("a.txt", "hello")
        let base = "http://127.0.0.1:\(fixture.port)/\(Self.token)"

        #expect(try fixture.request("MKCOL", "/\(Self.token)/folder").status == 201)
        #expect(try fixture.request("MKCOL", "/\(Self.token)/folder").status == 405)
        #expect(try fixture.request("MKCOL", "/\(Self.token)/missing/child").status == 409)

        let move = try fixture.request("MOVE", "/\(Self.token)/a.txt", headers: ["Destination": "\(base)/folder/b%20c.txt"])
        #expect(move.status == 201)
        let moved = fixture.root.appendingPathComponent("folder/b c.txt")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("a.txt").path))

        try fixture.write("other.txt", "other")
        let refused = try fixture.request("MOVE", "/\(Self.token)/other.txt", headers: [
            "Destination": "\(base)/folder/b%20c.txt",
            "Overwrite": "F",
        ])
        #expect(refused.status == 412)
        let copy = try fixture.request("COPY", "/\(Self.token)/other.txt", headers: ["Destination": "\(base)/folder/b%20c.txt"])
        #expect(copy.status == 204)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "other")

        let outside = try fixture.request("MOVE", "/\(Self.token)/other.txt", headers: ["Destination": "http://127.0.0.1/wrong/x.txt"])
        #expect(outside.status == 403)
        let escape = try fixture.request("COPY", "/\(Self.token)/other.txt", headers: ["Destination": "\(base)/../x.txt"])
        #expect(escape.status == 403)

        #expect(try fixture.request("DELETE", "/\(Self.token)/folder").status == 204)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("folder").path))
        #expect(try fixture.request("DELETE", "/\(Self.token)/folder").status == 404)
        #expect(try fixture.request("DELETE", "/\(Self.token)/").status == 403)
        #expect(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    @Test("refuses paths that leave the shared folder")
    func pathTraversal() throws {
        let fixture = try Fixture()
        let outside = fixture.base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try Data("secret".utf8).write(to: fixture.base.appendingPathComponent("x"))
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("dirlink"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("filelink"),
            withDestinationURL: outside.appendingPathComponent("secret.txt")
        )
        try fixture.write("inside.txt", "fine")
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("innerlink"),
            withDestinationURL: fixture.root.appendingPathComponent("inside.txt")
        )

        #expect(try fixture.request("GET", "/\(Self.token)/../x").status == 403)
        #expect(try fixture.request("GET", "/\(Self.token)/%2e%2e/x").status == 403)
        #expect(try fixture.request("GET", "/\(Self.token)/dirlink/secret.txt").status == 403)
        #expect(try fixture.request("GET", "/\(Self.token)/filelink").status == 403)
        #expect(try fixture.request("PUT", "/\(Self.token)/dirlink/new.txt", body: Data("x".utf8)).status == 403)
        #expect(try fixture.request("MKCOL", "/\(Self.token)/dirlink/deeper").status == 403)
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("new.txt").path))
        #expect(try fixture.request("GET", "/\(Self.token)/innerlink").text == "fine")

        let listing = try fixture.request("PROPFIND", "/\(Self.token)/", headers: ["Depth": "1"]).text
        #expect(!listing.contains("dirlink"))
        #expect(!listing.contains("filelink"))
        #expect(listing.contains("innerlink"))
    }

    @Test("read-only refuses every change")
    func readOnly() throws {
        let fixture = try Fixture(readOnly: true)
        try fixture.write("a.txt", "hello")
        #expect(try fixture.request("PUT", "/\(Self.token)/b.txt", body: Data("x".utf8)).status == 403)
        #expect(try fixture.request("DELETE", "/\(Self.token)/a.txt").status == 403)
        #expect(try fixture.request("MKCOL", "/\(Self.token)/d").status == 403)
        #expect(try fixture.request("LOCK", "/\(Self.token)/a.txt").status == 403)
        #expect(try fixture.request("GET", "/\(Self.token)/a.txt").text == "hello")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["a.txt"])
    }

    @Test("Range GET returns the requested slice")
    func rangeGet() throws {
        let fixture = try Fixture()
        try fixture.write("digits.txt", "0123456789")
        let middle = try fixture.request("GET", "/\(Self.token)/digits.txt", headers: ["Range": "bytes=2-5"])
        #expect(middle.status == 206)
        #expect(middle.text == "2345")
        #expect(middle.headers["content-range"] == "bytes 2-5/10")
        #expect(try fixture.request("GET", "/\(Self.token)/digits.txt", headers: ["Range": "bytes=-3"]).text == "789")
        #expect(try fixture.request("GET", "/\(Self.token)/digits.txt", headers: ["Range": "bytes=7-"]).text == "789")
        let beyond = try fixture.request("GET", "/\(Self.token)/digits.txt", headers: ["Range": "bytes=20-"])
        #expect(beyond.status == 416)
        #expect(beyond.headers["content-range"] == "bytes */10")
    }

    @Test("LOCK hands out a token, PROPPATCH and UNLOCK succeed")
    func lockAndPropPatch() throws {
        let fixture = try Fixture()
        let lock = try fixture.request("LOCK", "/\(Self.token)/new.docx", headers: ["Depth": "0"], body: Data("""
        <?xml version="1.0"?><D:lockinfo xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope>\
        <D:locktype><D:write/></D:locktype></D:lockinfo>
        """.utf8))
        #expect(lock.status == 201)
        #expect(lock.headers["lock-token"]?.hasPrefix("<opaquelocktoken:") == true)
        #expect(lock.text.contains("<D:lockdiscovery>"))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("new.docx").path))

        let patch = try fixture.request("PROPPATCH", "/\(Self.token)/new.docx", body: Data("""
        <?xml version="1.0" encoding="utf-8"?><D:propertyupdate xmlns:D="DAV:" xmlns:Z="urn:schemas-microsoft-com:">\
        <D:set><D:prop><Z:Win32LastModifiedTime>Wed, 01 Jan 2025 00:00:00 GMT</Z:Win32LastModifiedTime>\
        <Z:Win32FileAttributes>00000020</Z:Win32FileAttributes></D:prop></D:set></D:propertyupdate>
        """.utf8))
        #expect(patch.status == 207)
        #expect(patch.text.contains("Win32LastModifiedTime"))
        #expect(patch.text.contains("Win32FileAttributes"))
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.root.appendingPathComponent("new.docx").path)
        #expect((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 == 1_735_689_600)

        let unlock = try fixture.request("UNLOCK", "/\(Self.token)/new.docx", headers: ["Lock-Token": lock.headers["lock-token"] ?? ""])
        #expect(unlock.status == 204)
    }
}
