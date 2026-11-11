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
        let sharedSocket = vmModel.snapshot?.latestConsoleLaunch?.qmpSocketPath
            .map(QEMUSharedFramebuffer.socketPath(forQMPSocketPath:))
            .flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        GuestFramebufferSource.shared.update(
            surface: vmModel.snapshot?.latestConsoleLaunch?.displaySurface,
            sharedFramebufferSocketPath: sharedSocket,
            isNeeded: isNeeded
        )
        if isNeeded {
            matchGuestDisplayToMacScreen()
            fitMirroredWindowsOntoGuestDisplay()
            // Repeated placements are dropped by the scheduler, so this only sends windows that are
            // somewhere else in the guest, such as after a reconnect or a display change.
            for placement in windowsAppWindowPresenter.currentPlacements() {
                placeGuestWindow(windowId: placement.windowId, contentFrame: placement.contentFrame, screenFrame: placement.screenFrame)
            }
        }
        if model.health?.capabilities.windowLayout == true,
           let windowIds = GuestFramebufferSource.shared.cropListToReport() {
            Task { @MainActor in
                await model.setCroppedWindows(windowIds: windowIds)
            }
        }
    }

    /// Makes the guest display the size of the Mac screen in points while app windows are shown, so the
    /// guest layout can be the Mac layout (`CoherencePlacement`). The desktop view sizes the display to
    /// its own window instead, so this only runs in the apps view. Requested once per target size.
    private func matchGuestDisplayToMacScreen() {
        guard shellNavigation.viewMode == .apps,
              model.health?.capabilities.displayResize == true,
              let layout = GuestWindowLayoutStore.shared.latest,
              let screen = NSScreen.main?.frame,
              let target = CoherencePlacement.displayMatching(screenFrame: screen),
              layout.display.width != target.width || layout.display.height != target.height,
              GuestFramebufferSource.shared.recordDisplayRequest(target) else {
            return
        }
        Task { @MainActor in
            _ = await model.resizeDisplay(width: target.width, height: target.height)
        }
    }

    /// Moves a mirrored window in Windows to where its Mac window is. Called on every move and live-resize
    /// step; only the newest placement per window is sent, at most every 80 ms.
    func placeGuestWindow(windowId: String, contentFrame: CGRect, screenFrame: CGRect) {
        guard model.health?.capabilities.windowLayout == true,
              let layout = GuestWindowLayoutStore.shared.latest,
              let origin = CoherencePlacement.guestOrigin(contentFrame: contentFrame, screenFrame: screenFrame, display: layout.display),
              model.mirrorSessions.first(where: { $0.id == windowId })?.window.isPopup == false else {
            return
        }
        // Already there: nothing to send.
        if let frame = layout.windows.first(where: { $0.windowId == windowId })?.frame,
           frame.x == origin.x, frame.y == origin.y {
            return
        }
        GuestFramebufferSource.shared.schedulePlacement(windowId: windowId, x: origin.x, y: origin.y) { windowId, x, y in
            await model.moveMirrorSession(windowId: windowId, x: x, y: y)
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
