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
                      let service = vmModel.runtimeService as? LocalVMRuntimeService else {
                    continue
                }
                if await guardDeletedSystemDisk(service) {
                    continue
                }
                guard pausedByGuard || vmModel.snapshot?.state == .running else {
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

    /// Puts the Windows disk file back when it was deleted while Windows runs (`HostDiskFileGuard`).
    /// Returns true while the file is missing, so nothing else acts on Windows until it is back.
    private func guardDeletedSystemDisk(_ service: LocalVMRuntimeService) async -> Bool {
        guard await service.missingSystemDiskPath() != nil else {
            if vmModel.systemDiskFileIssue != nil {
                vmModel.systemDiskFileIssue = nil
                await windowsNotificationPresenter.removeDelivered(identifier: Self.deletedDiskNotificationIdentifier)
            }
            return false
        }
        // A copy that could not start is tried again now and then, not on every pass.
        if vmModel.systemDiskFileIssue != nil,
           let lastAttempt = lastSystemDiskRestoreAttempt,
           Date().timeIntervalSince(lastAttempt) < Self.systemDiskRestoreRetrySeconds {
            return true
        }
        lastSystemDiskRestoreAttempt = Date()
        vmModel.systemDiskFileIssue = .restoring
        await notifyDeletedDisk(body: WindowsShellCopy.deletedDiskRestoringNotificationBody)

        switch await service.restoreMissingSystemDisk() {
        case .present:
            vmModel.systemDiskFileIssue = nil
            await windowsNotificationPresenter.removeDelivered(identifier: Self.deletedDiskNotificationIdentifier)
            return false
        case .restored:
            vmModel.systemDiskFileIssue = nil
            await notifyDeletedDisk(body: WindowsShellCopy.deletedDiskRestoredNotificationBody)
            return false
        case .notEnoughSpace(let needed, let available):
            vmModel.systemDiskFileIssue = .notEnoughSpace(neededBytes: needed, availableBytes: available)
            await notifyDeletedDisk(body: WindowsShellCopy.deletedDiskNeedsSpaceNotificationBody(neededBytes: needed))
            return true
        case .failed(let reason):
            vmModel.systemDiskFileIssue = .failed(reason: reason)
            await notifyDeletedDisk(body: WindowsShellCopy.deletedDiskFailedNotificationBody)
            return true
        }
    }

    static let systemDiskRestoreRetrySeconds: TimeInterval = 60
    static let deletedDiskNotificationIdentifier = "org.uulab.veil.deleted-system-disk"

    /// Windows runs on a disk file that was deleted on the Mac and is not back yet. Shutting it down,
    /// suspending it or turning it off would erase it.
    var isSystemDiskFileDeleted: Bool {
        vmModel.systemDiskFileIssue != nil
    }

    private func notifyDeletedDisk(body: String) async {
        let request = WindowsNotificationPresentationRequest(
            identifier: Self.deletedDiskNotificationIdentifier,
            title: String(localized: "Windows Disk Was Deleted"),
            body: body,
            threadIdentifier: "org.uulab.veil.runtime",
            userInfo: [:]
        )
        await windowsNotificationPresenter.presentHostNotice(request)
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
