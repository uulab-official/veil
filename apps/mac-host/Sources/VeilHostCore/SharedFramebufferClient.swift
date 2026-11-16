import CoreGraphics
import Darwin
import Foundation

/// Reads the guest display from Veil's patched QEMU (`QEMUSharedFramebuffer`) and hands the newest frame
/// to the main thread.
///
/// A worker thread reads the socket; each update only marks the frame dirty. At most one delivery is in
/// flight, and it snapshots the whole shared buffer at that moment, so a burst of updates becomes one frame
/// and the screen never works through a backlog. The connection retries until `stop()`.
public final class SharedFramebufferClient: @unchecked Sendable {
    public typealias FrameHandler = @MainActor (CGImage) -> Void

    private let socketPath: String
    private let onFrame: FrameHandler
    private let lock = NSLock()
    private var stopped = false
    private var socketFD: Int32 = -1
    private var mapping: (pointer: UnsafeMutableRawPointer, size: Int)?
    private var surface: (width: Int, height: Int, stride: Int, format: UInt32)?
    private var deliveryScheduled = false
    private var dirty = false

    public init(socketPath: String, onFrame: @escaping FrameHandler) {
        self.socketPath = socketPath
        self.onFrame = onFrame
    }

    public func start() {
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "app.veil.shared-framebuffer"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func stop() {
        lock.lock()
        stopped = true
        let fd = socketFD
        lock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func run() {
        while !isStopped {
            if let fd = connectSocket() {
                lock.lock()
                socketFD = fd
                lock.unlock()
                readLines(fd)
                lock.lock()
                socketFD = -1
                lock.unlock()
                close(fd)
            }
            if !isStopped {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        lock.lock()
        unmapLocked()
        lock.unlock()
    }

    private func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return nil
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private func readLines(_ fd: Int32) {
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while !isStopped {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else {
                return
            }
            pending.append(contentsOf: chunk[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                if let message = QEMUSharedFramebuffer.Message(line: Data(line)) {
                    handle(message)
                }
            }
            if pending.count > 65_536 {
                // Lines are a few dozen bytes; anything this long is not the protocol.
                return
            }
        }
    }

    private func handle(_ message: QEMUSharedFramebuffer.Message) {
        switch message {
        case .surface(let name, let width, let height, let stride, let format):
            guard format == QEMUSharedFramebuffer.Message.pixmanX8R8G8B8
                    || format == QEMUSharedFramebuffer.Message.pixmanA8R8G8B8 else {
                return
            }
            map(name: name, size: stride * height)
            lock.lock()
            surface = mapping == nil ? nil : (width, height, stride, format)
            lock.unlock()
            markDirty()
        case .update:
            markDirty()
        }
    }

    private func map(name: String, size: Int) {
        let fd = name.withCString { Self.openSharedMemoryReadOnly($0) }
        guard fd >= 0 else {
            return
        }
        defer { close(fd) }
        let pointer = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
        lock.lock()
        unmapLocked()
        if let pointer, pointer != MAP_FAILED {
            mapping = (pointer, size)
        }
        lock.unlock()
    }

    private func unmapLocked() {
        if let mapping {
            munmap(mapping.pointer, mapping.size)
        }
        mapping = nil
        surface = nil
    }

    /// `shm_open` is variadic, which Swift cannot call. Without `O_CREAT` the mode argument is never
    /// read, so the two-argument form through its address is the same call.
    private static let shmOpen: (@convention(c) (UnsafePointer<CChar>, Int32) -> Int32)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "shm_open") else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (UnsafePointer<CChar>, Int32) -> Int32).self)
    }()

    private static func openSharedMemoryReadOnly(_ name: UnsafePointer<CChar>) -> Int32 {
        shmOpen?(name, O_RDONLY) ?? -1
    }

    private func markDirty() {
        lock.lock()
        dirty = true
        let schedules = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()
        guard schedules else {
            return
        }
        Task { @MainActor [weak self] in
            self?.deliver()
        }
    }

    @MainActor
    private func deliver() {
        lock.lock()
        deliveryScheduled = false
        guard dirty, let mapping, let surface else {
            lock.unlock()
            return
        }
        dirty = false
        // A copy, taken now: Core Animation reads image memory later, while QEMU keeps writing the shared
        // buffer.
        let pixels = Data(bytes: mapping.pointer, count: surface.stride * surface.height)
        lock.unlock()

        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: surface.width,
                height: surface.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: surface.stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.noneSkipFirst.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return
        }
        onFrame(image)
    }
}
