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
