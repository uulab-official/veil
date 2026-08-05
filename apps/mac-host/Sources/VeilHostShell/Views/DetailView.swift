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
    var launchWindowsAppAction: () -> Void
    var openNewWindowsAppAction: (String) -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var optimizationStatus: WindowsOptimizationStatus
    var optimizeWindowsAction: () -> Void
    var retryWindowsOptimizationAction: () -> Void
    var cancelWindowsOptimizationAction: () -> Void
    var windowsDisplaySizeChangedAction: (Int, Int) -> Void
    var displayMessage: String?
    @State private var showsWindowsDesktop = InstalledWorkspacePresentationPolicy.initiallyShowsDesktop

    var body: some View {
        VMRuntimeView(
            model: vmModel,
            apps: model.apps,
            mirrorSessions: model.mirrorSessions,
            selectedWindowsAppId: $model.selectedAppId,
            dashboardPhase: model.phase,
            hasLiveAgentConnection: model.hasLiveAgentConnection,
            guestAgentInstallEvidence: model.guestAgentInstallEvidence,
            agentDiagnostic: model.agentDiagnostic,
            canLaunchWindowsApp: model.canLaunchSelectedApp,
            canRequestWindowsAppLaunch: model.canRequestSelectedAppLaunch,
            canOpenNewWindowsApp: model.hasLiveAgentConnection && model.health?.capabilities.appLaunch == true,
            selectedWindowsAppName: model.selectedApp?.name,
            pendingLaunch: model.pendingLaunchStatus(),
            canFulfillPendingLaunch: model.canFulfillPendingLaunch,
            pendingWindowsAppName: pendingWindowsAppName,
            activeMirrorSession: activeMirrorSession,
            launchPlan: runtimeStatusReport.launchPlan,
            primaryNextAction: runtimeStatusReport.primaryNextAction,
            oneScreenUX: runtimeStatusReport.oneScreenUX,
            launchOnboarding: runtimeStatusReport.launchOnboarding,
            recommendedProofKind: proofPlan.recommendedProofKind,
            recommendedProofCommand: proofPlan.recommendedProofCommand,
            startVMAction: startVMAction,
            stopVMAction: stopVMAction,
            markWindowsInstalledAction: markWindowsInstalledAction,
            installGuestAgentAction: installGuestAgentAction,
            prepareSparsePackageAction: prepareSparsePackageAction,
            waitForGuestAgentAction: waitForGuestAgentAction,
            repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
            recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
            launchWindowsAppAction: launchWindowsAppAction,
            openNewWindowsAppAction: openNewWindowsAppAction,
            fulfillPendingLaunchAction: fulfillPendingLaunchAction,
            restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
            closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
            restartStaleFrameStreamsAction: restartStaleFrameStreamsAction,
            requestNotificationConsentAction: requestNotificationConsentAction,
            runNotificationProofAction: runNotificationProofAction,
            runRecommendedProofAction: runRecommendedProofAction,
            runMultiAppProofAction: runMultiAppProofAction,
            quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
            optimizationStatus: optimizationStatus,
            optimizeWindowsAction: optimizeWindowsAction,
            retryWindowsOptimizationAction: retryWindowsOptimizationAction,
            cancelWindowsOptimizationAction: cancelWindowsOptimizationAction,
            windowsDisplaySizeChangedAction: windowsDisplaySizeChangedAction,
            displayMessage: displayMessage,
            showsFullDesktop: $showsWindowsDesktop
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeMirrorSession: WindowMirrorSession? {
        model.mirrorSessions.first { $0.latestFrame != nil }
            ?? model.mirrorSessions.first
    }

    private var pendingWindowsAppName: String? {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return nil
        }

        return model.apps.first { $0.id == pendingAppId }?.name
    }

    private var proofPlan: WindowsAppRuntimeProofPlanStatus {
        runtimeStatusReport.proofPlan
    }

    private var runtimeStatusReport: WindowsAppRuntimeStatusReport {
        model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot)
        )
    }

}

enum InstalledWorkspacePresentationPolicy {
    static let initiallyShowsDesktop = false

    static func shouldKeepDesktopVisible(
        requested: Bool,
        runtimeState: VMRuntimeState,
        hasDesktopDisplay: Bool
    ) -> Bool {
        requested && runtimeState == .running && hasDesktopDisplay
    }

    static func shouldKeepDesktopVisibleAfterProfileIdentityChange(
        requested: Bool,
        previousAvailableProfileIdentity: InstalledWorkspaceAvailableProfileIdentity?,
        availableProfileIdentity: InstalledWorkspaceAvailableProfileIdentity?
    ) -> Bool {
        requested
            && previousAvailableProfileIdentity != nil
            && previousAvailableProfileIdentity == availableProfileIdentity
    }
}

struct InstalledWorkspaceAvailableProfileIdentity: Equatable {
    let profileName: String
    let virtualDiskPath: String

    init(profileName: String, virtualDiskPath: String) {
        self.profileName = profileName
        self.virtualDiskPath = virtualDiskPath
    }

    init?(snapshot: VMRuntimeSnapshot) {
        guard let profileName = snapshot.profileName,
              !profileName.isEmpty,
              let virtualDiskPath = snapshot.virtualDiskPath,
              !virtualDiskPath.isEmpty else {
            return nil
        }

        self.init(profileName: profileName, virtualDiskPath: virtualDiskPath)
    }
}
