import SwiftUI
import VeilHostCore

/// Makes Windows follow the Mac: a wake or a resumed session marks the guest clock as suspect, and an
/// appearance change is picked up by the next flush because the confirmed theme no longer matches.
extension VeilHostShellApp {
    func startMacHostStateObservation() {
        macHostStateObserver.start(
            onWake: {
                guestStateSync.requestTimeSync(.macWake)
                Task { @MainActor in await flushGuestStateSync() }
            },
            onAppearanceChange: {
                Task { @MainActor in await flushGuestStateSync() }
            }
        )
    }

    /// Covers every resume path the app can see (launcher, dock menu, idle resume): the restored guest
    /// still has the clock it had when it was suspended.
    func noteGuestRuntimeStateChange(from oldState: VMRuntimeState?, to newState: VMRuntimeState?) {
        guard oldState == .suspended, newState == .running || newState == .starting else {
            return
        }
        guestStateSync.requestTimeSync(.vmResume)
        Task { @MainActor in await flushGuestStateSync() }
    }

    func matchMacAppearanceSettingChanged(isOn: Bool) {
        guard isOn else {
            return
        }
        guestStateSync.invalidateAppearance()
        Task { @MainActor in await flushGuestStateSync() }
    }

    /// Asks Windows to register the task that corrects its clock, then checks the clock again a few times:
    /// the approval prompt waits for the user, and network time takes a moment to answer.
    func repairWindowsClock() {
        Task { @MainActor in
            guard let status = await model.repairGuestClock() else {
                displayMessage = "Windows could not be asked to set its clock."
                return
            }
            guard status.outcome == "approval-requested" || status.outcome == "already-running" else {
                displayMessage = status.message.map { String(localized: "Windows could not set its clock: \($0)") }
                return
            }
            displayMessage = "Approve the request in Windows to set its clock."
            for seconds in [20, 60, 180] {
                try? await Task.sleep(for: .seconds(seconds))
                guestStateSync.requestTimeSync(.manual)
                await flushGuestStateSync()
                if !model.guestClockNeedsRepair {
                    return
                }
            }
        }
    }

    @MainActor
    func flushGuestStateSync() async {
        await model.flushGuestStateSync(
            guestStateSync,
            macTheme: MacHostStateObserver.currentTheme(),
            matchMacAppearance: matchMacAppearanceInWindows,
            reduceVisualEffects: reduceWindowsVisualEffects
        )
        // Also called on every agent poll, so a reconnected agent gets the IME mode back.
        await syncGuestImeMode()
        await HostFolderSharing.shared.sync(model: model)
    }
}
