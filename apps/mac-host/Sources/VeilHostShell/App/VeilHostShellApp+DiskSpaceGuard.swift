import Foundation
import VeilHostCore

extension VeilHostShellApp {
    /// Pauses Windows before the Mac volume holding its disk fills up, and continues it once space is
    /// freed (`HostDiskSpaceGuard`). Runs for the life of the app; each pass is one `statfs` unless space
    /// is low or Windows is paused here.
    func startDiskSpaceGuardLoopIfNeeded() {
        guard diskSpaceGuardTask == nil else {
            return
        }

        diskSpaceGuardTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HostDiskSpaceGuard.checkIntervalSeconds))
                guard !Task.isCancelled else {
                    return
                }
                let launchKey = currentLaunchPauseOwnerKey
                let recordedOwner = UserDefaults.standard.string(forKey: Self.diskSpaceGuardPauseOwnerKey)
                if let recordedOwner, recordedOwner != launchKey, launchKey != nil {
                    // Recorded for a QEMU that is gone; this one was not paused by the guard.
                    UserDefaults.standard.removeObject(forKey: Self.diskSpaceGuardPauseOwnerKey)
                }
                let pausedByGuard = vmModel.lowDiskSpacePauseAvailableBytes != nil
                    || (launchKey != nil && recordedOwner == launchKey)
                // While an operation such as a suspend runs, the machine's state belongs to it.
                guard vmModel.phase != .loading,
                      pausedByGuard || vmModel.snapshot?.state == .running,
                      let service = vmModel.runtimeService as? LocalVMRuntimeService else {
                    continue
                }
                await applyDiskSpaceGuard(await service.guardDiskSpace(pausedByGuard: pausedByGuard))
            }
        }
    }

    private func applyDiskSpaceGuard(_ outcome: HostDiskSpaceGuard.Outcome) async {
        switch outcome {
        case .unchanged:
            break
        case .paused(let available):
            vmModel.lowDiskSpacePauseAvailableBytes = available
            if let launchKey = currentLaunchPauseOwnerKey {
                UserDefaults.standard.set(launchKey, forKey: Self.diskSpaceGuardPauseOwnerKey)
            }
            await notifyLowDiskSpacePause(availableBytes: available)
        case .stillPaused(let available):
            // Also what a Veil opened after the pause sees first, so the menu says why Windows is still.
            vmModel.lowDiskSpacePauseAvailableBytes = available
        case .resumed, .released:
            vmModel.lowDiskSpacePauseAvailableBytes = nil
            UserDefaults.standard.removeObject(forKey: Self.diskSpaceGuardPauseOwnerKey)
            await windowsNotificationPresenter.removeDelivered(identifier: Self.lowDiskSpaceNotificationIdentifier)
        }
    }

    /// Which QEMU launch a recorded pause belongs to; see `HostDiskSpaceGuard.pauseOwnerKey`.
    static let diskSpaceGuardPauseOwnerKey = "veil.diskSpaceGuard.pausedLaunch"

    private var currentLaunchPauseOwnerKey: String? {
        guard let launch = vmModel.snapshot?.latestConsoleLaunch, let pid = launch.pid else {
            return nil
        }
        return HostDiskSpaceGuard.pauseOwnerKey(pid: pid, startedAt: launch.startedAt)
    }

    /// Windows is paused because the Mac volume holding its disk is nearly full. It can neither shut down
    /// nor be suspended then: it answers nothing, and saving its memory would fill the volume.
    var isWindowsPausedForDiskSpace: Bool {
        vmModel.lowDiskSpacePauseAvailableBytes != nil
    }

    static let lowDiskSpaceNotificationIdentifier = "org.uulab.veil.low-disk-space-pause"

    private func notifyLowDiskSpacePause(availableBytes: Int64) async {
        let request = WindowsNotificationPresentationRequest(
            identifier: Self.lowDiskSpaceNotificationIdentifier,
            title: String(localized: "Windows Paused: Mac Disk Almost Full"),
            body: WindowsShellCopy.lowDiskSpacePauseNotificationBody(availableBytes: availableBytes),
            threadIdentifier: "org.uulab.veil.runtime",
            userInfo: [:]
        )
        await windowsNotificationPresenter.presentHostNotice(request)
    }
}
