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
        if model.health?.capabilities.windowLayout == true,
           let windowIds = GuestFramebufferSource.shared.cropListToReport() {
            Task { @MainActor in
                await model.setCroppedWindows(windowIds: windowIds)
            }
        }
    }

    /// Raises a window in Windows when its Mac window becomes key and another app's window covers it there,
    /// so the guest z-order follows the Mac's and the window can be cropped from the framebuffer again.
    /// Without this it stayed on captured frames until the first click reached it.
    func raiseGuestWindowForCrop(windowId: String) async {
        guard model.health?.capabilities.windowLayout == true,
              let window = GuestWindowLayoutStore.shared.latest?.windows.first(where: { $0.windowId == windowId }),
              window.isShown,
              !window.fullyVisible,
              !window.isForeground,
              model.mirrorSessions.first(where: { $0.id == windowId })?.window.isPopup == false else {
            return
        }
        _ = await model.focusMirrorSession(windowId: windowId)
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
