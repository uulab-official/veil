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
            return windowsInstalled ? "Ready to open Windows apps" : "Set up Windows apps on this Mac"
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

    static func menuStatusTitle(
        runtimeState: VMRuntimeState?,
        windowsInstalled: Bool,
        hasLiveAppConnection: Bool,
        hasQueuedApp: Bool,
        openAppWindowCount: Int
    ) -> String {
        if openAppWindowCount > 0 {
            return openAppWindowCount == 1 ? "1 Windows App Open" : "\(openAppWindowCount) Windows Apps Open"
        }

        if hasQueuedApp {
            return "App Waiting to Open"
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
            return windowsInstalled ? "Ready to Open Apps" : "Set Up Windows"
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
}
