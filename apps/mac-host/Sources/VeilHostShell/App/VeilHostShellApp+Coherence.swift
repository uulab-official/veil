import AppKit
import Foundation
import VeilHostCore

extension VeilHostShellApp {
    /// Keeps the shared guest framebuffer connected while mirrored windows can use it: Windows is running
    /// with a loopback display, the agent sends `window.layout`, and at least one app window is mirrored.
    func syncGuestFramebufferSource() {
        let isNeeded = vmModel.snapshot?.state == .running
            && model.health?.capabilities.windowLayout == true
            && !model.mirrorSessions.isEmpty
        GuestFramebufferSource.shared.update(
            surface: vmModel.snapshot?.latestConsoleLaunch?.displaySurface,
            isNeeded: isNeeded
        )
        if isNeeded {
            fitMirroredWindowsOntoGuestDisplay()
        }
    }

    /// A mirrored window that reaches past the guest display or under the taskbar cannot be cropped from
    /// the framebuffer. Re-sending its size grows the display to fit (`MirroredWindowDisplayFit`) and lets
    /// the agent move the window back onto the work area. Sent once per window and size.
    private func fitMirroredWindowsOntoGuestDisplay() {
        guard let layout = GuestWindowLayoutStore.shared.latest,
              let screen = NSScreen.main?.frame.size else {
            return
        }

        for window in layout.windows where window.isShown && !window.fullyVisible {
            guard let session = model.mirrorSessions.first(where: { $0.id == window.windowId }),
                  !session.window.isPopup,
                  CoherenceDisplayFit.needsFit(window: window.frame, display: layout.display),
                  GuestFramebufferSource.shared.recordFitAttempt(windowId: window.windowId, frame: window.frame) else {
                continue
            }

            let scale = session.latestFrame?.scale ?? 1
            let width = Int((Double(window.frame.width) / max(scale, 0.5)).rounded())
            let height = Int((Double(window.frame.height) / max(scale, 0.5)).rounded())
            Task { @MainActor in
                _ = await model.resizeMirrorSession(
                    windowId: window.windowId,
                    width: width,
                    height: height,
                    macScreenWidth: Int(screen.width),
                    macScreenHeight: Int(screen.height)
                )
            }
        }
    }
}
