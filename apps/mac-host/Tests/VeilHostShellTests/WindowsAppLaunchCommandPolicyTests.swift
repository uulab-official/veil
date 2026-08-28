import Testing
@testable import VeilHostShell

@Suite("Windows app launch command policy")
struct WindowsAppLaunchCommandPolicyTests {
    @Test("keeps one-click launch available while a stale QEMU display can be recovered")
    func keepsLaunchAvailableDuringRecoverableTransportFailure() {
        #expect(
            WindowsAppLaunchCommandPolicy.isEnabled(
                canRequestLaunch: true,
                canFulfillPendingLaunch: false,
                hasRecoverableRuntimeDisplay: true,
                hasLiveAgentConnection: false
            )
        )
    }

    @Test("disables launch when neither a new nor queued launch can proceed")
    func disablesUnavailableLaunch() {
        #expect(
            !WindowsAppLaunchCommandPolicy.isEnabled(
                canRequestLaunch: false,
                canFulfillPendingLaunch: false,
                hasRecoverableRuntimeDisplay: true,
                hasLiveAgentConnection: false
            )
        )
    }

    @Test("keeps the selected app as the launcher hero while Windows is installed")
    func prefersSelectedAppAsInstalledLauncherHero() {
        #expect(
            WindowsAppLaunchCommandPolicy.prefersLaunchAsHero(
                windowsInstalled: true,
                hasSelectedApp: true
            )
        )
        #expect(
            !WindowsAppLaunchCommandPolicy.prefersLaunchAsHero(
                windowsInstalled: false,
                hasSelectedApp: true
            )
        )
    }
}
