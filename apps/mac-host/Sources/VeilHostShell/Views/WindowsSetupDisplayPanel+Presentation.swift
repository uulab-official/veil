import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

extension WindowsSetupDisplayPanel {
    private var selectedInstallerName: String? {
        snapshot.installerMediaPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var selectedDriverName: String? {
        snapshot.driverMediaPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    var controlBarTitle: String {
        if canStop {
            return "Windows is open"
        }

        if canStart {
            return "Windows 11"
        }

        return "Set up Windows 11"
    }

    var controlBarSubtitle: String {
        if canStop {
            return effectiveInstallEvidence.isInstalled
                ? "Installed Windows disk"
                : (selectedInstallerName ?? "Local Windows display")
        }

        if effectiveInstallEvidence.isInstalled {
            return "Installer ISO detached after setup"
        }

        if installerNeedsFilePickerAccess, let selectedInstallerName {
            return "Re-select \(selectedInstallerName)"
        }

        if let selectedInstallerName {
            return selectedInstallerName
        }

        return "Download the latest Windows 11 Arm64 ISO or use an existing ISO"
    }

    var effectiveInstallEvidence: VMInstallEvidenceSummary {
        guestAgentInstallEvidence ?? snapshot.installEvidence
    }

    var canInstallGuestAgent: Bool {
        canShowDisplay && effectiveInstallEvidence.kind != .guestAgent
    }

    var canWaitForGuestAgent: Bool {
        canShowDisplay && guestAgentInstallEvidence == nil
    }

    var canMarkWindowsInstalled: Bool {
        canShowDisplay && !effectiveInstallEvidence.isInstalled
    }

    var installActionTitle: String {
        switch effectiveInstallEvidence.kind {
        case .setupReady:
            "Install Windows"
        default:
            "Install Windows"
        }
    }

    private var virtualDiskSummary: String {
        guard snapshot.virtualDiskPath != nil else {
            return "Not created"
        }

        if let allocatedBytes = snapshot.virtualDiskAllocatedBytes {
            return "\(formattedByteCount(allocatedBytes)) used"
        }

        return resourceName(from: snapshot.virtualDiskPath) ?? "Selected"
    }

    private var isVirtualDiskEmptyForWindowsInstall: Bool {
        guard snapshot.bootReady,
              !effectiveInstallEvidence.isInstalled,
              let allocatedBytes = snapshot.virtualDiskAllocatedBytes else {
            return false
        }

        return allocatedBytes < 1_024 * 1_024 * 1_024
    }

    var flowItems: [InstallFlowItem] {
        let installerDetail: String
        let installerState: InstallFlowState
        if effectiveInstallEvidence.isInstalled {
            installerDetail = "Installed; ISO no longer required"
            installerState = .complete
        } else if let selectedInstallerName {
            installerDetail = installerNeedsFilePickerAccess ? "Re-select \(selectedInstallerName)" : selectedInstallerName
            installerState = installerNeedsFilePickerAccess ? .current : .complete
        } else {
            installerDetail = "Select the Windows 11 Arm ISO"
            installerState = .current
        }

        return [
            InstallFlowItem(
                title: "Windows ISO",
                detail: installerDetail,
                symbolName: "opticaldisc",
                state: installerState
            ),
            InstallFlowItem(
                title: "Virtual Disk",
                detail: snapshot.virtualDiskPath == nil
                    ? "Create a local 128 GB sparse disk"
                    : URL(fileURLWithPath: snapshot.virtualDiskPath ?? "").lastPathComponent,
                symbolName: "internaldrive",
                state: snapshot.virtualDiskPath == nil ? .pending : .complete
            ),
            InstallFlowItem(
                title: "Installer",
                detail: canShowDisplay
                    ? "Windows display is active in Veil"
                    : (canStart ? "Start Windows Setup" : "Waiting for preparation"),
                symbolName: "display",
                state: canShowDisplay ? .complete : (canStart ? .current : .pending)
            ),
            InstallFlowItem(
                title: "Mac Integration",
                detail: "Install Veil integration after Windows setup",
                symbolName: "macwindow.on.rectangle",
                state: snapshot.state == .running ? .current : .pending
            )
        ]
    }

    var appDisplayName: String {
        if pendingLaunch.isQueued {
            return pendingAppDisplayName
        }

        return selectedWindowsAppName ?? "Windows App"
    }

    var pendingAppDisplayName: String {
        pendingWindowsAppName ?? "Windows App"
    }

    var machineTitle: String {
        effectiveInstallEvidence.isInstalled ? "Windows 11" : "Install Windows 11"
    }

    var machineSubtitle: String {
        if effectiveInstallEvidence.isInstalled {
            if let activeMirrorSession {
                return "\(activeMirrorSession.window.title) is open as a Mac window"
            }

            if canFulfillPendingLaunch {
                return "Open \(pendingAppDisplayName) as a Mac window"
            }

            if pendingLaunch.willLaunchOnAgentReconnect {
                switch snapshot.state {
                case .running, .starting:
                    return "\(pendingAppDisplayName) will open when the app connection is ready"
                default:
                    return "\(pendingAppDisplayName) is queued. Start Windows to continue"
                }
            }

            if prefersOneClickAppLaunch {
                return "Open \(appDisplayName)"
            }

            if canRequestWindowsAppLaunch {
                return "Open Windows apps from macOS"
            }

            return effectiveInstallEvidence.kind == .guestAgent
                ? "App connection ready"
                : "Connect app integration to open Mac windows"
        }

        if snapshot.bootReady {
            return snapshot.runtimeProvider?.kind == .appleVirtualization
                ? "Windows will open in an Apple Virtualization console"
                : "Press play to start Windows in this window"
        }

        if installerNeedsFilePickerAccess {
            return "Re-select the ISO to grant macOS file access"
        }

        if snapshot.runtimeProvider?.kind == .appleVirtualization {
            return "Apple Virtualization compatibility mode • bring your Windows 11 Arm installer"
        }

        return "Bring your own Windows 11 Arm installer"
    }

    var machineHeroGradient: LinearGradient {
        switch snapshot.state {
        case .running:
            LinearGradient(colors: [Color(red: 0.04, green: 0.34, blue: 0.24), Color(red: 0.03, green: 0.18, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .failed, .unsupported:
            LinearGradient(colors: [Color(red: 0.42, green: 0.18, blue: 0.08), Color(red: 0.15, green: 0.12, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [Color(red: 0.02, green: 0.32, blue: 0.62), Color(red: 0.08, green: 0.09, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var showsUnavailableGuestAgentRoute: Bool {
        agentDiagnostic?.status == .unavailable
            && agentDiagnostic?.endpoint.hasPrefix("unavailable://") == true
    }

    private func resourceName(from path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var primaryTitle: String {
        if effectiveInstallEvidence.isInstalled {
            if canFulfillPendingLaunch {
                return "Open \(pendingAppDisplayName)"
            }

            if pendingLaunch.willLaunchOnAgentReconnect {
                switch snapshot.state {
                case .running, .starting:
                    return "Repair App Connection"
                default:
                    return "Continue Opening \(pendingAppDisplayName)"
                }
            }

            if prefersOneClickAppLaunch {
                return "Open \(appDisplayName)"
            }

            if canRequestWindowsAppLaunch {
                return "Open \(appDisplayName)"
            }

            if canInstallGuestAgent {
                return "Repair App Connection"
            }
        }

        if canRecoverRuntimeDisplay {
            return "Refresh Display"
        }

        if canStop {
            return "Stop Windows"
        }

        if effectiveInstallEvidence.isInstalled {
            return "Start Windows"
        }

        if canStart {
            return installSimulation.phase == .running ? "Starting..." : "Start Windows"
        }

        if snapshot.installerMediaPath == nil || installerNeedsFilePickerAccess {
            return "Download Windows 11"
        }

        return snapshot.profileName == nil ? "Prepare Windows" : "Continue Setup"
    }

    var primarySymbol: String {
        if effectiveInstallEvidence.isInstalled {
            if canFulfillPendingLaunch || pendingLaunch.willLaunchOnAgentReconnect {
                return pendingLaunch.willLaunchOnAgentReconnect && !canFulfillPendingLaunch
                    ? "bolt.horizontal.circle"
                    : "macwindow.badge.plus"
            }

            if prefersOneClickAppLaunch {
                return "macwindow.badge.plus"
            }

            if canRequestWindowsAppLaunch {
                return "macwindow.badge.plus"
            }

            if canInstallGuestAgent {
                return "person.crop.circle.badge.plus"
            }
        }

        if canRecoverRuntimeDisplay {
            return "display.trianglebadge.exclamationmark"
        }

        if canStop {
            return "stop.fill"
        }

        if canStart {
            return "play.fill"
        }

        if snapshot.installerMediaPath == nil || installerNeedsFilePickerAccess {
            return "arrow.down.circle"
        }

        return "wand.and.stars"
    }

    private var primaryHint: String {
        if effectiveInstallEvidence.isInstalled {
            if canFulfillPendingLaunch {
                return "Open the queued \(pendingAppDisplayName) launch as a Mac-managed window."
            }

            if pendingLaunch.willLaunchOnAgentReconnect {
                switch snapshot.state {
                case .running, .starting:
                    return "Windows is running; Veil is waiting for the app connection before opening \(pendingAppDisplayName)."
                default:
                    return "Start Windows, wait for the app connection, then open \(pendingAppDisplayName)."
                }
            }

            if prefersOneClickAppLaunch {
                return "Open \(appDisplayName); Veil will recover the Windows app connection automatically if needed."
            }

            if canRequestWindowsAppLaunch {
                return "Launch \(appDisplayName) as a Mac-managed window."
            }
        }

        if canStop {
            return "Stop Windows on this Mac."
        }

        if effectiveInstallEvidence.isInstalled {
            return "Start Windows and open its desktop in a separate window."
        }

        if canStart {
            return "Start Windows Setup in a separate desktop window."
        }

        if snapshot.installerMediaPath == nil {
            return "Download the latest Windows 11 Arm64 ISO from Microsoft. Veil will save it, prepare the VM, and open Windows Setup automatically."
        }

        if installerNeedsFilePickerAccess {
            return "Download Windows again or use the existing ISO so Veil can restore macOS file access."
        }

        return "Create the profile, disk, shared folder, and install media."
    }
}
