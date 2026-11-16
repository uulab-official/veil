import AppIntents
import VeilHostCore

/// Shortcuts and Siri actions. Each one does what the matching menu item does, but waits for the result so
/// a shortcut can tell success from failure, and does not pull the main window forward: an automation that
/// suspends Windows at night should not leave Veil in front of the user.
extension VeilHostShellApp: VeilShortcutPerforming {
    func configureShortcutIntentBridge() {
        VeilShortcutBridge.shared.performer = self
        // Lets "Open <app> in Veil" phrases name the apps this guest actually has.
        VeilAppShortcuts.updateAppShortcutParameters()
    }

    var shortcutWindowsApps: [WindowsApp] {
        model.apps
    }

    var shortcutStopNeedsConfirmation: Bool {
        WindowsRuntimeStopConfirmation.needsConfirmation(
            hasMirroredWindowsApp: !model.mirrorSessions.isEmpty,
            hasQueuedLaunch: model.pendingLaunchAppId != nil
        )
    }

    func shortcutStartWindows() async throws -> LocalizedStringResource {
        guard AppWindowEngineStatus.resolve(
            bootProvider: vmRuntimeBooter.provider,
            providers: vmModel.snapshot?.runtimeProviders ?? []
        ).canRunWindows else {
            throw VeilShortcutError(localizedStringResource: "Veil cannot run Windows on this Mac yet. Open Veil to finish setup.")
        }

        cancelAutomaticQuietRuntime()
        await startOrResumeWindows()
        guard isWindowsRunningOrStarting else {
            throw failure(fallback: "Windows could not start.")
        }

        scheduleAutomaticGuestAgentRecoveryIfNeeded()
        return "Windows is running."
    }

    func shortcutStopWindows() async throws -> LocalizedStringResource {
        await vmModel.refreshRuntimeEvidence()
        guard vmModel.canStop else {
            return "Windows is already shut down."
        }

        oneClickAppLaunchGate.cancel()
        cancelAutomaticQuietRuntime()
        cancelAutomaticGuestAgentRecovery()
        cancelAutomaticRuntimeConnectionRecovery()
        hasObservedLiveAgentConnection = false
        await vmModel.stop()
        qemuConsoleWindowPresenter.closeConsole()
        guard vmModel.snapshot?.state == .stopped else {
            throw failure(fallback: "Windows did not shut down.")
        }

        windowsAppWindowPresenter.closeAll()
        return "Windows is shut down."
    }

    func shortcutSuspendWindows() async throws -> LocalizedStringResource {
        await vmModel.refreshRuntimeEvidence()
        if vmModel.snapshot?.state == .suspended {
            return "Windows is already suspended."
        }
        guard vmModel.canSuspend else {
            throw VeilShortcutError(localizedStringResource: "Windows is not running, so there is nothing to suspend.")
        }

        cancelAutomaticQuietRuntime()
        cancelAutomaticRuntimeConnectionRecovery()
        await vmModel.suspend()
        guard vmModel.snapshot?.state == .suspended else {
            throw failure(fallback: "Windows could not be suspended.")
        }

        return "Windows is suspended."
    }

    func shortcutResumeWindows() async throws -> LocalizedStringResource {
        await vmModel.refreshRuntimeEvidence()
        if isWindowsRunningOrStarting {
            return "Windows is already running."
        }
        // Resume never cold boots: a shortcut named Resume that silently started a fresh Windows would hide
        // that the saved session is gone.
        guard vmModel.canResume else {
            throw VeilShortcutError(localizedStringResource: "There is no suspended Windows session to resume.")
        }

        cancelAutomaticQuietRuntime()
        await startOrResumeWindows()
        guard isWindowsRunningOrStarting else {
            throw failure(fallback: "Windows could not be resumed.")
        }

        return "Windows is running."
    }

    func shortcutOpenWindowsApp(id: String) async throws -> LocalizedStringResource {
        guard let app = model.apps.first(where: { $0.id == id })
                ?? KnownWindowsAppCatalog.apps.first(where: { $0.id == id }) else {
            throw VeilShortcutError(localizedStringResource: "That Windows app is no longer available.")
        }
        guard vmModel.snapshot?.installEvidence.isInstalled == true else {
            throw VeilShortcutError(localizedStringResource: "Windows is not installed yet. Open Veil to finish setup.")
        }

        // The one-click path starts or resumes Windows and waits for the app connection on its own, and
        // reports progress in Veil. The shortcut does not wait for the window, which can take a minute on a
        // cold start.
        runOneClickAppLaunch(appId: app.id)
        return "Opening \(app.name) in Windows."
    }

    private var isWindowsRunningOrStarting: Bool {
        vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    }

    private func failure(fallback: LocalizedStringResource) -> VeilShortcutError {
        guard let detail = vmModel.errorMessage else {
            return VeilShortcutError(localizedStringResource: fallback)
        }

        return VeilShortcutError(localizedStringResource: "\(String(localized: fallback)) \(detail)")
    }
}
