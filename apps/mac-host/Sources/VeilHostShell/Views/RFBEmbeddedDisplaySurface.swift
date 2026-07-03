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
    private(set) var activeEndpoint: String?
    @ObservationIgnored private var worker: RFBEmbeddedDisplayWorker?

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
        image = nil
        frameSequence = nil
        status = .connecting

        guard let parsedEndpoint = RFBDisplayEndpoint(endpoint) else {
            status = .failed("Display endpoint unavailable")
            return
        }

        let worker = RFBEmbeddedDisplayWorker(endpoint: parsedEndpoint)
        self.worker = worker
        worker.start(
            onFrame: { [weak self] frame in
                guard let image = frame.makeNSImage() else {
                    self?.status = .failed("Display frame unavailable")
                    return
                }

                self?.image = image
                self?.frameSequence = frame.sequence
                self?.status = .receiving
            },
            onFailure: { [weak self] message in
                guard self?.activeEndpoint == endpoint else {
                    return
                }

                self?.status = .failed(message)
            }
        )
    }

    func stop() {
        worker?.stop()
        worker = nil
        activeEndpoint = nil
        frameSequence = nil
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
    private var isStopped = false
    private var stream: RFBByteStream?

    init(endpoint: RFBDisplayEndpoint) {
        self.endpoint = endpoint
    }

    func start(
        onFrame: @escaping @MainActor (RFBRenderedFrame) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        queue.async { [weak self] in
            self?.run(onFrame: onFrame, onFailure: onFailure)
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        stream?.close()
        stream = nil
        lock.unlock()
    }

    private func run(
        onFrame: @escaping @MainActor (RFBRenderedFrame) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        do {
            let socket = try RFBLoopbackSocket(host: endpoint.host, port: endpoint.port)
            setStream(socket)
            let client = RFBFrameStreamClient(stream: socket)
            let serverInit = try client.startSharedSession()
            let renderer = try RFBFramebufferRenderer(serverInit: serverInit)
            try client.requestFramebufferUpdate(incremental: false)

            while !isWorkerStopped {
                let update = try client.readFramebufferUpdate()
                let frame = try renderer.apply(update)
                Task { @MainActor in
                    onFrame(frame)
                }

                try client.requestFramebufferUpdate(incremental: true)
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
