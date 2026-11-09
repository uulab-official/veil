import Darwin
import Foundation

/// Keeps QEMU's USB tablet at the cursor position the Windows agent last injected.
///
/// The tablet is an absolute device that keeps reporting the last position QEMU gave it. Coherence input
/// moves the guest cursor with `SendInput`, which the tablet does not know about, so its next report snapped
/// the cursor back: a stroke drawn in a mirrored Paint window had segments jumping to wherever the tablet
/// last was. Moving the tablet to the injected position (no buttons) makes both agree.
///
/// Moves arrive for every mouse event of a drag, so this keeps one QMP connection open instead of starting
/// a process per move the way the one-off console taps do.
public actor QEMUTabletPositionSync {
    private let launchRecordStore: any QEMULaunchRecordStore
    private var socket: Int32 = -1
    private var socketPath: String?

    public init(launchRecordStore: any QEMULaunchRecordStore) {
        self.launchRecordStore = launchRecordStore
    }

    deinit {
        if socket >= 0 {
            close(socket)
        }
    }

    /// Best effort: a failed move only means the tablet may snap the cursor once more.
    public func move(to position: GuestPointerPosition) async {
        let maximum = QEMUQMPPointerCommandBuilder.maximumAbsoluteCoordinate
        guard (0...maximum).contains(position.x),
              (0...maximum).contains(position.y),
              let command = try? QEMUQMPPointerCommandBuilder.absoluteMoveCommand(x: position.x, y: position.y) else {
            return
        }

        if socket < 0 {
            await connect()
        }
        guard socket >= 0 else {
            return
        }

        drainReplies()
        if !write(command + "\n") {
            disconnect()
        }
    }

    private func connect() async {
        guard let path = try? await launchRecordStore.loadLatest()?.qmpSocketPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            close(descriptor)
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return
        }

        // QMP refuses commands until capabilities are negotiated. Replies are drained before each write so the
        // socket buffer never fills; nothing here waits on them.
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        socket = descriptor
        socketPath = path
        if !write(QEMUQMPKeyboardCommandBuilder.capabilitiesCommand() + "\n") {
            disconnect()
        }
    }

    private func write(_ line: String) -> Bool {
        var bytes = Array(line.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeMutableBytes { buffer in
                Darwin.write(socket, buffer.baseAddress! + offset, buffer.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EAGAIN || errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    private func drainReplies() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(socket, $0.baseAddress, $0.count) }
            if count > 0 {
                continue
            }
            if count == 0 || (errno != EAGAIN && errno != EINTR) {
                // QEMU closed the connection, for example after a restart with a new socket.
                disconnect()
            }
            return
        }
    }

    private func disconnect() {
        if socket >= 0 {
            close(socket)
        }
        socket = -1
        socketPath = nil
    }
}
