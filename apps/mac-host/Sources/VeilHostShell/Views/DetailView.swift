import SwiftUI
import VeilHostCore

struct DetailView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var prepareSparsePackageAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var updateGuestToolsAction: () -> Void = {}
    var displayMessage: String?
    @Environment(ShellNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        // Built once per render. Each read of the computed property rebuilt the whole report, six times a
        // render, which was most of the main thread's time while a mirrored app was drawing.
        let report = runtimeStatusReport
        VMRuntimeView(
                model: vmModel,
                guestAgentInstallEvidence: model.guestAgentInstallEvidence,
                agentDiagnostic: model.agentDiagnostic,
                canLaunchWindowsApp: model.canLaunchSelectedApp,
                canRequestWindowsAppLaunch: model.canRequestSelectedAppLaunch,
                selectedWindowsAppName: model.selectedApp?.name,
                pendingLaunch: model.pendingLaunchStatus(),
                canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                pendingWindowsAppName: pendingWindowsAppName,
                activeMirrorSession: activeMirrorSession,
                launchPlan: report.launchPlan,
                primaryNextAction: report.primaryNextAction,
                oneScreenUX: report.oneScreenUX,
                launchOnboarding: report.launchOnboarding,
                recommendedProofKind: report.proofPlan.recommendedProofKind,
                recommendedProofCommand: report.proofPlan.recommendedProofCommand,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction,
                markWindowsInstalledAction: markWindowsInstalledAction,
                installGuestAgentAction: installGuestAgentAction,
                prepareSparsePackageAction: prepareSparsePackageAction,
                waitForGuestAgentAction: waitForGuestAgentAction,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                showWindowsDisplayAction: showWindowsDisplayAction,
                launchWindowsAppAction: launchWindowsAppAction,
                fulfillPendingLaunchAction: fulfillPendingLaunchAction,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
                restartStaleFrameStreamsAction: restartStaleFrameStreamsAction,
                requestNotificationConsentAction: requestNotificationConsentAction,
                runNotificationProofAction: runNotificationProofAction,
                runRecommendedProofAction: runRecommendedProofAction,
                runMultiAppProofAction: runMultiAppProofAction,
                quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
                guestToolsUpdateAvailable: guestToolsUpdateAvailable,
                updateGuestToolsAction: updateGuestToolsAction,
                displayResizeAction: { width, height in
                    Task { @MainActor in
                        _ = await model.resizeDisplay(width: width, height: height)
                    }
                },
                displayMessage: displayMessage,
                showsFullDesktop: $navigation.showsWindowsDesktop
            )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            synchronizeWorkspacePresentation()
        }
        .onChange(of: vmModel.snapshot?.state) { _, _ in
            synchronizeWorkspacePresentation()
        }
        .onChange(of: model.hasLiveAgentConnection) { _, isConnected in
            // Losing the app connection leaves the launcher with nothing it can open, so fall back
            // to the desktop, unless app windows are showing; see `synchronizeWorkspacePresentation`.
            // Regaining it returns to apps once an app has a frame to show, instead of pulling the user
            // out of the desktop they are using.
            if isConnected {
                returnToAppsIfReady()
            } else {
                synchronizeWorkspacePresentation()
            }
        }
        .onChange(of: hasFirstAppFrame) { _, _ in
            returnToAppsIfReady()
        }
        .onChange(of: model.mirrorSessions.isEmpty) { _, _ in
            returnToAppsIfReady()
        }
    }

    private var hasFirstAppFrame: Bool {
        model.mirrorSessions.contains { $0.latestFrame != nil }
    }

    /// Leaves the desktop Veil chose by itself once apps can show. Checked on every change rather than only
    /// on the first frame: after the app connection drops and comes back, the windows still hold the frames
    /// they had, so no first frame arrives and the desktop stayed up over them.
    private func returnToAppsIfReady() {
        if navigation.isShowingDesktopAutomatically,
           RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
            windowsInstalled: hasInstalledWindows,
            hasFirstAppFrame: hasFirstAppFrame,
            hasAppWindows: !model.mirrorSessions.isEmpty,
            hasLiveAppConnection: model.hasLiveAgentConnection
           ) {
            navigation.showDesktopAutomatically(false)
        }
    }

    private var activeMirrorSession: WindowMirrorSession? {
        Self.activeMirrorSession(in: model.mirrorSessions, runtimeState: vmModel.snapshot?.state)
    }

    /// Sessions are kept across a shutdown so their windows can be restored, but a stopped Windows
    /// has no open app; naming one made the launcher say Paint was open while Windows was off.
    static func activeMirrorSession(
        in sessions: [WindowMirrorSession],
        runtimeState: VMRuntimeState?
    ) -> WindowMirrorSession? {
        guard runtimeState == .running else {
            return nil
        }
        return sessions.first { $0.latestFrame != nil } ?? sessions.first
    }

    private var hasInstalledWindows: Bool {
        guard let snapshot = vmModel.snapshot else {
            return false
        }

        return snapshot.installEvidence.isInstalled ||
            (snapshot.profileName != nil && model.guestAgentInstallEvidence?.isInstalled == true)
    }

    private func synchronizeWorkspacePresentation() {
        let hasDesktopDisplay = vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
        let showsDesktop = RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
            windowsInstalled: hasInstalledWindows,
            runtimeState: vmModel.snapshot?.state,
            hasDesktopDisplay: hasDesktopDisplay,
            hasLiveAppConnection: model.hasLiveAgentConnection
        )
        if showsDesktop,
           RuntimeWorkspacePresentationPolicy.keepsAppWindows(
            showsApps: !navigation.showsWindowsDesktop,
            windowsInstalled: hasInstalledWindows,
            hasAppWindows: hasFirstAppFrame
           ) {
            return
        }
        navigation.showDesktopAutomatically(showsDesktop)
    }

    /// The connected agent is older than the tools this Veil ships.
    private var guestToolsUpdateAvailable: Bool {
        model.hasLiveAgentConnection && GuestToolsUpdatePolicy.isOutdated(
            installedVersion: model.health?.agentVersion,
            bundledVersion: ShellGuestTools.bundledVersion
        )
    }

    private var pendingWindowsAppName: String? {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return nil
        }

        return model.apps.first { $0.id == pendingAppId }?.name
    }

    private var runtimeStatusReport: WindowsAppRuntimeStatusReport {
        model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot),
            hostBackingScale: HostDisplayScale.current
        )
    }

}

enum RuntimeWorkspacePresentationPolicy {
    /// Like a Parallels VM window, a running Windows shows its desktop. The app launcher replaces it
    /// only when Windows apps can actually open as Mac windows, which needs the Veil agent's
    /// connection; without it the launcher offers buttons that cannot work.
    static func defaultShowsFullDesktop(
        windowsInstalled: Bool,
        runtimeState: VMRuntimeState?,
        hasDesktopDisplay: Bool,
        hasLiveAppConnection: Bool = false
    ) -> Bool {
        guard runtimeState == .running, hasDesktopDisplay else {
            return false
        }
        return !windowsInstalled || !hasLiveAppConnection
    }

    /// Whether the desktop Veil chose by itself gives way to apps: the app connection is up to drive them,
    /// and either an app has a picture to show or no app window is waiting for one. Requiring a picture
    /// even with no app open left the whole Windows desktop in Veil's main window for as long as Veil ran,
    /// whenever it was opened with no Windows app open; Parallels shows its Control Center then, not the
    /// desktop.
    static func shouldReturnToApps(
        windowsInstalled: Bool,
        hasFirstAppFrame: Bool,
        hasAppWindows: Bool = true,
        hasLiveAppConnection: Bool = true
    ) -> Bool {
        windowsInstalled && hasLiveAppConnection && (hasFirstAppFrame || !hasAppWindows)
    }

    /// Whether app windows stay where they are when the desktop would otherwise take over by itself. The
    /// app connection drops for a moment whenever the agent restarts or updates; switching to the desktop
    /// then took every app window off screen and put all of Windows in the main window behind the user's
    /// work. The windows keep their last picture until the connection returns, as in Parallels Coherence.
    static func keepsAppWindows(showsApps: Bool, windowsInstalled: Bool, hasAppWindows: Bool) -> Bool {
        showsApps && windowsInstalled && hasAppWindows
    }

    static func showsAppDock(
        hasApps: Bool,
        hasInstalledWindows: Bool,
        showsFullDesktop: Bool
    ) -> Bool {
        hasApps && hasInstalledWindows && !showsFullDesktop
    }
}

enum WindowsDisplayAvailabilityPolicy {
    static func canShowDesktop(
        runtimeState: VMRuntimeState?,
        supportsNativeDisplayWindow: Bool,
        hasCapturedSurface: Bool
    ) -> Bool {
        guard runtimeState == .running || runtimeState == .starting else {
            return false
        }

        return supportsNativeDisplayWindow || hasCapturedSurface
    }
}

