import AppKit
import SwiftUI
import VeilHostCore

enum WindowsAppLaunchCommandPolicy {
    static func prefersLaunchAsHero(
        windowsInstalled: Bool,
        hasSelectedApp: Bool
    ) -> Bool {
        windowsInstalled && hasSelectedApp
    }

    static func isEnabled(
        canRequestLaunch: Bool,
        canFulfillPendingLaunch: Bool,
        hasRecoverableRuntimeDisplay _: Bool,
        hasLiveAgentConnection _: Bool
    ) -> Bool {
        // Display and agent recovery are part of the one-click launch lifecycle.
        // A recoverable transport failure must not make that lifecycle unreachable.
        canRequestLaunch || canFulfillPendingLaunch
    }
}

enum MenuBarPrimaryActionRoute: Equatable {
    case openMainWindow
    case bringWindowsAppsForward
    case restorePreviousApps
    case recoverDisplay
    case fulfillPendingLaunch
    case repairAppConnection
    case startWindowsForApp
    case waitForAgent
    case preparePackageIdentity
    case requestNotificationConsent
    case runNotificationProof
    case showPrinterBridgePlan
    case refreshRuntimeStatus
    case restartFrameStream
    case recoverWindowCapture
    case reopenWindow
    case launchSelectedApp
    case runRecommendedProof
    case runMultiAppProof

    static func resolve(actionId: String) -> MenuBarPrimaryActionRoute? {
        switch actionId {
        case "dock.openMainWindow":
            return .openMainWindow
        case "dock.bringWindowsAppsForward":
            return .bringWindowsAppsForward
        case "windowsApps.restorePrevious", "windowsApps.reconnectRestore":
            return .restorePreviousApps
        case "runtime.recoverDisplay":
            return .recoverDisplay
        case "runtime.fulfillPendingLaunch":
            return .fulfillPendingLaunch
        case "runtime.repairGuestAgentForApp":
            return .repairAppConnection
        case "runtime.startWindowsForApp":
            return .startWindowsForApp
        case "runtime.waitAgent":
            return .waitForAgent
        case "dailyUse.verifyWindowCapture":
            return .refreshRuntimeStatus
        case "windowsApps.restartFrameStream":
            return .restartFrameStream
        case "windowsApps.recoverWindowCapture":
            return .recoverWindowCapture
        case "windowsApps.reopenWindow":
            return .reopenWindow
        case "runtime.prepareSparsePackage":
            return .preparePackageIdentity
        case "dailyUse.requestNotificationConsent":
            return .requestNotificationConsent
        case "dailyUse.verifyNotifications":
            return .runNotificationProof
        case "dailyUse.planPrinterBridge":
            return .showPrinterBridgePlan
        case "windowsApps.launchSelected":
            return .launchSelectedApp
        case "proof.recommended":
            return .runRecommendedProof
        case "proof.multiApp", "dailyUse.verifyIntegrations":
            return .runMultiAppProof
        default:
            return nil
        }
    }

    var symbolName: String? {
        switch self {
        case .openMainWindow:
            return "macwindow"
        case .bringWindowsAppsForward:
            return "arrow.up.forward.app"
        case .restorePreviousApps:
            return "arrow.clockwise.square"
        case .recoverDisplay:
            return "display.trianglebadge.exclamationmark"
        case .fulfillPendingLaunch, .launchSelectedApp:
            return "arrow.up.forward.app"
        case .repairAppConnection:
            return "bolt.horizontal.circle"
        case .startWindowsForApp:
            return "play.fill"
        case .waitForAgent:
            return "antenna.radiowaves.left.and.right"
        case .preparePackageIdentity:
            return "shippingbox"
        case .requestNotificationConsent:
            return "bell.badge"
        case .runNotificationProof:
            return "bell.badge.fill"
        case .showPrinterBridgePlan:
            return "printer"
        case .refreshRuntimeStatus:
            return "arrow.clockwise"
        case .restartFrameStream:
            return "arrow.clockwise"
        case .recoverWindowCapture:
            return "wrench.and.screwdriver"
        case .reopenWindow:
            return "arrow.triangle.2.circlepath"
        case .runRecommendedProof:
            return "checkmark.seal"
        case .runMultiAppProof:
            return "checkmark.seal.fill"
        }
    }
}

enum MenuBarPrimaryActionPresentation {
    static func symbolName(for actionId: String, fallbackSymbolName: String) -> String {
        MenuBarPrimaryActionRoute.resolve(actionId: actionId)?.symbolName ?? fallbackSymbolName
    }
}

struct LauncherWindowVisibilityPolicy {
    /// - Parameter lastAppClosedByUser: the user just closed the last Windows app. Like Parallels
    ///   Coherence, that leaves nothing on screen: bringing the Veil window up in its place showed Windows
    ///   behind the app the user had just closed. Windows keeps running, or quiets, in the background, and
    ///   the Dock icon and menu bar bring the window back.
    static func shouldHideLauncher(
        visibleMirroredWindowCount: Int,
        modelRequestsHide: Bool,
        lastAppClosedByUser: Bool = false
    ) -> Bool {
        visibleMirroredWindowCount > 0 || modelRequestsHide || lastAppClosedByUser
    }
}

enum PreviousAppsRestoreHandoffAction: Equatable {
    case prepareGuestAgentRecovery(shouldShowDisplay: Bool)
    case startRuntime
    case waitForRuntimeAvailability
}

struct PreviousAppsRestoreHandoffPolicy {
    static func action(
        runtimeState: VMRuntimeState?,
        canStartRuntime: Bool,
        supportsNativeDisplayWindow: Bool
    ) -> PreviousAppsRestoreHandoffAction {
        switch runtimeState {
        case .running, .starting:
            return .prepareGuestAgentRecovery(shouldShowDisplay: supportsNativeDisplayWindow)
        default:
            return canStartRuntime ? .startRuntime : .waitForRuntimeAvailability
        }
    }
}

enum LauncherReopenPolicy {
    enum Destination: Equatable {
        case mainWindow
        case windowsAppWindows
    }

    static func destination(
        visibleMirroredWindowCount: Int,
        modelRequestsHideLauncher: Bool
    ) -> Destination {
        guard visibleMirroredWindowCount > 0 else {
            return .mainWindow
        }

        return modelRequestsHideLauncher ? .windowsAppWindows : .mainWindow
    }
}
