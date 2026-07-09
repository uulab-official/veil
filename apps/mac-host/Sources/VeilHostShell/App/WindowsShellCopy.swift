import Foundation
import VeilHostCore

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
}
