import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func runOneClickSelectedApp() {
        guard let appId = model.selectedAppId else {
            displayMessage = "Select a Windows app before opening it."
            return
        }

        runOneClickAppLaunch(appId: appId)
    }

    func runOneClickPendingLaunch() {
        guard let appId = model.pendingLaunchAppId else {
            displayMessage = "There is no queued Windows app to open."
            return
        }

        runOneClickAppLaunch(appId: appId)
    }

    func runOneClickAppLaunch(appId: String) {
        cancelAutomaticQuietRuntime()
        cancelAutomaticGuestAgentRecovery()
        cancelAutomaticRuntimeConnectionRecovery()

        Task { @MainActor in
            let outcome = await oneClickAppLaunchGate.run {
                let driver = OneClickAppLaunchDriver<WindowsAppLaunchResult>(
                    context: { self.currentAppLaunchContext() },
                    requestLaunch: { requestedAppId in
                        self.model.selectedAppId = requestedAppId
                        return await self.model.launchSelectedApp()
                    },
                    startOrResumeWindows: {
                        await self.startOrResumeWindows()
                        return self.vmModel.snapshot?.state == .running
                            || self.vmModel.snapshot?.state == .starting
                    },
                    waitForGuestAgent: { seconds in
                        let report = await self.model.waitForLiveAgentConnection(
                            endpoint: self.agentURLString,
                            timeoutSeconds: seconds
                        )
                        return report.status == .connected
                    },
                    recoverStalledRuntime: {
                        self.displayMessage = "Windows app connection stalled. Reconnecting Windows automatically."
                        let result = await self.vmRuntimeBooter.recoverStalledRuntime()
                        await self.vmModel.refreshRuntimeEvidence()
                        switch result {
                        case .recovered:
                            return true
                        case .notNeeded, .unsupported:
                            return false
                        case .unavailable(let detail), .failed(let detail):
                            VeilLog.agent.notice(
                                "One-click QEMU runtime recovery did not complete: \(detail, privacy: .public)"
                            )
                            return false
                        }
                    },
                    repairGuestAgent: {
                        _ = try await self.vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                        await self.vmModel.refreshRuntimeEvidence()
                    },
                    fulfillLaunch: {
                        await self.model.fulfillPendingLaunch()
                    }
                )

                return await OneClickAppLaunchCoordinator().run(
                    appId: appId,
                    driver: driver
                )
            }

            switch outcome {
            case .opened(let result):
                displayMessage = "\(result.window.title) opened as a macOS window."
                showWindowsAppWindow(for: result)
                syncLauncherWindowVisibility()
            case .blocked(let failure):
                activateMainWindow()
                displayMessage = failure.userMessage
            }
        }
    }

    private func currentAppLaunchContext() -> AppLaunchLifecycleContext {
        AppLaunchLifecycleContext(
            hasQueuedLaunch: model.pendingLaunchAppId != nil,
            canFulfillQueuedLaunch: model.canFulfillPendingLaunch,
            hasLiveAgentConnection: model.hasLiveAgentConnection,
            runtimeState: vmModel.snapshot?.state,
            canStartOrResume: vmModel.canStart || vmModel.canResume,
            guestAgentEndpointAvailable: agentConnectionPlan.isAvailable,
            agentWaitTimedOut: false,
            repairAttemptCount: 0,
            canRecoverStalledRuntime: vmRuntimeBooter.provider == .qemu
                && (hasObservedLiveAgentConnection || vmModel.snapshot?.installEvidence.kind == .guestAgent)
        )
    }

    private func fulfillPendingWindowsAppWindow() {
        runOneClickPendingLaunch()
    }

    private func fulfillPendingWindowsAppWindowFromCurrentState() async {
        cancelAutomaticQuietRuntime()
        if model.apps.isEmpty {
            await model.load()
        }

        guard model.canFulfillPendingLaunch else {
            if model.pendingLaunchStatus().willLaunchOnAgentReconnect {
                advancePendingLaunchLifecycle()
            } else {
                displayMessage = model.pendingLaunchStatus().reason
            }
            return
        }

        guard let result = await model.fulfillPendingLaunch() else {
            displayMessage = model.errorMessage ?? "Queued Windows app could not open."
            return
        }

        displayMessage = "\(result.window.title) opened as a macOS window."
        showWindowsAppWindow(for: result)
        syncLauncherWindowVisibility()
    }

    func advancePendingLaunchLifecycle() {
        let appName = pendingLaunchDisplayName()
        let nextStep = AppLaunchLifecycleCoordinator.nextStep(
            hasQueuedLaunch: model.pendingLaunchAppId != nil,
            canFulfillQueuedLaunch: model.canFulfillPendingLaunch,
            hasLiveAgentConnection: model.hasLiveAgentConnection,
            runtimeState: vmModel.snapshot?.state,
            canStartOrResume: vmModel.canStart,
            guestAgentEndpointAvailable: agentConnectionPlan.isAvailable
        )

        switch nextStep {
        case .waitForGuestAgent:
            activateMainWindow()
            displayMessage = "Windows is running. Veil is preparing the app connection so \(appName) can open as a Mac window."
            scheduleAutomaticGuestAgentRecoveryIfNeeded()
            if vmRuntimeBooter.supportsNativeDisplayWindow {
                showWindowsDisplay()
            }
        case .recoverStalledRuntime:
            runOneClickPendingLaunch()
        case .repairGuestAgent:
            activateMainWindow()
            displayMessage = "Windows is running. Veil is repairing the app connection so \(appName) can open as a Mac window."
            scheduleAutomaticGuestAgentRecoveryIfNeeded()
        case .blockedGuestAgentRecovery:
            activateMainWindow()
            displayMessage = "Windows is running, but the app connection did not recover after two attempts. Open recovery to repair Veil Agent."
        case .startOrResumeWindows:
            displayMessage = "Starting Windows. Veil will open \(appName) when the app connection is ready."
            startWindowsAndShowDisplay()
        case .blockedGuestAgentEndpoint:
            activateMainWindow()
            displayMessage = "\(appName) is queued, but this VM provider has no configured Windows app connection. \(agentConnectionPlan.detail)"
        case .blockedRuntimeSetup:
            displayMessage = "Veil queued \(appName). Finish Windows setup before the app can open."
        case .fulfillQueuedLaunch:
            fulfillPendingWindowsAppWindow()
        case .requestLaunch:
            runOneClickSelectedApp()
        }
    }

    func scheduleAutomaticGuestAgentRecoveryIfNeeded() {
        guard automaticGuestAgentRecoveryTask == nil,
              !model.hasLiveAgentConnection,
              !hasObservedLiveAgentConnection,
              model.phase != .launching,
              shouldRecoverGuestAgentForPendingApp,
              let recoveryToken = currentGuestAgentRecoveryToken,
              !automaticGuestAgentRecoveryAttemptedTokens.contains(recoveryToken) else {
            return
        }

        automaticGuestAgentRecoveryAttemptedTokens.insert(recoveryToken)
        automaticGuestAgentRecoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))

            guard !Task.isCancelled,
                  !model.hasLiveAgentConnection,
                  shouldRecoverGuestAgentForPendingApp else {
                automaticGuestAgentRecoveryTask = nil
                return
            }

            displayMessage = "Windows is running. Veil is repairing the app connection for \(pendingLaunchDisplayName())."

            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "App connection repair sent. Veil will open \(pendingLaunchDisplayName()) when Windows responds."
                await vmModel.refreshRuntimeEvidence()
            } catch {
                displayMessage = "App connection repair could not start: \(userMessage(for: error))"
            }

            automaticGuestAgentRecoveryTask = nil
        }
    }

    /// Repairs a long-lived QEMU process whose QMP socket answers while RFB and the Windows agent
    /// have stopped responding. This is independent of guest-agent installation: a healthy agent
    /// that temporarily lost its transport should not require a second installation.
    func scheduleAutomaticRuntimeConnectionRecoveryIfNeeded() {
        guard automaticRuntimeConnectionRecoveryTask == nil,
              vmRuntimeBooter.provider == .qemu,
              hasObservedLiveAgentConnection,
              !model.hasLiveAgentConnection,
              model.phase != .launching,
              model.hasOpenedAppWindowThisSession,
              (!model.mirrorSessions.isEmpty || !model.restorableAppIds.isEmpty),
              vmModel.snapshot?.state == .running,
              let recoveryToken = currentGuestAgentRecoveryToken else {
            return
        }

        let now = Date()
        if let cooldownUntil = automaticRuntimeConnectionRecoveryCooldownUntil[recoveryToken],
           cooldownUntil > now {
            return
        }

        automaticRuntimeConnectionRecoveryCooldownUntil[recoveryToken] = now.addingTimeInterval(120)
        automaticRuntimeConnectionRecoveryTask = Task { @MainActor in
            // Give a transient WebSocket/RFB reconnect a chance before touching QEMU state.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  !model.hasLiveAgentConnection,
                  hasObservedLiveAgentConnection,
                  vmModel.snapshot?.state == .running else {
                automaticRuntimeConnectionRecoveryTask = nil
                return
            }

            displayMessage = "Windows app connection interrupted. Reconnecting automatically."
            let result = await vmRuntimeBooter.recoverStalledRuntime()
            await vmModel.refreshRuntimeEvidence()

            switch result {
            case .recovered:
                displayMessage = "Windows connection recovered. Reconnecting app windows."
                let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
                for launch in restoredLaunches {
                    showWindowsAppWindow(for: launch)
                }
                syncLauncherWindowVisibility()
            case .notNeeded:
                VeilLog.agent.notice("Automatic runtime recovery skipped because QEMU was not running.")
            case .unsupported:
                VeilLog.agent.notice("Automatic runtime recovery is unavailable for the active VM provider.")
            case .unavailable(let detail), .failed(let detail):
                VeilLog.agent.notice("Automatic QEMU runtime recovery did not complete: \(detail, privacy: .public)")
            }

            automaticRuntimeConnectionRecoveryTask = nil
        }
    }

    private var shouldRecoverGuestAgentForPendingApp: Bool {
        let hasQueuedLaunch = model.pendingLaunchStatus().willLaunchOnAgentReconnect
            || model.pendingLaunchAppId != nil
        let hasRestoreIntent = !model.restorableAppIds.isEmpty && model.mirrorSessions.isEmpty
        let runtimeIsRunning = vmModel.snapshot?.state == .running
            || vmModel.snapshot?.state == .starting

        return runtimeIsRunning && (hasQueuedLaunch || hasRestoreIntent)
    }

    private var currentGuestAgentRecoveryToken: String? {
        guard let snapshot = vmModel.snapshot,
              snapshot.state == .running || snapshot.state == .starting else {
            return nil
        }

        if let pid = snapshot.latestConsoleLaunch?.pid {
            return "qemu-pid:\(pid)"
        }

        if let pid = snapshot.runningQEMUProcess?.pid {
            return "detected-qemu-pid:\(pid)"
        }

        if let diskPath = snapshot.virtualDiskPath {
            return "disk:\(diskPath)"
        }

        return snapshot.profileName.map { "profile:\($0)" }
    }

    func pendingLaunchDisplayName() -> String {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return "the queued app"
        }

        return model.apps.first { $0.id == pendingAppId }?.name ?? "the queued app"
    }
}
