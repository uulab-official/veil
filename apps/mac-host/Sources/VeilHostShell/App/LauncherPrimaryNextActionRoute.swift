enum LauncherPrimaryNextActionRoute: Equatable {
    case launchSelectedApp
    case fulfillPendingLaunch
    case recoverDisplay
    case waitForAgent
    case repairAppConnection
    case startWindows
    case startWindowsForApp
    case prepareWindows
    case refreshRuntimeStatus
    case reconnectPreviousApps
    case closeAllWindowsApps
    case quietWindows
    case runRecommendedProof

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
        case "runtime.refreshStatus":
            return .refreshRuntimeStatus
        case "windowsApps.reconnectRestore", "windowsApps.restorePrevious":
            return .reconnectPreviousApps
        case "windowsApps.closeAll":
            return .closeAllWindowsApps
        case "runtime.quietWhenIdle", "runtime.stopWhenIdle":
            return .quietWindows
        case "proof.recommended", "dailyUse.verifyIntegrations":
            return .runRecommendedProof
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

        if command.contains("--action repair-agent") || command.contains("qemu-install-agent") {
            return .repairAppConnection
        }

        if command.contains("guest-agent-wait") {
            return .waitForAgent
        }

        if command.contains("qemu-start") {
            return .startWindows
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

        if command.contains("--action reconnect-restore")
            || command.contains("--action restore") {
            return .reconnectPreviousApps
        }

        if command.contains("--action close-all") {
            return .closeAllWindowsApps
        }

        if command.contains("--action stop-runtime")
            || command.contains("--action quiet-when-idle") {
            return .quietWindows
        }

        if command.contains("--action proof-recommended") {
            return .runRecommendedProof
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
        case .refreshRuntimeStatus:
            return "Refresh Status"
        case .reconnectPreviousApps:
            return "Reconnect Apps"
        case .closeAllWindowsApps:
            return "Close Apps"
        case .quietWindows:
            return "Quiet Windows"
        case .runRecommendedProof:
            return "Check App"
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
        case .refreshRuntimeStatus:
            return "arrow.clockwise"
        case .reconnectPreviousApps:
            return "arrow.clockwise.square"
        case .closeAllWindowsApps:
            return "xmark.circle.fill"
        case .quietWindows:
            return "moon.zzz.fill"
        case .runRecommendedProof:
            return "checkmark.seal"
        }
    }
}
