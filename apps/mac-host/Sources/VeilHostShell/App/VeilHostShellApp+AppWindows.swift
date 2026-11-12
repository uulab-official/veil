import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func restoreWindowsAppWindows() {
        shellNavigation.viewMode = .apps
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
                displayMessage = String(localized: "Could not restore previous Windows apps: \(errorMessage)")
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
                    displayMessage = String(localized: "Windows could not start for previous apps: \(errorMessage)")
                }
            }
        case .waitForRuntimeAvailability:
            displayMessage = "Veil found previous Windows apps to reconnect. Start Windows when setup is available."
        }
    }

    func focusWindowsAppWindow(windowId: String) {
        shellNavigation.viewMode = .apps
        Task { @MainActor in
            let response = await model.focusMirrorSession(windowId: windowId)
            guard response?.accepted == true else {
                activateMainWindow()
                displayMessage = model.errorMessage
                    ?? WindowsAppWindowPresentationFailure.mirrorSessionMissing.userMessage(
                        appName: "Windows app"
                    )
                return
            }

            presentWindowsAppWindowWhenReady(
                windowId: windowId,
                intent: .userRequested,
                bringToFront: true,
                successMessage: nil
            )
        }
    }

    func bringAllWindowsAppWindowsToFront() {
        shellNavigation.viewMode = .apps
        let knownWindowIds = Set(windowsAppWindowPresenter.visibleWindowIds)
        let sessions = model.mirrorSessions.filter { knownWindowIds.contains($0.id) }
        for session in sessions {
            _ = presentWindowsAppWindowWhenReady(
                windowId: session.id,
                expectedAppId: session.window.appId,
                intent: .userRequested,
                bringToFront: true,
                successMessage: nil
            )
        }
        if let focusedSession = sessions.last {
            focusWindowsAppWindow(windowId: focusedSession.id)
        } else {
            activateMainWindow()
            displayMessage = WindowsAppWindowPresentationFailure.mirrorSessionMissing.userMessage(
                appName: "Windows app"
            )
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
        if automatic {
            _ = await oneClickAppFrameMutationGate.runAutomaticMaintenance {
                await performFrameStreamMaintenanceWork(automatic: true)
            }
            return
        }

        let started = await oneClickAppFrameMutationGate.runManualRecovery {
            await performFrameStreamMaintenanceWork(automatic: false)
        }
        if !started {
            displayMessage = "An app screen is already opening or refreshing. Please wait for it to finish."
        }
    }

    @MainActor
    private func performFrameStreamMaintenanceWork(automatic: Bool) async {
        let appIdsByWindowId = Dictionary(
            uniqueKeysWithValues: model.mirrorSessions.map { ($0.id, $0.window.appId) }
        )
        let result = await model.maintainStaleFrameStreams(reopensWindows: !automatic)
        guard result.didPerformMaintenance else {
            if !automatic {
                displayMessage = "No paused app screens need restart."
            }
            return
        }

        var manualPresentationBlocked = false
        for reopened in result.reopenedWindows {
            windowsAppWindowPresenter.closeWindow(windowId: reopened.requestedWindowId)
            let windowId = reopened.launch.window.windowId
            if automatic {
                if let session = model.mirrorSessions.first(where: { $0.id == windowId }) {
                    presentWindowsAppWindowForEvent(session)
                }
            } else {
                let presented = await waitAndPresentRecoveredWindowsAppWindow(
                    windowId: windowId,
                    expectedAppId: reopened.launch.window.appId,
                    successMessage: "Reopened \(reopened.launch.window.title)."
                )
                manualPresentationBlocked = !presented || manualPresentationBlocked
            }
        }

        for windowId in result.recoveredFrameWindowIds + result.restartedFrameWindowIds {
            if automatic {
                if let session = model.mirrorSessions.first(where: { $0.id == windowId }) {
                    presentWindowsAppWindowForEvent(session)
                }
            } else {
                let presented = await waitAndPresentRecoveredWindowsAppWindow(
                    windowId: windowId,
                    expectedAppId: appIdsByWindowId[windowId],
                    successMessage: "Refreshed Windows app screen."
                )
                manualPresentationBlocked = !presented || manualPresentationBlocked
            }
        }

        if automatic && !manualPresentationBlocked {
            if !result.reopenedWindows.isEmpty {
                displayMessage = result.reopenedWindows.count == 1
                    ? String(localized: "Reopening \(result.reopenedWindows[0].launch.window.title).")
                    : String(localized: "Reopening \(result.reopenedWindows.count) app windows.")
            } else if !result.recoveredFrameWindowIds.isEmpty {
                displayMessage = result.recoveredFrameWindowIds.count == 1
                    ? "Recovering app screen."
                    : String(localized: "Recovering \(result.recoveredFrameWindowIds.count) app screens.")
            } else if !automatic {
                displayMessage = result.restartedFrameWindowIds.count == 1
                    ? "Restarting app screen."
                    : String(localized: "Restarting \(result.restartedFrameWindowIds.count) app screens.")
            }
        }

        syncDockTileRuntimeStatus()
        syncLauncherWindowVisibility()
    }

    func configureDockMenuBridge() {
        appDelegate.terminationHandler = {
            await suspendWindowsForQuitIfNeeded()
        }
        appDelegate.reopenHandler = {
            let destination = LauncherReopenPolicy.destination(
                visibleMirroredWindowCount: windowsAppWindowPresenter.visibleWindowIds.count,
                modelRequestsHideLauncher: model.runtimeStatusReport().launcherVisibility.shouldHideMainWindow
            )

            // Clicking the Dock icon while the desktop shows returns to it rather than leaving the mode.
            guard shellNavigation.viewMode == .apps else {
                activateMainWindow()
                return
            }
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

    enum WindowsAppPresentationIntent {
        case launchCompletion
        case userRequested
    }

    @discardableResult
    func waitAndPresentRecoveredWindowsAppWindow(
        windowId: String,
        expectedAppId: String?,
        successMessage: String
    ) async -> Bool {
        let appName = model.mirrorSessions.first { $0.id == windowId }?.window.title ?? "Windows app"
        displayMessage = String(localized: "Refreshing \(appName) screen.")
        do {
            let decision = try await WindowsAppWindowPresentationReadiness.wait(
                timeoutSeconds: OneClickAppLaunchCoordinator.firstFrameWaitSeconds,
                sessionProvider: {
                    model.mirrorSessions.first {
                        $0.id == windowId && (expectedAppId == nil || $0.window.appId == expectedAppId)
                    }
                },
                compositedImageProvider: { model.compositedFrameImage(for: $0) }
            )
            if case .blocked(let failure) = decision {
                activateMainWindow()
                displayMessage = failure.userMessage(appName: appName)
                return false
            }
            try Task.checkCancellation()
            return presentWindowsAppWindowWhenReady(
                windowId: windowId, expectedAppId: expectedAppId,
                intent: .userRequested, bringToFront: true, successMessage: successMessage
            )
        } catch {
            displayMessage = "App screen refresh was cancelled. You can try again when you are ready."
            return false
        }
    }

    func showWindowsAppWindow(for result: NotepadLaunchResult) {
        guard let session = model.mirrorSessions.first(where: {
            $0.id == result.window.windowId && $0.window.appId == result.window.appId
        }) else {
            MainWindowChrome.showMainWindow()
            return
        }

        _ = presentWindowsAppWindowForEvent(session, bringToFront: true)
    }

    @discardableResult
    func presentWindowsAppWindowWhenReady(
        windowId: String,
        expectedAppId: String? = nil,
        intent: WindowsAppPresentationIntent,
        bringToFront: Bool,
        successMessage: String?
    ) -> Bool {
        let session = model.mirrorSessions.first { session in
            session.id == windowId && (expectedAppId == nil || session.window.appId == expectedAppId)
        }
        let appId = session?.window.appId ?? expectedAppId
        let appName = session?.window.title
            ?? appId.flatMap { expectedId in model.apps.first { $0.id == expectedId }?.name }
            ?? "Windows app"
        let decision = WindowsAppWindowPresentationReadiness.resolve(
            session: session,
            compositedImage: session.map { model.compositedFrameImage(for: $0.id) } ?? nil
        )
        let authorized: Bool
        if let session {
            switch intent {
            case .launchCompletion:
                authorized = oneClickAppWindowPresentationGate.authorizeLaunchPresentation(
                    appId: session.window.appId,
                    windowId: session.id,
                    decision: decision
                )
            case .userRequested:
                authorized = oneClickAppWindowPresentationGate.authorizeUserPresentation(
                    appId: session.window.appId,
                    windowId: session.id,
                    decision: decision
                )
            }
        } else {
            authorized = false
        }

        guard authorized, let session else {
            if case .launchCompletion = intent {
                oneClickAppWindowPresentationGate.finishBlockedLaunch()
            }
            let failure: WindowsAppWindowPresentationFailure
            if case .blocked(let resolvedFailure) = decision {
                failure = resolvedFailure
            } else {
                failure = .firstFramePending
            }
            activateMainWindow()
            displayMessage = failure.userMessage(appName: appName)
            return false
        }

        windowsAppWindowPresenter.showWindow(for: session, bringToFront: bringToFront)
        syncWindowsAppLauncher(for: session)
        if let successMessage {
            displayMessage = successMessage
        } else if bringToFront {
            setForegroundWindowsAppMessage(windowId: session.id)
        }
        syncLauncherWindowVisibility()
        return true
    }

    @discardableResult
    func presentWindowsAppWindowForEvent(
        _ session: WindowMirrorSession,
        bringToFront: Bool = false
    ) -> Bool {
        let isAlreadyVisible = windowsAppWindowPresenter.visibleWindowIds.contains(session.id)
        if !isAlreadyVisible,
           WindowsAppWindowPresentationReadiness.resolve(
               session: session,
               compositedImage: model.compositedFrameImage(for: session.id)
           ) != .ready {
            // The main window shows a launch's progress, and only while no Windows app is on screen yet. A
            // window Windows opened by itself has no launch to show, and with other apps already open the
            // new one simply appears; Veil's main window coming forward would cover what the person is doing.
            syncLauncherWindowVisibility()
            return false
        }
        guard oneClickAppWindowPresentationGate.allowsEventDrivenPresentation(
            appId: session.window.appId,
            windowId: session.id,
            isAlreadyVisible: isAlreadyVisible
        ) else {
            syncLauncherWindowVisibility()
            return false
        }

        // A window that opens while the person works in another Mac app appears without taking the keyboard.
        windowsAppWindowPresenter.showWindow(
            for: session,
            bringToFront: bringToFront,
            activatesApplication: NSApp.isActive
        )
        syncWindowsAppLauncher(for: session)
        refreshAppListForUnknownApp(session.window.appId)
        return true
    }

    /// A window can belong to an app that is not in the list yet, such as File Explorer, which Windows only
    /// reports once it has a window. Its name and icon come with the next app list.
    private func refreshAppListForUnknownApp(_ appId: String) {
        guard !model.apps.contains(where: { $0.id == appId }),
              windowsAppWindowPresenter.appIdsAwaitingIdentity.insert(appId).inserted else {
            return
        }
        Task { @MainActor in
            await model.refreshApps()
            windowsAppWindowPresenter.refreshIdentities()
        }
    }

    private func setForegroundWindowsAppMessage(windowId: String) {
        guard let title = model.mirrorSessions.first(where: { $0.id == windowId })?.window.title else {
            return
        }

        displayMessage = String(localized: "\(title) is frontmost as a macOS window.")
    }

    /// Makes the two viewing modes exclusive, the way Parallels switches between Window mode and Coherence:
    /// the full desktop takes every mirrored window off screen and pauses its frames, and apps mode puts
    /// them back and closes the separate desktop window. Nothing in the guest is closed either way.
    func applyViewMode(_ mode: MachineViewMode) {
        switch mode {
        case .desktop:
            windowsAppWindowPresenter.hideAllForDesktop()
            MainWindowChrome.showMainWindow()
        case .apps:
            // The desktop view resizes Windows to its window, so the size mirrored windows last set is stale.
            model.forgetGuestDisplaySize()
            qemuConsoleWindowPresenter.closeConsole()
            windowsAppWindowPresenter.showAllAfterDesktop()
            syncLauncherWindowVisibility()
        }
    }

    func syncLauncherWindowVisibility() {
        // The main window is where the desktop shows, so it stays up however many apps are mirrored.
        if shellNavigation.viewMode == .desktop {
            MainWindowChrome.showMainWindow()
        } else if shouldHideLauncherWindowForCoherence() {
            MainWindowChrome.hideMainWindow()
        } else {
            MainWindowChrome.showMainWindow()
        }
    }

    private func shouldHideLauncherWindowForCoherence() -> Bool {
        if oneClickAppWindowPresentationGate.keepsLauncherVisible,
           windowsAppWindowPresenter.visibleWindowIds.isEmpty {
            return false
        }

        return LauncherWindowVisibilityPolicy.shouldHideLauncher(
            visibleMirroredWindowCount: windowsAppWindowPresenter.visibleWindowIds.count,
            modelRequestsHide: model.runtimeStatusReport().launcherVisibility.shouldHideMainWindow,
            lastAppClosedByUser: launcherDismissedWithLastApp
        )
    }
}
