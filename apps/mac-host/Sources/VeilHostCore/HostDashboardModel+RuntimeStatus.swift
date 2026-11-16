import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    /// - Parameter hostBackingScale: This Mac's backing scale factor, supplied by the app shell because
    ///   VeilHostCore does not import AppKit. `nil` reports display scaling as unknown rather than
    ///   assuming 1, which would claim a mismatch on every Retina Mac whose scale was never read.
    public func runtimeStatusReport(
        generatedAt: Date = Date(),
        agentEndpoint: String = HostDashboardModel.defaultAgentEndpoint,
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil,
        hostBackingScale: Double? = nil
    ) -> WindowsAppRuntimeStatusReport {
        let localRuntime = localRuntimeWithGuestAgentEvidence(localRuntime ?? localRuntimeStatus(snapshot: nil))
        let quietRuntime = quietRuntimeStatus(localRuntime: localRuntime)
        let macWindowIntegration = macWindowIntegrationStatus(generatedAt: generatedAt)
        let launcherVisibility = launcherVisibilityStatus(
            macWindowIntegration: macWindowIntegration
        )
        let visibleSurfacePolicy = visibleSurfacePolicyStatus(
            launcherVisibility: launcherVisibility,
            macWindowIntegration: macWindowIntegration
        )
        let launchPlan = launchPlanStatus(localRuntime: localRuntime)
        let proofPlan = proofPlanStatus()
        let proofArtifacts = proofArtifactStatus()
        let dailyUseReadiness = dailyUseReadinessStatus(proofPlan: proofPlan)
        let notificationBridge = notificationBridgeStatus(dailyUseReadiness: dailyUseReadiness)
        let pendingLaunch = pendingLaunchStatus()
        let releaseGate = releaseGateStatus(
            localRuntime: localRuntime,
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            quietRuntime: quietRuntime,
            launchPlan: launchPlan,
            pendingLaunch: pendingLaunch,
            proofPlan: proofPlan,
            proofArtifacts: proofArtifacts
        )
        let primaryNextAction = primaryNextActionStatus(releaseGate: releaseGate)
        let menuBarIntegration = menuBarIntegrationStatus(
            localRuntime: localRuntime,
            launchPlan: launchPlan,
            pendingLaunch: pendingLaunch,
            dailyUseReadiness: dailyUseReadiness
        )
        let oneScreenUX = oneScreenUXStatus(
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            menuBarIntegration: menuBarIntegration,
            primaryNextAction: primaryNextAction
        )
        let launchOnboarding = launchOnboardingStatus(
            releaseGate: releaseGate,
            primaryNextAction: primaryNextAction,
            oneScreenUX: oneScreenUX
        )
        return WindowsAppRuntimeStatusReport(
            generatedAt: generatedAt,
            phase: phase,
            selectedAppId: selectedAppId,
            pendingLaunchAppId: pendingLaunchAppId,
            pendingLaunch: pendingLaunch,
            connection: WindowsAppRuntimeConnectionStatus(
                mode: connectionMode,
                hasLiveAgentConnection: hasLiveAgentConnection,
                agentVersion: hasLiveAgentConnection ? health?.agentVersion : nil,
                os: hasLiveAgentConnection ? health?.os : nil,
                capabilities: hasLiveAgentConnection ? health?.capabilities : nil,
                packageIdentityStatus: hasLiveAgentConnection ? health?.packageIdentityStatus : nil,
                notificationListener: hasLiveAgentConnection ? health?.notificationListener : nil,
                connectionDetail: connectionDetail
            ),
            guestAgentDiagnostics: guestAgentDiagnosticsStatus(endpoint: agentEndpoint),
            localRuntime: localRuntime,
            apps: apps.map { app in
                WindowsAppRuntimeAppStatus(
                    id: app.id,
                    name: app.name,
                    canRequestLaunch: canRequestAppLaunch(appId: app.id),
                    canLaunchNow: canLaunchApp(appId: app.id)
                )
            },
            mirrorSessions: mirrorSessions.map { session in
                let frameStream = WindowFrameStreamAssessment.assess(
                    session: session,
                    generatedAt: generatedAt
                )
                return WindowsAppRuntimeWindowStatus(
                    windowId: session.id,
                    appId: session.window.appId,
                    title: session.window.title,
                    captureState: session.captureState,
                    frameStreamStatus: frameStream.status,
                    frameStreamRequestedAt: session.frameStreamRequestedAt,
                    latestFrameReceivedAt: session.frameTiming?.latestFrameReceivedAt,
                    latestFrameAgeMilliseconds: frameStream.latestFrameAgeMilliseconds,
                    latestActivityAgeMilliseconds: frameStream.latestActivityAgeMilliseconds,
                    latestFrameIntervalMilliseconds: frameStream.latestFrameIntervalMilliseconds,
                    frameStreamWaitingAgeMilliseconds: frameStream.waitingForFirstFrameMilliseconds,
                    receivedFrameCount: frameStream.receivedFrameCount,
                    unchangedHeartbeatCount: frameStream.unchangedHeartbeatCount,
                    frameStreamRecommendedAction: frameStream.recommendedAction,
                    frameStreamRestartCount: session.frameStreamRestartCount,
                    latestFrameStreamRestartedAt: session.latestFrameStreamRestartedAt,
                    frameStreamRecoveryEscalated: frameStream.recoveryEscalated,
                    frameStreamReopenEscalated: frameStream.reopenEscalated,
                    canFocus: canFocusMirrorSession(windowId: session.id),
                    canClose: canCloseMirrorSession(windowId: session.id),
                    canSendInput: canSendInput(to: session.id)
                )
            },
            restorableAppIds: restorableAppIds,
            dockIntegration: WindowsAppRuntimeDockIntegrationStatus(
                isEnabled: true,
                openWindowCount: mirrorSessions.count,
                pendingLaunchCount: pendingLaunch.isQueued ? 1 : 0,
                restorableAppCount: restorableAppIds.count,
                restorableWindowCount: restorableWindowCount,
                badgeLabel: dockBadgeLabel(pendingLaunch: pendingLaunch),
                canOpenMainWindow: true,
                canBringWindowsAppsForward: !mirrorSessions.isEmpty,
                canRestorePreviousApps: canRestoreMirrorSessions,
                canReconnectPreviousApps: canReconnectRestoreMirrorSessions,
                canLaunchSelectedApp: canRequestSelectedAppLaunch
            ),
            menuBarIntegration: menuBarIntegration,
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            oneScreenUX: oneScreenUX,
            launchOnboarding: launchOnboarding,
            macWindowIntegration: macWindowIntegration,
            displayScaling: displayScalingStatus(hostBackingScale: hostBackingScale),
            quietRuntime: quietRuntime,
            launchPlan: launchPlan,
            proofPlan: proofPlan,
            proofArtifacts: proofArtifacts,
            dailyUseReadiness: dailyUseReadiness,
            notificationBridge: notificationBridge,
            releaseGate: releaseGate,
            primaryNextAction: primaryNextAction,
            actions: [
                WindowsAppRuntimeActionStatus(
                    id: "dock.openMainWindow",
                    title: "Open Veil From Dock",
                    isAvailable: true
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dock.bringWindowsAppsForward",
                    title: "Bring Windows Apps Forward",
                    isAvailable: !mirrorSessions.isEmpty
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.restorePrevious",
                    title: "Restore Previous Apps",
                    isAvailable: canRestoreMirrorSessions
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.reconnectRestore",
                    title: "Reconnect Previous Apps",
                    isAvailable: canReconnectRestoreMirrorSessions
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.closeAll",
                    title: "Close All Windows Apps",
                    isAvailable: canCloseAllMirrorSessions
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.restartFrameStream",
                    title: "Restart App Screen",
                    isAvailable: macWindowIntegration.staleFrameWindowCount > 0
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.maintainFrameStreams",
                    title: "Keep App Screens Live",
                    isAvailable: macWindowIntegration.staleFrameWindowCount > 0
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.reopenWindow",
                    title: "Reopen App Window",
                    isAvailable: hasReopenEscalatedFrameStream(generatedAt: generatedAt)
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.recoverWindowCapture",
                    title: "Recover App Screen",
                    isAvailable: hasEscalatedFrameStreamRecovery(generatedAt: generatedAt)
                ),
                WindowsAppRuntimeActionStatus(
                    id: "macWindows.autoOpen",
                    title: "Show App Windows Automatically",
                    isAvailable: macWindowIntegration.acceptsGuestWindowEvents
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.launchSelected",
                    title: "Open Selected Windows App",
                    isAvailable: canRequestSelectedAppLaunch
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.prepareWindows",
                    title: "Prepare Windows",
                    isAvailable: localRuntime.recommendedPrepareCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.refreshStatus",
                    title: "Refresh Windows Status",
                    isAvailable: true
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.startWindowsForApp",
                    title: "Start Windows To Open App",
                    isAvailable: launchPlan.recommendedStartCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.repairGuestAgentForApp",
                    title: "Repair App Connection",
                    isAvailable: launchPlan.recommendedRepairCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.prepareSparsePackage",
                    title: "Prepare Package Identity",
                    isAvailable: dailyUseReadiness.recommendedAction == "prepare-sparse-package"
                        && dailyUseReadiness.recommendedCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dailyUse.verifyIntegrations",
                    title: "Verify Daily Use",
                    isAvailable: dailyUseReadiness.recommendedAction == "verify-daily-use-integrations"
                        && (dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-action --json --action proof-multi-app"
                            || dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-action --json --action proof-recommended")
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dailyUse.verifyWindowCapture",
                    title: "Verify Window Capture",
                    isAvailable: dailyUseReadiness.borderlessCaptureRecommendedAction == "verify-window-capture"
                        && dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-status --json"
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dailyUse.requestNotificationConsent",
                    title: "Check Notifications",
                    isAvailable: canRequestWindowsNotificationConsent(
                        dailyUseReadiness: dailyUseReadiness
                    )
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dailyUse.verifyNotifications",
                    title: "Check Notifications",
                    isAvailable: canRunWindowsNotificationProof(
                        dailyUseReadiness: dailyUseReadiness,
                        notificationBridge: notificationBridge
                    )
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dailyUse.planPrinterBridge",
                    title: "Printer Setup",
                    isAvailable: dailyUseReadiness.printerBridgeRecommendedAction == WindowsAppRuntimePrinterBridgeDefaults.recommendedAction
                        && !dailyUseReadiness.printerBridgePlanCommand.isEmpty
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.recoverDisplay",
                    title: "Refresh Windows Display",
                    isAvailable: localRuntime.recommendedRecoveryCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.fulfillPendingLaunch",
                    title: "Open Queued Windows App",
                    isAvailable: pendingLaunch.isQueued && canFulfillPendingLaunch
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.waitAgent",
                    title: "Check App Connection",
                    isAvailable: !hasLiveAgentConnection
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.quietWhenIdle",
                    title: "Quiet Windows When Idle",
                    isAvailable: quietRuntime.canQuietRuntime
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.stopWhenIdle",
                    title: "Stop Windows When Idle",
                    isAvailable: quietRuntime.canQuietRuntime
                        || localRuntime.recommendedPowerDownCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.appWindow",
                    title: "Check App Window",
                    isAvailable: canRunAppWindowProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.coherence",
                    title: "Check App Input",
                    isAvailable: canRunCoherenceProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.mvp",
                    title: "Check Full App Flow",
                    isAvailable: canRunCoherenceProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.recommended",
                    title: "Check Windows App",
                    isAvailable: proofPlan.recommendedProofCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.multiApp",
                    title: "Check Daily Use Apps",
                    isAvailable: proofPlan.recommendedMultiAppProofCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "clipboard.setText",
                    title: "Set Windows Clipboard Text",
                    isAvailable: canSendHostClipboardText
                )
            ]
        )
    }

    public func pendingLaunchStatus() -> WindowsAppRuntimePendingLaunchStatus {
        guard let pendingLaunchAppId else {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: false,
                appId: nil,
                willLaunchOnAgentReconnect: false,
                recommendedAction: "none",
                reason: "No Windows app launch is queued."
            )
        }

        let appCanBeRequested = canRequestAppLaunch(appId: pendingLaunchAppId)
        if hasLiveAgentConnection && canLaunchApp(appId: pendingLaunchAppId) {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: true,
                appId: pendingLaunchAppId,
                willLaunchOnAgentReconnect: false,
                recommendedAction: "launch-pending-now",
                reason: "The Windows app connection is active; retry the queued app launch now."
            )
        }

        if appCanBeRequested && !hasLiveAgentConnection {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: true,
                appId: pendingLaunchAppId,
                willLaunchOnAgentReconnect: true,
                recommendedAction: "auto-launch-on-agent-reconnect",
                reason: "Veil will launch the queued Windows app after the app connection returns."
            )
        }

        return WindowsAppRuntimePendingLaunchStatus(
            isQueued: true,
            appId: pendingLaunchAppId,
            willLaunchOnAgentReconnect: false,
            recommendedAction: "select-supported-app",
            reason: "The queued Windows app is not available in the current app catalog."
        )
    }

    public func launchPlanStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil
    ) -> WindowsAppRuntimeLaunchPlanStatus {
        guard let selectedAppId else {
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: nil,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: false,
                canLaunchSelectedAppNow: false,
                willOpenAppAutomatically: false,
                requiresRuntimeStart: false,
                requiresGuestAgent: false,
                recommendedAction: "select-app",
                reason: "Select a Windows app before opening the app runtime."
            )
        }

        let canRequest = canRequestAppLaunch(appId: selectedAppId)
        let canLaunchNow = canLaunchApp(appId: selectedAppId)
        let launchCommand = "veil-vmctl app-runtime-action --json --action launch --app-id \(selectedAppId)"
        let fulfillPendingCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending"
        let repairCommand = "veil-vmctl app-runtime-action --json --action repair-agent --wait-seconds 120"
        let hasPendingSelectedAppLaunch = pendingLaunchAppId == selectedAppId
        let localRuntime = localRuntime ?? localRuntimeStatus(snapshot: nil)

        if canLaunchNow {
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: selectedAppId,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: canRequest,
                canLaunchSelectedAppNow: true,
                willOpenAppAutomatically: true,
                requiresRuntimeStart: false,
                requiresGuestAgent: false,
                recommendedAction: hasPendingSelectedAppLaunch ? "fulfill-pending-now" : "launch-now",
                recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                reason: hasPendingSelectedAppLaunch
                    ? "The live Windows agent can fulfill the queued app launch now."
                    : "The live Windows agent can launch the selected app now."
            )
        }

        if canRequest {
            let runtimeIsAlreadyRunning = localRuntime.isKnown && localRuntime.isRunning
            let requiresRuntimeStart = !hasLiveAgentConnection && !runtimeIsAlreadyRunning
            if localRuntime.requiresGuestToolsMediaRebuild {
                return WindowsAppRuntimeLaunchPlanStatus(
                    selectedAppId: selectedAppId,
                    pendingLaunchAppId: pendingLaunchAppId,
                    canRequestSelectedAppLaunch: true,
                    canLaunchSelectedAppNow: false,
                    willOpenAppAutomatically: false,
                    requiresRuntimeStart: !runtimeIsAlreadyRunning,
                    requiresGuestAgent: true,
                    recommendedAction: "rebuild-guest-tools-media-before-launch",
                    recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                    reason: "The selected Windows app can be requested, but guest tools media must be rebuilt before Veil can repair the app connection."
                )
            }
            if requiresRuntimeStart && localRuntime.isKnown && !localRuntime.canStart {
                return WindowsAppRuntimeLaunchPlanStatus(
                    selectedAppId: selectedAppId,
                    pendingLaunchAppId: pendingLaunchAppId,
                    canRequestSelectedAppLaunch: true,
                    canLaunchSelectedAppNow: false,
                    willOpenAppAutomatically: false,
                    requiresRuntimeStart: true,
                    requiresGuestAgent: true,
                    recommendedAction: "prepare-local-runtime",
                    recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                    reason: "The selected Windows app can be requested, but the local Windows runtime is not boot ready. \(localRuntime.reason)"
                )
            }

            let recommendedAction: String
            if runtimeIsAlreadyRunning {
                recommendedAction = hasPendingSelectedAppLaunch
                    ? "repair-guest-agent-for-pending-launch"
                    : "repair-guest-agent-for-app-launch"
            } else {
                recommendedAction = hasPendingSelectedAppLaunch
                    ? "start-runtime-for-pending-launch"
                    : "start-runtime-and-wait-for-agent"
            }
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: selectedAppId,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: true,
                canLaunchSelectedAppNow: false,
                willOpenAppAutomatically: true,
                requiresRuntimeStart: requiresRuntimeStart,
                requiresGuestAgent: !hasLiveAgentConnection,
                recommendedAction: recommendedAction,
                recommendedStartCommand: requiresRuntimeStart ? "veil-vmctl qemu-start --json --wait-seconds 30" : nil,
                recommendedWaitCommand: hasLiveAgentConnection ? nil : "veil-vmctl guest-agent-wait --json --wait-seconds 30",
                recommendedRepairCommand: runtimeIsAlreadyRunning ? repairCommand : nil,
                recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                reason: hasPendingSelectedAppLaunch
                    ? (runtimeIsAlreadyRunning
                        ? "Windows is running and the selected app launch is queued; repair or start the guest agent, then open the app automatically."
                        : "The selected app launch is queued until Windows starts and the guest agent connects.")
                    : (runtimeIsAlreadyRunning
                        ? "Windows is running; repair or start the guest agent, then launch the selected app."
                        : "Start Windows, wait for the guest agent, then launch the selected app.")
            )
        }

        return WindowsAppRuntimeLaunchPlanStatus(
            selectedAppId: selectedAppId,
            pendingLaunchAppId: pendingLaunchAppId,
            canRequestSelectedAppLaunch: false,
            canLaunchSelectedAppNow: false,
            willOpenAppAutomatically: false,
            requiresRuntimeStart: false,
            requiresGuestAgent: !hasLiveAgentConnection,
            recommendedAction: "unavailable",
            recommendedWaitCommand: hasLiveAgentConnection ? nil : "veil-vmctl guest-agent-wait --json --wait-seconds 30",
            reason: "The selected Windows app is not available for launch."
        )
    }

    public func dailyUseReadinessStatus(
        proofPlan: WindowsAppRuntimeProofPlanStatus? = nil
    ) -> WindowsAppRuntimeDailyUseReadinessStatus {
        guard hasLiveAgentConnection else {
            return WindowsAppRuntimeDailyUseReadinessStatus(
                packageIdentityReady: false,
                borderlessCapturePreflightPassed: false,
                borderlessCaptureRecommendedAction: "connect-agent",
                notificationBridgePreflightPassed: false,
                notificationBridgeRecommendedAction: "connect-agent",
                printerBridgeMode: "manual-ipp-experiment",
                packageIdentityStatus: nil,
                recommendedAction: "connect-agent",
                recommendedCommand: "veil-vmctl guest-agent-wait --json --wait-seconds 30",
                reason: "Connect the Windows app agent before checking Daily Use integrations."
            )
        }

        let packageIdentityReady = health?.capabilities.packageIdentity == true
        let borderlessCapturePreflightPassed = packageIdentityReady && health?.capabilities.windowCapture == true
        let notificationBridgePreflightPassed = packageIdentityReady
            && (health?.notificationListener?.canListen ?? true)

        if !packageIdentityReady {
            let packageStatus = health?.packageIdentityStatus
            return WindowsAppRuntimeDailyUseReadinessStatus(
                packageIdentityReady: false,
                borderlessCapturePreflightPassed: false,
                borderlessCaptureRecommendedAction: "prepare-sparse-package",
                notificationBridgePreflightPassed: false,
                notificationBridgeRecommendedAction: "prepare-sparse-package",
                printerBridgeMode: "manual-ipp-experiment",
                packageIdentityStatus: packageStatus,
                packageIdentityStage: packageStatus?.stage,
                packageIdentitySucceeded: packageStatus?.succeeded,
                packageIdentityMessage: packageStatus?.message,
                packageIdentityEvidencePath: packageStatus?.statusPath,
                recommendedAction: "prepare-sparse-package",
                recommendedCommand: "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120",
                reason: packageIdentityReason(status: packageStatus)
            )
        }

        let packageStatus = health?.packageIdentityStatus
        let proofRecommendedCommand = "veil-vmctl app-runtime-action --json --action proof-recommended"
        let multiAppProofCommand = "veil-vmctl app-runtime-action --json --action proof-multi-app"
        let dailyUseProofCommand = proofPlan?.recommendedMultiAppProofCommand != nil
            ? multiAppProofCommand
            : proofRecommendedCommand
        let recommendedCommand = borderlessCapturePreflightPassed && proofPlan?.recommendedProofCommand != nil
            ? dailyUseProofCommand
            : "veil-vmctl app-runtime-status --json"
        let borderlessCaptureRecommendedAction = borderlessCapturePreflightPassed
            ? "verify-daily-use-integrations"
            : "verify-window-capture"
        let notificationBridgeRecommendedAction: String
        if let notificationListener = health?.notificationListener {
            notificationBridgeRecommendedAction = notificationListener.canListen
                ? "run-notification-proof"
                : notificationListener.recommendedAction
        } else {
            notificationBridgeRecommendedAction = "verify-notification-listener-consent"
        }

        return WindowsAppRuntimeDailyUseReadinessStatus(
            packageIdentityReady: true,
            borderlessCapturePreflightPassed: borderlessCapturePreflightPassed,
            borderlessCaptureRecommendedAction: borderlessCaptureRecommendedAction,
            notificationBridgePreflightPassed: notificationBridgePreflightPassed,
            notificationBridgeRecommendedAction: notificationBridgeRecommendedAction,
            printerBridgeMode: "manual-ipp-experiment",
            packageIdentityStatus: packageStatus,
            packageIdentityStage: packageStatus?.stage,
            packageIdentitySucceeded: packageStatus?.succeeded,
            packageIdentityMessage: packageStatus?.message,
            packageIdentityEvidencePath: packageStatus?.statusPath,
            recommendedAction: borderlessCaptureRecommendedAction,
            recommendedCommand: recommendedCommand,
            reason: borderlessCapturePreflightPassed
                ? "Package identity is available; run the strongest Windows app check before enabling borderless capture, notifications, and printer experiments."
                : "Package identity is available, but window capture must be verified before borderless app capture can be enabled."
        )
    }

    private func packageIdentityReason(status: PackageIdentityStatus?) -> String {
        guard let status else {
            return "A signed sparse package is required before borderless app capture or Windows notifications can be enabled."
        }

        let outcome = status.succeeded ? "last sparse package preparation succeeded" : "last sparse package preparation is not complete"
        let message: String
        if let statusMessage = status.message, !statusMessage.isEmpty {
            message = " (\(statusMessage))"
        } else {
            message = ""
        }
        return "A signed sparse package is required before borderless app capture or Windows notifications can be enabled; \(outcome) at stage \(status.stage)\(message)."
    }

    func canRequestWindowsNotificationConsent(
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    ) -> Bool {
        guard hasLiveAgentConnection,
              health?.capabilities.packageIdentity == true,
              health?.notificationListener != nil else {
            return false
        }

        return dailyUseReadiness.notificationBridgeRecommendedAction == "request-notification-listener-consent"
            || dailyUseReadiness.notificationBridgeRecommendedAction == "enable-notification-listener-settings"
    }

    private func canRunWindowsNotificationProof(
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus,
        notificationBridge: WindowsAppRuntimeNotificationBridgeStatus
    ) -> Bool {
        hasLiveAgentConnection
            && health?.capabilities.packageIdentity == true
            && dailyUseReadiness.notificationBridgePreflightPassed
            && notificationBridge.canReceiveNotifications
            && notificationBridge.recommendedAction == "run-notification-proof"
    }

    public func notificationBridgeStatus(
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    ) -> WindowsAppRuntimeNotificationBridgeStatus {
        guard hasLiveAgentConnection else {
            return WindowsAppRuntimeNotificationBridgeStatus(
                canReceiveNotifications: false,
                deliveredNotificationCount: latestWindowsNotifications.count,
                latestNotification: latestWindowsNotifications.first,
                recommendedAction: "connect-agent",
                reason: "Connect the Windows app agent before listening for Windows notifications."
            )
        }

        guard dailyUseReadiness.notificationBridgePreflightPassed else {
            let reason = dailyUseReadiness.notificationBridgeRecommendedAction == "prepare-sparse-package"
                ? "A signed sparse package identity is required before Windows notification listener consent can be requested."
                : "Windows notification listener consent is required before Veil can mirror Windows notifications."
            return WindowsAppRuntimeNotificationBridgeStatus(
                canReceiveNotifications: false,
                deliveredNotificationCount: latestWindowsNotifications.count,
                latestNotification: latestWindowsNotifications.first,
                recommendedAction: dailyUseReadiness.notificationBridgeRecommendedAction,
                reason: reason
            )
        }

        if latestWindowsNotifications.isEmpty {
            return WindowsAppRuntimeNotificationBridgeStatus(
                canReceiveNotifications: true,
                deliveredNotificationCount: 0,
                latestNotification: nil,
                recommendedAction: dailyUseReadiness.notificationBridgeRecommendedAction,
                reason: "Windows notification listener consent is ready; run notification-proof and wait for the first notification.received event."
            )
        }

        return WindowsAppRuntimeNotificationBridgeStatus(
            canReceiveNotifications: true,
            deliveredNotificationCount: latestWindowsNotifications.count,
            latestNotification: latestWindowsNotifications.first,
            recommendedAction: "receiving-windows-notifications",
            reason: "Windows notification events are reaching the macOS host bridge."
        )
    }

    public func releaseGateStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus,
        visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        proofPlan: WindowsAppRuntimeProofPlanStatus,
        proofArtifacts: WindowsAppRuntimeProofArtifactStatus
    ) -> WindowsAppRuntimeReleaseGateStatus {
        let displayRecoveryRequired = localRuntime.recommendedAction == "recover-runtime-display"
            || localRuntime.recommendedRecoveryCommand != nil
        let setupPassing = localRuntime.bootReady
            && localRuntime.windowsInstalled
            && !localRuntime.requiresGuestToolsMediaRebuild
            && !displayRecoveryRequired
        let setupCommand: String?
        if displayRecoveryRequired {
            setupCommand = localRuntime.recommendedRecoveryCommand
                ?? localRuntime.recommendedDisplayCommand
                ?? localRuntime.recommendedInstallStatusCommand
        } else if setupPassing {
            setupCommand = localRuntime.recommendedInstallStatusCommand
        } else if localRuntime.requiresGuestToolsMediaRebuild, localRuntime.isRunning {
            setupCommand = localRuntime.recommendedPowerDownCommand
        } else {
            setupCommand = localRuntime.recommendedMediaRebuildCommand
                ?? localRuntime.recommendedPrepareCommand
                ?? localRuntime.recommendedInstallStatusCommand
        }
        let surfacePassing = launcherVisibility.isEnabled
            && visibleSurfacePolicy.isEnabled
            && visibleSurfacePolicy.keepsRecoveryDisplayManual
            && (visibleSurfacePolicy.primarySurface == "launcher" || macWindowIntegration.hidesLauncherWhenMirroring)
        // A launchable agent is a prerequisite, not proof that the product opened a usable macOS
        // window. Keep the release gate open until the host has adopted at least one real HWND.
        let launchPassing = macWindowIntegration.mirroredWindowCount > 0
        let launchCommand = nextLaunchGateCommand(launchPlan: launchPlan)
        let checkPassing = proofArtifacts.latestProofPath != nil
            && proofArtifacts.latestProofKind != nil
        let quietOrRestorePassing = quietRuntime.canQuietRuntime
            || macWindowIntegration.mirroredWindowCount > 0
            || canReconnectRestoreMirrorSessions
            || canRestoreMirrorSessions

        let steps = [
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "windowsSetup",
                title: "Windows Setup Ready",
                state: setupPassing ? "passed" : "blocked",
                isPassing: setupPassing,
                evidence: localRuntime.reason,
                nextActionCommand: setupCommand
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "oneScreenPath",
                title: "One-Screen App Path",
                state: surfacePassing ? "passed" : "blocked",
                isPassing: surfacePassing,
                evidence: visibleSurfacePolicy.reason,
                nextActionCommand: "veil-vmctl app-runtime-status --json"
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "openWindowsApp",
                title: launchGateTitle(launchPlan: launchPlan, pendingLaunch: pendingLaunch),
                state: launchPassing ? "ready" : (launchCommand == nil ? "blocked" : "ready"),
                isPassing: launchPassing,
                evidence: launchPlan.reason,
                nextActionCommand: launchCommand
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "appCheckEvidence",
                title: "App Check Evidence",
                state: checkPassing ? "passed" : (proofPlan.recommendedProofCommand == nil ? "blocked" : "ready"),
                isPassing: checkPassing,
                evidence: proofArtifacts.reason,
                nextActionCommand: proofPlan.recommendedProofCommand
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "closeOrRestore",
                title: "Close Or Restore Apps",
                state: quietOrRestorePassing ? "ready" : "pending",
                isPassing: quietOrRestorePassing,
                evidence: quietRuntime.reason,
                nextActionCommand: closeOrRestoreGateCommand(
                    macWindowIntegration: macWindowIntegration,
                    quietRuntime: quietRuntime
                )
            )
        ]

        let requiredSteps = steps.filter(\.isRequired)
        let passingStepCount = requiredSteps.filter(\.isPassing).count
        let isPassing = passingStepCount == requiredSteps.count
        let firstUnmetStep = requiredSteps.first { !$0.isPassing }

        return WindowsAppRuntimeReleaseGateStatus(
            requiredStepCount: requiredSteps.count,
            passingStepCount: passingStepCount,
            isPassing: isPassing,
            recommendedAction: firstUnmetStep?.id ?? "ready-for-release-card",
            steps: steps,
            screenshotSlots: [
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "preBootLauncher",
                    title: "Pre-Boot Launcher",
                    expectedSurface: "One Veil launcher window with setup or start action visible."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "firstAppLaunch",
                    title: "First App Launch",
                    expectedSurface: "A selected Windows app is opening, queued, or ready with one concrete next action."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "appWindowOnly",
                    title: "App Window Only",
                    expectedSurface: "The mirrored Windows app window is visible while the launcher is hidden unless recovery is needed."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "menuRestore",
                    title: "Menu Restore",
                    expectedSurface: "Menu or Dock controls can bring forward, restore, reconnect, or close Windows app windows."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "closeQuiet",
                    title: "Close And Quiet",
                    expectedSurface: "After the final Windows app window closes, the launcher returns or quiet Windows action is available."
                )
            ],
            reason: isPassing
                ? "The one-screen Windows app release gate has current setup, launch, app check, and close or restore evidence."
                : "Continue the first unmet release gate step before promoting the one-screen Windows app flow."
        )
    }

    private func nextLaunchGateCommand(
        launchPlan: WindowsAppRuntimeLaunchPlanStatus
    ) -> String? {
        if launchPlan.canLaunchSelectedAppNow {
            return launchPlan.recommendedLaunchCommand
                ?? launchPlan.recommendedStartCommand
                ?? launchPlan.recommendedRepairCommand
                ?? launchPlan.recommendedWaitCommand
        }

        return launchPlan.recommendedStartCommand
            ?? launchPlan.recommendedRepairCommand
            ?? launchPlan.recommendedWaitCommand
            ?? launchPlan.recommendedLaunchCommand
    }

    private func launchGateTitle(
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    ) -> String {
        let appName = self.appName(for: pendingLaunch.appId ?? launchPlan.selectedAppId) ?? "Windows App"
        if pendingLaunch.isQueued {
            return prefixedMenuItemTitle(prefix: "Continue", title: appName)
        }

        return prefixedMenuItemTitle(prefix: "Open", title: appName)
    }

    private func closeOrRestoreGateCommand(
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus
    ) -> String? {
        if macWindowIntegration.mirroredWindowCount > 0 {
            return "veil-vmctl app-runtime-action --json --action close-all"
        }

        if let recommendedStopCommand = quietRuntime.recommendedStopCommand {
            return recommendedStopCommand
        }

        if canReconnectRestoreMirrorSessions || canRestoreMirrorSessions {
            return "veil-vmctl app-runtime-action --json --action reconnect-restore"
        }

        return nil
    }

    private func primaryNextActionStatus(
        releaseGate: WindowsAppRuntimeReleaseGateStatus
    ) -> WindowsAppRuntimePrimaryNextActionStatus {
        if releaseGate.isPassing {
            return WindowsAppRuntimePrimaryNextActionStatus(
                id: "ready-for-release-card",
                title: "Review App Flow",
                source: "releaseGate",
                isAvailable: true,
                runsInApp: false,
                command: "veil-vmctl app-runtime-review --json",
                reason: releaseGate.reason
            )
        }

        guard let step = releaseGate.steps.first(where: { $0.id == releaseGate.recommendedAction }) else {
            return WindowsAppRuntimePrimaryNextActionStatus(
                id: releaseGate.recommendedAction,
                title: "Review App Flow",
                source: "releaseGate",
                isAvailable: false,
                runsInApp: false,
                reason: releaseGate.reason
            )
        }

        let actionId = primaryNextActionId(stepId: step.id, command: step.nextActionCommand)
        return WindowsAppRuntimePrimaryNextActionStatus(
            id: step.id,
            title: step.title,
            source: "releaseGate",
            isAvailable: step.nextActionCommand != nil,
            runsInApp: actionId != nil,
            actionId: actionId,
            command: step.nextActionCommand,
            reason: step.evidence
        )
    }

    private func primaryNextActionId(stepId: String, command: String?) -> String? {
        guard let command else {
            return nil
        }

        switch stepId {
        case "windowsSetup":
            if command == "veil-vmctl qemu-install-status --json"
                || command == "veil-vmctl app-runtime-status --json" {
                return "runtime.refreshStatus"
            }
            if command.contains("--action stop-runtime")
                || command.contains("qemu-powerdown") {
                return "runtime.stopWhenIdle"
            }
            if command.contains("--action quiet-when-idle") {
                return "runtime.quietWhenIdle"
            }
            if command.contains("qemu-capture")
                || command.contains("qemu-display-smoke")
                || command.contains("--action recover-display") {
                return "runtime.recoverDisplay"
            }
            if command.hasPrefix("veil-vmctl prepare") {
                return "runtime.prepareWindows"
            }
            if command.contains("qemu-start") {
                return "runtime.startWindowsForApp"
            }
        case "oneScreenPath":
            return "runtime.refreshStatus"
        case "openWindowsApp":
            if command.contains("--action fulfill-pending") {
                return "runtime.fulfillPendingLaunch"
            }
            if command.contains("--action launch") {
                return "windowsApps.launchSelected"
            }
            if command.contains("--action recover-display") {
                return "runtime.recoverDisplay"
            }
            if command.contains("--action wait-agent") {
                return "runtime.waitAgent"
            }
            if command.contains("--action repair-agent") || command.contains("qemu-install-agent") {
                return "runtime.repairGuestAgentForApp"
            }
            if command.contains("qemu-start") {
                return "runtime.startWindowsForApp"
            }
        case "appCheckEvidence":
            return "proof.recommended"
        case "closeOrRestore":
            if command.contains("--action close-all") {
                return "windowsApps.closeAll"
            }
            if command.contains("--action reconnect-restore")
                || command.contains("--action restore") {
                return "windowsApps.reconnectRestore"
            }
            if command.contains("--action stop-runtime")
                || command.contains("--action quiet-when-idle") {
                return "runtime.quietWhenIdle"
            }
        default:
            break
        }

        return nil
    }

    func installedRuntimeHeroSupports(actionId: String?) -> Bool {
        guard let actionId else {
            return false
        }

        switch actionId {
        case "windowsApps.launchSelected",
             "runtime.fulfillPendingLaunch",
             "runtime.recoverDisplay",
             "runtime.waitAgent",
             "runtime.repairGuestAgentForApp",
             "runtime.prepareSparsePackage",
             "runtime.startWindowsForApp",
             "runtime.prepareWindows",
             "runtime.refreshStatus",
             "windowsApps.reconnectRestore",
             "windowsApps.restorePrevious",
             "windowsApps.closeAll",
             "runtime.quietWhenIdle",
             "runtime.stopWhenIdle",
             "dailyUse.requestNotificationConsent",
             "dailyUse.verifyNotifications",
             "dailyUse.verifyIntegrations",
             "dailyUse.verifyWindowCapture",
             "dailyUse.planPrinterBridge",
             "proof.recommended",
             "proof.multiApp":
            return true
        default:
            return false
        }
    }
}
