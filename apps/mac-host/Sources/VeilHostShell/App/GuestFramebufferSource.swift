import CoreGraphics
import Foundation
import VeilHostCore

/// The whole guest display, shared by every mirrored window. It comes from Veil's patched QEMU through
/// shared memory (`QEMUSharedFramebuffer`) when the launch has it, and otherwise from QEMU's loopback VNC
/// server, whose 30 ms refresh tick caps it near 33 frames a second.
///
/// Each mirrored window whose `window.layout` entry is fully visible crops its pixels from these frames
/// instead of waiting for frames the agent captures, diffs, and encodes. The connection is passive: it
/// sends no input and never moves the guest pointer. See
/// docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md.
@MainActor
final class GuestFramebufferSource {
    static let shared = GuestFramebufferSource()

    private let display = RFBEmbeddedDisplayModel()
    private var sharedClient: SharedFramebufferClient?
    private var sharedSocketPath: String?
    private var sinks: [UUID: (CGImage) -> Void] = [:]
    private(set) var latestFrame: CGImage?

    private init() {
        display.wakesDisplayOnConnect = false
        display.frameSink = { [weak self] image in
            self?.deliver(image)
        }
    }

    /// Connects while `isNeeded` holds: to the shared framebuffer socket when there is one, otherwise to
    /// `surface` when it is a live loopback display. Disconnects otherwise.
    func update(surface: VMConsoleDisplaySurface?, sharedFramebufferSocketPath: String?, isNeeded: Bool) {
        guard isNeeded else {
            stopShared()
            stopVNC()
            latestFrame = nil
            return
        }

        if let sharedFramebufferSocketPath {
            stopVNC()
            guard sharedSocketPath != sharedFramebufferSocketPath else {
                return
            }
            stopShared()
            sharedSocketPath = sharedFramebufferSocketPath
            let client = SharedFramebufferClient(socketPath: sharedFramebufferSocketPath) { [weak self] image in
                self?.deliver(image)
            }
            sharedClient = client
            client.start()
            VeilLog.window.notice("Guest framebuffer from shared memory at \(sharedFramebufferSocketPath, privacy: .public)")
            return
        }

        stopShared()
        guard let surface, surface.kind == .vncLoopback else {
            stopVNC()
            latestFrame = nil
            return
        }
        display.connectIfNeeded(to: surface)
    }

    /// Which source frames come from, for diagnostics.
    var sourceName: String {
        if sharedClient != nil {
            return "sharedMemory"
        }
        return display.activeEndpoint == nil ? "none" : "vnc"
    }

    private func stopShared() {
        sharedClient?.stop()
        sharedClient = nil
        sharedSocketPath = nil
    }

    private func stopVNC() {
        if display.activeEndpoint != nil {
            display.stop()
        }
    }

    func addSink(_ sink: @escaping (CGImage) -> Void) -> UUID {
        let token = UUID()
        sinks[token] = sink
        if let latestFrame {
            sink(latestFrame)
        }
        return token
    }

    func removeSink(_ token: UUID) {
        sinks[token] = nil
    }

    private var fitAttempts: [String: GuestPixelRect] = [:]
    /// Windows whose view currently shows the cropped framebuffer instead of captured frames.
    private(set) var croppingWindowIds: Set<String> = []
    private var lastReportedCrop: (windowIds: Set<String>, at: Date)?

    func setCropping(windowId: String, _ isCropping: Bool) {
        if isCropping {
            croppingWindowIds.insert(windowId)
        } else {
            croppingWindowIds.remove(windowId)
        }
    }

    /// The crop list to send the agent now, or nil when it was sent recently and has not changed. The agent
    /// lets a list lapse after six seconds, so it is repeated every two.
    func cropListToReport(now: Date = Date()) -> [String]? {
        if let lastReportedCrop,
           lastReportedCrop.windowIds == croppingWindowIds,
           now.timeIntervalSince(lastReportedCrop.at) < 2 {
            return nil
        }
        lastReportedCrop = (croppingWindowIds, now)
        return croppingWindowIds.sorted()
    }

    /// True the first time a window is fitted at this frame, so a window that still does not fit is not
    /// resized again on every layout.
    func recordFitAttempt(windowId: String, frame: GuestPixelRect) -> Bool {
        guard fitAttempts[windowId] != frame else {
            return false
        }
        fitAttempts[windowId] = frame
        return true
    }

    /// When recent frames arrived, for the debug statistics below.
    private var recentFrameTimes: [Date] = []

    /// The frame source and how many frames arrived in the last five seconds.
    func statistics(now: Date = Date()) -> [String: Any] {
        let recent = recentFrameTimes.filter { now.timeIntervalSince($0) <= 5 }
        return [
            "source": sourceName,
            "framesLast5s": recent.count,
            "framesPerSecond": Double(recent.count) / 5,
            "croppingWindowIds": croppingWindowIds.sorted()
        ]
    }

    private func deliver(_ image: CGImage) {
        let now = Date()
        recentFrameTimes.append(now)
        if recentFrameTimes.count > 1_200 {
            recentFrameTimes.removeFirst(recentFrameTimes.count - 1_200)
        }
        latestFrame = image
        for sink in sinks.values {
            sink(image)
        }
    }
}
