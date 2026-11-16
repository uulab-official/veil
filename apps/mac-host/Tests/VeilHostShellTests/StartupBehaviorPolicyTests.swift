import Foundation
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

    private func quitAction(
        _ snapshot: VMRuntimeSnapshot?,
        canSuspend: Bool = true,
        isBusy: Bool = false,
        keepsRunning: Bool = false,
        isSystemQuit: Bool = false
    ) -> StartupBehaviorPolicy.QuitAction {
        StartupBehaviorPolicy.quitAction(
            snapshot: snapshot,
            canSuspend: canSuspend,
            isBusy: isBusy,
            keepsWindowsRunningWithoutAsking: keepsRunning,
            isSystemQuit: isSystemQuit
        )
    }

    @Test("quitting suspends a running Windows with the setting on")
    func suspendsOnQuit() {
        #expect(quitAction(snapshot(state: .running)) == .suspend)
        // The setting wins over a logout: suspending is what the user asked for.
        #expect(quitAction(snapshot(state: .running), isSystemQuit: true) == .suspend)
    }

    @Test("quitting asks about a running Windows instead of leaving it running unannounced")
    func asksOnQuit() {
        #expect(quitAction(snapshot(state: .running, suspendOnQuit: false)) == .ask)
        #expect(quitAction(snapshot(state: .running, suspendOnQuit: nil)) == .ask)
    }

    @Test("quitting just quits when there is nothing to ask about")
    func quitsWithoutAsking() {
        #expect(quitAction(nil) == .quit)
        #expect(quitAction(snapshot(state: .stopped, suspendOnQuit: false)) == .quit)
        #expect(quitAction(snapshot(state: .suspended, suspendOnQuit: false)) == .quit)
        #expect(quitAction(snapshot(state: .running, suspendOnQuit: false), canSuspend: false) == .quit)
        #expect(quitAction(snapshot(state: .running), isBusy: true) == .quit)
        #expect(quitAction(snapshot(state: .running, suspendOnQuit: false), keepsRunning: true) == .quit)
        // A logout must not wait on a question.
        #expect(quitAction(snapshot(state: .running, suspendOnQuit: false), isSystemQuit: true) == .quit)
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

@Suite("Automatic tools setup policy")
struct AutomaticToolsSetupPolicyTests {
    private let bootedAt = Date(timeIntervalSince1970: 1_782_752_400)

    private func snapshot(
        kind: VMInstallEvidenceKind = .windowsBootManager,
        driverMediaPath: String? = "/Users/test/virtio-win.iso",
        state: VMRuntimeState = .running
    ) -> VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: state,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            driverMediaPath: driverMediaPath,
            latestConsoleLaunch: VMConsoleLaunchEvidence(
                provider: "QEMU/HVF",
                pid: 4242,
                processLogPath: "/tmp/qemu.log",
                monitorSocketPath: "/tmp/qemu.sock",
                qmpSocketPath: "/tmp/qemu.qmp.sock",
                vncHost: "127.0.0.1",
                vncPort: 5900,
                consoleScreenshotPath: nil,
                startedAt: bootedAt
            ),
            installEvidence: VMInstallEvidenceSummary(kind: kind, isInstalled: true, title: "", detail: ""),
            detail: ""
        )
    }

    @Test("a Windows on disk with driver media and no agent gets the tools once it had time to reach the desktop")
    func installsToolsAfterGrace() {
        #expect(AutomaticToolsSetupPolicy.installsTools(snapshot: snapshot(), hasLiveAgent: false, now: bootedAt.addingTimeInterval(200)))
        #expect(!AutomaticToolsSetupPolicy.installsTools(snapshot: snapshot(), hasLiveAgent: false, now: bootedAt.addingTimeInterval(60)))
    }

    @Test("Veil never types into Windows when the agent answers, the drivers are missing, or the agent was proven")
    func leavesWindowsAlone() {
        let later = bootedAt.addingTimeInterval(600)
        #expect(!AutomaticToolsSetupPolicy.installsTools(snapshot: snapshot(), hasLiveAgent: true, now: later))
        #expect(!AutomaticToolsSetupPolicy.installsTools(snapshot: snapshot(driverMediaPath: nil), hasLiveAgent: false, now: later))
        #expect(!AutomaticToolsSetupPolicy.installsTools(snapshot: snapshot(kind: .guestAgent), hasLiveAgent: false, now: later))
        #expect(!AutomaticToolsSetupPolicy.installsTools(snapshot: snapshot(state: .starting), hasLiveAgent: false, now: later))
    }
}
