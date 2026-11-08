import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    private func recoverWindowsAppScreen(windowId: String) async {
        let sessionBeforeRecovery = model.mirrorSessions.first(where: { $0.id == windowId })
        let assessment = sessionBeforeRecovery.map { WindowFrameStreamAssessment.assess(session: $0) }
        if assessment?.reopenEscalated == true,
           let result = await model.reopenAppWindow(windowId: windowId) {
            windowsAppWindowPresenter.closeWindow(windowId: result.requestedWindowId)
            await waitAndPresentRecoveredWindowsAppWindow(
                windowId: result.launch.window.windowId,
                expectedAppId: result.launch.window.appId,
                successMessage: "Reopened \(result.launch.window.title)."
            )
            syncLauncherWindowVisibility()
            return
        }

        let shouldRecover = assessment?.recoveryEscalated == true
        let didRecover: Bool
        if shouldRecover {
            didRecover = await model.recoverFrameCapture(windowId: windowId)
        } else {
            didRecover = await model.restartFrameSubscription(windowId: windowId)
        }
        guard didRecover else {
            activateMainWindow()
            displayMessage = model.errorMessage
                ?? "Veil could not refresh this Windows app screen. Try the recovery action again."
            return
        }

        await waitAndPresentRecoveredWindowsAppWindow(
            windowId: windowId,
            expectedAppId: sessionBeforeRecovery?.window.appId,
            successMessage: shouldRecover ? "Recovered app screen." : "Restarted app screen."
        )
    }

    func configureWindowsAppWindowCloseBridge() {
        windowsAppWindowPresenter.appIdentityProvider = { appId in
            WindowsAppWindowIdentity.resolve(appId: appId, apps: model.apps)
        }
        windowsAppWindowPresenter.onUserWindowClose = { windowId in
            Task { @MainActor in
                _ = await model.closeMirrorSession(windowId: windowId)
                scheduleAutomaticQuietRuntimeIfNeeded()
                syncLauncherWindowVisibility()
            }
        }
        windowsAppWindowPresenter.onMouseInput = { windowId, event, x, y in
            Task { @MainActor in
                await model.sendMouseInput(windowId: windowId, event: event, x: x, y: y)
            }
        }
        windowsAppWindowPresenter.onKeyInput = { windowId, event, key, windowsVirtualKey, modifiers in
            Task { @MainActor in
                await model.sendKeyInput(
                    windowId: windowId,
                    event: event,
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            }
        }
        windowsAppWindowPresenter.onWindowVisibilityChange = { windowId, isVisible in
            Task { @MainActor in
                if isVisible {
                    await model.resumeFrameStream(windowId: windowId)
                } else {
                    await model.pauseFrameStream(windowId: windowId)
                }
            }
        }
        windowsAppWindowPresenter.onWindowResize = { windowId, width, height in
            Task { @MainActor in
                _ = await model.resizeMirrorSession(windowId: windowId, width: width, height: height)
            }
        }
        windowsAppWindowPresenter.onDropRefused = { refusal in
            Task { @MainActor in
                model.recordFileDropRefusal(refusal)
            }
        }
        windowsAppWindowPresenter.onFileDrop = { appId, windowId, fileName, contentBase64 in
            Task { @MainActor in
                await model.openFile(appId: appId, fileName: fileName, contentBase64: contentBase64)
                // Windows reports failures the host cannot predict: the app was uninstalled, the write
                // failed, the launch failed. `openFile` records those as drop refusals, so they belong on
                // the same sheet as the checks the host made itself.
                if let refusal = model.lastFileDropRefusal {
                    windowsAppWindowPresenter.showDropRefusal(refusal, windowId: windowId)
                }
            }
        }
        windowsAppWindowPresenter.onRestartFrameStream = { windowId in
            Task { @MainActor in
                let started = await oneClickAppFrameMutationGate.runManualRecovery {
                    await recoverWindowsAppScreen(windowId: windowId)
                }
                if !started {
                    displayMessage = "An app screen is already opening or refreshing. Please wait for it to finish."
                }
            }
        }
        windowsAppWindowPresenter.compositedImageProvider = { windowId in
            model.compositedFrameImage(for: windowId)
        }
        windowsAppWindowPresenter.sessionProvider = { windowId in
            model.mirrorSessions.first { $0.id == windowId }
        }
        windowsAppWindowPresenter.onTextInput = { windowId, text in
            Task { @MainActor in
                await model.sendTextInput(windowId: windowId, text: text)
            }
        }
        windowsAppWindowPresenter.onPasteShortcut = { windowId, key, windowsVirtualKey, modifiers, content in
            Task { @MainActor in
                // Ctrl+V does not fail when the clipboard write did. It pastes whatever Windows had before,
                // into the user's document, with nothing to indicate the content is stale. So a clipboard write
                // that could not be delivered cancels the paste instead of completing it with wrong content.
                let clipboardOutcome: HostClipboardSendOutcome
                switch content {
                case .text(let text):
                    clipboardOutcome = await model.sendHostClipboardText(text)
                case .image(let png):
                    clipboardOutcome = await model.sendHostClipboardImage(png: png)
                case .files(let urls):
                    clipboardOutcome = await sendHostClipboardFiles(urls)
                }
                if case .failed(let reason) = clipboardOutcome {
                    windowsAppWindowPresenter.showWindowsAppMessage(
                        title: String(localized: "Veil could not paste into Windows"),
                        detail: String(localized: "The clipboard could not be sent, so nothing was pasted rather than pasting older content.") + " \(reason)",
                        windowId: windowId
                    )
                    return
                }
                await model.sendKeyInput(
                    windowId: windowId,
                    event: "keyDown",
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
                await model.sendKeyInput(
                    windowId: windowId,
                    event: "keyUp",
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            }
        }
    }

    /// Copies the Finder selection into the shared folder, then names it to the guest. The copy happens here,
    /// at paste time, so only files the user chose to paste ever reach Windows.
    @MainActor
    func sendHostClipboardFiles(_ urls: [URL]) async -> HostClipboardSendOutcome {
        let transport = QEMUWindowsSharedFolderTransport.guestSMB
        let mount = VMSharedFolderHostMountProbe.read(transport: transport)
        guard mount.isMounted, let mountPath = mount.mountPath else {
            return .failed(reason: ClipboardFilePasteRefusal.sharedFolderUnavailable.localizedDescription)
        }
        guard model.canSendHostClipboardFiles else {
            return .failed(reason: HostDashboardServiceError.clipboardFormatUnsupported.localizedDescription)
        }

        let plan: ClipboardFilePastePlan
        do {
            plan = try ClipboardFilePaste.plan(fileURLs: urls)
        } catch {
            return .failed(reason: error.localizedDescription)
        }

        // Up to 512 MiB over SMB; off the main actor so the window keeps drawing while it copies.
        let shareRoot = URL(filePath: mountPath, directoryHint: .isDirectory)
        let copyFailure = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try ClipboardFilePaste.copy(plan, intoShareAt: shareRoot)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let copyFailure {
            return .failed(reason: copyFailure)
        }

        return await model.sendHostClipboardFiles(
            shareName: QEMUWindowsSharedFolderTransport.shareName,
            relativePaths: plan.relativePaths
        )
    }

    /// Guest updates reach the Mac pasteboard only while Veil is the active app. A Windows app that sets the
    /// clipboard in the background would otherwise replace what the user just copied in a Mac app. A
    /// background update is dropped rather than queued, so switching back to Veil never surprises either.
    @MainActor
    private var acceptsGuestClipboardUpdate: Bool {
        ClipboardSharingPreferences.isSharingEnabled() && NSApp.isActive
    }

    @MainActor
    func syncGuestClipboardToPasteboard() {
        guard acceptsGuestClipboardUpdate,
              let text = model.latestGuestClipboardText else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @MainActor
    func syncGuestClipboardImageToPasteboard() {
        guard acceptsGuestClipboardUpdate,
              let image = model.latestGuestClipboardImage else {
            return
        }

        HostPasteboardContent.writeImage(image, to: .general)
    }

    func showWindowsDisplay() {
        Task { @MainActor in
            let didShow = await presentWindowsDesktopWhenReady()
            if didShow {
                displayMessage = "Windows desktop brought forward."
            } else {
                activateMainWindow()
                displayMessage = "The Windows desktop is not ready yet. Start Windows or refresh the display."
            }
        }
    }

    /// A QEMU process can be running before its VNC endpoint has produced the first
    /// usable framebuffer. A single presentation attempt races that normal boot gap
    /// and leaves the user staring at the launcher. Keep refreshing the evidence and
    /// retrying the presenter for a short, bounded window so the desktop actually
    /// appears after Start/Show Desktop.
    @MainActor
    func presentWindowsDesktopWhenReady(timeoutSeconds: Double = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline, !Task.isCancelled {
            await vmModel.refreshRuntimeEvidence()

            if presentWindowsDesktopIfAvailable() {
                return true
            }

            guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
                return false
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return false
    }

    @MainActor
    private func presentWindowsDesktopIfAvailable() -> Bool {
        if vmRuntimeBooter.provider == .appleVirtualization {
            return vmRuntimeBooter.showConsoleIfRunning()
        }

        guard let snapshot = vmModel.snapshot,
              snapshot.state == .running || snapshot.state == .starting,
              let surface = snapshot.latestConsoleLaunch?.displaySurface,
              surface.kind != .unavailable else {
            return false
        }

        return qemuConsoleWindowPresenter.showConsole(
            surface: surface,
            screenshotPath: snapshot.latestConsoleScreenshotPath,
            pointerTapAction: { normalizedX, normalizedY in
                Task {
                    await vmModel.sendConsolePointerTap(
                        normalizedX: normalizedX,
                        normalizedY: normalizedY
                    )
                }
            },
            keyAction: { key in
                Task {
                    await vmModel.sendConsoleKey(key)
                }
            },
            displayResizeAction: { width, height in
                Task { @MainActor in
                    _ = await model.resizeDisplay(width: width, height: height)
                }
            },
            commandKeyMapping: snapshot.commandKeyMapping ?? .default
        )
    }

    func installGuestAgentFromDisplay() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Sending the Veil app connection installer to Windows."
            do {
                _ = try await vmRuntimeBooter.installCurrentGuestTools(vmModel: vmModel)
                displayMessage = "App connection installer sent. Veil will connect when Windows is ready."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()
            } catch {
                displayMessage = String(localized: "App connection install could not start: \(userMessage(for: error))")
            }
        }
    }

    func prepareSparsePackageFromDisplay() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            displayMessage = "Preparing Windows package identity. Keep the Windows setup display open for prompts."

            do {
                _ = try await vmRuntimeBooter.prepareSparsePackageFromAttachedMedia()
                displayMessage = "Package identity preparation sent. Waiting for the Windows app connection to return."
                await vmModel.refreshRuntimeEvidence()

                let report = await model.waitForLiveAgentConnection(
                    endpoint: agentURLString,
                    timeoutSeconds: 120
                )
                await recordGuestAgentInstallEvidenceIfNeeded()
                await model.load()

                if report.diagnostic.health?.capabilities.packageIdentity == true {
                    displayMessage = "Windows package identity is ready."
                } else if report.status == .connected {
                    displayMessage = "Windows reconnected, but package identity is not ready yet. Check sparse package evidence."
                } else {
                    displayMessage = "Package identity preparation was sent. Windows has not reconnected yet."
                }
            } catch {
                displayMessage = String(localized: "Package identity preparation could not start: \(userMessage(for: error))")
            }
        }
    }

    func requestWindowsNotificationConsent() {
        Task { @MainActor in
            activateMainWindow()

            guard model.hasLiveAgentConnection else {
                displayMessage = "Connect the Windows app connection before allowing Windows notifications."
                return
            }

            guard model.health?.capabilities.packageIdentity == true else {
                displayMessage = "Prepare Windows package identity before allowing Windows notifications."
                return
            }

            displayMessage = "Asking Windows to allow Veil notifications."

            do {
                let client = VeilHostClient(
                    transport: URLSessionWebSocketTransport(url: URL(string: agentURLString)!)
                )
                let response = try await client.requestWindowsNotificationListenerConsent()
                await model.load()

                if response.accepted {
                    displayMessage = "Windows notifications are allowed. Run the notification check after a Windows notification appears."
                } else {
                    displayMessage = notificationConsentMessage(for: response.notificationListener)
                }
            } catch {
                displayMessage = String(localized: "Windows notification access could not be requested: \(userMessage(for: error))")
            }
        }
    }

    private func notificationConsentMessage(for status: WindowsNotificationListenerStatus) -> String {
        switch status.recommendedAction {
        case "request-notification-listener-consent":
            return "Windows has not allowed Veil notifications yet. Try Allow Notifications again from Veil."
        case "enable-notification-listener-settings":
            return "Allow Veil in Windows notification access settings, then run the notification check."
        case "prepare-sparse-package":
            return "Prepare Windows package identity before allowing Windows notifications."
        case "connect-agent":
            return "Connect the Windows app connection before allowing Windows notifications."
        default:
            return status.message ?? "Windows notification access is not ready yet."
        }
    }

    func waitForGuestAgent() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Checking the Windows app connection."
            let report = await model.waitForLiveAgentConnection(
                endpoint: agentURLString,
                timeoutSeconds: 5
            )
            await recordGuestAgentInstallEvidenceIfNeeded()

            if report.status == .connected {
                displayMessage = "Windows app connection is ready."
                if let fulfilledLaunch = await model.refreshLiveAgentIfNeeded() {
                    showWindowsAppWindow(for: fulfilledLaunch)
                    syncLauncherWindowVisibility()
                }
            } else if let hostForwardProbe = report.diagnostic.hostForwardProbe {
                displayMessage = String(localized: "Windows app connection is not ready yet (\(hostForwardProbe.status.rawValue)).")
            } else {
                displayMessage = "Windows app connection is not ready yet."
            }
        }
    }

    func repairGuestAgentForAppLaunch() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()

            guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
                advancePendingLaunchLifecycle()
                return
            }

            let appName = pendingLaunchDisplayName()
            displayMessage = String(localized: "Repairing the Windows app connection so \(appName) can open as a Mac window.")
            shellNavigation.showsWindowsDesktop = true

            do {
                _ = try await vmRuntimeBooter.installCurrentGuestTools(vmModel: vmModel)
                displayMessage = String(localized: "App connection repair sent. Veil will open \(appName) when Windows responds.")
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()

                if let fulfilledLaunch = await model.refreshLiveAgentIfNeeded() {
                    showWindowsAppWindow(for: fulfilledLaunch)
                    syncLauncherWindowVisibility()
                }
            } catch {
                displayMessage = String(localized: "App connection repair could not start: \(userMessage(for: error))")
            }
        }
    }

    /// Installs the Windows tools this Veil ships into a running Windows whose agent is older:
    /// inserts the tools update disc, runs its U.cmd, waits for the new agent, and ejects the disc.
    func updateGuestTools() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            guard vmModel.snapshot?.state == .running else {
                return
            }

            displayMessage = String(localized: "Updating Windows tools. When Windows asks for approval, choose Yes.")
            // The approval prompt appears on the Windows desktop; the launcher would hide it, and an
            // unanswered prompt left the update to fail without the user ever seeing it.
            shellNavigation.showsWindowsDesktop = true
            if let refusal = await vmModel.insertGuestToolsUpdateMedia() {
                displayMessage = String(localized: "Windows tools could not be updated: \(refusal)")
                return
            }
            do {
                _ = try await vmRuntimeBooter.updateGuestToolsFromRemovableMedia()
            } catch {
                displayMessage = String(localized: "Windows tools could not be updated: \(userMessage(for: error))")
                await vmModel.ejectRemovableMedia()
                return
            }

            // The repair restarts the agent after the approval, so give the user time to answer it.
            let bundledVersion = ShellGuestTools.bundledVersion
            try? await Task.sleep(for: .seconds(20))
            for _ in 0..<36 where model.health?.agentVersion != bundledVersion {
                await model.load()
                if model.health?.agentVersion == bundledVersion {
                    break
                }
                try? await Task.sleep(for: .seconds(5))
            }
            await vmModel.ejectRemovableMedia()
            await recordGuestAgentInstallEvidenceIfNeeded()

            if model.health?.agentVersion == bundledVersion {
                displayMessage = String(localized: "Windows tools updated. Restart Windows once so the screen follows the window size.")
            } else {
                displayMessage = String(localized: "Windows tools were not updated. Choose Update Tools again and approve the Windows prompt.")
            }
        }
    }

    func markWindowsInstalledFromSetup() {
        Task { @MainActor in
            activateMainWindow()
            await vmModel.markWindowsInstalled()
            if vmModel.snapshot?.windowsInstalled == true {
                displayMessage = "Windows is marked installed. Veil will boot from the local disk and leave the installer ISO detached."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = String(localized: "Windows install state could not be updated: \(errorMessage)")
            }
        }
    }

    func refreshRuntime() {
        Task {
            await vmModel.load()
        }
    }

    func recoverRuntimeDisplayEvidence() {
        Task { @MainActor in
            activateMainWindow()
            let beforeStatus = vmModel.snapshot?.latestConsoleLaunch?.previewStatus
            displayMessage = "Refreshing the embedded Windows display."
            await vmModel.refreshRuntimeEvidence()

            let afterStatus = vmModel.snapshot?.latestConsoleLaunch?.previewStatus
            if afterStatus == .fresh {
                displayMessage = "Windows display evidence refreshed."
            } else {
                let statusText = afterStatus?.rawValue ?? beforeStatus?.rawValue ?? "unavailable"
                displayMessage = WindowsShellCopy.displayRecoveryStillStaleMessage(statusText: statusText)
            }
        }
    }

    func refreshApps() {
        Task { @MainActor in
            await model.load()
            await recordGuestAgentInstallEvidenceIfNeeded()
        }
    }

    func activateMainWindow() {
        Task { @MainActor in
            MainWindowChrome.showMainWindow()
        }
    }

    func presentWindowsNotification(notificationId: String) {
        guard let notification = model.latestWindowsNotifications.first(where: { $0.notificationId == notificationId }) else {
            return
        }

        Task { @MainActor in
            let result = await windowsNotificationPresenter.present(notification)
            switch result {
            case .scheduled:
                displayMessage = String(localized: "Windows notification shown on macOS: \(notification.title)")
            case .permissionDenied:
                displayMessage = "Windows notification received, but macOS notifications are not allowed for Veil."
            case .authorizationRequestDeclined:
                displayMessage = "Windows notification received, but notification permission was not granted."
            case .invalidNotification:
                displayMessage = "Windows notification received, but it was missing a title."
            }
        }
    }

    var canShowWindowsDisplay: Bool {
        WindowsDisplayAvailabilityPolicy.canShowDesktop(
            runtimeState: vmModel.snapshot?.state,
            supportsNativeDisplayWindow: vmRuntimeBooter.supportsNativeDisplayWindow,
            hasCapturedSurface: vmModel.snapshot?.latestConsoleLaunch?.displaySurface.kind != nil
                && vmModel.snapshot?.latestConsoleLaunch?.displaySurface.kind != .unavailable
        )
    }

    var canInstallGuestAgent: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && (vmModel.snapshot?.installEvidence.kind != .guestAgent || !model.hasLiveAgentConnection)
    }

    var canRecoverRuntimeDisplay: Bool {
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            return false
        }

        return vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .stale
            || vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .unavailable
    }

    var canMarkWindowsInstalled: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && vmModel.snapshot?.installEvidence.isInstalled != true
    }

    private var appRuntimeStatusReport: WindowsAppRuntimeStatusReport {
        model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot),
            hostBackingScale: HostDisplayScale.current
        )
    }

    var menuBarSymbolName: String {
        appRuntimeStatusReport.menuBarIntegration.symbolName
    }

    func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
