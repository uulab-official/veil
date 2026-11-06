import Foundation
import VeilHostCore

enum WindowsRuntimeReadinessState: Equatable {
    case complete
    case current
    case pending
    case attention
}

struct WindowsRuntimeReadinessStep: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
    let state: WindowsRuntimeReadinessState
}

enum WindowsRuntimeReadiness {
    static func resolve(
        snapshot: VMRuntimeSnapshot,
        installEvidence: VMInstallEvidenceSummary? = nil,
        agentDiagnostic: AgentConnectionDiagnostic?,
        hasDisplay: Bool,
        asOf: Date = Date()
    ) -> [WindowsRuntimeReadinessStep] {
        let hasProfile = snapshot.profileName?.isEmpty == false
        let hasConnectedAgent = agentDiagnostic?.status == .connected
        let isActive = snapshot.state == .running || snapshot.state == .starting
        let isWindowsInstalled = (installEvidence ?? snapshot.installEvidence).isInstalled
        let consoleIsStillBooting = snapshot.latestConsoleLaunch?.isRecentlyBooting(asOf: asOf) == true
        let consoleBootStalled = shouldBlockAgentRepair(
            snapshot: snapshot,
            agentConnected: hasConnectedAgent,
            asOf: asOf
        )

        let profile = WindowsRuntimeReadinessStep(
            id: "profile",
            title: "Profile",
            detail: hasProfile ? "Local VM profile ready" : "Create a local VM profile",
            symbolName: hasProfile ? "checkmark.circle.fill" : "person.crop.rectangle.stack",
            state: hasProfile ? .complete : .current
        )

        let bootState: WindowsRuntimeReadinessState
        let bootDetail: String
        if snapshot.bootReady {
            bootState = .complete
            bootDetail = "Preflight checks pass"
        } else if hasProfile {
            bootState = .current
            bootDetail = "Finish local setup checks"
        } else {
            bootState = .pending
            bootDetail = "Waiting for profile"
        }
        let boot = WindowsRuntimeReadinessStep(
            id: "boot",
            title: "Boot",
            detail: bootDetail,
            symbolName: bootState == .complete ? "checkmark.seal.fill" : "gearshape.2",
            state: bootState
        )

        let windowsState: WindowsRuntimeReadinessState
        let windowsDetail: String
        let windowsSymbol: String
        switch snapshot.state {
        case .running where consoleBootStalled:
            windowsState = .attention
            windowsDetail = "Windows boot stalled; capture diagnostics and retry"
            windowsSymbol = "exclamationmark.triangle.fill"
        case .running:
            windowsState = .complete
            windowsDetail = "Windows runtime is running"
            windowsSymbol = "play.circle.fill"
        case .starting where consoleBootStalled:
            windowsState = .attention
            windowsDetail = "Windows boot stalled; capture diagnostics and retry"
            windowsSymbol = "exclamationmark.triangle.fill"
        case .starting:
            windowsState = .current
            windowsDetail = "Windows is starting"
            windowsSymbol = "arrow.triangle.2.circlepath"
        case .failed:
            windowsState = .attention
            windowsDetail = "The last Windows start failed"
            windowsSymbol = "exclamationmark.triangle.fill"
        case .suspended:
            windowsState = .current
            windowsDetail = "Resume the suspended session"
            windowsSymbol = "pause.circle"
        case .stopped where snapshot.bootReady:
            windowsState = .current
            windowsDetail = "Start Windows"
            windowsSymbol = "play.circle"
        default:
            windowsState = .pending
            windowsDetail = "Waiting for boot readiness"
            windowsSymbol = "play.circle"
        }
        let windows = WindowsRuntimeReadinessStep(
            id: "windows",
            title: "Windows",
            detail: windowsDetail,
            symbolName: windowsSymbol,
            state: windowsState
        )

        let displayState: WindowsRuntimeReadinessState
        let displayDetail: String
        if consoleBootStalled {
            displayState = .attention
            displayDetail = "No usable console after 180 seconds"
        } else if consoleIsStillBooting {
            displayState = .current
            displayDetail = "Waiting for the first Windows frame"
        } else if hasDisplay {
            displayState = .complete
            displayDetail = "Display surface attached"
        } else if snapshot.state == .failed {
            displayState = .attention
            displayDetail = "Display could not be attached"
        } else if isActive {
            displayState = .current
            displayDetail = "Waiting for the first Windows frame"
        } else {
            displayState = .pending
            displayDetail = "Starts with Windows"
        }
        let display = WindowsRuntimeReadinessStep(
            id: "display",
            title: "Screen",
            detail: displayDetail,
            symbolName: displayState == .complete ? "display.fill" : "display",
            state: displayState
        )

        let appState: WindowsRuntimeReadinessState
        let appDetail: String
        let appSymbol: String
        if !isWindowsInstalled {
            appState = .pending
            appDetail = "Available after Windows setup"
            appSymbol = "macwindow"
        } else if consoleBootStalled && !hasConnectedAgent {
            appState = .pending
            appDetail = "Restart Windows before reconnecting apps"
            appSymbol = "macwindow"
        } else if hasConnectedAgent {
            appState = .complete
            appDetail = "Windows apps are connected"
            appSymbol = "bolt.horizontal.circle.fill"
        } else if snapshot.state == .starting {
            appState = .current
            appDetail = "Waiting for the app connection"
            appSymbol = "antenna.radiowaves.left.and.right"
        } else if snapshot.state == .running {
            appState = .attention
            appDetail = "Repair the app connection"
            appSymbol = "bolt.horizontal.circle"
        } else {
            appState = .current
            appDetail = "Start Windows to connect apps"
            appSymbol = "macwindow"
        }
        let apps = WindowsRuntimeReadinessStep(
            id: "apps",
            title: "Apps",
            detail: appDetail,
            symbolName: appSymbol,
            state: appState
        )

        return [profile, boot, windows, display, apps]
    }

    static func shouldBlockAgentRepair(
        snapshot: VMRuntimeSnapshot,
        agentConnected: Bool = false,
        asOf: Date = Date()
    ) -> Bool {
        // A connected agent means Windows finished booting, whatever the console classifier last saw.
        guard !agentConnected else {
            return false
        }
        // Setup's boot entry means the firmware already handed off to Windows; a dark console then
        // is Windows turning its display off, and the agent repair is exactly what it needs.
        guard snapshot.installEvidence.kind != .windowsBootManager else {
            return false
        }
        return snapshot.latestConsoleLaunch?.isBootStalled(asOf: asOf) == true
    }
}

/// Whether the guest has been writing to its system disk recently.
///
/// The stall check only knows whether a console screenshot was classified, so a Windows Setup that
/// is copying files at 11% read as "hasn't finished starting" and offered to erase it. A disk that
/// keeps growing is the strongest local sign that the install is alive.
struct DiskWriteActivity: Equatable {
    static let activeWindowSeconds: TimeInterval = 120

    private(set) var lastAllocatedBytes: Int64?
    private(set) var lastGrowthAt: Date?

    mutating func observe(allocatedBytes: Int64?, at date: Date) {
        guard let allocatedBytes else {
            return
        }
        if let lastAllocatedBytes, allocatedBytes > lastAllocatedBytes {
            lastGrowthAt = date
        }
        lastAllocatedBytes = allocatedBytes
    }

    func isActive(asOf date: Date) -> Bool {
        guard let lastGrowthAt else {
            return false
        }
        return date.timeIntervalSince(lastGrowthAt) <= Self.activeWindowSeconds
    }
}
