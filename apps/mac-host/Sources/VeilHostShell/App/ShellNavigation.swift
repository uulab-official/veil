import AppKit
import Foundation
import Observation
import SwiftUI
import VeilHostCore

/// How the main window presents a running Windows machine, mirroring Parallels' View menu.
///
/// `apps` is the coherence-style default: Windows apps open as their own Mac windows and the main
/// window stays a launcher. `desktop` shows the full Windows desktop inside the main window.
enum MachineViewMode: String, CaseIterable, Identifiable {
    case apps
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Apps as Mac Windows"
        case .desktop: "Windows Desktop"
        }
    }

    var symbolName: String {
        switch self {
        case .apps: "macwindow.on.rectangle"
        case .desktop: "display"
        }
    }
}

/// Tabs of the machine configuration sheet, in the order Parallels' Configuration window uses.
enum MachineConfigurationTab: String, CaseIterable, Identifiable {
    case general
    case hardware
    case disk
    case installation
    case integration
    case usb
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .hardware: "Hardware"
        case .disk: "Disk"
        case .installation: "Installation"
        case .integration: "Mac Integration"
        case .usb: "USB Devices"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "info.circle"
        case .hardware: "cpu"
        case .disk: "internaldrive"
        case .installation: "opticaldisc"
        case .integration: "macwindow.on.rectangle"
        case .usb: "cable.connector"
        case .diagnostics: "stethoscope"
        }
    }
}

/// Window-level navigation shared by the toolbar, the menu bar commands, and the runtime view.
///
/// The menu commands live on the `App` scene while the sheets are presented deep inside the runtime
/// view, so this state cannot be `@State` on any one view.
@MainActor
@Observable
final class ShellNavigation {
    var presentedSheet: VMRuntimeSheetDestination?
    var configurationTab: MachineConfigurationTab = .general
    var viewMode: MachineViewMode = .apps {
        didSet {
            isShowingDesktopAutomatically = false
        }
    }
    /// True only while Veil itself chose the desktop, because the app connection was not up yet. Veil
    /// then returns to apps mode on its own once an app shows; a desktop the user picked stays.
    private(set) var isShowingDesktopAutomatically = false

    /// Shows the desktop or apps as Veil decided, rather than the user; see `isShowingDesktopAutomatically`.
    func showDesktopAutomatically(_ showsDesktop: Bool) {
        showsWindowsDesktop = showsDesktop
        isShowingDesktopAutomatically = showsDesktop
    }
    /// Set by the Actions menu, the assistant, and the stalled-boot bar; the main window asks once.
    var showsRestartInstallationConfirmation = false
    /// Set when the saved Windows session cannot be resumed; the main window asks whether to start
    /// Windows fresh, which discards it.
    var showsDiscardSavedSessionConfirmation = false
    /// The latest live Windows frame for the sidebar thumbnail; cleared when Windows stops.
    var liveThumbnail: NSImage?

    var showsWindowsDesktop: Bool {
        get { viewMode == .desktop }
        set { viewMode = newValue ? .desktop : .apps }
    }

    func openConfiguration(_ tab: MachineConfigurationTab = .general) {
        configurationTab = tab
        presentedSheet = .settings
    }

    func openWindowsDownload() {
        presentedSheet = .windowsDownload
    }

    func requestRestartInstallation() {
        showsRestartInstallationConfirmation = true
    }
}

/// Whether an unfinished Windows installation can be erased and started over. A Windows the guest
/// agent or the profile marks installed is never offered this, and there must be a disk to reset.
/// A disk that only has Setup's boot entry may still be stuck before the desktop, so the menu keeps
/// the command there, behind a confirmation that says Windows is on the disk.
enum RestartInstallationAvailability {
    static func isAvailable(snapshot: VMRuntimeSnapshot?, isBusy: Bool) -> Bool {
        guard let snapshot, !isBusy, snapshot.virtualDiskPath != nil else {
            return false
        }
        return !snapshot.installEvidence.isInstalled || snapshot.installEvidence.kind == .windowsBootManager
    }

    /// A blank sparse disk allocates nothing; Windows Setup writes partitions within seconds. Past
    /// this mark an earlier attempt left something behind that the next boot would trust.
    static let previousAttemptAllocatedBytes: Int64 = 64 * 1_024 * 1_024

    static func hasPreviousAttempt(snapshot: VMRuntimeSnapshot?) -> Bool {
        guard let snapshot, !snapshot.installEvidence.isInstalled else {
            return false
        }
        return (snapshot.virtualDiskAllocatedBytes ?? 0) >= previousAttemptAllocatedBytes
    }
}

/// The one-line machine status used by the sidebar row and the toolbar, kept free of SwiftUI state
/// so it can be unit tested.
struct MachineStatusPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case active
        case progress
        case warning
    }

    var title: String
    var symbolName: String
    var tone: Tone

    static func resolve(
        state: VMRuntimeState?,
        windowsInstalled: Bool,
        appConnectionNeedsRepair: Bool
    ) -> MachineStatusPresentation {
        switch state {
        case .running where !windowsInstalled:
            // Windows Setup runs for a long while; "Running" would read as a ready machine.
            return MachineStatusPresentation(title: "Installing Windows", symbolName: "arrow.down.circle.dotted", tone: .progress)
        case .starting where !windowsInstalled:
            return MachineStatusPresentation(title: "Starting Windows Setup…", symbolName: "circle.dotted", tone: .progress)
        case .running:
            if appConnectionNeedsRepair {
                return MachineStatusPresentation(title: "Running • App connection lost", symbolName: "exclamationmark.triangle.fill", tone: .warning)
            }
            return MachineStatusPresentation(title: "Running", symbolName: "circle.fill", tone: .active)
        case .starting:
            return MachineStatusPresentation(title: "Starting…", symbolName: "circle.dotted", tone: .progress)
        case .suspended:
            return MachineStatusPresentation(title: "Suspended", symbolName: "pause.circle.fill", tone: .neutral)
        case .failed:
            return MachineStatusPresentation(title: "Needs attention", symbolName: "exclamationmark.triangle.fill", tone: .warning)
        case .unsupported:
            return MachineStatusPresentation(title: "Not supported on this Mac", symbolName: "xmark.octagon.fill", tone: .warning)
        case .stopped:
            return windowsInstalled
                ? MachineStatusPresentation(title: "Shut down", symbolName: "circle", tone: .neutral)
                : MachineStatusPresentation(title: "Ready to install", symbolName: "arrow.down.circle", tone: .neutral)
        case .notConfigured, nil:
            return MachineStatusPresentation(title: "Not set up", symbolName: "plus.circle", tone: .neutral)
        }
    }

    var tint: Color {
        switch tone {
        case .neutral: .secondary
        case .active: .green
        case .progress: .blue
        case .warning: .orange
        }
    }
}

/// Which power controls the toolbar offers, matching Parallels' play / pause / shut-down cluster.
struct MachinePowerControls: Equatable {
    var showsStart: Bool
    var startTitle: String
    var showsSuspend: Bool
    var showsShutDown: Bool

    static func resolve(
        state: VMRuntimeState?,
        canStart: Bool,
        canStop: Bool,
        canSuspend: Bool,
        canResume: Bool
    ) -> MachinePowerControls {
        let isLive = state == .running || state == .starting
        return MachinePowerControls(
            showsStart: !isLive,
            startTitle: canResume ? "Resume" : "Start",
            showsSuspend: isLive && canSuspend,
            // `canStop` also covers a suspended machine, whose saved session can be discarded.
            showsShutDown: canStop
        )
    }
}
