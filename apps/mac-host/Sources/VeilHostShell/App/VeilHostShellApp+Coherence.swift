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
        DisplayResolutionPreference.guestCanSetScale = model.canSetDisplayScale
        if shellNavigation.viewMode != .apps {
            syncScaleOutsideAppsView()
        }
        if isNeeded {
            matchGuestDisplayToMacScreen()
            fitMirroredWindowsOntoGuestDisplay()
            // Repeated placements are dropped by the scheduler, so this only sends windows that are
            // somewhere else in the guest, such as after a reconnect or a display change.
            for placement in windowsAppWindowPresenter.currentPlacements() {
                placeGuestWindow(windowId: placement.windowId, contentFrame: placement.contentFrame, screenFrame: placement.screenFrame)
            }
        }
        // The Windows taskbar is hidden while apps show as their own windows, and back in the desktop view.
        let hidesDesktop = isNeeded && shellNavigation.viewMode == .apps
        if model.health?.capabilities.windowLayout == true,
           let windowIds = GuestFramebufferSource.shared.cropListToReport(hidesDesktop: hidesDesktop) {
            Task { @MainActor in
                await model.setCroppedWindows(windowIds: windowIds, hidesDesktop: hidesDesktop)
            }
        }
    }

    /// Makes the guest display the Mac screen's size while app windows are shown, so the guest layout can be
    /// the Mac layout (`CoherencePlacement`). With Retina resolution on a Retina Mac it is twice the screen
    /// in points and Windows runs at 200%, so windows keep their size in points and get four times the
    /// pixels (`CoherenceDisplayScale`). The desktop view sizes the display to its own window instead, so
    /// this only runs in the apps view. Each size and scale is requested once.
    private func matchGuestDisplayToMacScreen() {
        let source = GuestFramebufferSource.shared
        guard shellNavigation.viewMode == .apps,
              model.health?.capabilities.displayResize == true,
              !source.isApplyingDisplayScale,
              let layout = GuestWindowLayoutStore.shared.latest,
              let screen = NSScreen.main,
              let target = CoherenceDisplayScale.target(
                screenFrame: screen.frame,
                backingScale: Double(screen.backingScaleFactor),
                retinaEnabled: DisplayResolutionPreference.isRetinaResolutionEnabled(guestCanSetScale: model.canSetDisplayScale),
                agentCanScale: model.canSetDisplayScale,
                scaleRefused: source.scaleRefused
              ) else {
            return
        }

        let wantedScale = GuestFramebufferSource.RequestedScale(percent: target.scalePercent, display: nil)
        let changesScale = model.canSetDisplayScale && source.requestedScale != wantedScale
        let resizes = (layout.display.width != target.display.width || layout.display.height != target.display.height)
            && source.recordDisplayRequest(target.display)
        guard changesScale || resizes else {
            source.coherencePixelsPerPoint = target.pixelsPerPoint
            return
        }

        source.isApplyingDisplayScale = true
        let resizesFirst = CoherenceDisplayScale.resizesDisplayFirst(
            fromScalePercent: source.reportedScalePercent,
            toScalePercent: target.scalePercent
        )
        Task { @MainActor in
            defer {
                source.isApplyingDisplayScale = false
            }
            if resizes, resizesFirst {
                _ = await model.resizeDisplay(width: target.display.width, height: target.display.height)
            }
            if changesScale {
                let reported = await model.setDisplayScale(scalePercent: target.scalePercent)
                source.requestedScale = wantedScale
                source.reportedScalePercent = reported
                if let wanted = target.scalePercent, reported != wanted {
                    // Windows did not take it: go back to one pixel per point on the next layout.
                    VeilLog.window.notice("Windows did not take \(wanted, privacy: .public)% scale; staying at one pixel per point")
                    source.scaleRefused = true
                }
            }
            if resizes, !resizesFirst {
                _ = await model.resizeDisplay(width: target.display.width, height: target.display.height)
            }
            source.coherencePixelsPerPoint = source.scaleRefused ? 1 : target.pixelsPerPoint
        }
    }

    /// Outside the apps view the guest display follows the desktop view's window, sized with
    /// `DisplayResolutionPreference.guestPixelsPerPoint`, so Windows' scale follows the same choice: 200%
    /// with Retina resolution on a Retina Mac, the user's own otherwise. It is asked again whenever the
    /// display size changes, since Windows lowers a step a small display cannot take.
    private func syncScaleOutsideAppsView() {
        let source = GuestFramebufferSource.shared
        source.coherencePixelsPerPoint = 1
        guard model.canSetDisplayScale, !source.isApplyingDisplayScale else {
            return
        }
        let wanted = DisplayResolutionPreference.windowsScalePercent(
            guestPixelsPerPoint: DisplayResolutionPreference.guestPixelsPerPoint(
                screenScale: NSScreen.main?.backingScaleFactor
            )
        )
        let request = GuestFramebufferSource.RequestedScale(
            percent: wanted,
            display: wanted == nil ? nil : GuestWindowLayoutStore.shared.latest.map {
                GuestDisplaySize(width: $0.display.width, height: $0.display.height)
            }
        )
        guard source.requestedScale != request else {
            return
        }
        source.isApplyingDisplayScale = true
        Task { @MainActor in
            defer {
                source.isApplyingDisplayScale = false
            }
            source.reportedScalePercent = await model.setDisplayScale(scalePercent: wanted)
            source.requestedScale = request
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
                    macScreenHeight: Int(screen.height),
                    pixelsPerPoint: GuestFramebufferSource.shared.coherencePixelsPerPoint
                )
            }
        }
    }
}
