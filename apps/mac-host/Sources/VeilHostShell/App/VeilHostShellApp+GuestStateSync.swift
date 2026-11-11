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

    @MainActor
    func flushGuestStateSync() async {
        await model.flushGuestStateSync(
            guestStateSync,
            macTheme: MacHostStateObserver.currentTheme(),
            matchMacAppearance: matchMacAppearanceInWindows
        )
        // Also called on every agent poll, so a reconnected agent gets the IME mode back.
        await syncGuestImeMode()
    }
}
