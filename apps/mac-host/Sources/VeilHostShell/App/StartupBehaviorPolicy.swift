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

    enum QuitAction: Equatable {
        /// Quit, leaving Windows as it is.
        case quit
        /// Suspend Windows, then quit.
        case suspend
        /// Ask whether to suspend Windows or keep it running.
        case ask
    }

    /// What quitting Veil does with a running Windows. Quitting used to leave Windows running in the
    /// background without a word whenever "Suspend Windows when Veil quits" was off, still using memory
    /// and battery with nothing on screen to say so. Veil asks instead, as Parallels does, unless the
    /// user already answered for good or macOS is logging out, where a question would hold the logout up.
    static func quitAction(
        snapshot: VMRuntimeSnapshot?,
        canSuspend: Bool,
        isBusy: Bool,
        keepsWindowsRunningWithoutAsking: Bool,
        isSystemQuit: Bool
    ) -> QuitAction {
        guard let snapshot, snapshot.state == .running, !isBusy, canSuspend else {
            return .quit
        }
        if snapshot.suspendOnQuit == true {
            return .suspend
        }
        if keepsWindowsRunningWithoutAsking || isSystemQuit {
            return .quit
        }
        return .ask
    }

    static let keepsWindowsRunningOnQuitKey = "veil.quit.keepsWindowsRunningWithoutAsking"
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
