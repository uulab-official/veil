import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func restoreWindowsAppWindows() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
            for launch in restoredLaunches {
                showWindowsAppWindow(for: launch)
            }

            // restoreMirroredWindowsAfterReconnect() can come back empty either because there was
            // genuinely nothing to restore, or because every restore attempt failed -- those look
            // identical to the user (no windows reappear) unless the failure reason is surfaced here.
            if restoredLaunches.isEmpty, let errorMessage = model.errorMessage {
                displayMessage = "Could not restore previous Windows apps: \(errorMessage)"
            }

            if restoredLaunches.isEmpty,
               !model.hasLiveAgentConnection,
               model.canReconnectRestoreMirrorSessions {
                continuePreviousAppsRestoreHandoff()
            }

            syncLauncherWindowVisibility()
        }
    }

    private func continuePreviousAppsRestoreHandoff() {
        let handoff = PreviousAppsRestoreHandoffPolicy.action(
            runtimeState: vmModel.snapshot?.state,
            canStartRuntime: vmModel.canStart,
            supportsNativeDisplayWindow: vmRuntimeBooter.supportsNativeDisplayWindow
        )

        switch handoff {
        case .prepareGuestAgentRecovery(let shouldShowDisplay):
            activateMainWindow()
            displayMessage = "Windows is running. Veil is preparing the app connection to reconnect previous apps."
            scheduleAutomaticGuestAgentRecoveryIfNeeded()
            if shouldShowDisplay {
                showWindowsDisplay()
            }
        case .startRuntime:
            Task { @MainActor in
                cancelAutomaticQuietRuntime()
                activateMainWindow()
                // Resumes a suspended session rather than cold booting, so previous apps come back as
                // themselves instead of being relaunched into empty windows.
                await startOrResumeWindows()

                if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                    displayMessage = "Windows is running. Veil is preparing the app connection to reconnect previous apps."
                    scheduleAutomaticGuestAgentRecoveryIfNeeded()
                } else if let errorMessage = vmModel.errorMessage {
                    displayMessage = "Windows could not start for previous apps: \(errorMessage)"
                }
            }
        case .waitForRuntimeAvailability:
            displayMessage = "Veil found previous Windows apps to reconnect. Start Windows when setup is available."
        }
    }

    func focusWindowsAppWindow(windowId: String) {
        Task { @MainActor in
            let response = await model.focusMirrorSession(windowId: windowId)
            guard response?.accepted == true,
                  let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                return
            }

            // An explicit focus request is exactly the case that should raise a window.
            windowsAppWindowPresenter.showWindow(for: session, bringToFront: true)
            setForegroundWindowsAppMessage(windowId: windowId)
        }
    }

    func bringAllWindowsAppWindowsToFront() {
        windowsAppWindowPresenter.bringAllToFront()
        if let focusedSession = model.mirrorSessions.last {
            setForegroundWindowsAppMessage(windowId: focusedSession.id)
            focusWindowsAppWindow(windowId: focusedSession.id)
        }
    }

    func closeWindowsAppWindow(windowId: String) {
        Task { @MainActor in
            let response = await model.closeMirrorSession(windowId: windowId)
            guard response?.accepted == true else {
                return
            }

            windowsAppWindowPresenter.closeWindow(windowId: windowId)
            scheduleAutomaticQuietRuntimeIfNeeded()
            syncLauncherWindowVisibility()
        }
    }

    func closeAllWindowsAppWindows() {
        Task { @MainActor in
            let responses = await model.closeAllMirrorSessions()
            for response in responses where response.accepted {
                windowsAppWindowPresenter.closeWindow(windowId: response.windowId)
            }
            scheduleAutomaticQuietRuntimeIfNeeded()
            syncLauncherWindowVisibility()
        }
    }

    func restartStaleFrameStreams() {
        Task { @MainActor in
            await performFrameStreamMaintenance(automatic: false)
        }
    }

    @MainActor
    func performFrameStreamMaintenance(automatic: Bool) async {
        let result = await model.maintainStaleFrameStreams()
        guard result.didPerformMaintenance else {
            if !automatic {
                displayMessage = "No paused app screens need restart."
            }
            return
        }

        for reopened in result.reopenedWindows {
            windowsAppWindowPresenter.closeWindow(windowId: reopened.requestedWindowId)
            if let session = model.mirrorSessions.first(where: { $0.id == reopened.launch.window.windowId }) {
                windowsAppWindowPresenter.showWindow(for: session)
            }
        }

        for windowId in result.recoveredFrameWindowIds + result.restartedFrameWindowIds {
            if let session = model.mirrorSessions.first(where: { $0.id == windowId }) {
                windowsAppWindowPresenter.showWindow(for: session)
            }
        }

        if !result.reopenedWindows.isEmpty {
            displayMessage = result.reopenedWindows.count == 1
                ? "Reopening \(result.reopenedWindows[0].launch.window.title)."
                : "Reopening \(result.reopenedWindows.count) app windows."
        } else if !result.recoveredFrameWindowIds.isEmpty {
            displayMessage = result.recoveredFrameWindowIds.count == 1
                ? "Recovering app screen."
                : "Recovering \(result.recoveredFrameWindowIds.count) app screens."
        } else if !automatic {
            displayMessage = result.restartedFrameWindowIds.count == 1
                ? "Restarting app screen."
                : "Restarting \(result.restartedFrameWindowIds.count) app screens."
        }

        syncDockTileRuntimeStatus()
        syncLauncherWindowVisibility()
    }

    func configureDockMenuBridge() {
        appDelegate.reopenHandler = {
            let destination = LauncherReopenPolicy.destination(
                visibleMirroredWindowCount: windowsAppWindowPresenter.visibleWindowIds.count,
                modelRequestsHideLauncher: model.runtimeStatusReport().launcherVisibility.shouldHideMainWindow
            )

            switch destination {
            case .windowsAppWindows:
                bringAllWindowsAppWindowsToFront()
            case .mainWindow:
                activateMainWindow()
            }
        }
        appDelegate.dockMenuProvider = {
            AppRuntimeDockMenuFactory.makeMenu(
                model: model,
                vmModel: vmModel,
                activateMainWindowAction: activateMainWindow,
                bringAllWindowsAppWindowsToFrontAction: bringAllWindowsAppWindowsToFront,
                focusWindowsAppWindowAction: focusWindowsAppWindow(windowId:),
                closeWindowsAppWindowAction: closeWindowsAppWindow(windowId:),
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
                restartStaleFrameStreamsAction: restartStaleFrameStreams,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
                launchWindowsAppByIdAction: runOneClickAppLaunch(appId:),
                fulfillPendingLaunchAction: runOneClickPendingLaunch,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunch,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
                startVMAction: startWindowsAndShowDisplay,
                stopVMAction: stopWindowsAndCloseDisplay,
                quietWindowsWhenIdleAction: quietWindowsWhenIdle
            )
        }
    }

    func syncDockTileRuntimeStatus() {
        DockTileRuntimePresenter.update(model.runtimeStatusReport().dockIntegration)
    }

    func showWindowsAppWindow(for result: NotepadLaunchResult) {
        let session = model.mirrorSessions.first { $0.id == result.window.windowId }
                ?? WindowMirrorSession(
                    window: result.window,
                    connectionMode: model.connectionMode,
                    captureState: .unavailable
                )
        // An app the user just launched or restored should come forward. Content refreshes elsewhere
        // deliberately do not, so a background window's frames cannot steal focus.
        windowsAppWindowPresenter.showWindow(for: session, bringToFront: true)
        syncLauncherWindowVisibility()
    }

    private func setForegroundWindowsAppMessage(windowId: String) {
        guard let title = model.mirrorSessions.first(where: { $0.id == windowId })?.window.title else {
            return
        }

        displayMessage = "\(title) is frontmost as a macOS window."
    }

    func syncLauncherWindowVisibility() {
        if shouldHideLauncherWindowForCoherence() {
            MainWindowChrome.hideMainWindow()
        } else {
            MainWindowChrome.showMainWindow()
        }
    }

    private func shouldHideLauncherWindowForCoherence() -> Bool {
        LauncherWindowVisibilityPolicy.shouldHideLauncher(
            visibleMirroredWindowCount: windowsAppWindowPresenter.visibleWindowIds.count,
            modelRequestsHide: model.runtimeStatusReport().launcherVisibility.shouldHideMainWindow
        )
    }
}
