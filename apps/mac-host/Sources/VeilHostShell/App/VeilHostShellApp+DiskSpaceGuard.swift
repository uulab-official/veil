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
                let pausedByGuard = vmModel.lowDiskSpacePauseAvailableBytes != nil
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
            await notifyLowDiskSpacePause(availableBytes: available)
        case .resumed, .released:
            vmModel.lowDiskSpacePauseAvailableBytes = nil
            await windowsNotificationPresenter.removeDelivered(identifier: Self.lowDiskSpaceNotificationIdentifier)
        }
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
