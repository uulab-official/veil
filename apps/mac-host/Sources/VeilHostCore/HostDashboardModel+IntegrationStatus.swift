import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    public func quietRuntimeStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil
    ) -> WindowsAppRuntimeQuietPolicyStatus {
        let recommendedAction: String
        let reason: String
        let canStopLocalRuntime = canStopLocalRuntime(localRuntime)
        let canQuietRuntime = canQuietRuntimeWhenIdle && canStopLocalRuntime
        // Suspend needs a *running* machine to stream. A `.suspended` VM is already quiet and a
        // `.starting` one has no consistent guest state yet, so neither is a suspend candidate.
        let canSuspendSession = localRuntime?.canSuspendSession == true && localRuntime?.state == .running
        let quietMode: String

        if !canQuietRuntime {
            quietMode = WindowsAppRuntimeQuietPolicyStatus.noneMode
        } else if canSuspendSession {
            quietMode = WindowsAppRuntimeQuietPolicyStatus.suspendMode
        } else {
            quietMode = WindowsAppRuntimeQuietPolicyStatus.stopMode
        }

        if !hasOpenedAppWindowThisSession {
            recommendedAction = "none"
            reason = "No Windows app window has opened in this host session."
        } else if !mirrorSessions.isEmpty {
            recommendedAction = "keep-running"
            reason = "Windows app windows are still open."
        } else if canQuietRuntime {
            // Names the one action that will run. The previous `stop-or-suspend-runtime` named both
            // without committing, so a reader could not tell whether their open apps were about to be
            // closed -- which is the only part of this they actually care about.
            recommendedAction = canSuspendSession ? "suspend-runtime" : "stop-runtime"
            reason = canSuspendSession
                ? "All Windows app windows are closed. Windows will be suspended, so open apps and unsaved work survive until the next launch."
                : "All Windows app windows are closed and Windows is ready to shut down cleanly. This session cannot be suspended, so open apps will not survive."
        } else if localRuntime?.isKnown == true && !canStopLocalRuntime {
            recommendedAction = "already-quiet"
            reason = "All Windows app windows are closed and Windows is already quiet."
        } else {
            recommendedAction = "wait-for-agent"
            reason = "Wait for the Windows app connection before stopping Windows cleanly."
        }

        return WindowsAppRuntimeQuietPolicyStatus(
            isEnabled: true,
            hasOpenedAppWindowThisSession: hasOpenedAppWindowThisSession,
            openWindowCount: mirrorSessions.count,
            canQuietRuntime: canQuietRuntime,
            willQuietAutomatically: canQuietRuntime,
            automaticQuietDelaySeconds: automaticQuietDelaySeconds,
            quietMode: quietMode,
            canSuspendSession: canSuspendSession,
            recommendedAction: recommendedAction,
            recommendedSuspendCommand: canQuietRuntime && canSuspendSession
                ? "veil-vmctl app-runtime-action --json --action suspend-runtime"
                : nil,
            // Stop stays available as the fallback even when suspend is the plan, because a suspend that
            // fails partway has to have somewhere to go.
            recommendedStopCommand: canQuietRuntime ? "veil-vmctl app-runtime-action --json --action stop-runtime" : nil,
            reason: reason
        )
    }

    private func canStopLocalRuntime(_ localRuntime: WindowsAppRuntimeLocalRuntimeStatus?) -> Bool {
        guard let localRuntime, localRuntime.isKnown else {
            return true
        }

        return localRuntime.state == .running || localRuntime.state == .suspended
    }

    public func macWindowIntegrationStatus(
        generatedAt: Date = Date()
    ) -> WindowsAppRuntimeMacWindowIntegrationStatus {
        let pendingFrameWindowCount = mirrorSessions.filter { $0.captureState == .pending }.count
        let streamingWindowCount = mirrorSessions.filter { $0.captureState == .streaming }.count
        let frameAssessments = mirrorSessions.map { session in
            (
                session: session,
                assessment: WindowFrameStreamAssessment.assess(session: session, generatedAt: generatedAt)
            )
        }
        let frameStatuses = frameAssessments.map(\.assessment.status)
        let freshFrameWindowCount = frameStatuses.filter { $0 == .fresh }.count
        let delayedFrameWindowCount = frameStatuses.filter { $0 == .delayed }.count
        let staleFrameWindowCount = frameStatuses.filter { $0 == .stale }.count
        let slowestFrame = frameAssessments.compactMap { entry -> (session: WindowMirrorSession, age: Int)? in
            let age = entry.assessment.latestFrameAgeMilliseconds
                ?? entry.assessment.waitingForFirstFrameMilliseconds
            guard let age else {
                return nil
            }

            return (entry.session, age)
        }
        .max { lhs, rhs in lhs.age < rhs.age }
        let frameLatencyHealth: String
        let frameLatencyRecommendedAction: String
        let reason: String

        if !hasLiveAgentConnection {
            frameLatencyHealth = "idle"
            frameLatencyRecommendedAction = "wait-for-agent"
            reason = "Waiting for the Windows app connection before opening app windows on macOS automatically."
        } else if mirrorSessions.isEmpty {
            frameLatencyHealth = "idle"
            frameLatencyRecommendedAction = "open-windows-app"
            reason = "Ready to open the next Windows app as a macOS window."
        } else if staleFrameWindowCount > 0 {
            frameLatencyHealth = "stale"
            frameLatencyRecommendedAction = "maintain-frame-streams"
            reason = "Windows app windows are mirrored, but at least one frame stream is stale."
        } else if delayedFrameWindowCount > 0 {
            frameLatencyHealth = "delayed"
            frameLatencyRecommendedAction = "refresh-runtime-status"
            reason = "Windows app windows are mirrored, with at least one delayed frame stream."
        } else if frameStatuses.contains(.waitingForFirstFrame) {
            frameLatencyHealth = "waiting"
            frameLatencyRecommendedAction = "wait-for-first-frame"
            reason = "Windows app windows are mirrored and waiting for the first app screen frame."
        } else {
            frameLatencyHealth = "healthy"
            frameLatencyRecommendedAction = "none"
            reason = "Windows app windows are mirrored as macOS windows."
        }

        return WindowsAppRuntimeMacWindowIntegrationStatus(
            isEnabled: true,
            acceptsGuestWindowEvents: hasLiveAgentConnection,
            opensMacWindowsAutomatically: true,
            hidesLauncherWhenMirroring: hasLiveAgentConnection && !mirrorSessions.isEmpty,
            mirroredWindowCount: mirrorSessions.count,
            foregroundableWindowCount: mirrorSessions.count,
            foregroundWindowId: mirrorSessions.last?.id,
            foregroundWindowTitle: mirrorSessions.last?.window.title,
            pendingFrameWindowCount: pendingFrameWindowCount,
            streamingWindowCount: streamingWindowCount,
            freshFrameWindowCount: freshFrameWindowCount,
            delayedFrameWindowCount: delayedFrameWindowCount,
            staleFrameWindowCount: staleFrameWindowCount,
            frameLatencyHealth: frameLatencyHealth,
            frameLatencyBudgetMilliseconds: WindowFrameStreamAssessment.freshFrameAgeThresholdMilliseconds,
            frameStaleTimeoutMilliseconds: WindowFrameStreamAssessment.delayedFrameAgeThresholdMilliseconds,
            slowestFrameWindowId: slowestFrame?.session.id,
            slowestFrameWindowTitle: slowestFrame?.session.window.title,
            slowestFrameAgeMilliseconds: slowestFrame?.age,
            frameLatencyRecommendedAction: frameLatencyRecommendedAction,
            reason: reason
        )
    }

    public func hasEscalatedFrameStreamRecovery(generatedAt: Date = Date()) -> Bool {
        mirrorSessions.contains {
            WindowFrameStreamAssessment.assess(
                session: $0,
                generatedAt: generatedAt
            ).recoveryEscalated
        }
    }

    public func hasReopenEscalatedFrameStream(generatedAt: Date = Date()) -> Bool {
        mirrorSessions.contains {
            WindowFrameStreamAssessment.assess(
                session: $0,
                generatedAt: generatedAt
            ).reopenEscalated
        }
    }

    /// - Parameter hostBackingScale: This Mac's backing scale factor. `nil` when the caller cannot supply
    ///   it — VeilHostCore does not import AppKit, so the app shell passes `NSScreen.backingScaleFactor`.
    ///   A `nil` reports the scaling state as unknown rather than assuming 1, which would claim a
    ///   mismatch on every Retina Mac whose scale was simply never read.
    public func displayScalingStatus(
        hostBackingScale: Double? = nil
    ) -> WindowsAppRuntimeDisplayScalingStatus {
        // The foreground window, matching how macWindowIntegration picks one. Guest display scaling is a
        // single Windows setting, so any mirrored window is representative of it.
        let reportedGuestScale = mirrorSessions.last?.latestFrame?.scale
        // Filtered where it is read, so an unusable value is never echoed into the report. It is only ever a
        // divisor or a number shown to the user, and it is good for neither.
        let guestRenderScale = reportedGuestScale.flatMap {
            Self.isPlausibleDisplayScale($0) ? $0 : nil
        }

        guard let hostBackingScale, hostBackingScale > 0 else {
            return WindowsAppRuntimeDisplayScalingStatus(
                guestRenderScale: guestRenderScale,
                recommendedAction: "inspect-host-display-scale",
                reason: "This Mac's display scale was not supplied, so Veil cannot tell whether Windows is rendering at the resolution this display shows."
            )
        }

        // A guest can put any `Double` in a frame's `scale`. A denormal such as 1e-320 passes a bare `> 0`
        // check and makes `hostBackingScale / guestRenderScale` infinite, which `JSONEncoder` refuses to
        // encode — so one malformed frame would have made `veil-vmctl app-runtime-status --json` fail
        // outright, taking every unrelated section of the report down with it.
        if reportedGuestScale != nil, guestRenderScale == nil {
            return WindowsAppRuntimeDisplayScalingStatus(
                hostBackingScale: hostBackingScale,
                recommendedAction: "inspect-guest-display-scale",
                reason: "Windows reported a display scale Veil cannot use, so its rendering resolution cannot be compared against this display."
            )
        }

        guard let guestRenderScale, guestRenderScale > 0 else {
            return WindowsAppRuntimeDisplayScalingStatus(
                hostBackingScale: hostBackingScale,
                recommendedAction: mirrorSessions.isEmpty ? "open-windows-app" : "wait-for-first-frame",
                reason: mirrorSessions.isEmpty
                    ? "Open a Windows app to compare its rendering resolution against this display."
                    : "Waiting for the first app screen frame before comparing rendering resolution against this display."
            )
        }

        let scaleRatio = hostBackingScale / guestRenderScale
        // A tolerance rather than exact equality: Windows offers 125% and 150% steps that will never equal
        // a Mac's 1x or 2x, and nagging about a 4% difference nobody can see would be noise.
        let isMatched = abs(scaleRatio - 1) <= 0.05
        let recommendedGuestScalePercent = Int((hostBackingScale * 100).rounded())

        if isMatched {
            return WindowsAppRuntimeDisplayScalingStatus(
                hostBackingScale: hostBackingScale,
                guestRenderScale: guestRenderScale,
                scaleRatio: scaleRatio,
                recommendedGuestScalePercent: recommendedGuestScalePercent,
                recommendedAction: "none",
                reason: "Windows is rendering app windows at the resolution this display shows, so mirrored windows are as sharp as the display allows."
            )
        }

        let isUpscaling = scaleRatio > 1
        return WindowsAppRuntimeDisplayScalingStatus(
            hostBackingScale: hostBackingScale,
            guestRenderScale: guestRenderScale,
            scaleRatio: scaleRatio,
            isUpscaling: isUpscaling,
            isOverRendering: !isUpscaling,
            recommendedGuestScalePercent: recommendedGuestScalePercent,
            // Named as a guest setting rather than a Veil action, because Veil cannot change Windows'
            // display scaling from outside the guest.
            recommendedAction: isUpscaling ? "raise-guest-display-scaling" : "lower-guest-display-scaling",
            reason: isUpscaling
                ? "Windows is rendering app windows at a lower resolution than this display shows, so macOS is enlarging them and text looks soft. Set Windows display scaling to \(recommendedGuestScalePercent)% to match."
                : "Windows is rendering more pixels than this display can show. Those pixels are encoded, sent, and composited before being discarded on every frame. Set Windows display scaling to \(recommendedGuestScalePercent)% to stop paying for them."
        )
    }

    public func launcherVisibilityStatus(
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus? = nil
    ) -> WindowsAppRuntimeLauncherVisibilityStatus {
        let macWindowIntegration = macWindowIntegration ?? macWindowIntegrationStatus()
        let shouldHideMainWindow = macWindowIntegration.hidesLauncherWhenMirroring
        let recommendedAction: String
        let reason: String

        if shouldHideMainWindow {
            recommendedAction = "hide-main-window-use-app-windows"
            reason = "A live Windows app window is mirrored, so the main launcher should stay hidden while Dock and menu controls remain available."
        } else if pendingLaunchAppId != nil {
            recommendedAction = "show-launcher-for-pending-launch"
            reason = "A Windows app launch is queued and may need the launcher to show start or reconnect recovery."
        } else if canRestoreMirrorSessions {
            recommendedAction = "show-launcher-or-restore-apps"
            reason = "No mirrored app window is open, but previous Windows app intent can be restored."
        } else {
            recommendedAction = "show-launcher"
            reason = "No live mirrored Windows app window needs the launcher hidden."
        }

        return WindowsAppRuntimeLauncherVisibilityStatus(
            isEnabled: true,
            canOpenMainWindow: true,
            shouldHideMainWindow: shouldHideMainWindow,
            keepsDockMenuAvailable: true,
            recommendedAction: recommendedAction,
            reason: reason
        )
    }

    public func visibleSurfacePolicyStatus(
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus? = nil,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus? = nil
    ) -> WindowsAppRuntimeVisibleSurfacePolicyStatus {
        let macWindowIntegration = macWindowIntegration ?? macWindowIntegrationStatus()
        let launcherVisibility = launcherVisibility ?? launcherVisibilityStatus(
            macWindowIntegration: macWindowIntegration
        )

        if launcherVisibility.shouldHideMainWindow && macWindowIntegration.mirroredWindowCount > 0 {
            return WindowsAppRuntimeVisibleSurfacePolicyStatus(
                isEnabled: true,
                primarySurface: "windows-app-windows",
                expectedVisibleSurfaceCount: macWindowIntegration.mirroredWindowCount,
                shouldHideLauncher: true,
                keepsRecoveryDisplayManual: true,
                reason: "Only mirrored Windows app windows should be visible during normal app runtime use; the main launcher and VM display stay out of the way unless recovery is requested."
            )
        }

        return WindowsAppRuntimeVisibleSurfacePolicyStatus(
            isEnabled: true,
            primarySurface: "launcher",
            expectedVisibleSurfaceCount: 1,
            shouldHideLauncher: false,
            keepsRecoveryDisplayManual: true,
            reason: "The main Veil launcher is the single normal surface until a live Windows app window is mirrored."
        )
    }

    public func oneScreenUXStatus(
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus,
        visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        menuBarIntegration: WindowsAppRuntimeMenuBarIntegrationStatus,
        primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
    ) -> WindowsAppRuntimeOneScreenUXStatus {
        let isMirroringApps = visibleSurfacePolicy.primarySurface == "windows-app-windows"
        let usesSinglePrimarySurfaceFamily = visibleSurfacePolicy.isEnabled
            && visibleSurfacePolicy.expectedVisibleSurfaceCount > 0
            && (visibleSurfacePolicy.primarySurface == "launcher" || isMirroringApps)
            && (!isMirroringApps || macWindowIntegration.mirroredWindowCount == visibleSurfacePolicy.expectedVisibleSurfaceCount)
        let hidesLauncherDuringAppMirroring = isMirroringApps
            ? launcherVisibility.shouldHideMainWindow && macWindowIntegration.hidesLauncherWhenMirroring
            : !launcherVisibility.shouldHideMainWindow
        let canRecoverFromMenuOrDock = isMirroringApps
            ? (menuBarIntegration.canBringWindowsAppsForward && launcherVisibility.keepsDockMenuAvailable)
            : (menuBarIntegration.canOpenMainWindow || launcherVisibility.canOpenMainWindow)
        let returnsToLauncherWhenNoAppWindows = isMirroringApps
            || (visibleSurfacePolicy.primarySurface == "launcher"
                && visibleSurfacePolicy.expectedVisibleSurfaceCount == 1
                && !launcherVisibility.shouldHideMainWindow)
        let primaryActionId = oneScreenPrimaryActionId(
            primaryNextAction: primaryNextAction,
            menuBarIntegration: menuBarIntegration
        )
        let primaryActionComesFromMenu = primaryActionId == menuBarIntegration.primaryActionId
            && primaryNextAction.actionId != primaryActionId
        let heroRunsPrimaryAction = installedRuntimeHeroSupports(actionId: primaryActionId)
            && (primaryNextAction.runsInApp || (primaryActionComesFromMenu && menuBarIntegration.primaryActionAvailable))
        let reason: String

        if isMirroringApps {
            reason = "Windows app windows are the only normal work surface, with Dock and menu controls available for recovery."
        } else {
            reason = "The launcher is the only normal setup surface until a Windows app opens as a macOS window."
        }

        return WindowsAppRuntimeOneScreenUXStatus(
            isEnabled: true,
            mode: visibleSurfacePolicy.primarySurface,
            expectedVisibleSurfaceCount: visibleSurfacePolicy.expectedVisibleSurfaceCount,
            usesSinglePrimarySurfaceFamily: usesSinglePrimarySurfaceFamily,
            hidesLauncherDuringAppMirroring: hidesLauncherDuringAppMirroring,
            keepsMenuBarControlAvailable: menuBarIntegration.isEnabled,
            keepsDockControlAvailable: launcherVisibility.keepsDockMenuAvailable,
            canRecoverFromMenuOrDock: canRecoverFromMenuOrDock,
            returnsToLauncherWhenNoAppWindows: returnsToLauncherWhenNoAppWindows,
            keepsDisplayRecoveryManual: visibleSurfacePolicy.keepsRecoveryDisplayManual,
            primaryActionId: primaryActionId,
            heroRunsPrimaryAction: heroRunsPrimaryAction,
            reason: reason
        )
    }

    private func oneScreenPrimaryActionId(
        primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus,
        menuBarIntegration: WindowsAppRuntimeMenuBarIntegrationStatus
    ) -> String? {
        if primaryNextAction.actionId == "runtime.refreshStatus",
           (menuBarIntegration.primaryActionId == "dailyUse.verifyIntegrations"
                || menuBarIntegration.primaryActionId == "dailyUse.verifyWindowCapture"
                || menuBarIntegration.primaryActionId == "dailyUse.requestNotificationConsent"
                || menuBarIntegration.primaryActionId == "dailyUse.verifyNotifications"),
           menuBarIntegration.primaryActionAvailable {
            return menuBarIntegration.primaryActionId
        }

        return primaryNextAction.actionId ?? menuBarIntegration.primaryActionId
    }

    public func launchOnboardingStatus(
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus,
        oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    ) -> WindowsAppRuntimeLaunchOnboardingStatus {
        let launchPrimaryActionId = oneScreenUX.heroRunsPrimaryAction
            ? (oneScreenUX.primaryActionId ?? primaryNextAction.actionId)
            : primaryNextAction.actionId
        let canContinueInApp = primaryNextAction.isAvailable
            && oneScreenUX.heroRunsPrimaryAction
            && launchPrimaryActionId != nil
        let state: String
        let reason: String

        if releaseGate.isPassing {
            state = "ready-for-review"
            reason = "The app-first launch flow is ready for review evidence."
        } else if canContinueInApp {
            state = "continue-in-app"
            reason = "Continue from the single Veil launcher action without opening a separate VM manager surface."
        } else if primaryNextAction.isAvailable {
            state = "external-check"
            reason = "The next app-flow check is available, but it should run as a review or CLI handoff instead of an in-app launcher button."
        } else {
            state = "blocked"
            reason = "The one-screen Windows app launch flow needs setup or recovery before it can continue."
        }
        let requiredSteps = releaseGate.steps.filter(\.isRequired)
        // Progress is sequential: a later optional integration proof must not make the launcher say
        // three steps are complete while the user is still being asked to perform step three.
        let completedStepCount = requiredSteps.prefix(while: \.isPassing).count
        let totalStepCount = releaseGate.requiredStepCount
        let currentStepNumber: Int
        if releaseGate.isPassing {
            currentStepNumber = totalStepCount
        } else if let currentIndex = requiredSteps.firstIndex(where: { $0.id == releaseGate.recommendedAction }) {
            currentStepNumber = currentIndex + 1
        } else {
            currentStepNumber = min(completedStepCount + 1, totalStepCount)
        }

        return WindowsAppRuntimeLaunchOnboardingStatus(
            state: state,
            currentStepId: primaryNextAction.id,
            currentStepTitle: primaryNextAction.title,
            currentStepDetail: launchOnboardingStepDetail(
                releaseGate: releaseGate,
                primaryNextAction: primaryNextAction
            ),
            usesSinglePrimarySurface: oneScreenUX.usesSinglePrimarySurfaceFamily,
            expectedVisibleSurfaceCount: oneScreenUX.expectedVisibleSurfaceCount,
            canContinueInApp: canContinueInApp,
            heroRunsPrimaryAction: oneScreenUX.heroRunsPrimaryAction,
            keepsRecoveryInMenuOrDock: oneScreenUX.canRecoverFromMenuOrDock,
            keepsVMDisplayManual: oneScreenUX.keepsDisplayRecoveryManual,
            pendingLiveProof: !releaseGate.isPassing,
            completedStepCount: completedStepCount,
            totalStepCount: totalStepCount,
            currentStepNumber: currentStepNumber,
            progressLabel: "Step \(currentStepNumber) of \(totalStepCount)",
            primaryActionId: launchPrimaryActionId,
            primaryCommand: primaryNextAction.command,
            reason: reason
        )
    }

    private func launchOnboardingStepDetail(
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
    ) -> String {
        if releaseGate.isPassing {
            return "Review and share the current app-flow evidence."
        }

        switch primaryNextAction.id {
        case "windowsSetup":
            switch primaryNextAction.actionId {
            case "runtime.recoverDisplay":
                return "Refresh the Windows display before continuing the app flow."
            case "runtime.stopWhenIdle", "runtime.quietWhenIdle":
                return "Quiet Windows, update setup media, then continue the app flow."
            case "runtime.prepareWindows":
                return "Finish Windows setup before opening apps."
            default:
                return "Check Windows setup, then continue the app flow."
            }
        case "oneScreenPath":
            return "Keep Veil as the only launcher until the app window opens."
        case "openWindowsApp":
            switch primaryNextAction.actionId {
            case "runtime.repairGuestAgentForApp":
                let appName = primaryNextAction.title.hasPrefix("Continue ")
                    ? String(primaryNextAction.title.dropFirst("Continue ".count))
                    : "the selected app"
                return "Reconnect the app connection, then open \(appName) automatically."
            case "runtime.startWindowsForApp":
                return "Start Windows, then open the selected app automatically."
            case "runtime.fulfillPendingLaunch":
                return "Open the queued app as a macOS window."
            case "runtime.waitAgent":
                return "Wait for the app connection, then continue automatically."
            case "runtime.prepareSparsePackage":
                return "Prepare Windows app identity, then continue Daily Use checks from Veil."
            case "windowsApps.launchSelected":
                return "Open the selected Windows app as a macOS window."
            default:
                return "Continue the selected Windows app from Veil."
            }
        case "appCheckEvidence":
            return "Run Check App and save current app evidence."
        case "closeOrRestore":
            return "Restore, bring forward, or close Windows app windows from Veil."
        default:
            return "Continue the next app-flow step."
        }
    }

    public func guestAgentDiagnosticsStatus(
        endpoint: String = HostDashboardModel.defaultAgentEndpoint
    ) -> WindowsAppRuntimeGuestAgentDiagnosticsStatus {
        if hasLiveAgentConnection {
            return WindowsAppRuntimeGuestAgentDiagnosticsStatus(
                endpoint: endpoint,
                isConnected: true,
                diagnosticCommand: "veil-host-probe --diagnose-agent",
                waitCommand: "veil-vmctl guest-agent-wait --json --wait-seconds 30",
                recommendedAction: "run-app-window-proof",
                reason: "The live Windows guest agent is connected; proceed to app launch and HWND frame proof."
            )
        }

        return WindowsAppRuntimeGuestAgentDiagnosticsStatus(
            endpoint: endpoint,
            isConnected: false,
            diagnosticCommand: "veil-host-probe --diagnose-agent",
            waitCommand: "veil-vmctl guest-agent-wait --json --wait-seconds 30",
            recommendedAction: "diagnose-agent",
            reason: "Run the guest-agent diagnostic before and after installing the Windows agent so setup evidence is captured consistently."
        )
    }

    public func localRuntimeStatus(
        snapshot: VMRuntimeSnapshot?
    ) -> WindowsAppRuntimeLocalRuntimeStatus {
        guard let snapshot else {
            return WindowsAppRuntimeLocalRuntimeStatus(
                isKnown: false,
                state: nil,
                bootReady: false,
                canStart: true,
                isRunning: false,
                windowsInstalled: false,
                installEvidence: guestAgentInstallEvidence,
                recommendedAction: "inspect-local-runtime",
                recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
                reason: "Local Windows runtime readiness has not been loaded for this status report."
            )
        }

        let isRunning = snapshot.state == .running || snapshot.state == .starting
        let automaticInstallMediaStatus = snapshot.windowsInstallStatusReport().automaticInstallMediaStatus
        let requiresGuestToolsMediaRebuild = snapshot.windowsInstalled
            && snapshot.installEvidence.kind != .guestAgent
            && (automaticInstallMediaStatus.state == .stale || automaticInstallMediaStatus.state == .missing)
        let canStart = snapshot.virtualizationAvailable
            && snapshot.minimumOSSupported
            && snapshot.profileName != nil
            && snapshot.bootReady
            && !requiresGuestToolsMediaRebuild
            && (snapshot.state == .stopped || snapshot.state == .suspended)
        let recommendedAction: String
        let recommendedPrepareCommand: String?
        let recommendedDisplayCommand: String?
        let recommendedRecoveryCommand: String?
        let recommendedMediaRebuildCommand = requiresGuestToolsMediaRebuild
            ? (automaticInstallMediaStatus.rebuildCommand ?? prepareCommand(for: snapshot))
            : nil
        // Setup's boot entry means the firmware already handed off to Windows. An old console
        // screenshot then says nothing about the live display, and the agent is what is missing.
        let windowsOnDisk = snapshot.installEvidence.kind == .windowsBootManager
        let consolePreviewStatus = snapshot.latestConsoleLaunch?.previewStatus
        let consoleIsStillBooting = !windowsOnDisk
            && snapshot.latestConsoleLaunch?.isRecentlyBooting(asOf: Date()) == true
        let consoleBootStalled = !windowsOnDisk
            && snapshot.latestConsoleLaunch?.isBootStalled(asOf: Date()) == true
        let recommendedPowerDownCommand = isRunning && (requiresGuestToolsMediaRebuild || consoleBootStalled)
            ? "veil-vmctl app-runtime-action --json --action stop-runtime"
            : nil
        let reason: String

        if isRunning, requiresGuestToolsMediaRebuild {
            recommendedAction = "rebuild-guest-tools-media"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = nil
            recommendedRecoveryCommand = nil
            reason = "The local Windows runtime is running with stale guest tools media attached; power down Windows, rebuild VeilAutoInstall.iso, then restart before repairing the app connection."
        } else if isRunning, consoleIsStillBooting {
            recommendedAction = "wait-for-guest-agent"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = snapshot.latestConsoleLaunch?.displaySurface.isLiveCapable == true
                ? "veil-vmctl qemu-display-smoke --json --wait-seconds 30"
                : nil
            recommendedRecoveryCommand = nil
            reason = "Windows is still booting; Veil has not observed a usable embedded console yet. Veil will wait for the guest agent instead of starting repair while the desktop is unavailable."
        } else if isRunning, consoleBootStalled {
            recommendedAction = "recover-runtime-display"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = snapshot.latestConsoleLaunch?.displaySurface.isLiveCapable == true
                ? "veil-vmctl qemu-display-smoke --json --wait-seconds 30"
                : nil
            recommendedRecoveryCommand = "veil-vmctl qemu-capture --json"
            reason = "Windows has been running for more than 180 seconds without a usable embedded console. Capture the current display evidence, stop Windows, and retry the boot before repairing the guest agent."
        } else if isRunning {
            let displayNeedsRecovery = !windowsOnDisk
                && (consolePreviewStatus == .stale || consolePreviewStatus == .unavailable)
            let liveDisplayValidationCommand = snapshot.latestConsoleLaunch?.displaySurface.isLiveCapable == true
                ? "veil-vmctl qemu-display-smoke --json"
                : nil
            recommendedAction = displayNeedsRecovery ? "recover-runtime-display" : "wait-for-guest-agent"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = liveDisplayValidationCommand
            recommendedRecoveryCommand = displayNeedsRecovery
                ? (liveDisplayValidationCommand ?? "veil-vmctl qemu-capture --json")
                : nil
            reason = displayNeedsRecovery
                ? "The local Windows runtime is running, but the embedded console preview is \(consolePreviewStatus?.rawValue ?? "unavailable"); validate the live display before relying on app launch recovery."
                : "The local Windows runtime is already running; wait for the guest agent before opening Windows apps."
        } else if requiresGuestToolsMediaRebuild {
            recommendedAction = "rebuild-guest-tools-media"
            recommendedPrepareCommand = recommendedMediaRebuildCommand
            recommendedDisplayCommand = nil
            recommendedRecoveryCommand = nil
            reason = "VeilAutoInstall.iso is stale or missing; rebuild guest tools media before starting Windows so app connection repair uses the current guest-agent bundle."
        } else if canStart {
            recommendedAction = "start-runtime"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = nil
            recommendedRecoveryCommand = nil
            reason = "The local Windows runtime is boot ready."
        } else {
            recommendedAction = "prepare-local-runtime"
            recommendedPrepareCommand = prepareCommand(for: snapshot)
            recommendedDisplayCommand = nil
            recommendedRecoveryCommand = nil
            reason = snapshot.detail
        }

        return WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: snapshot.state,
            bootReady: snapshot.bootReady,
            canStart: canStart,
            isRunning: isRunning,
            // Derived from the same persistence summary `vm-session-status` reports, so the app screen
            // and the CLI can never disagree about whether an idle VM can be suspended.
            canSuspendSession: VMSessionActionReportFactory
                .persistenceSummary(snapshot: snapshot)
                .isSupported,
            windowsInstalled: snapshot.windowsInstalled,
            installEvidence: guestAgentInstallEvidence ?? snapshot.installEvidence,
            automaticInstallMediaStatus: automaticInstallMediaStatus,
            requiresGuestToolsMediaRebuild: requiresGuestToolsMediaRebuild,
            recommendedAction: recommendedAction,
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            recommendedPrepareCommand: recommendedPrepareCommand,
            recommendedDisplayCommand: recommendedDisplayCommand,
            recommendedRecoveryCommand: recommendedRecoveryCommand,
            recommendedMediaRebuildCommand: recommendedMediaRebuildCommand,
            recommendedPowerDownCommand: recommendedPowerDownCommand,
            consolePreviewStatus: consolePreviewStatus,
            reason: reason
        )
    }

    func localRuntimeWithGuestAgentEvidence(
        _ localRuntime: WindowsAppRuntimeLocalRuntimeStatus
    ) -> WindowsAppRuntimeLocalRuntimeStatus {
        guard let guestAgentInstallEvidence else {
            return localRuntime
        }

        var runtime = localRuntime
        runtime.windowsInstalled = true
        runtime.installEvidence = guestAgentInstallEvidence
        if runtime.isRunning,
           runtime.recommendedAction == "recover-runtime-display" {
            // The embedded VNC preview is a setup/recovery surface. Once the live guest agent is
            // healthy, app HWND capture is the authoritative display path and a missing console
            // preview must not send the user back to Windows Setup.
            runtime.recommendedAction = "guest-agent-connected"
            runtime.recommendedDisplayCommand = nil
            runtime.recommendedRecoveryCommand = nil
            runtime.reason = "The Windows guest agent is connected; continue to the app window flow. The VM console remains available as a manual recovery surface."
        }
        return runtime
    }

    private func prepareCommand(for snapshot: VMRuntimeSnapshot) -> String {
        let installerPath = snapshot.installerMediaPath ?? "/path/to/Windows.iso"
        var command = "veil-vmctl prepare --installer \(shellQuotedArgument(installerPath))"

        if let driverPath = snapshot.driverMediaPath, !driverPath.isEmpty {
            command += " --drivers \(shellQuotedArgument(driverPath))"
        }

        return command
    }

    private func shellQuotedArgument(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    public var guestAgentInstallEvidence: VMInstallEvidenceSummary? {
        guard hasLiveAgentConnection, let health else {
            return nil
        }

        return VMInstallEvidenceSummary(
            kind: .guestAgent,
            isInstalled: true,
            title: "Guest agent connected",
            detail: "Windows is running the Veil guest agent \(health.agentVersion) over the local runtime channel."
        )
    }
}
