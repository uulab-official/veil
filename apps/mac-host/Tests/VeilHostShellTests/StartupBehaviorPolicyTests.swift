import Testing
import VeilHostCore

@testable import VeilHostShell

@Suite("Startup behavior policy")
struct StartupBehaviorPolicyTests {
    private func snapshot(
        state: VMRuntimeState,
        installed: Bool = true,
        autoStart: Bool? = true,
        suspendOnQuit: Bool? = true
    ) -> VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: state,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            windowsInstalled: installed,
            autoStart: autoStart,
            suspendOnQuit: suspendOnQuit,
            detail: ""
        )
    }

    @Test("an installed, stopped or suspended Windows starts when Veil opens")
    func autoStartsInstalledWindows() {
        #expect(StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: snapshot(state: .stopped), launchArgumentRequested: false, canRunWindows: true))
        #expect(StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: snapshot(state: .suspended), launchArgumentRequested: false, canRunWindows: true))
    }

    @Test("Veil never boots an installer, a running VM, or an engine that cannot run Windows on its own")
    func skipsAutoStart() {
        #expect(!StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: snapshot(state: .stopped, installed: false), launchArgumentRequested: false, canRunWindows: true))
        #expect(!StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: snapshot(state: .running), launchArgumentRequested: false, canRunWindows: true))
        #expect(!StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: snapshot(state: .stopped, autoStart: false), launchArgumentRequested: false, canRunWindows: true))
        #expect(!StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: snapshot(state: .stopped), launchArgumentRequested: false, canRunWindows: false))
        #expect(StartupBehaviorPolicy.startsWindowsOnLaunch(snapshot: nil, launchArgumentRequested: true, canRunWindows: false))
    }

    @Test("quitting suspends only a running Windows with the setting on")
    func suspendsOnQuit() {
        #expect(StartupBehaviorPolicy.suspendsWindowsOnQuit(snapshot: snapshot(state: .running), canSuspend: true, isBusy: false))
        #expect(!StartupBehaviorPolicy.suspendsWindowsOnQuit(snapshot: snapshot(state: .running, suspendOnQuit: false), canSuspend: true, isBusy: false))
        #expect(!StartupBehaviorPolicy.suspendsWindowsOnQuit(snapshot: snapshot(state: .stopped), canSuspend: true, isBusy: false))
        #expect(!StartupBehaviorPolicy.suspendsWindowsOnQuit(snapshot: snapshot(state: .running), canSuspend: false, isBusy: false))
        #expect(!StartupBehaviorPolicy.suspendsWindowsOnQuit(snapshot: snapshot(state: .running), canSuspend: true, isBusy: true))
    }
}

@Suite("Driver media attach policy")
struct DriverMediaAttachPolicyTests {
    private func snapshot(state: VMRuntimeState, driverMediaPath: String? = nil) -> VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: state,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            driverMediaPath: driverMediaPath,
            detail: ""
        )
    }

    @Test("a stopped Windows without drivers gets the virtio-win ISO on its next cold start")
    func attachesToStoppedWindows() {
        #expect(DriverMediaAttachPolicy.attachesOnColdStart(snapshot: snapshot(state: .stopped)))
        #expect(DriverMediaAttachPolicy.attachesOnColdStart(snapshot: snapshot(state: .failed)))
    }

    @Test("a chosen driver ISO, a running Windows, and a saved session stay untouched")
    func leavesOtherStatesAlone() {
        #expect(!DriverMediaAttachPolicy.attachesOnColdStart(snapshot: snapshot(state: .stopped, driverMediaPath: "/Users/test/virtio.iso")))
        #expect(!DriverMediaAttachPolicy.attachesOnColdStart(snapshot: snapshot(state: .running)))
        #expect(!DriverMediaAttachPolicy.attachesOnColdStart(snapshot: snapshot(state: .suspended)))
    }
}
