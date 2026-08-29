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
    @ObservationIgnored private var worker: RFBEmbeddedDisplayWorker?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var connectionGeneration = 0
    @ObservationIgnored private var retryDelaySeconds: Double = 1

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
                if presentation == .available,
                   let pending = self.pendingResizeTarget {
                    self.pendingResizeTarget = nil
                    self.worker?.requestDesktopResize(width: pending.width, height: pending.height)
                }
            }
        )
    }

    /// Forwards a settled host-window target to the live RFB connection. Targets
    /// that arrive before the capability probe completes are held and flushed when
    /// the connection reports available; unsupported connections keep holding them
    /// so the desktop stays at its stable aspect-fit size.
    func requestDesktopResize(width: Int, height: Int) {
        if resizePresentation == .available, let worker {
            worker.requestDesktopResize(width: width, height: height)
            return
        }

        pendingResizeTarget = (width, height)
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
        status = .connecting

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
        connectionGeneration += 1
        worker?.stop()
        worker = nil
        activeEndpoint = nil
        frameSequence = nil
        resizePresentation = .unavailable
        pendingResizeTarget = nil
        status = .idle
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
        guard let activeClient else {
            return
        }

        let now = Date().timeIntervalSince1970
        let target = RFBDesktopResizeTarget(widthInPixels: width, heightInPixels: height)
        stateLock.lock()
        let shouldSend = resizeMachine.request(target) != nil
        stateLock.unlock()
        guard shouldSend else {
            return
        }

        do {
            try sendOnClient(activeClient) {
                try $0.sendSetDesktopSize(width: width, height: height)
            }
            stateLock.lock()
            resizeMachine.markRequestSent(target, now: now)
            stateLock.unlock()
        } catch {
            // The run loop observes the same socket failure and starts the retry path.
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
                    stateLock.lock()
                    resizeMachine.handleDesktopSizeResponse(response)
                    let queued = resizeMachine.takeQueuedTarget()
                    let presentation = resizeMachine.presentation
                    stateLock.unlock()
                    report(presentation)

                    if response.isSuccess {
                        try sessionClient.applyDesktopSize(width: response.width, height: response.height)
                        if let appliedInit = sessionClient.serverInit {
                            renderer = try RFBFramebufferRenderer(serverInit: appliedInit)
                        }
                        try sendOnClient(sessionClient) {
                            try $0.requestFramebufferUpdate(incremental: false)
                        }
                    }

                    if let queued {
                        try sendOnClient(sessionClient) {
                            try $0.sendSetDesktopSize(
                                width: queued.widthInPixels,
                                height: queued.heightInPixels
                            )
                        }
                        stateLock.lock()
                        resizeMachine.markRequestSent(
                            queued,
                            now: Date().timeIntervalSince1970
                        )
                        stateLock.unlock()
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
