import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func startWindowsAndShowDisplay() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            await startOrResumeWindows()

            // Like a Parallels VM, Windows shows up in the main window. The separate desktop window
            // opens only from View > Open Desktop in Separate Window, never as a side effect of Start.
            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = "Windows is running in this window."
                scheduleAutomaticGuestAgentRecoveryIfNeeded()
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = String(localized: "Windows display could not start: \(errorMessage)")
            }
        }
    }

    /// Erases an unfinished installation and boots Windows Setup again from the installer.
    func restartWindowsInstallation() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            if vmModel.canStop {
                await vmModel.stop()
            }
            guard await vmModel.restartWindowsInstallation() else {
                displayMessage = vmModel.errorMessage.map { String(localized: "Veil could not restart the installation: \($0)") }
                return
            }

            displayMessage = "Windows Setup is starting over."
            if AppWindowEngineStatus.resolve(
                bootProvider: vmRuntimeBooter.provider,
                providers: vmModel.snapshot?.runtimeProviders ?? []
            ).canRunWindows {
                startWindowsAndShowDisplay()
            }
        }
    }

    /// Resumes a suspended session when one exists, and cold boots otherwise.
    ///
    /// `vmModel.canStart` is true for a suspended VM, so calling `start()` here would boot Windows fresh
    /// and throw away the session idle suspend just saved. That would make the round trip lossy in
    /// exactly the case this is supposed to protect.
    @MainActor
    func startOrResumeWindows() async {
        // The app can be launched while QEMU is already booting (or while a previous
        // Veil instance is being replaced). Refresh the authoritative runtime evidence
        // before deciding to start; otherwise we race the existing process and surface
        // a misleading "already running" failure instead of attaching its desktop.
        await vmModel.refreshRuntimeEvidence()
        if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
            displayMessage = "Windows is already running. Connecting to its desktop."
            return
        }

        if vmModel.canResume {
            displayMessage = "Resuming your Windows session."
            await vmModel.resume()
            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                return
            }

            // Resume keeps the saved state file on failure, so the VM is reported as still suspended and
            // the user can retry. Cold booting here would silently discard the session instead.
            if let errorMessage = vmModel.errorMessage {
                displayMessage = String(localized: "Your Windows session could not be resumed: \(errorMessage)")
            }
            return
        }

        await attachDriverMediaForColdStartIfNeeded()
        displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
        await vmModel.start()
    }

    /// A Windows installed before Veil fetched VirtIO drivers has no guest network: its boot plan
    /// falls back to usb-net, which Windows binds as a serial port. A cold start attaches the
    /// virtio-win ISO when it is already on this Mac, which switches the plan to virtio-net-pci; the
    /// agent repair then installs NetKVM from it. Otherwise the ISO downloads in the background for
    /// the next start, so starting Windows never waits on an 877 MB download. Resume is never
    /// changed here, since a saved session needs the same devices.
    @MainActor
    func attachDriverMediaForColdStartIfNeeded() async {
        guard let snapshot = vmModel.snapshot,
              DriverMediaAttachPolicy.attachesOnColdStart(snapshot: snapshot) else {
            return
        }

        guard let media = await VirtioWinDriverMediaProvider.shared.cachedMedia() else {
            await VirtioWinDriverMediaProvider.shared.prefetch()
            return
        }

        await vmModel.updateProfilePaths(
            installerMediaPath: snapshot.installerMediaPath,
            driverMediaPath: media.path,
            virtualDiskPath: snapshot.virtualDiskPath
        )
    }

    /// Toolbar and Actions-menu suspend. Unlike the idle quiet policy this never falls back to a shut
    /// down: the user asked to keep the session, so a failed suspend reports the error instead.
    func suspendWindows() {
        Task { @MainActor in
            guard vmModel.canSuspend, vmModel.phase != .loading else {
                return
            }

            cancelAutomaticQuietRuntime()
            cancelAutomaticRuntimeConnectionRecovery()
            await vmModel.suspend()
            if vmModel.snapshot?.state == .suspended {
                displayMessage = "Windows is suspended. Resume it to continue where you left off."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = String(localized: "Windows could not be suspended: \(errorMessage)")
            }
        }
    }

    /// Quit with "Suspend Windows when Veil quits" on saves the session instead of leaving QEMU running.
    @MainActor
    func suspendWindowsForQuitIfNeeded() async {
        guard StartupBehaviorPolicy.suspendsWindowsOnQuit(
            snapshot: vmModel.snapshot,
            canSuspend: vmModel.canSuspend,
            isBusy: vmModel.phase == .loading
        ) else {
            return
        }

        cancelAutomaticQuietRuntime()
        cancelAutomaticRuntimeConnectionRecovery()
        displayMessage = "Suspending Windows before Veil quits."
        await vmModel.suspend()
    }

    func stopWindowsAndCloseDisplay() {
        oneClickAppLaunchGate.cancel()
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            cancelAutomaticGuestAgentRecovery()
            cancelAutomaticRuntimeConnectionRecovery()
            hasObservedLiveAgentConnection = false
            activateMainWindow()
            displayMessage = String(localized: "Shutting down Windows. Windows may ask to save changes or finish updates first.")
            let poweredOff = await shutDownWindowsGracefully()
            await vmModel.stop()
            qemuConsoleWindowPresenter.closeConsole()

            if vmModel.snapshot?.state == .stopped {
                windowsAppWindowPresenter.closeAll()
                displayMessage = poweredOff
                    ? String(localized: "Windows shut down.")
                    : String(localized: "Windows did not shut down in time, so Veil turned it off.")
            }
        }
    }

    /// Shuts Windows down before the VM is turned off; see `GracefulWindowsShutdown`. Returns
    /// false when Windows never powered off and the caller has to turn it off.
    @MainActor
    func shutDownWindowsGracefully() async -> Bool {
        guard vmModel.snapshot?.state == .running else {
            return false
        }
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { await model.requestSystemShutdown() },
            pressPowerButton: { await vmModel.pressPowerButton() },
            isStillRunning: {
                await vmModel.load()
                return vmModel.snapshot?.state == .running
            }
        )
        return outcome.poweredOff
    }

    /// The quiet policy resolved against the live VM snapshot.
    ///
    /// The snapshot has to be passed in. `quietRuntimeStatus()` with no local runtime cannot know
    /// whether this VM can persist a session, so it conservatively resolves to stopping -- which would
    /// silently shut Windows down on every idle timeout even where suspend works.
    @MainActor
    private func resolvedQuietRuntimeStatus() -> WindowsAppRuntimeQuietPolicyStatus {
        model.quietRuntimeStatus(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot)
        )
    }

    /// Runs whichever quiet mode the status resolved to.
    ///
    /// Suspending keeps the user's open apps and unsaved work; stopping loses them. Both the manual
    /// menu action and the automatic idle timer route through here so they can never do different
    /// things for the same state.
    @MainActor
    private func performQuietRuntime(_ quietRuntime: WindowsAppRuntimeQuietPolicyStatus) async {
        cancelAutomaticRuntimeConnectionRecovery()
        if quietRuntime.quietMode == WindowsAppRuntimeQuietPolicyStatus.suspendMode,
           vmModel.canSuspend {
            await vmModel.suspend()
            if vmModel.snapshot?.state == .suspended {
                displayMessage = "Windows is suspended. Your open apps are still there and will come back with the next launch."
                return
            }

            // Fall through to stopping. A memory-state save that fails partway leaves the guest paused,
            // which is the one state the launcher offers no action for. Stopping costs the user their
            // open apps but leaves a VM they can start again. The fallback is deliberately one-way:
            // stopping always works, so a stop failure has no safe second attempt.
            displayMessage = "Windows could not be suspended, so it is shutting down instead."
        }

        _ = await shutDownWindowsGracefully()
        await vmModel.stop()
        if vmModel.snapshot?.state == .stopped {
            displayMessage = "Windows is quiet. No Windows app windows are open."
        } else if let errorMessage = vmModel.errorMessage {
            displayMessage = String(localized: "Windows could not quiet: \(errorMessage)")
        }
    }

    func quietWindowsWhenIdle() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            let quietRuntime = resolvedQuietRuntimeStatus()
            guard model.canQuietRuntimeWhenIdle else {
                displayMessage = quietRuntime.reason
                return
            }

            guard vmModel.canStop && vmModel.phase != .loading else {
                displayMessage = WindowsShellCopy.quietStopWaitingMessage
                return
            }

            await performQuietRuntime(quietRuntime)
        }
    }

    func scheduleAutomaticQuietRuntimeIfNeeded() {
        let quietRuntime = resolvedQuietRuntimeStatus()
        guard quietRuntime.willQuietAutomatically,
              AutomaticQuietPolicy.allowsQuiet(lastAppWindowClosedByUser: lastAppWindowClosedByUser) else {
            cancelAutomaticQuietRuntime()
            return
        }

        guard vmModel.canStop && vmModel.phase != .loading else {
            cancelAutomaticQuietRuntime()
            return
        }

        automaticQuietRuntimeTask?.cancel()
        automaticQuietRuntimeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(quietRuntime.automaticQuietDelaySeconds))
            guard !Task.isCancelled,
                  lastAppWindowClosedByUser,
                  model.canQuietRuntimeWhenIdle,
                  vmModel.canStop,
                  vmModel.phase != .loading else {
                return
            }

            // Re-resolved after the delay rather than reusing the mode captured when the timer was
            // scheduled. The VM state can change during those seconds, and acting on a stale mode is how
            // a suspend gets attempted against a machine that is no longer running.
            let currentQuietRuntime = resolvedQuietRuntimeStatus()
            displayMessage = currentQuietRuntime.quietMode == WindowsAppRuntimeQuietPolicyStatus.suspendMode
                ? "All Windows app windows closed. Suspending Windows so your apps come back."
                : "All Windows app windows closed. Quieting Windows."
            await performQuietRuntime(currentQuietRuntime)
        }
    }

    func cancelAutomaticQuietRuntime() {
        automaticQuietRuntimeTask?.cancel()
        automaticQuietRuntimeTask = nil
    }

    func cancelAutomaticGuestAgentRecovery() {
        automaticGuestAgentRecoveryTask?.cancel()
        automaticGuestAgentRecoveryTask = nil
    }

    func cancelAutomaticRuntimeConnectionRecovery() {
        automaticRuntimeConnectionRecoveryTask?.cancel()
        automaticRuntimeConnectionRecoveryTask = nil
    }

    func noteLiveAgentConnectionIfPresent() {
        if model.hasLiveAgentConnection {
            hasObservedLiveAgentConnection = true
        }
    }

    func startAutomaticFrameStreamMaintenanceLoopIfNeeded() {
        guard automaticFrameStreamMaintenanceTask == nil else {
            return
        }

        automaticFrameStreamMaintenanceTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else {
                    return
                }

                await performFrameStreamMaintenance(automatic: true)
            }
        }
    }
}

/// When Veil may quiet Windows on its own once no app windows are left.
enum AutomaticQuietPolicy {
    /// Only after the user closed the last app window. An empty window list is not enough: windows also go
    /// away when the Windows agent restarts and forgets them, while the apps stay open in Windows.
    static func allowsQuiet(lastAppWindowClosedByUser: Bool) -> Bool {
        lastAppWindowClosedByUser
    }
}
