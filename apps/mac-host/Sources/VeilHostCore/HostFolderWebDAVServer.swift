import Darwin
import Foundation
import Network

/// Serves one Mac folder to the Windows guest over WebDAV, so it can be mounted with the built-in redirector
/// (`net use Z: \\10.0.2.2@PORT\TOKEN`).
///
/// QEMU usermode networking lets the guest reach the host's loopback at 10.0.2.2, so the listener binds to
/// 127.0.0.1 only: nothing else on the Mac's networks can reach the folder. Plain HTTP means the Windows
/// WebClient refuses Basic auth, so the first path segment is the only credential. It is compared in constant
/// time and every request without it is answered 404 before any file is looked at.
///
/// All file access is confined to `root` after resolving symlinks, because the guest controls every path and a
/// symlink inside the shared folder must not become a way out of it.
public final class HostFolderWebDAVServer: @unchecked Sendable {
    public enum StartError: Error, Equatable {
        case alreadyStarted
        case invalidToken
        case invalidRoot
        case invalidPort
        case listenerFailed(String)
        case timedOut
    }

    public let root: URL
    public let token: String
    public let readOnly: Bool

    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: WebDAVConnection] = [:]
    private let listenerQueue = DispatchQueue(label: "veil.webdav.listener")

    public init(root: URL, token: String, readOnly: Bool = false) {
        self.root = root
        self.token = token
        self.readOnly = readOnly
    }

    deinit {
        stop()
    }

    /// Starts listening on 127.0.0.1 and returns the bound port (useful when `port` is 0).
    @discardableResult
    public func start(port: UInt16 = 0) throws -> UInt16 {
        // The token ends up in a UNC path and in every href we emit, so keep it to characters that need no
        // escaping anywhere. That also rules out a token that could smuggle a path separator.
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard !token.isEmpty, token != ".", token != "..", token.allSatisfy({ allowed.contains($0) }) else {
            throw StartError.invalidToken
        }
        guard let rootReal = WebDAVPaths.realPath(root.path),
              WebDAVPaths.info(rootReal)?.isDirectory == true else {
            throw StartError.invalidRoot
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw StartError.invalidPort
        }

        lock.lock()
        let alreadyStarted = listener != nil
        lock.unlock()
        if alreadyStarted {
            throw StartError.alreadyStarted
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        parameters.acceptLocalOnly = true
        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters)
        } catch {
            throw StartError.listenerFailed(String(describing: error))
        }

        let context = WebDAVContext(rootURL: root, rootReal: rootReal, token: token, readOnly: readOnly)
        let outcome = WebDAVStartOutcome()
        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                outcome.resolve(nil)
            case .failed(let error), .waiting(let error):
                outcome.resolve(String(describing: error))
            case .cancelled:
                outcome.resolve("cancelled")
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, context: context)
        }
        newListener.start(queue: listenerQueue)

        guard outcome.semaphore.wait(timeout: .now() + 5) == .success else {
            newListener.cancel()
            throw StartError.timedOut
        }
        if let failure = outcome.failure {
            newListener.cancel()
            throw StartError.listenerFailed(failure)
        }
        guard let boundPort = newListener.port?.rawValue, boundPort != 0 else {
            newListener.cancel()
            throw StartError.listenerFailed("no port")
        }

        lock.lock()
        listener = newListener
        lock.unlock()
        return boundPort
    }

    /// Stops listening and drops every open connection. Uploads in flight lose their temporary files.
    public func stop() {
        lock.lock()
        let current = listener
        listener = nil
        let open = Array(connections.values)
        connections.removeAll()
        lock.unlock()

        current?.cancel()
        for connection in open {
            connection.cancel()
        }
    }

    private func accept(_ connection: NWConnection, context: WebDAVContext) {
        let handler = WebDAVConnection(connection: connection, context: context) { [weak self] id in
            guard let self else { return }
            self.lock.lock()
            self.connections.removeValue(forKey: id)
            self.lock.unlock()
        }
        lock.lock()
        let running = listener != nil
        if running {
            connections[ObjectIdentifier(handler)] = handler
        }
        lock.unlock()
        if running {
            handler.start()
        } else {
            connection.cancel()
        }
    }
}

/// Carries the listener's first state change back to the thread blocked in `start`.
private final class WebDAVStartOutcome: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var resolved = false
    private(set) var failure: String?

    func resolve(_ failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return }
        resolved = true
        self.failure = failure
        semaphore.signal()
    }
}

struct WebDAVContext: Sendable {
    let rootURL: URL
    let rootReal: String
    let token: String
    let readOnly: Bool
}

// MARK: - Paths

/// A request path that has passed the token check and the confinement check.
struct WebDAVTarget {
    let url: URL
    let segments: [String]

    func href(token: String, isDirectory: Bool) -> String {
        var href = "/" + WebDAVPaths.encode(token) + "/"
        href += segments.map(WebDAVPaths.encode).joined(separator: "/")
        if isDirectory, !segments.isEmpty {
            href += "/"
        }
        return href
    }

    func child(_ name: String) -> WebDAVTarget {
        WebDAVTarget(url: url.appendingPathComponent(name, isDirectory: false), segments: segments + [name])
    }
}

struct WebDAVFileInfo {
    let isDirectory: Bool
    let size: UInt64
    let modified: Date
    let created: Date
}

enum WebDAVPaths {
    /// Prefix of in-progress uploads. Hidden from listings so Explorer never shows a half-written file.
    static let uploadPrefix = ".veil-upload-"

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference: UInt8 = left.count == right.count ? 0 : 1
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            difference |= a ^ b
        }
        return difference == 0
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Follows symlinks, so a link that stays inside the root reports what it points at.
    static func info(_ path: String) -> WebDAVFileInfo? {
        var status = Darwin.stat()
        guard stat(path, &status) == 0 else { return nil }
        return WebDAVFileInfo(
            isDirectory: (status.st_mode & S_IFMT) == S_IFDIR,
            size: UInt64(max(0, status.st_size)),
            modified: date(status.st_mtimespec),
            created: date(status.st_birthtimespec)
        )
    }

    static func exists(_ path: String) -> Bool {
        var status = Darwin.stat()
        return Darwin.lstat(path, &status) == 0
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Whether `url` (or, if it does not exist yet, its nearest existing ancestor) resolves inside the root.
    ///
    /// Checking the nearest existing ancestor rather than only the parent matters for paths like
    /// `link/new/file`: `link/new` does not exist, but `link` might point outside.
    static func isConfined(_ url: URL, rootReal: String, rootURL: URL) -> Bool {
        var candidate = url
        let rootPath = rootURL.standardizedFileURL.path
        while !exists(candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path || candidate.standardizedFileURL.path == rootPath {
                return false
            }
            candidate = parent
        }
        // A dangling symlink fails realpath and is refused: we cannot tell where it would lead.
        guard let real = realPath(candidate.path) else { return false }
        return real == rootReal || real.hasPrefix(rootReal == "/" ? "/" : rootReal + "/")
    }
}

// MARK: - XML and dates

enum WebDAVFormat {
    static let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
            default:
                // Control characters are not representable in XML 1.0; one in a file name must not make the
                // whole listing unparseable for Windows.
                if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF {
                    result += "\u{FFFD}"
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    static func contentType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "txt", "log", "md": return "text/plain"
        case "html", "htm": return "text/html"
        case "xml": return "application/xml"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }

    static func etag(_ info: WebDAVFileInfo) -> String {
        let modified = UInt64(max(0, info.modified.timeIntervalSince1970 * 1_000_000))
        return "\"\(String(info.size, radix: 16))-\(String(modified, radix: 16))\""
    }
}

/// Collects the property names a PROPPATCH names, and the Win32 modification time if it sets one.
private final class WebDAVPropPatchParser: NSObject, XMLParserDelegate {
    struct Property {
        let namespace: String
        let name: String
    }

    private(set) var properties: [Property] = []
    private(set) var lastModified: String?
    private var stack: [(namespace: String, name: String)] = []
    private var capturing: String?

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let namespace = namespaceURI ?? ""
        if let parent = stack.last, parent.namespace == "DAV:", parent.name == "prop" {
            properties.append(Property(namespace: namespace, name: elementName))
            if namespace == "urn:schemas-microsoft-com:", elementName == "Win32LastModifiedTime" {
                capturing = ""
            }
        }
        stack.append((namespace, elementName))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing != nil {
            capturing! += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let captured = capturing, elementName == "Win32LastModifiedTime" {
            lastModified = captured.trimmingCharacters(in: .whitespacesAndNewlines)
            capturing = nil
        }
        _ = stack.popLast()
    }
}

// MARK: - Connection

private struct WebDAVRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let keepAlive: Bool

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

private struct WebDAVResponse {
    var status: Int
    var headers: [(String, String)] = []
    var body = Data()
    /// Streamed after the headers instead of `body`, so multi-gigabyte files never sit in memory.
    var file: (handle: FileHandle, length: UInt64)?
    var omitBody = false

    init(status: Int, headers: [(String, String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func xml(_ status: Int, _ xml: String, headers: [(String, String)] = []) -> WebDAVResponse {
        WebDAVResponse(
            status: status,
            headers: [("Content-Type", "text/xml; charset=\"utf-8\"")] + headers,
            body: Data(xml.utf8)
        )
    }
}

private struct WebDAVStatusError: Error {
    let status: Int
}

private enum WebDAVBodyError: Error {
    case tooLarge
    case malformed
    case writeFailed
}

/// Where a request body goes while it arrives.
private final class WebDAVBodySink {
    enum Kind {
        case collect(limit: Int)
        case discard
        case upload(handle: FileHandle, temporary: URL, destination: URL, existed: Bool)
    }

    let kind: Kind
    private(set) var data = Data()

    init(_ kind: Kind) {
        self.kind = kind
    }

    func write(_ chunk: Data) throws {
        switch kind {
        case .collect(let limit):
            guard data.count + chunk.count <= limit else { throw WebDAVBodyError.tooLarge }
            data.append(chunk)
        case .discard:
            break
        case .upload(let handle, _, _, _):
            do {
                try handle.write(contentsOf: chunk)
            } catch {
                throw WebDAVBodyError.writeFailed
            }
        }
    }

    /// Removes a temporary upload that will never be committed.
    func abandon() {
        if case .upload(let handle, let temporary, _, _) = kind {
            try? handle.close()
            unlink(temporary.path)
        }
    }
}

private enum WebDAVBodyState {
    case none
    case length(UInt64)
    case chunkSize
    case chunkData(UInt64)
    case chunkDataEnd
    case trailer
}

/// One HTTP/1.1 connection. Everything runs on its own serial queue, so the mutable state below is only touched
/// from there; a slow upload on one connection does not stall Explorer's other connections.
final class WebDAVConnection: @unchecked Sendable {
    private static let maximumHeaderBytes = 64 * 1024
    private static let maximumXMLBodyBytes = 1024 * 1024
    private static let receiveChunk = 256 * 1024
    private static let sendChunk = 256 * 1024
    private static let crlf = Data("\r\n".utf8)
    private static let headerEnd = Data("\r\n\r\n".utf8)

    private let connection: NWConnection
    private let context: WebDAVContext
    private let queue = DispatchQueue(label: "veil.webdav.connection")
    private let onClose: @Sendable (ObjectIdentifier) -> Void

    private var buffer = Data()
    private var closed = false
    private var request: WebDAVRequest?
    private var sink: WebDAVBodySink?
    private var bodyState = WebDAVBodyState.none
    private var pendingError: Int?

    init(connection: NWConnection, context: WebDAVContext, onClose: @escaping @Sendable (ObjectIdentifier) -> Void) {
        self.connection = connection
        self.context = context
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.async { self.readRequest() }
    }

    func cancel() {
        queue.async { self.finish() }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        sink?.abandon()
        sink = nil
        connection.cancel()
        onClose(ObjectIdentifier(self))
    }

    private func receiveMore(_ then: @escaping @Sendable () -> Void) {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunk) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                then()
            } else if isComplete || error != nil {
                self.finish()
            } else {
                self.receiveMore(then)
            }
        }
    }

    // MARK: Request parsing

    private func readRequest() {
        guard !closed else { return }
        guard let end = buffer.range(of: Self.headerEnd) else {
            if buffer.count > Self.maximumHeaderBytes {
                sendAndClose(WebDAVResponse(status: 431))
            } else {
                receiveMore { [weak self] in self?.readRequest() }
            }
            return
        }
        let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex..<end.upperBound)

        var lines = head.components(separatedBy: "\r\n")
        // Tolerate stray blank lines between pipelined requests, as RFC 9112 asks.
        while lines.first == "" { lines.removeFirst() }
        guard let requestLine = lines.first else {
            readRequest()
            return
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else {
            sendAndClose(WebDAVResponse(status: 400))
            return
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        let version = String(parts[2])
        let connectionHeader = headers["connection"]?.lowercased() ?? ""
        let keepAlive = version == "HTTP/1.1"
            ? !connectionHeader.contains("close")
            : connectionHeader.contains("keep-alive")
        let parsed = WebDAVRequest(method: String(parts[0]).uppercased(), target: String(parts[1]), headers: headers, keepAlive: keepAlive)

        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            bodyState = .chunkSize
        } else if let lengthText = headers["content-length"] {
            guard let length = UInt64(lengthText) else {
                sendAndClose(WebDAVResponse(status: 400))
                return
            }
            bodyState = length > 0 ? .length(length) : .none
        } else {
            bodyState = .none
        }
        request = parsed
        beginBody(parsed)
    }

    private func beginBody(_ request: WebDAVRequest) {
        pendingError = nil
        if request.method == "PUT" {
            switch prepareUpload(request) {
            case .success(let upload):
                sink = upload
            case .failure(let failure):
                pendingError = failure.status
                sink = WebDAVBodySink(.discard)
            }
        } else if context.readOnly, Self.mutatingMethods.contains(request.method) {
            pendingError = 403
            sink = WebDAVBodySink(.discard)
        } else {
            sink = WebDAVBodySink(.collect(limit: Self.maximumXMLBodyBytes))
        }

        let hasBody: Bool
        if case .none = bodyState { hasBody = false } else { hasBody = true }
        if hasBody, request.header("expect")?.lowercased() == "100-continue" {
            if let pendingError {
                // The client has not sent the body yet, so refuse now rather than pull in data we will drop.
                sendAndClose(WebDAVResponse(status: pendingError))
                return
            }
            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil { self.finish() } else { self.pumpBody() }
            })
            return
        }
        pumpBody()
    }

    private func pumpBody() {
        guard !closed, let sink else { return }
        do {
            while true {
                switch bodyState {
                case .none:
                    bodyComplete()
                    return
                case .length(let remaining):
                    if remaining == 0 {
                        bodyState = .none
                        continue
                    }
                    if buffer.isEmpty {
                        receiveMore { [weak self] in self?.pumpBody() }
                        return
                    }
                    let count = Int(min(remaining, UInt64(buffer.count)))
                    try sink.write(Data(buffer.prefix(count)))
                    buffer.removeFirst(count)
                    bodyState = .length(remaining - UInt64(count))
                case .chunkSize:
                    guard let line = takeLine() else {
                        try waitForLine()
                        return
                    }
                    let sizeText = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                    guard let size = UInt64(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else {
                        throw WebDAVBodyError.malformed
                    }
                    bodyState = size == 0 ? .trailer : .chunkData(size)
                case .chunkData(let remaining):
                    if remaining == 0 {
                        bodyState = .chunkDataEnd
                        continue
                    }
                    if buffer.isEmpty {
                        receiveMore { [weak self] in self?.pumpBody() }
                        return
                    }
                    let count = Int(min(remaining, UInt64(buffer.count)))
                    try sink.write(Data(buffer.prefix(count)))
                    buffer.removeFirst(count)
                    bodyState = .chunkData(remaining - UInt64(count))
                case .chunkDataEnd:
                    guard let line = takeLine() else {
                        try waitForLine()
                        return
                    }
                    guard line.isEmpty else { throw WebDAVBodyError.malformed }
                    bodyState = .chunkSize
                case .trailer:
                    guard let line = takeLine() else {
                        try waitForLine()
                        return
                    }
                    if line.isEmpty {
                        bodyState = .none
                    }
                }
            }
        } catch WebDAVBodyError.tooLarge {
            sendAndClose(WebDAVResponse(status: 413))
        } catch WebDAVBodyError.writeFailed {
            sendAndClose(WebDAVResponse(status: 507))
        } catch {
            sendAndClose(WebDAVResponse(status: 400))
        }
    }

    private func takeLine() -> String? {
        guard let end = buffer.range(of: Self.crlf) else { return nil }
        let line = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex..<end.upperBound)
        return line
    }

    private func waitForLine() throws {
        guard buffer.count < 8 * 1024 else { throw WebDAVBodyError.malformed }
        receiveMore { [weak self] in self?.pumpBody() }
    }

    private func bodyComplete() {
        guard let request, let sink else { return }
        if let pendingError {
            self.sink = nil
            sink.abandon()
            send(WebDAVResponse(status: pendingError))
            return
        }
        let response = handle(request, body: sink)
        self.sink = nil
        send(response)
    }

    // MARK: Sending

    private static func reason(_ status: Int) -> String {
        switch status {
        case 100: return "Continue"
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 207: return "Multi-Status"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 412: return "Precondition Failed"
        case 413: return "Content Too Large"
        case 416: return "Range Not Satisfiable"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 507: return "Insufficient Storage"
        default: return "Status"
        }
    }

    private func sendAndClose(_ response: WebDAVResponse) {
        send(response, forceClose: true)
    }

    private func send(_ response: WebDAVResponse, forceClose: Bool = false) {
        guard !closed else { return }
        let keepAlive = !forceClose && (request?.keepAlive ?? false)
        let length = response.file.map { $0.length } ?? UInt64(response.body.count)
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        head += "Date: \(WebDAVFormat.rfc1123.string(from: Date()))\r\n"
        head += "Server: Veil-WebDAV\r\n"
        for (name, value) in response.headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(length)\r\n"
        head += keepAlive ? "Connection: keep-alive\r\n" : "Connection: close\r\n"
        head += "\r\n"

        var first = Data(head.utf8)
        if !response.omitBody, response.file == nil {
            first.append(response.body)
        }
        let file = response.omitBody ? nil : response.file
        if response.omitBody, let handle = response.file?.handle {
            try? handle.close()
        }
        connection.send(content: first, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                if let handle = file?.handle { try? handle.close() }
                self.finish()
            } else if let file {
                self.stream(file.handle, remaining: file.length, keepAlive: keepAlive)
            } else {
                self.responseDone(keepAlive: keepAlive)
            }
        })
    }

    /// Sends the file a chunk at a time, waiting for each send to complete so a slow guest applies backpressure
    /// instead of the whole file piling up in memory.
    private func stream(_ handle: FileHandle, remaining: UInt64, keepAlive: Bool) {
        guard !closed else {
            try? handle.close()
            return
        }
        guard remaining > 0 else {
            try? handle.close()
            responseDone(keepAlive: keepAlive)
            return
        }
        let count = Int(min(remaining, UInt64(Self.sendChunk)))
        guard let chunk = try? handle.read(upToCount: count), !chunk.isEmpty else {
            // The file shrank under us. Content-Length is already on the wire, so the only honest thing left is
            // to drop the connection rather than let the guest read the next response as file data.
            try? handle.close()
            finish()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                try? handle.close()
                self.finish()
            } else {
                self.stream(handle, remaining: remaining - UInt64(chunk.count), keepAlive: keepAlive)
            }
        })
    }

    private func responseDone(keepAlive: Bool) {
        request = nil
        if keepAlive {
            readRequest()
        } else {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.finish()
            })
        }
    }

    // MARK: Path resolution

    private enum Resolution {
        case target(WebDAVTarget)
        case error(Int)
    }

    /// Strips an absolute-form or Destination URL down to its path.
    private static func pathPart(_ raw: String) -> String {
        var path = raw
        if let schemeEnd = path.range(of: "://") {
            let afterScheme = path[schemeEnd.upperBound...]
            path = afterScheme.firstIndex(of: "/").map { String(afterScheme[$0...]) } ?? "/"
        }
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<cut])
        }
        return path
    }

    private func tokenMatches(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let first = path.dropFirst().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let decoded = String(first).removingPercentEncoding ?? ""
        return WebDAVPaths.constantTimeEquals(decoded, context.token)
    }

    private func resolve(_ raw: String) -> Resolution {
        let path = Self.pathPart(raw)
        guard tokenMatches(path) else { return .error(404) }
        let rawSegments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        var segments: [String] = []
        for rawSegment in rawSegments where !rawSegment.isEmpty {
            guard let decoded = String(rawSegment).removingPercentEncoding else { return .error(400) }
            if decoded == "." { continue }
            if decoded == ".." { return .error(403) }
            if decoded.contains("/") || decoded.contains("\0") { return .error(400) }
            segments.append(decoded)
        }
        var url = context.rootURL
        for segment in segments {
            url.appendPathComponent(segment, isDirectory: false)
        }
        guard WebDAVPaths.isConfined(url, rootReal: context.rootReal, rootURL: context.rootURL) else {
            return .error(403)
        }
        return .target(WebDAVTarget(url: url, segments: segments))
    }

    // MARK: Methods

    private static let mutatingMethods: Set<String> = ["PUT", "DELETE", "MKCOL", "COPY", "MOVE", "PROPPATCH", "LOCK", "UNLOCK"]

    private var allowedMethods: String {
        context.readOnly
            ? "OPTIONS, GET, HEAD, PROPFIND"
            : "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK"
    }

    private func handle(_ request: WebDAVRequest, body: WebDAVBodySink) -> WebDAVResponse {
        if request.method == "OPTIONS" {
            return options(request)
        }
        let target: WebDAVTarget
        switch resolve(request.target) {
        case .target(let resolved): target = resolved
        case .error(let status):
            body.abandon()
            return WebDAVResponse(status: status)
        }
        switch request.method {
        case "PROPFIND": return propfind(request, target)
        case "GET": return get(request, target, omitBody: false)
        case "HEAD": return get(request, target, omitBody: true)
        case "PUT": return commitUpload(body)
        case "DELETE": return delete(target)
        case "MKCOL": return mkcol(target)
        case "COPY", "MOVE": return copyOrMove(request, target)
        case "PROPPATCH": return proppatch(target, body: body.data)
        case "LOCK": return lock(request, target)
        case "UNLOCK": return WebDAVResponse(status: 204)
        default: return WebDAVResponse(status: 405, headers: [("Allow", allowedMethods)])
        }
    }

    private func options(_ request: WebDAVRequest) -> WebDAVResponse {
        let path = Self.pathPart(request.target)
        // The redirector probes the server root before the share, and answering that probe reveals nothing: it
        // never touches a file. Everything else still needs the token.
        guard request.target == "*" || path == "/" || tokenMatches(path) else {
            return WebDAVResponse(status: 404)
        }
        return WebDAVResponse(status: 200, headers: [
            ("DAV", "1, 2"),
            ("MS-Author-Via", "DAV"),
            ("Allow", allowedMethods),
            ("Accept-Ranges", "bytes"),
        ])
    }

    private func propfind(_ request: WebDAVRequest, _ target: WebDAVTarget) -> WebDAVResponse {
        guard let info = WebDAVPaths.info(target.url.path) else { return WebDAVResponse(status: 404) }
        // Depth infinity is treated as 1: walking a whole tree for one request is how a guest (or a stray
        // Explorer search) turns a home folder into minutes of blocked I/O.
        let depth = request.header("depth") == "0" ? 0 : 1

        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        xml += "<D:multistatus xmlns:D=\"DAV:\" xmlns:Z=\"urn:schemas-microsoft-com:\">\n"
        xml += propResponse(target, info: info)
        if depth == 1, info.isDirectory {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: target.url.path)) ?? []
            for name in names.sorted() where !name.hasPrefix(WebDAVPaths.uploadPrefix) {
                let child = target.child(name)
                // Entries that escape the root (symlinks to elsewhere) are left out entirely rather than listed
                // and then refused, so Explorer never shows something it cannot open.
                guard WebDAVPaths.isConfined(child.url, rootReal: context.rootReal, rootURL: context.rootURL),
                      let childInfo = WebDAVPaths.info(child.url.path) else { continue }
                xml += propResponse(child, info: childInfo)
            }
        }
        xml += "</D:multistatus>\n"
        return .xml(207, xml)
    }

    private func propResponse(_ target: WebDAVTarget, info: WebDAVFileInfo) -> String {
        let name = target.segments.last ?? ""
        let modified = WebDAVFormat.rfc1123.string(from: info.modified)
        let created = WebDAVFormat.rfc1123.string(from: info.created)
        var attributes: UInt32 = info.isDirectory ? 0x10 : 0x20
        if name.hasPrefix(".") { attributes |= 0x2 }
        if context.readOnly, !info.isDirectory { attributes |= 0x1 }

        var xml = "<D:response><D:href>\(WebDAVFormat.escape(target.href(token: context.token, isDirectory: info.isDirectory)))</D:href>"
        xml += "<D:propstat><D:prop>"
        xml += "<D:displayname>\(WebDAVFormat.escape(name))</D:displayname>"
        if info.isDirectory {
            xml += "<D:resourcetype><D:collection/></D:resourcetype>"
        } else {
            xml += "<D:resourcetype/>"
            xml += "<D:getcontentlength>\(info.size)</D:getcontentlength>"
            xml += "<D:getcontenttype>\(WebDAVFormat.contentType(for: name))</D:getcontenttype>"
        }
        xml += "<D:getlastmodified>\(modified)</D:getlastmodified>"
        xml += "<D:creationdate>\(WebDAVFormat.iso8601.string(from: info.created))</D:creationdate>"
        xml += "<D:getetag>\(WebDAVFormat.escape(WebDAVFormat.etag(info)))</D:getetag>"
        xml += "<D:supportedlock><D:lockentry><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock>"
        xml += "<Z:Win32CreationTime>\(created)</Z:Win32CreationTime>"
        xml += "<Z:Win32LastAccessTime>\(modified)</Z:Win32LastAccessTime>"
        xml += "<Z:Win32LastModifiedTime>\(modified)</Z:Win32LastModifiedTime>"
        xml += "<Z:Win32FileAttributes>\(String(format: "%08X", attributes))</Z:Win32FileAttributes>"
        xml += "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>\n"
        return xml
    }

    private enum RangeRequest {
        case full
        case unsatisfiable
        case bytes(UInt64, UInt64)
    }

    private static func parseRange(_ header: String?, size: UInt64) -> RangeRequest {
        guard let header, header.lowercased().hasPrefix("bytes=") else { return .full }
        let spec = header.dropFirst("bytes=".count).trimmingCharacters(in: .whitespaces)
        // Multiple ranges would need multipart/byteranges; ignoring Range and sending the whole file is allowed.
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .full }
        let startText = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let endText = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if startText.isEmpty {
            guard let suffix = UInt64(endText) else { return .full }
            guard suffix > 0, size > 0 else { return .unsatisfiable }
            return .bytes(size > suffix ? size - suffix : 0, size - 1)
        }
        guard let start = UInt64(startText) else { return .full }
        guard start < size else { return .unsatisfiable }
        if endText.isEmpty {
            return .bytes(start, size - 1)
        }
        guard let end = UInt64(endText), end >= start else { return .full }
        return .bytes(start, min(end, size - 1))
    }

    private func get(_ request: WebDAVRequest, _ target: WebDAVTarget, omitBody: Bool) -> WebDAVResponse {
        guard let info = WebDAVPaths.info(target.url.path) else { return WebDAVResponse(status: 404) }
        guard !info.isDirectory else {
            return WebDAVResponse(status: 405, headers: [("Allow", "OPTIONS, PROPFIND")])
        }
        guard let handle = try? FileHandle(forReadingFrom: target.url) else { return WebDAVResponse(status: 403) }

        var headers: [(String, String)] = [
            ("Content-Type", WebDAVFormat.contentType(for: target.segments.last ?? "")),
            ("Last-Modified", WebDAVFormat.rfc1123.string(from: info.modified)),
            ("ETag", WebDAVFormat.etag(info)),
            ("Accept-Ranges", "bytes"),
        ]
        var status = 200
        var offset: UInt64 = 0
        var length = info.size
        switch Self.parseRange(request.header("range"), size: info.size) {
        case .full:
            break
        case .unsatisfiable:
            try? handle.close()
            return WebDAVResponse(status: 416, headers: [("Content-Range", "bytes */\(info.size)")])
        case .bytes(let start, let end):
            status = 206
            offset = start
            length = end - start + 1
            headers.append(("Content-Range", "bytes \(start)-\(end)/\(info.size)"))
        }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            try? handle.close()
            return WebDAVResponse(status: 500)
        }
        var response = WebDAVResponse(status: status, headers: headers)
        response.file = (handle, length)
        response.omitBody = omitBody
        return response
    }

    private func prepareUpload(_ request: WebDAVRequest) -> Result<WebDAVBodySink, WebDAVStatusError> {
        if context.readOnly { return .failure(WebDAVStatusError(status: 403)) }
        let target: WebDAVTarget
        switch resolve(request.target) {
        case .target(let resolved): target = resolved
        case .error(let status): return .failure(WebDAVStatusError(status: status))
        }
        guard !target.segments.isEmpty else { return .failure(WebDAVStatusError(status: 405)) }
        let existing = WebDAVPaths.info(target.url.path)
        if existing?.isDirectory == true { return .failure(WebDAVStatusError(status: 405)) }
        let parent = target.url.deletingLastPathComponent()
        guard WebDAVPaths.info(parent.path)?.isDirectory == true else { return .failure(WebDAVStatusError(status: 409)) }

        // Written beside the destination and renamed into place, so the Mac never sees a half-written file under
        // the real name and an interrupted upload leaves the previous version intact.
        let temporary = parent.appendingPathComponent("\(WebDAVPaths.uploadPrefix)\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: temporary) else {
            return .failure(WebDAVStatusError(status: 403))
        }
        return .success(WebDAVBodySink(.upload(handle: handle, temporary: temporary, destination: target.url, existed: existing != nil)))
    }

    private func commitUpload(_ body: WebDAVBodySink) -> WebDAVResponse {
        guard case .upload(let handle, let temporary, let destination, let existed) = body.kind else {
            return WebDAVResponse(status: 500)
        }
        do {
            try handle.close()
        } catch {
            unlink(temporary.path)
            return WebDAVResponse(status: 507)
        }
        guard rename(temporary.path, destination.path) == 0 else {
            unlink(temporary.path)
            return WebDAVResponse(status: 409)
        }
        return WebDAVResponse(status: existed ? 204 : 201)
    }

    private func delete(_ target: WebDAVTarget) -> WebDAVResponse {
        guard !target.segments.isEmpty else { return WebDAVResponse(status: 403) }
        guard WebDAVPaths.exists(target.url.path) else { return WebDAVResponse(status: 404) }
        do {
            try FileManager.default.removeItem(at: target.url)
        } catch {
            return WebDAVResponse(status: 403)
        }
        return WebDAVResponse(status: 204)
    }

    private func mkcol(_ target: WebDAVTarget) -> WebDAVResponse {
        guard !target.segments.isEmpty, !WebDAVPaths.exists(target.url.path) else {
            return WebDAVResponse(status: 405)
        }
        guard WebDAVPaths.info(target.url.deletingLastPathComponent().path)?.isDirectory == true else {
            return WebDAVResponse(status: 409)
        }
        guard mkdir(target.url.path, 0o755) == 0 else { return WebDAVResponse(status: 403) }
        return WebDAVResponse(status: 201)
    }

    private func copyOrMove(_ request: WebDAVRequest, _ source: WebDAVTarget) -> WebDAVResponse {
        guard !source.segments.isEmpty || request.method == "COPY" else { return WebDAVResponse(status: 403) }
        guard let sourceInfo = WebDAVPaths.info(source.url.path) else { return WebDAVResponse(status: 404) }
        guard let destinationHeader = request.header("destination") else { return WebDAVResponse(status: 400) }
        let destination: WebDAVTarget
        switch resolve(destinationHeader) {
        case .target(let resolved): destination = resolved
        case .error(let status): return WebDAVResponse(status: status == 400 ? 400 : 403)
        }
        guard !destination.segments.isEmpty else { return WebDAVResponse(status: 403) }
        let sourcePath = source.url.standardizedFileURL.path
        let destinationPath = destination.url.standardizedFileURL.path
        if destinationPath == sourcePath || (sourceInfo.isDirectory && destinationPath.hasPrefix(sourcePath + "/")) {
            return WebDAVResponse(status: 403)
        }
        guard WebDAVPaths.info(destination.url.deletingLastPathComponent().path)?.isDirectory == true else {
            return WebDAVResponse(status: 409)
        }
        let overwrite = request.header("overwrite")?.uppercased() != "F"
        let existed = WebDAVPaths.exists(destination.url.path)
        if existed {
            guard overwrite else { return WebDAVResponse(status: 412) }
            do {
                try FileManager.default.removeItem(at: destination.url)
            } catch {
                return WebDAVResponse(status: 403)
            }
        }
        do {
            if request.method == "MOVE" {
                try FileManager.default.moveItem(at: source.url, to: destination.url)
            } else {
                try FileManager.default.copyItem(at: source.url, to: destination.url)
            }
        } catch {
            return WebDAVResponse(status: 403)
        }
        return WebDAVResponse(status: existed ? 204 : 201)
    }

    private func proppatch(_ target: WebDAVTarget, body: Data) -> WebDAVResponse {
        guard WebDAVPaths.exists(target.url.path) else { return WebDAVResponse(status: 404) }
        let parser = WebDAVPropPatchParser()
        parser.parse(body)
        // Windows sets its Win32 times and attributes after every copy and fails the copy if any is refused.
        // Only the modification time maps onto something the Mac keeps; the rest are acknowledged and dropped.
        if let text = parser.lastModified, let date = WebDAVFormat.rfc1123.date(from: text) {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: target.url.path)
        }
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<D:multistatus xmlns:D=\"DAV:\">"
        xml += "<D:response><D:href>\(WebDAVFormat.escape(target.href(token: context.token, isDirectory: WebDAVPaths.info(target.url.path)?.isDirectory == true)))</D:href>"
        xml += "<D:propstat><D:prop>"
        for property in parser.properties {
            xml += "<P:\(property.name) xmlns:P=\"\(WebDAVFormat.escape(property.namespace))\"/>"
        }
        xml += "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>\n"
        return .xml(207, xml)
    }

    private func lock(_ request: WebDAVRequest, _ target: WebDAVTarget) -> WebDAVResponse {
        var status = 200
        if !WebDAVPaths.exists(target.url.path) {
            // Locking an unmapped URL creates an empty file; Office and Explorer lock before their first PUT.
            guard !target.segments.isEmpty,
                  WebDAVPaths.info(target.url.deletingLastPathComponent().path)?.isDirectory == true else {
                return WebDAVResponse(status: 409)
            }
            guard FileManager.default.createFile(atPath: target.url.path, contents: nil) else {
                return WebDAVResponse(status: 403)
            }
            status = 201
        }
        // Locks are not enforced: the Mac side can always change the folder, so a real lock would promise
        // something we cannot keep. A refresh keeps the token the client already holds.
        let existingToken = request.header("if").flatMap { header -> String? in
            guard let start = header.range(of: "opaquelocktoken:") else { return nil }
            let rest = header[start.lowerBound...]
            let end = rest.firstIndex(where: { $0 == ">" || $0 == ")" || $0 == " " }) ?? rest.endIndex
            return String(rest[..<end])
        }
        let lockToken = existingToken ?? "opaquelocktoken:\(UUID().uuidString.lowercased())"
        let depth = request.header("depth")?.lowercased() == "0" ? "0" : "infinity"
        let isDirectory = WebDAVPaths.info(target.url.path)?.isDirectory == true
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<D:prop xmlns:D=\"DAV:\"><D:lockdiscovery><D:activelock>"
        xml += "<D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope>"
        xml += "<D:depth>\(depth)</D:depth><D:timeout>Second-3600</D:timeout>"
        xml += "<D:locktoken><D:href>\(WebDAVFormat.escape(lockToken))</D:href></D:locktoken>"
        xml += "<D:lockroot><D:href>\(WebDAVFormat.escape(target.href(token: context.token, isDirectory: isDirectory)))</D:href></D:lockroot>"
        xml += "</D:activelock></D:lockdiscovery></D:prop>\n"
        return .xml(status, xml, headers: [("Lock-Token", "<\(lockToken)>")])
    }
}
