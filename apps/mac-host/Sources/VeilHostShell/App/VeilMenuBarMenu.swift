import AppKit
import SwiftUI
import VeilHostCore

struct VeilMenuBarMenu: View {
    @AppStorage(GuestStateSyncSettings.matchMacAppearanceKey) private var matchMacAppearanceInWindows = true
    var model: HostDashboardModel
    var vmModel: VMRuntimeModel
    var activateMainWindowAction: () -> Void
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var prepareSparsePackageAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var launchWindowsAppByIdAction: (String) -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var bringAllWindowsAppWindowsToFrontAction: () -> Void
    var focusWindowsAppWindowAction: (String) -> Void
    var closeWindowsAppWindowAction: (String) -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var prepareReviewEvidenceAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var refreshAppsAction: () -> Void
    var refreshRuntimeAction: () -> Void
    var supportsNativeDisplayWindow: Bool

    var body: some View {
        // Built once per render; every computed read used to rebuild the whole runtime report.
        let report = appRuntimeStatusReport
        let primaryAction = report.menuBarIntegration
        Button(
            primaryAction.primaryActionTitle,
            systemImage: MenuBarPrimaryActionPresentation.symbolName(
                for: primaryAction.primaryActionId,
                fallbackSymbolName: primaryAction.symbolName
            )
        ) {
            runMenuBarPrimaryAction()
        }
        .disabled(!primaryAction.primaryActionAvailable)

        if primaryAction.primaryActionId != "dock.openMainWindow" {
            Button("Open Veil", systemImage: "macwindow") {
                openMainWindow()
            }
        }

        Divider()

        Label(primaryAction.statusTitle, systemImage: primaryAction.symbolName)

        if !model.mirrorSessions.isEmpty {
            Label(runningAppsTitle, systemImage: "rectangle.3.group")
        }

        Divider()

        if !model.mirrorSessions.isEmpty {
            Menu("Running Windows Apps", systemImage: "rectangle.3.group") {
                Button(
                    activeWindowsAppsForwardTitle,
                    systemImage: "arrow.up.forward.app"
                ) {
                    bringAllWindowsAppWindowsToFrontAction()
                }

                Divider()

                ForEach(model.mirrorSessions) { session in
                    Menu(
                        WindowsShellCopy.menuItemTitle(session.window.title),
                        systemImage: "macwindow"
                    ) {
                        Button("Bring to Front", systemImage: "arrow.up.forward.app") {
                            focusWindowsAppWindowAction(session.id)
                        }
                        .disabled(!model.canFocusMirrorSession(windowId: session.id))

                        Button("Close", systemImage: "xmark.circle") {
                            closeWindowsAppWindowAction(session.id)
                        }
                        .disabled(!model.canCloseMirrorSession(windowId: session.id))
                    }
                }

                Divider()

                Button("Close All", systemImage: "xmark.circle.fill") {
                    closeAllWindowsAppWindowsAction()
                }
                .disabled(!model.canCloseAllMirrorSessions)
            }

            Divider()
        }

        if model.apps.isEmpty {
            Button("Load Windows Apps", systemImage: "square.grid.2x2") {
                openMainWindow()
                refreshAppsAction()
            }
            .disabled(model.phase == .loading || model.phase == .launching)
        } else {
            Menu("Windows Apps", systemImage: "square.grid.2x2") {
                ForEach(model.apps) { app in
                    Button(WindowsShellCopy.menuItemTitle(app.name), systemImage: symbolName(for: app)) {
                        if !model.hasLiveAgentConnection {
                            openMainWindow()
                        }
                        launchWindowsAppByIdAction(app.id)
                    }
                    .disabled(
                        !WindowsAppLaunchCommandPolicy.isEnabled(
                            canRequestLaunch: model.canRequestAppLaunch(appId: app.id),
                            canFulfillPendingLaunch: false,
                            hasRecoverableRuntimeDisplay: canRecoverRuntimeDisplay,
                            hasLiveAgentConnection: model.hasLiveAgentConnection
                        )
                    )
                }
            }
        }

        if shouldShowSecondaryPreviousAppsRestore {
            Button(restorePreviousAppsTitle, systemImage: "arrow.clockwise.square") {
                restoreWindowsAppWindowsAction()
            }
            .disabled(!model.canReconnectRestoreMirrorSessions)
        }

        if let queuedLaunchMenuState, shouldShowSecondaryQueuedLaunch {
            Button(queuedLaunchMenuState.title, systemImage: queuedLaunchMenuState.symbolName) {
                runQueuedLaunchAction(queuedLaunchMenuState)
            }
            .disabled(!queuedLaunchMenuState.isEnabled)
        }

        Button("Check Windows App", systemImage: "checkmark.seal") {
            openMainWindow()
            runRecommendedProofAction()
        }
        .disabled(report.proofPlan.recommendedProofCommand == nil)

        Button("Check Daily Use Apps", systemImage: "checkmark.seal.fill") {
            openMainWindow()
            runMultiAppProofAction()
        }
        .disabled(report.proofPlan.recommendedMultiAppProofCommand == nil)

        Button("Prepare Review Evidence", systemImage: "folder.badge.plus") {
            openMainWindow()
            prepareReviewEvidenceAction()
        }

        Divider()

        Button(openWindowsActionTitle, systemImage: "play.fill") {
            openMainWindow()
            startVMAction()
        }
        .disabled(!vmModel.canStart || vmModel.phase == .loading)

        if canShowWindowsDisplay {
            Button("Show Windows Display", systemImage: "display") {
                showWindowsDisplayAction()
            }
        }

        Button("Refresh Display", systemImage: "display.trianglebadge.exclamationmark") {
            openMainWindow()
            recoverRuntimeDisplayAction()
        }
        .disabled(!canRecoverRuntimeDisplay)

        Button("Repair App Connection", systemImage: "person.crop.circle.badge.plus") {
            openMainWindow()
            installGuestAgentAction()
        }
        .disabled(!canInstallGuestAgent)

        Button("Check App Connection", systemImage: "antenna.radiowaves.left.and.right") {
            openMainWindow()
            waitForGuestAgentAction()
        }
        .disabled(!canWaitForGuestAgent)

        Button("Mark Windows Installed", systemImage: "checkmark.seal") {
            openMainWindow()
            markWindowsInstalledAction()
        }
        .disabled(!canMarkWindowsInstalled)

        Button(WindowsShellCopy.closeWindowsActionTitle, systemImage: "stop.fill") {
            openMainWindow()
            stopVMAction()
        }
        .disabled(!vmModel.canStop || vmModel.phase == .loading)

        if model.canQuietRuntimeWhenIdle {
            Button("Quiet Windows", systemImage: "moon.zzz.fill") {
                quietWindowsWhenIdleAction()
            }
            .disabled(!vmModel.canStop || vmModel.phase == .loading)
        }

        Divider()

        Toggle("Match Mac Appearance in Windows", isOn: $matchMacAppearanceInWindows)

        Divider()

        Button(WindowsShellCopy.refreshWindowsStatusTitle, systemImage: "arrow.clockwise") {
            refreshRuntimeAction()
        }
        .disabled(vmModel.phase == .loading)

        Divider()

        Button("Quit Veil", systemImage: "power") {
            NSApp.terminate(nil)
        }
    }

    var canShowWindowsDisplay: Bool {
        supportsNativeDisplayWindow
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
    }

    private var openWindowsActionTitle: String {
        WindowsShellCopy.openWindowsActionTitle(
            windowsInstalled: vmModel.snapshot?.windowsInstalled == true
        )
    }

    var canInstallGuestAgent: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && (vmModel.snapshot?.installEvidence.kind != .guestAgent || !model.hasLiveAgentConnection)
    }

    private var canWaitForGuestAgent: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && !model.hasLiveAgentConnection
    }

    var canRecoverRuntimeDisplay: Bool {
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            return false
        }

        return vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .stale
            || vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .unavailable
    }

    private var canRepairQueuedAppLaunch: Bool {
        model.pendingLaunchStatus().willLaunchOnAgentReconnect
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && !model.canFulfillPendingLaunch
    }

    private var queuedLaunchMenuState: AppQueuedLaunchMenuState? {
        guard model.pendingLaunchAppId != nil else {
            return nil
        }

        return AppQueuedLaunchMenuState.make(
            appName: queuedLaunchAppName,
            canRecoverRuntimeDisplay: canRecoverRuntimeDisplay,
            canFulfillPendingLaunch: model.canFulfillPendingLaunch,
            canRepairQueuedAppLaunch: canRepairQueuedAppLaunch,
            canStartWindows: vmModel.canStart,
            runtimeIsLoading: vmModel.phase == .loading
        )
    }

    private var queuedLaunchAppName: String {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return "Windows App"
        }

        return model.apps.first { $0.id == pendingAppId }?.name ?? "Windows App"
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

    private var menuBarPrimaryAction: WindowsAppRuntimeMenuBarIntegrationStatus {
        appRuntimeStatusReport.menuBarIntegration
    }

    private var runningAppsTitle: String {
        let count = model.mirrorSessions.count
        return count == 1 ? "1 Windows App Running" : "\(count) Windows Apps Running"
    }

    private var activeWindowsAppsForwardTitle: String {
        WindowsShellCopy.bringWindowsAppsForwardTitle(
            openAppWindowCount: model.mirrorSessions.count,
            singleAppName: activeSingleAppName
        )
    }

    private var activeSingleAppName: String? {
        guard model.mirrorSessions.count == 1,
              let session = model.mirrorSessions.first else {
            return nil
        }

        return model.apps.first { $0.id == session.window.appId }?.name
            ?? session.window.title
    }

    private var restorePreviousAppsTitle: String {
        WindowsShellCopy.previousAppsRestoreTitle(
            canRestoreNow: model.canRestoreMirrorSessions,
            singleAppName: restorableSingleAppName,
            restoreWindowCount: model.restorableWindowCount
        )
    }

    private var shouldPromotePreviousAppsRestore: Bool {
        !model.restorableAppIds.isEmpty && model.mirrorSessions.isEmpty
    }

    private var shouldShowSecondaryPreviousAppsRestore: Bool {
        !model.restorableAppIds.isEmpty && !shouldPromotePreviousAppsRestore
    }

    private var shouldPromoteQueuedLaunch: Bool {
        model.pendingLaunchAppId != nil
            && model.mirrorSessions.isEmpty
            && !shouldPromotePreviousAppsRestore
    }

    private var shouldShowSecondaryQueuedLaunch: Bool {
        model.pendingLaunchAppId != nil && !shouldPromoteQueuedLaunch
    }

    private var restorableSingleAppName: String? {
        guard model.restorableAppIds.count == 1,
              let appId = model.restorableAppIds.first else {
            return nil
        }

        return model.apps.first { $0.id == appId }?.name
    }

    private func runQueuedLaunchAction(_ state: AppQueuedLaunchMenuState) {
        switch state.kind {
        case .recoverRuntimeDisplay:
            openMainWindow()
            recoverRuntimeDisplayAction()
        case .fulfillPendingLaunch:
            fulfillPendingLaunchAction()
        case .repairGuestAgentForAppLaunch:
            openMainWindow()
            repairGuestAgentForAppLaunchAction()
        case .startWindows:
            openMainWindow()
            startVMAction()
        }
    }

    private func runMenuBarPrimaryAction() {
        switch MenuBarPrimaryActionRoute.resolve(actionId: menuBarPrimaryAction.primaryActionId) ?? .openMainWindow {
        case .openMainWindow:
            openMainWindow()
        case .bringWindowsAppsForward:
            bringAllWindowsAppWindowsToFrontAction()
        case .restorePreviousApps:
            restoreWindowsAppWindowsAction()
        case .recoverDisplay:
            openMainWindow()
            recoverRuntimeDisplayAction()
        case .fulfillPendingLaunch:
            fulfillPendingLaunchAction()
        case .repairAppConnection:
            openMainWindow()
            repairGuestAgentForAppLaunchAction()
        case .startWindowsForApp:
            openMainWindow()
            launchWindowsAppAction()
        case .waitForAgent:
            openMainWindow()
            waitForGuestAgentAction()
        case .preparePackageIdentity:
            openMainWindow()
            prepareSparsePackageAction()
        case .requestNotificationConsent:
            openMainWindow()
            requestNotificationConsentAction()
        case .runNotificationProof:
            openMainWindow()
            runNotificationProofAction()
        case .showPrinterBridgePlan:
            openMainWindow()
        case .refreshRuntimeStatus:
            openMainWindow()
        case .restartFrameStream:
            restartStaleFrameStreamsAction()
        case .recoverWindowCapture:
            restartStaleFrameStreamsAction()
        case .reopenWindow:
            restartStaleFrameStreamsAction()
        case .launchSelectedApp:
            if !model.hasLiveAgentConnection {
                openMainWindow()
            }
            launchWindowsAppAction()
        case .runRecommendedProof:
            openMainWindow()
            runRecommendedProofAction()
        case .runMultiAppProof:
            openMainWindow()
            runMultiAppProofAction()
        }
    }

    private func openMainWindow() {
        MainWindowChrome.showMainWindow()
    }

    private func symbolName(for app: WindowsApp) -> String {
        switch app.iconId {
        case "icon_notepad":
            "note.text"
        case "icon_calculator":
            "plus.forwardslash.minus"
        case "icon_paint":
            "paintpalette"
        default:
            "macwindow"
        }
    }
}
