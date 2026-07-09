import Foundation
import VeilHostCore

enum WindowsShellStatusTone: Equatable {
    case green
    case blue
    case orange
    case secondary
}

struct WindowsLauncherMetadataStatus: Equatable {
    var title: String
    var value: String
    var symbolName: String
    var tone: WindowsShellStatusTone
}

enum WindowsShellCopy {
    static func headerSubtitle(
        hasLiveAppConnection: Bool,
        runtimeState: VMRuntimeState?,
        windowsInstalled: Bool
    ) -> String {
        if hasLiveAppConnection {
            return "Windows apps open on your Mac"
        }

        switch runtimeState {
        case .running:
            return "Preparing Windows apps"
        case .starting:
            return "Opening Windows"
        default:
            return windowsInstalled ? "Start Windows to open apps" : "Set up Windows apps on this Mac"
        }
    }

    static let quietStopWaitingMessage =
        "Windows app windows are closed. Veil will stop Windows after status refreshes."

    static func displayRecoveryStillStaleMessage(statusText: String) -> String {
        "Display is still \(statusText). Refresh the Windows display before opening an app."
    }

    static func openWindowsActionTitle(windowsInstalled: Bool) -> String {
        windowsInstalled ? "Open Windows" : "Set Up Windows"
    }

    static let closeWindowsActionTitle = "Close Windows"
    static let refreshWindowsStatusTitle = "Refresh Status"

    static func previousAppsRestoreTitle(
        canRestoreNow: Bool,
        singleAppName: String? = nil,
        restoreWindowCount: Int = 0
    ) -> String {
        if restoreWindowCount > 1,
           let singleAppName,
           !singleAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(canRestoreNow ? "Restore" : "Reconnect") \(restoreWindowCount) \(menuItemTitle(singleAppName)) Windows"
        }

        guard let singleAppName,
              !singleAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return canRestoreNow ? "Restore Previous Apps" : "Reconnect Previous Apps"
        }

        return prefixedMenuItemTitle(
            prefix: canRestoreNow ? "Restore" : "Reconnect",
            title: singleAppName
        )
    }

    static func previousAppsStatusTitle(
        canRestoreNow: Bool,
        singleAppName: String? = nil,
        restoreWindowCount: Int = 0
    ) -> String {
        if restoreWindowCount > 1,
           let singleAppName,
           !singleAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(menuItemTitle(singleAppName)) Windows \(canRestoreNow ? "Ready" : "Can Reconnect")"
        }

        guard let singleAppName,
              !singleAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return canRestoreNow ? "Previous Apps Ready" : "Previous Apps Can Reconnect"
        }

        return suffixedMenuItemTitle(
            prefix: "",
            title: singleAppName,
            suffix: canRestoreNow ? "Ready" : "Can Reconnect"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func bringWindowsAppsForwardTitle(
        openAppWindowCount: Int,
        singleAppName: String? = nil
    ) -> String {
        if openAppWindowCount == 1 {
            guard let singleAppName,
                  !singleAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Bring Windows App Forward"
            }

            return suffixedMenuItemTitle(
                prefix: "Bring",
                title: singleAppName,
                suffix: "Forward"
            )
        }

        return "Bring Windows Apps Forward"
    }

    static func menuItemTitle(_ title: String, maxCount: Int = 30) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "Windows App"
        }

        guard trimmedTitle.count > maxCount else {
            return trimmedTitle
        }

        let prefixCount = max(1, maxCount - 3)
        let prefix = String(trimmedTitle.prefix(prefixCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    static func prefixedMenuItemTitle(
        prefix: String,
        title: String,
        maxCount: Int = 30
    ) -> String {
        let itemTitleLimit = max(1, maxCount - prefix.count - 1)
        return "\(prefix) \(menuItemTitle(title, maxCount: itemTitleLimit))"
    }

    static func suffixedMenuItemTitle(
        prefix: String,
        title: String,
        suffix: String,
        maxCount: Int = 30
    ) -> String {
        let itemTitleLimit = max(1, maxCount - prefix.count - suffix.count - 2)
        return "\(prefix) \(menuItemTitle(title, maxCount: itemTitleLimit)) \(suffix)"
    }

    static func menuStatusTitle(
        runtimeState: VMRuntimeState?,
        windowsInstalled: Bool,
        hasLiveAppConnection: Bool,
        hasQueuedApp: Bool,
        queuedAppName: String? = nil,
        canRestorePreviousApps: Bool = false,
        canReconnectPreviousApps: Bool = false,
        restorableAppName: String? = nil,
        restorableWindowCount: Int = 0,
        openAppWindowCount: Int
    ) -> String {
        if openAppWindowCount > 0 {
            return openAppWindowCount == 1 ? "1 Windows App Open" : "\(openAppWindowCount) Windows Apps Open"
        }

        if hasQueuedApp {
            if let queuedAppName,
               !queuedAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return suffixedMenuItemTitle(
                    prefix: "",
                    title: queuedAppName,
                    suffix: "Waiting"
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return "App Waiting to Open"
        }

        if canRestorePreviousApps || canReconnectPreviousApps {
            return previousAppsStatusTitle(
                canRestoreNow: canRestorePreviousApps,
                singleAppName: restorableAppName,
                restoreWindowCount: restorableWindowCount
            )
        }

        if hasLiveAppConnection {
            return "Apps Ready"
        }

        switch runtimeState {
        case .running:
            return "Preparing Apps"
        case .starting:
            return "Opening Windows"
        case .suspended:
            return "Windows Paused"
        case .failed, .unsupported:
            return "Needs Attention"
        case .notConfigured:
            return "Set Up Windows"
        case .stopped, nil:
            return windowsInstalled ? "Start Windows for Apps" : "Set Up Windows"
        }
    }

    static func installedLauncherMetadata(
        windowsIsRunning: Bool,
        windowsCanStart: Bool,
        displayNeedsRefresh: Bool,
        appValue: String,
        appTone: WindowsShellStatusTone,
        appConnectionReady: Bool,
        appConnectionWaiting: Bool
    ) -> [WindowsLauncherMetadataStatus] {
        [
            WindowsLauncherMetadataStatus(
                title: "Windows",
                value: windowsIsRunning ? "Running" : (windowsCanStart ? "Ready" : "Stopped"),
                symbolName: "play.rectangle",
                tone: windowsIsRunning ? .green : (windowsCanStart ? .blue : .secondary)
            ),
            WindowsLauncherMetadataStatus(
                title: "App",
                value: appValue,
                symbolName: "macwindow",
                tone: appTone
            ),
            WindowsLauncherMetadataStatus(
                title: "Display",
                value: displayNeedsRefresh ? "Refresh" : (windowsIsRunning ? "Available" : "Hidden"),
                symbolName: displayNeedsRefresh ? "display.trianglebadge.exclamationmark" : "display",
                tone: displayNeedsRefresh ? .orange : (windowsIsRunning ? .green : .secondary)
            ),
            WindowsLauncherMetadataStatus(
                title: "Connection",
                value: appConnectionReady ? "Ready" : (appConnectionWaiting ? "Connecting" : "Needed"),
                symbolName: "bolt.horizontal.circle",
                tone: appConnectionReady ? .green : (appConnectionWaiting ? .blue : .orange)
            )
        ]
    }

    static func appCheckStatusTitle(
        recommendedProofKind: String?,
        latestProofFileName: String?
    ) -> String {
        switch recommendedProofKind {
        case "mvp":
            return "Full Check"
        case "coherence":
            return "Input Check"
        case "app-window":
            return "Window Check"
        default:
            return latestProofFileName == nil ? "Waiting" : "Saved"
        }
    }

    static func appCheckDetail(
        canRunMVPProof: Bool,
        canRunCoherenceProof: Bool,
        canRunAppWindowProof: Bool,
        recommendedProofCommand: String?,
        latestProofFileName: String?,
        reason: String
    ) -> String {
        if recommendedProofCommand != nil {
            if canRunMVPProof {
                return "Window, input, and clipboard are ready."
            }

            if canRunCoherenceProof {
                return "Window and input are ready."
            }

            if canRunAppWindowProof {
                return "Window capture is ready."
            }
        }

        if latestProofFileName != nil {
            return "Latest app check saved in diagnostics."
        }

        return reason
    }

    static func appFlowStatusTitle(
        isPassing: Bool,
        passingStepCount: Int,
        requiredStepCount: Int
    ) -> String {
        if isPassing {
            return "Ready"
        }

        return "\(passingStepCount) of \(requiredStepCount)"
    }

    static func appFlowDetail(
        recommendedAction: String,
        isPassing: Bool
    ) -> String {
        if isPassing {
            return "Setup, launch, app checks, and close controls are covered."
        }

        switch recommendedAction {
        case "windowsSetup":
            return "Finish Windows setup before opening apps."
        case "oneScreenPath":
            return "Keep setup, launch, and recovery in one clean app flow."
        case "openWindowsApp":
            return "Open or queue a Windows app from this screen."
        case "appCheckEvidence":
            return "Run Check App to save current app evidence."
        case "closeOrRestore":
            return "Close, restore, or quiet Windows from app controls."
        default:
            return "Continue the next app setup step."
        }
    }

    static func launchOnboardingTitle(
        state: String,
        canContinueInApp: Bool
    ) -> String {
        if canContinueInApp {
            return "Continue in Veil"
        }

        switch state {
        case "ready-for-review":
            return "Share App Flow"
        case "external-check":
            return "Review App Flow"
        case "blocked":
            return "Needs Attention"
        default:
            return "Continue App Flow"
        }
    }

    static func launchOnboardingDetail(
        currentStepTitle: String,
        pendingLiveProof: Bool
    ) -> String {
        pendingLiveProof ? "Next: \(currentStepTitle)" : currentStepTitle
    }

    static func primaryActionHandoffDetail(runsInApp: Bool) -> String {
        runsInApp ? "Runs inside Veil." : "Prepare Review Evidence."
    }

    static func launchOnboardingHandoffDetail(
        state: String,
        canContinueInApp: Bool
    ) -> String {
        if canContinueInApp {
            return "Runs inside Veil."
        }

        switch state {
        case "ready-for-review":
            return "Share Review Evidence."
        case "external-check":
            return "Prepare Review Evidence."
        case "blocked":
            return "Finish the highlighted setup step."
        default:
            return "Continue the app flow."
        }
    }

    static func launchOnboardingSymbolName(
        state: String,
        canContinueInApp: Bool
    ) -> String {
        if canContinueInApp {
            return "play.circle.fill"
        }

        switch state {
        case "ready-for-review":
            return "square.and.arrow.up"
        case "external-check":
            return "checkmark.seal"
        case "blocked":
            return "exclamationmark.triangle"
        default:
            return "arrow.forward.circle"
        }
    }
}
