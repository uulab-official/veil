import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func startWindowsAndShowDisplay() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            await startOrResumeWindows()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = await presentWindowsDesktopWhenReady()
                    ? "Windows desktop opened in its own window."
                    : "Windows is running. The desktop display is still connecting."
                scheduleAutomaticGuestAgentRecoveryIfNeeded()
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows display could not start: \(errorMessage)"
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
                displayMessage = "Your Windows session could not be resumed: \(errorMessage)"
            }
            return
        }

        displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
        await vmModel.start()
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
                displayMessage = "Windows could not be suspended: \(errorMessage)"
            }
        }
    }

    func stopWindowsAndCloseDisplay() {
        oneClickAppLaunchGate.cancel()
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            cancelAutomaticGuestAgentRecovery()
            cancelAutomaticRuntimeConnectionRecovery()
            hasObservedLiveAgentConnection = false
            activateMainWindow()
            await vmModel.stop()
            qemuConsoleWindowPresenter.closeConsole()

            if vmModel.snapshot?.state == .stopped {
                windowsAppWindowPresenter.closeAll()
                displayMessage = "Windows display closed."
            }
        }
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

        await vmModel.stop()
        if vmModel.snapshot?.state == .stopped {
            displayMessage = "Windows is quiet. No Windows app windows are open."
        } else if let errorMessage = vmModel.errorMessage {
            displayMessage = "Windows could not quiet: \(errorMessage)"
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
        guard quietRuntime.willQuietAutomatically else {
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
