enum LauncherPrimaryNextActionRoute: Equatable {
    case launchSelectedApp
    case fulfillPendingLaunch
    case recoverDisplay
    case waitForAgent
    case repairAppConnection
    case startWindows
    case startWindowsForApp
    case prepareWindows
    case preparePackageIdentity
    case refreshRuntimeStatus
    case reconnectPreviousApps
    case closeAllWindowsApps
    case restartFrameStream
    case recoverWindowCapture
    case reopenWindow
    case quietWindows
    case requestNotificationConsent
    case runNotificationProof
    case runRecommendedProof
    case runMultiAppProof

    static func resolve(
        actionId: String,
        command: String?,
        runsInApp: Bool
    ) -> LauncherPrimaryNextActionRoute? {
        guard runsInApp else {
            return nil
        }

        return resolve(actionId: actionId, command: command)
    }

    static func resolve(actionId: String, command: String?) -> LauncherPrimaryNextActionRoute? {
        switch actionId {
        case "windowsApps.launchSelected":
            return .launchSelectedApp
        case "runtime.fulfillPendingLaunch":
            return .fulfillPendingLaunch
        case "runtime.recoverDisplay":
            return .recoverDisplay
        case "runtime.waitAgent":
            return .waitForAgent
        case "runtime.repairGuestAgentForApp":
            return .repairAppConnection
        case "runtime.startWindowsForApp":
            return .startWindowsForApp
        case "runtime.prepareWindows":
            return .prepareWindows
        case "runtime.prepareSparsePackage":
            return .preparePackageIdentity
        case "runtime.refreshStatus", "dailyUse.verifyWindowCapture":
            return .refreshRuntimeStatus
        case "dailyUse.requestNotificationConsent":
            return .requestNotificationConsent
        case "dailyUse.verifyNotifications":
            return .runNotificationProof
        case "windowsApps.reconnectRestore", "windowsApps.restorePrevious":
            return .reconnectPreviousApps
        case "windowsApps.closeAll":
            return .closeAllWindowsApps
        case "windowsApps.restartFrameStream":
            return .restartFrameStream
        case "windowsApps.recoverWindowCapture":
            return .recoverWindowCapture
        case "windowsApps.reopenWindow":
            return .reopenWindow
        case "runtime.quietWhenIdle", "runtime.stopWhenIdle":
            return .quietWindows
        case "proof.recommended":
            return .runRecommendedProof
        case "proof.multiApp", "dailyUse.verifyIntegrations":
            return .runMultiAppProof
        default:
            break
        }

        guard let command else {
            return nil
        }

        if command.contains("app-window-proof")
            || command.contains("coherence-proof")
            || command.contains("mvp-proof") {
            return .runRecommendedProof
        }

        if command.contains("multi-app-proof") {
            return .runMultiAppProof
        }

        if command.contains("notification-proof") {
            return .runNotificationProof
        }

        if command.contains("--action repair-agent") || command.contains("qemu-install-agent") {
            return .repairAppConnection
        }

        if command.contains("guest-agent-wait") {
            return .waitForAgent
        }

        if command.contains("qemu-start") {
            return .startWindows
        }

        if command.contains("--action prepare-sparse-package")
            || command.contains("qemu-prepare-sparse-package") {
            return .preparePackageIdentity
        }

        if command.contains("prepare") {
            return .prepareWindows
        }

        if command.contains("qemu-install-status") || command.contains("app-runtime-status") {
            return .refreshRuntimeStatus
        }

        guard command.contains("app-runtime-action") else {
            return actionId == "appCheckEvidence" ? .runRecommendedProof : nil
        }

        if command.contains("--action fulfill-pending") {
            return .fulfillPendingLaunch
        }

        if command.contains("--action launch") {
            return .launchSelectedApp
        }

        if command.contains("--action recover-display") {
            return .recoverDisplay
        }

        if command.contains("--action wait-agent") {
            return .waitForAgent
        }

        if command.contains("--action prepare-sparse-package") {
            return .preparePackageIdentity
        }

        if command.contains("--action reconnect-restore")
            || command.contains("--action restore") {
            return .reconnectPreviousApps
        }

        if command.contains("--action close-all") {
            return .closeAllWindowsApps
        }

        if command.contains("--action restart-frame-stream") {
            return .restartFrameStream
        }

        if command.contains("--action recover-window-capture") {
            return .recoverWindowCapture
        }

        if command.contains("--action reopen-window") {
            return .reopenWindow
        }

        if command.contains("--action stop-runtime")
            || command.contains("--action quiet-when-idle") {
            return .quietWindows
        }

        if command.contains("--action request-notification-consent") {
            return .requestNotificationConsent
        }

        if command.contains("--action proof-recommended") {
            return .runRecommendedProof
        }

        if command.contains("--action proof-multi-app") {
            return .runMultiAppProof
        }

        return nil
    }

    var buttonTitle: String {
        switch self {
        case .launchSelectedApp:
            return "Open App"
        case .fulfillPendingLaunch:
            return "Open Queued"
        case .recoverDisplay:
            return "Refresh Display"
        case .waitForAgent:
            return "Check Connection"
        case .repairAppConnection:
            return "Repair Connection"
        case .startWindows:
            return "Open Windows"
        case .startWindowsForApp:
            return "Open App"
        case .prepareWindows:
            return "Prepare"
        case .preparePackageIdentity:
            return "Prepare Identity"
        case .refreshRuntimeStatus:
            return "Refresh Status"
        case .reconnectPreviousApps:
            return "Reconnect Apps"
        case .closeAllWindowsApps:
            return "Close Apps"
        case .restartFrameStream:
            return "Restart Screen"
        case .recoverWindowCapture:
            return "Recover Screen"
        case .reopenWindow:
            return "Reopen App"
        case .quietWindows:
            return "Quiet Windows"
        case .requestNotificationConsent:
            return "Allow Notifications"
        case .runNotificationProof:
            return "Check Notifications"
        case .runRecommendedProof:
            return "Check App"
        case .runMultiAppProof:
            return "Check Daily Use"
        }
    }

    var symbolName: String {
        switch self {
        case .launchSelectedApp, .fulfillPendingLaunch:
            return "macwindow.badge.plus"
        case .recoverDisplay:
            return "display.trianglebadge.exclamationmark"
        case .waitForAgent:
            return "antenna.radiowaves.left.and.right"
        case .repairAppConnection:
            return "bolt.horizontal.circle"
        case .startWindows:
            return "play.fill"
        case .startWindowsForApp:
            return "macwindow.badge.plus"
        case .prepareWindows:
            return "wand.and.stars"
        case .preparePackageIdentity:
            return "shippingbox"
        case .refreshRuntimeStatus:
            return "arrow.clockwise"
        case .reconnectPreviousApps:
            return "arrow.clockwise.square"
        case .closeAllWindowsApps:
            return "xmark.circle.fill"
        case .restartFrameStream:
            return "arrow.clockwise"
        case .recoverWindowCapture:
            return "wrench.and.screwdriver"
        case .reopenWindow:
            return "arrow.triangle.2.circlepath"
        case .quietWindows:
            return "moon.zzz.fill"
        case .requestNotificationConsent:
            return "bell.badge"
        case .runNotificationProof:
            return "bell.badge.fill"
        case .runRecommendedProof:
            return "checkmark.seal"
        case .runMultiAppProof:
            return "checkmark.seal.fill"
        }
    }
}
