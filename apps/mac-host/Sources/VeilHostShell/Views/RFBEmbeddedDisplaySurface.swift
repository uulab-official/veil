import AppKit
import Foundation
import SwiftUI
import VeilHostCore

@MainActor
@Observable
final class RFBEmbeddedDisplayModel {
    private(set) var image: NSImage?
    private(set) var frameSequence: Int?
    private(set) var status = RFBEmbeddedDisplayStatus.idle
    private(set) var resizePresentation = RFBDesktopResizePresentation.unavailable
    private(set) var activeEndpoint: String?
    private var pendingResizeTarget: (width: Int, height: Int)?
    private var lastRequestedResizeTarget: (width: Int, height: Int)?
    private var displayResizeFallback: ((Int, Int) -> Void)?
    @ObservationIgnored private var worker: RFBEmbeddedDisplayWorker?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var connectionGeneration = 0
    @ObservationIgnored private var retryDelaySeconds: Double = 1
    @ObservationIgnored private var lastDeliveredFrameAt = Date.distantPast

    var statusSymbolName: String {
        switch status {
        case .idle:
            return "dot.radiowaves.left.and.right"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .receiving:
            return "display"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var isReceiving: Bool {
        if case .receiving = status {
            return true
        }
        return false
    }

    func statusTitle(for surface: VMConsoleDisplaySurface) -> String {
        switch status {
        case .idle:
            return surface.endpoint ?? "Loopback display"
        case .connecting:
            return "Connecting \(surface.endpoint ?? "display")"
        case .receiving:
            guard let frameSequence else {
                return "Live Windows display"
            }

            return "Live Windows display #\(frameSequence)"
        case .failed(let message):
            return message
        }
    }

    func connectIfNeeded(to surface: VMConsoleDisplaySurface) {
        guard surface.kind == .vncLoopback, let endpoint = surface.endpoint else {
            stop()
            return
        }

        guard endpoint != activeEndpoint || worker == nil else {
            return
        }

        stop()
        activeEndpoint = endpoint
        startWorker(endpoint: endpoint, generation: connectionGeneration, resetFrames: true)
    }

    private func startWorker(endpoint: String, generation: Int, resetFrames: Bool) {
        guard activeEndpoint == endpoint else {
            return
        }

        if resetFrames {
            image = nil
            frameSequence = nil
        }
        status = .connecting

        guard let parsedEndpoint = RFBDisplayEndpoint(endpoint) else {
            status = .failed("Display endpoint unavailable")
            return
        }

        let worker = RFBEmbeddedDisplayWorker(endpoint: parsedEndpoint)
        self.worker = worker
        worker.start(
            onFrame: { [weak self] frame in
                guard let self,
                      self.activeEndpoint == endpoint,
                      self.connectionGeneration == generation else {
                    return
                }

                // Raw RFB frames can arrive faster than AppKit can decode and
                // display them. Drop excess intermediate frames so input handling
                // never waits behind a backlog of full-frame image conversions.
                let now = Date()
                guard now.timeIntervalSince(self.lastDeliveredFrameAt) >= (1.0 / 24.0) else {
                    return
                }
                self.lastDeliveredFrameAt = now

                guard let image = frame.makeNSImage() else {
                    self.handleDisplayFailure(
                        "Display frame unavailable",
                        endpoint: endpoint,
                        generation: generation
                    )
                    return
                }

                self.retryTask?.cancel()
                self.retryTask = nil
                self.retryDelaySeconds = 1
                self.image = image
                self.frameSequence = frame.sequence
                self.status = .receiving
            },
            onFailure: { [weak self] message in
                self?.handleDisplayFailure(
                    message,
                    endpoint: endpoint,
                    generation: generation
                )
            },
            onResizeState: { [weak self] presentation in
                guard let self,
                      self.activeEndpoint == endpoint,
                      self.connectionGeneration == generation else {
                    return
                }

                self.resizePresentation = presentation
                if presentation == .rejected,
                   let target = self.lastRequestedResizeTarget {
                    self.lastRequestedResizeTarget = nil
                    self.displayResizeFallback?(target.width, target.height)
                }
                if presentation == .recovering || presentation == .available,
                   let pending = self.pendingResizeTarget {
                    self.pendingResizeTarget = nil
                    self.lastRequestedResizeTarget = pending
                    self.worker?.requestDesktopResize(width: pending.width, height: pending.height)
                }
            }
        )
    }

    /// Forwards a settled host-window target to the live RFB connection. The first
    /// target is allowed through while the connection is still probing because the
    /// probe itself is the SetDesktopSize request on servers that do not advertise
    /// ExtendedDesktopSize in the initial framebuffer update.
    func requestDesktopResize(width: Int, height: Int) {
        VeilLog.runtime.debug(
            "RFB resize target received: \(width)x\(height), presentation=\(String(describing: self.resizePresentation))"
        )
        pendingResizeTarget = (width, height)
        if (resizePresentation == .available || resizePresentation == .recovering),
           let worker,
           pendingResizeTarget != nil {
            pendingResizeTarget = nil
            lastRequestedResizeTarget = (width, height)
            worker.requestDesktopResize(width: width, height: height)
        }
    }

    func setDisplayResizeFallback(_ action: ((Int, Int) -> Void)?) {
        displayResizeFallback = action
    }

    func sendPointerTap(normalizedX: Double, normalizedY: Double) {
        worker?.sendPointerTap(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    func sendKey(_ key: String) {
        worker?.sendKey(key)
    }

    /// Keeps the last transport failure visible until the scheduled retry actually starts. Without
    /// this state, a timed-out VM looks indistinguishable from a healthy connection still opening.
    func showConnectionFailure(_ message: String) {
        status = .failed(message)
    }

    private func handleDisplayFailure(
        _ message: String,
        endpoint: String,
        generation: Int
    ) {
        guard activeEndpoint == endpoint,
              connectionGeneration == generation else {
            return
        }

        VeilLog.runtime.notice("RFB display connection interrupted; retrying automatically. \(message, privacy: .public)")
        worker?.stop()
        worker = nil
        showConnectionFailure(message)

        let delay = retryDelaySeconds
        retryDelaySeconds = min(retryDelaySeconds * 2, 8)
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  self.activeEndpoint == endpoint,
                  self.connectionGeneration == generation else {
                return
            }

            self.retryTask = nil
            self.startWorker(endpoint: endpoint, generation: generation, resetFrames: false)
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        retryDelaySeconds = 1
        lastDeliveredFrameAt = .distantPast
        connectionGeneration += 1
        worker?.stop()
        worker = nil
        activeEndpoint = nil
        frameSequence = nil
        resizePresentation = .unavailable
        pendingResizeTarget = nil
        lastRequestedResizeTarget = nil
        displayResizeFallback = nil
        status = .idle
    }
}

private enum RFBKeySymMapper {
    static func keysyms(for key: String) -> [UInt32] {
        key.split(separator: "-").compactMap { keysym(for: String($0)) }
    }

    private static func keysym(for rawKey: String) -> UInt32? {
        let key = rawKey.lowercased()
        if key.count == 1, let scalar = key.unicodeScalars.first,
           scalar.value >= 32, scalar.value <= 126 {
            return scalar.value
        }

        switch key {
        case "ret", "return", "enter": return 0xff0d
        case "spc", "space": return 0x20
        case "esc", "escape": return 0xff1b
        case "backspace": return 0xff08
        case "delete": return 0xffff
        case "insert": return 0xff63
        case "home": return 0xff50
        case "end": return 0xff57
        case "pgup": return 0xff55
        case "pgdn": return 0xff56
        case "left": return 0xff51
        case "up": return 0xff52
        case "right": return 0xff53
        case "down": return 0xff54
        case "shift": return 0xffe1
        case "ctrl", "control": return 0xffe3
        case "alt": return 0xffe9
        case "meta", "meta_l", "cmd", "win", "windows": return 0xffe7
        case "backslash": return 0x5c
        case "slash": return 0x2f
        case "minus": return 0x2d
        case "equal": return 0x3d
        case "dot": return 0x2e
        case "comma": return 0x2c
        case "semicolon": return 0x3b
        case "apostrophe": return 0x27
        case "grave_accent": return 0x60
        case "bracket_left": return 0x5b
        case "bracket_right": return 0x5d
        default:
            guard key.hasPrefix("f"),
                  let number = Int(key.dropFirst()), (1...12).contains(number) else {
                return nil
            }
            return UInt32(0xffbe + number - 1)
        }
    }
}

enum RFBEmbeddedDisplayStatus: Equatable {
    case idle
    case connecting
    case receiving
    case failed(String)
}

private struct RFBDisplayEndpoint: Equatable, Sendable {
    var host: String
    var port: Int

    init?(_ endpoint: String) {
        let parts = endpoint.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let port = Int(parts[1]),
              port > 0 else {
            return nil
        }

        self.host = parts[0]
        self.port = port
    }
}

private final class RFBEmbeddedDisplayWorker: @unchecked Sendable {
    private let endpoint: RFBDisplayEndpoint
    private let queue = DispatchQueue(label: "app.veil.rfb-display", qos: .userInitiated)
    private let lock = NSLock()
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var isStopped = false
    private var stream: RFBByteStream?
    private var client: RFBFrameStreamClient?
    private var resizeMachine = RFBDesktopResizeStateMachine()

    init(endpoint: RFBDisplayEndpoint) {
        self.endpoint = endpoint
    }

    func start(
        onFrame: @escaping @MainActor (RFBRenderedFrame) -> Void,
        onFailure: @escaping @MainActor (String) -> Void,
        onResizeState: @escaping @MainActor (RFBDesktopResizePresentation) -> Void
    ) {
        queue.async { [weak self] in
            self?.run(onFrame: onFrame, onFailure: onFailure, onResizeState: onResizeState)
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        stream?.close()
        stream = nil
        client = nil
        lock.unlock()
    }

    /// Sends a SetDesktopSize request from the caller's thread so it does not wait
    /// behind a blocking read. Reads and writes on one socket are full-duplex; the
    /// write lock only serializes concurrent writers.
    func requestDesktopResize(width: Int, height: Int) {
        lock.lock()
        let activeClient = client
        lock.unlock()
        guard activeClient != nil else {
            VeilLog.runtime.debug("RFB resize target held because the session client is not ready")
            return
        }
        guard let activeClient else { return }

        let now = Date().timeIntervalSince1970
        let target = RFBDesktopResizeTarget(widthInPixels: width, heightInPixels: height)
        stateLock.lock()
        let shouldSend = resizeMachine.request(target) != nil
        if shouldSend {
            // Mark the request before writing. QEMU can answer on the receive
            // thread immediately; marking after the write would let that response
            // race and be overwritten by a stale request-pending phase.
            resizeMachine.markRequestSent(target, now: now)
        }
        stateLock.unlock()
        guard shouldSend else {
            return
        }

        do {
            try sendOnClient(activeClient) {
                try $0.sendSetDesktopSize(width: width, height: height)
            }
            VeilLog.runtime.debug("RFB desktop resize request sent: \(width)x\(height)")
        } catch {
            // The run loop observes the same socket failure and starts the retry path.
        }
    }

    func sendPointerTap(normalizedX: Double, normalizedY: Double) {
        lock.lock()
        let activeClient = client
        lock.unlock()
        guard let activeClient,
              let serverInit = activeClient.serverInit,
              normalizedX.isFinite,
              normalizedY.isFinite else {
            return
        }

        let x = min(max(Int((normalizedX * Double(max(0, serverInit.width - 1))).rounded()), 0), max(0, serverInit.width - 1))
        let y = min(max(Int((normalizedY * Double(max(0, serverInit.height - 1))).rounded()), 0), max(0, serverInit.height - 1))

        writeLock.lock()
        defer { writeLock.unlock() }
        do {
            try activeClient.sendPointerEvent(buttonMask: 0, x: x, y: y)
            try activeClient.sendPointerEvent(buttonMask: 1, x: x, y: y)
            try activeClient.sendPointerEvent(buttonMask: 0, x: x, y: y)
        } catch {
            // The read loop owns reconnect/recovery. A transient input write should
            // not block the UI while that loop repairs the stream.
        }
    }

    func sendKey(_ key: String) {
        let keysyms = RFBKeySymMapper.keysyms(for: key)
        guard !keysyms.isEmpty else {
            return
        }

        lock.lock()
        let activeClient = client
        lock.unlock()
        guard let activeClient else {
            return
        }

        writeLock.lock()
        defer { writeLock.unlock() }
        do {
            for keysym in keysyms {
                try activeClient.sendKeyEvent(keysym: keysym, isDown: true)
            }
            for keysym in keysyms.reversed() {
                try activeClient.sendKeyEvent(keysym: keysym, isDown: false)
            }
        } catch {
            // See sendPointerTap: the receive loop handles reconnects.
        }
    }

    private func run(
        onFrame: @escaping @MainActor (RFBRenderedFrame) -> Void,
        onFailure: @escaping @MainActor (String) -> Void,
        onResizeState: @escaping @MainActor (RFBDesktopResizePresentation) -> Void
    ) {
        do {
            let socket = try RFBLoopbackSocket(host: endpoint.host, port: endpoint.port)
            setStream(socket)
            let sessionClient = RFBFrameStreamClient(stream: socket)
            let serverInit = try sessionClient.startSharedSession()

            lock.lock()
            client = sessionClient
            lock.unlock()

            var lastReportedPresentation: RFBDesktopResizePresentation?
            func report(_ presentation: RFBDesktopResizePresentation) {
                guard presentation != lastReportedPresentation else {
                    return
                }

                lastReportedPresentation = presentation
                Task { @MainActor in
                    onResizeState(presentation)
                }
            }

            stateLock.lock()
            resizeMachine.resetForReconnect()
            let initialPresentation = resizeMachine.presentation
            stateLock.unlock()
            report(initialPresentation)

            var renderer = try RFBFramebufferRenderer(serverInit: serverInit)
            try sendOnClient(sessionClient) {
                try $0.requestFramebufferUpdate(incremental: false)
            }

            while !isWorkerStopped {
                let event = try sessionClient.readUpdateEvent()
                let now = Date().timeIntervalSince1970

                switch event {
                case .framebuffer(let update):
                    stateLock.lock()
                    resizeMachine.handleFramebufferUpdateWithoutResizeResponse()
                    let presentation = resizeMachine.presentation
                    stateLock.unlock()
                    report(presentation)

                    // QEMU/VNC may send an empty framebuffer update as a heartbeat while the
                    // Windows compositor is still painting. Rendering that update would turn the
                    // renderer's zero-filled backing store into a black image and hide the last
                    // usable screenshot (or make the console look blank before the first frame).
                    // Keep the stream alive, but only publish updates that contain pixels.
                    guard update.rectangles.contains(where: { $0.width > 0 && $0.height > 0 }) else {
                        try sendOnClient(sessionClient) {
                            try $0.requestFramebufferUpdate(incremental: true)
                        }
                        continue
                    }

                    do {
                        let frame = try renderer.apply(update)
                        Task { @MainActor in
                            onFrame(frame)
                        }
                    } catch let error as RFBError {
                        guard case .invalidRectangleBounds = error else {
                            throw error
                        }

                        // The framebuffer changed size underneath this update. The
                        // stale surface cannot be composited, so request a full
                        // refresh at the current size instead of dropping the link.
                        try sendOnClient(sessionClient) {
                            try $0.requestFramebufferUpdate(incremental: false)
                        }
                        continue
                    }

                    try sendOnClient(sessionClient) {
                        try $0.requestFramebufferUpdate(incremental: true)
                    }

                case .desktopSize(let response):
                    VeilLog.runtime.debug(
                        "RFB desktop resize response: \(response.width)x\(response.height), reason=\(response.reasonCode), result=\(response.resultCode)"
                    )
                    let previousFramebufferSize = sessionClient.serverInit.map {
                        (width: $0.width, height: $0.height)
                    }
                    stateLock.lock()
                    resizeMachine.handleDesktopSizeResponse(response)
                    let queued = resizeMachine.takeQueuedTarget()
                    let presentation = resizeMachine.presentation
                    stateLock.unlock()
                    report(presentation)

                    // QEMU can repeat a successful ExtendedDesktopSize rectangle
                    // when a full update is requested even though the framebuffer
                    // did not change. Only rebuild the renderer and ask for another
                    // full frame when the dimensions actually changed; otherwise a
                    // response -> full update -> response loop starves input.
                    let framebufferSizeChanged = previousFramebufferSize?.width != response.width
                        || previousFramebufferSize?.height != response.height
                    if response.isSuccess, framebufferSizeChanged {
                        try sessionClient.applyDesktopSize(width: response.width, height: response.height)
                        if let appliedInit = sessionClient.serverInit {
                            renderer = try RFBFramebufferRenderer(serverInit: appliedInit)
                        }
                        try sendOnClient(sessionClient) {
                            try $0.requestFramebufferUpdate(incremental: false)
                        }
                    }

                    if let queued {
                        stateLock.lock()
                        resizeMachine.markRequestSent(
                            queued,
                            now: Date().timeIntervalSince1970
                        )
                        stateLock.unlock()
                        try sendOnClient(sessionClient) {
                            try $0.sendSetDesktopSize(
                                width: queued.widthInPixels,
                                height: queued.heightInPixels
                            )
                        }
                    }
                }

                stateLock.lock()
                let timedOut = resizeMachine.checkTimeout(now: now)
                let presentation = resizeMachine.presentation
                stateLock.unlock()
                if timedOut != nil {
                    report(presentation)
                }
            }
        } catch {
            guard !isWorkerStopped else {
                return
            }

            let message = Self.userFacingMessage(for: error)
            Task { @MainActor in
                onFailure(message)
            }
        }
    }

    private func sendOnClient(
        _ target: RFBFrameStreamClient,
        _ send: (RFBFrameStreamClient) throws -> Void
    ) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try send(target)
    }

    private var isWorkerStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }

    private func setStream(_ stream: RFBByteStream) {
        lock.lock()
        self.stream = stream
        lock.unlock()
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "Display stream unavailable"
    }
}

private extension RFBRenderedFrame {
    func makeNSImage() -> NSImage? {
        guard width > 0,
              height > 0,
              rgbaPixels.count >= width * height * 4,
              let provider = CGDataProvider(data: rgbaPixels as CFData) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
