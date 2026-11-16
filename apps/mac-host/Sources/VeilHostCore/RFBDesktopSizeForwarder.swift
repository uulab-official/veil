import Darwin
import Foundation

/// Hands a desktop size to QEMU's display over VNC (RFB SetDesktopSize), on its own short connection.
///
/// Triton's `viogpu3d` only switches to a size that QEMU has passed to the virtio-gpu device first: an
/// agent `display.resize.request` for 2048x1280 alone was refused (`display_mode_not_supported`), and the
/// same request right after QEMU answered SetDesktopSize with result 4 ("request forwarded") was accepted
/// (measured on the user's Windows, 2026-11-16). viogpudo on the software runtime takes the size through
/// the agent's driver escape instead, which viogpu3d does not answer. The desktop view already sends
/// SetDesktopSize from its live VNC session; the apps view has no VNC session, so it uses this.
public enum RFBDesktopSizeForwarder {
    /// Sends SetDesktopSize and returns QEMU's answer to it, or nil when none arrived. The stream must be
    /// fresh: this runs the RFB handshake.
    public static func forward(width: Int, height: Int, over stream: RFBByteStream) throws -> RFBDesktopSizeResponse? {
        let client = RFBFrameStreamClient(stream: stream)
        _ = try client.startSharedSession()
        // A one-pixel full update: QEMU answers each update request, and the first one also carries its
        // initial ExtendedDesktopSize rectangle (reason 0), which is not the answer to this request.
        let onePixel = RFBClientMessageBuilder.framebufferUpdateRequest(incremental: false, x: 0, y: 0, width: 1, height: 1)
        try stream.write(onePixel)
        _ = try client.readUpdateEvent()

        try client.sendSetDesktopSize(width: width, height: height)
        try stream.write(onePixel)
        for _ in 0..<4 {
            if case .desktopSize(let response) = try client.readUpdateEvent(), response.reasonCode == 1 {
                return response
            }
            try stream.write(onePixel)
        }
        return nil
    }

    /// Connects to QEMU's VNC Unix socket and forwards the size, giving up after `timeoutSeconds`.
    public static func forward(width: Int, height: Int, unixSocketPath: String, timeoutSeconds: Int = 3) -> RFBDesktopSizeResponse? {
        guard let stream = try? DeadlineUnixStream(path: unixSocketPath, timeoutSeconds: timeoutSeconds) else {
            return nil
        }
        defer {
            stream.close()
        }
        return try? forward(width: width, height: height, over: stream)
    }
}

/// A Unix socket whose reads fail once the deadline passes. `RFBLoopbackSocket` waits through read
/// timeouts on purpose, because a live display can stay unchanged for a long time; a one-shot request
/// must not hang on a QEMU that never answers.
final class DeadlineUnixStream: RFBByteStream {
    private var descriptor: Int32
    private let deadline: Date

    init(path: String, timeoutSeconds: Int) throws {
        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        guard path.hasPrefix("/"), pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw RFBLoopbackSocketError.invalidEndpoint("unix:\(path)")
        }
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw RFBLoopbackSocketError.socketOperationFailed("socket")
        }
        deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close()
            throw RFBLoopbackSocketError.socketOperationFailed("connect")
        }
    }

    func readExactly(_ byteCount: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: byteCount)
        var bytesRead = 0
        while bytesRead < byteCount {
            let result = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress!.advanced(by: bytesRead), byteCount - bytesRead)
            }
            if result == 0 {
                throw RFBLoopbackSocketError.connectionClosed
            }
            if result < 0 {
                guard errno == EAGAIN || errno == EWOULDBLOCK, Date() < deadline else {
                    throw RFBLoopbackSocketError.socketOperationFailed("read")
                }
                continue
            }
            bytesRead += result
        }
        return Data(buffer)
    }

    func write(_ data: Data) throws {
        var written = 0
        try data.withUnsafeBytes { raw in
            while written < data.count {
                let result = Darwin.write(descriptor, raw.baseAddress!.advanced(by: written), data.count - written)
                guard result > 0 else {
                    throw RFBLoopbackSocketError.socketOperationFailed("write")
                }
                written += result
            }
        }
    }

    func close() {
        guard descriptor >= 0 else {
            return
        }
        Darwin.close(descriptor)
        descriptor = -1
    }
}
