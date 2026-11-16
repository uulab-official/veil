import Darwin
import Foundation

/// Keeps QEMU's USB tablet at the cursor position the Windows agent last injected.
///
/// The tablet is an absolute device that keeps reporting the last position QEMU gave it. Coherence input
/// moves the guest cursor with `SendInput`, which the tablet does not know about, so its next report snapped
/// the cursor back: a stroke drawn in a mirrored Paint window had segments jumping to wherever the tablet
/// last was. Moving the tablet to the injected position (no buttons) makes both agree.
///
/// QEMU's QMP socket serves one client at a time, so each move connects, waits for QMP to answer, and
/// disconnects. Holding one connection open for speed locked out every other QMP user, including tools
/// updates and snapshots. Moves that arrive while one is in flight replace each other, and only the newest
/// is sent next, so a fast drag never queues stale positions.
public actor QEMUTabletPositionSync {
    private let launchRecordStore: any QEMULaunchRecordStore
    private var pending: GuestPointerPosition?
    private var isSending = false

    /// Bounds how long a move may hold the QMP socket waiting for its reply.
    static let replyTimeoutMilliseconds: Int32 = 200

    public init(launchRecordStore: any QEMULaunchRecordStore) {
        self.launchRecordStore = launchRecordStore
    }

    /// Best effort: a failed move only means the tablet may snap the cursor once more.
    public func move(to position: GuestPointerPosition) async {
        let maximum = QEMUQMPPointerCommandBuilder.maximumAbsoluteCoordinate
        guard (0...maximum).contains(position.x),
              (0...maximum).contains(position.y) else {
            return
        }

        pending = position
        guard !isSending else {
            return
        }

        isSending = true
        defer { isSending = false }
        while let next = pending {
            pending = nil
            guard let path = try? await launchRecordStore.loadLatest()?.qmpSocketPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  let command = try? QEMUQMPPointerCommandBuilder.absoluteMoveCommand(x: next.x, y: next.y) else {
                return
            }
            Self.send(command, toSocketAt: path)
        }
    }

    /// Connects, negotiates capabilities, sends one command, and waits until QMP has answered both before
    /// closing, so the command is applied rather than dropped with the connection.
    static func send(_ command: String, toSocketAt path: String) {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return
        }
        defer { close(descriptor) }

        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            return
        }

        let request = QEMUQMPKeyboardCommandBuilder.capabilitiesCommand() + "\n" + command + "\n"
        guard writeAll(request, to: descriptor) else {
            return
        }
        waitForReplies(2, on: descriptor)
    }

    private static func writeAll(_ text: String, to descriptor: Int32) -> Bool {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer in
                write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// Reads until `count` `"return"` replies arrived, the peer closed, or the timeout passed.
    private static func waitForReplies(_ count: Int, on descriptor: Int32) {
        var received = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        while received.components(separatedBy: "\"return\"").count - 1 < count {
            guard poll(&poller, 1, replyTimeoutMilliseconds) > 0 else {
                return
            }
            let readCount = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard readCount > 0 else {
                return
            }
            received += String(decoding: buffer[0..<readCount], as: UTF8.self)
        }
    }
}
