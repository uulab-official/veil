import CoreGraphics
import Foundation
import VeilHostCore

/// The whole guest display, received over QEMU's loopback VNC server, shared by every mirrored window.
///
/// Each mirrored window whose `window.layout` entry is fully visible crops its pixels from these frames
/// instead of waiting for frames the agent captures, diffs, and encodes. The connection is passive: it
/// sends no input and never moves the guest pointer. See
/// docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md.
@MainActor
final class GuestFramebufferSource {
    static let shared = GuestFramebufferSource()

    private let display = RFBEmbeddedDisplayModel()
    private var sinks: [UUID: (CGImage) -> Void] = [:]
    private(set) var latestFrame: CGImage?

    private init() {
        display.wakesDisplayOnConnect = false
        display.frameSink = { [weak self] image in
            self?.deliver(image)
        }
    }

    /// Connects while `surface` is a live loopback display and `isNeeded` holds, and disconnects otherwise.
    func update(surface: VMConsoleDisplaySurface?, isNeeded: Bool) {
        guard isNeeded, let surface, surface.kind == .vncLoopback else {
            if display.activeEndpoint != nil {
                display.stop()
            }
            latestFrame = nil
            return
        }
        display.connectIfNeeded(to: surface)
    }

    var isReceiving: Bool {
        display.isReceiving
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

    private func deliver(_ image: CGImage) {
        latestFrame = image
        for sink in sinks.values {
            sink(image)
        }
    }
}
