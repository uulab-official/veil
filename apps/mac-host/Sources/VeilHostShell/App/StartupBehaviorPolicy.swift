import Foundation
import VeilHostCore

/// When Veil starts or suspends Windows on its own as it opens and quits.
enum StartupBehaviorPolicy {
    /// `--start-vm` always starts Windows. Otherwise only an installed Windows starts on its own, so
    /// opening Veil never boots an installer the user has not asked for.
    static func startsWindowsOnLaunch(
        snapshot: VMRuntimeSnapshot?,
        launchArgumentRequested: Bool,
        canRunWindows: Bool
    ) -> Bool {
        if launchArgumentRequested {
            return true
        }
        guard let snapshot, snapshot.autoStart == true, snapshot.windowsInstalled, canRunWindows else {
            return false
        }
        switch snapshot.state {
        case .stopped, .suspended:
            return true
        case .notConfigured, .starting, .running, .failed, .unsupported:
            return false
        }
    }

    /// Suspend saves the session to disk; without it QEMU keeps Windows running after Veil exits.
    static func suspendsWindowsOnQuit(snapshot: VMRuntimeSnapshot?, canSuspend: Bool, isBusy: Bool) -> Bool {
        guard let snapshot, snapshot.suspendOnQuit == true, canSuspend, !isBusy else {
            return false
        }
        return snapshot.state == .running
    }
}

/// When a cold start may add the VirtIO driver ISO to a profile that has none.
enum DriverMediaAttachPolicy {
    static func attachesOnColdStart(snapshot: VMRuntimeSnapshot) -> Bool {
        guard snapshot.driverMediaPath?.isEmpty ?? true, snapshot.suspendedSession == nil else {
            return false
        }
        switch snapshot.state {
        case .stopped, .failed:
            return true
        case .notConfigured, .starting, .running, .suspended, .unsupported:
            return false
        }
    }
}

/// When Veil installs its tools in Windows on its own, like Parallels Tools after setup.
///
/// A Windows that Setup finished (its boot manager is on the disk) but whose agent has never
/// answered needs the agent repair: it installs NetKVM from the attached virtio-win ISO and starts
/// the agent. The repair types into Windows, so it waits until Windows has had time to reach the
/// desktop, and it needs the driver ISO attached, since without a guest network it cannot help.
enum AutomaticToolsSetupPolicy {
    static let desktopGraceSeconds: TimeInterval = 180

    static func installsTools(snapshot: VMRuntimeSnapshot?, hasLiveAgent: Bool, now: Date = Date()) -> Bool {
        guard let snapshot,
              !hasLiveAgent,
              snapshot.state == .running,
              snapshot.installEvidence.kind == .windowsBootManager,
              snapshot.driverMediaPath?.isEmpty == false,
              let startedAt = snapshot.latestConsoleLaunch?.startedAt else {
            return false
        }
        return now.timeIntervalSince(startedAt) >= desktopGraceSeconds
    }
}
