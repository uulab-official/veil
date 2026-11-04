import Foundation
import Testing
import VeilHostCore

@testable import VeilHostShell

@Suite("Parallels-style shell navigation")
@MainActor
struct ShellNavigationTests {
    @Test("the assistant asks for Windows first, including when file access was lost")
    func assistantStartsWithGetWindows() {
        #expect(InstallationAssistantStep.resolve(hasInstaller: false, installerNeedsPickerAccess: false, bootReady: false) == .getWindows)
        #expect(InstallationAssistantStep.resolve(hasInstaller: true, installerNeedsPickerAccess: true, bootReady: true) == .getWindows)
    }

    @Test("the assistant prepares the Mac until the profile can boot, then installs")
    func assistantPreparesThenInstalls() {
        #expect(InstallationAssistantStep.resolve(hasInstaller: true, installerNeedsPickerAccess: false, bootReady: false) == .prepare)
        #expect(InstallationAssistantStep.resolve(hasInstaller: true, installerNeedsPickerAccess: false, bootReady: true) == .install)
    }

    @Test("a stopped machine reads as shut down only once Windows is installed")
    func stoppedMachineStatus() {
        #expect(MachineStatusPresentation.resolve(state: .stopped, windowsInstalled: true, appConnectionNeedsRepair: false).title == "Shut down")
        #expect(MachineStatusPresentation.resolve(state: .stopped, windowsInstalled: false, appConnectionNeedsRepair: false).title == "Ready to install")
        #expect(MachineStatusPresentation.resolve(state: nil, windowsInstalled: false, appConnectionNeedsRepair: false).title == "Not set up")
    }

    @Test("a machine running Windows Setup reads as installing, not as a ready machine")
    func setupReadsAsInstalling() {
        let installing = MachineStatusPresentation.resolve(state: .running, windowsInstalled: false, appConnectionNeedsRepair: false)
        #expect(installing.title == "Installing Windows" && installing.tone == .progress)
        #expect(MachineStatusPresentation.resolve(state: .starting, windowsInstalled: false, appConnectionNeedsRepair: false).title == "Starting Windows Setup…")
        #expect(MachineStatusPresentation.resolve(state: .running, windowsInstalled: true, appConnectionNeedsRepair: false).title == "Running")
    }

    @Test("a running machine with a lost app connection is a warning, not a plain running state")
    func runningWithLostConnectionWarns() {
        let status = MachineStatusPresentation.resolve(state: .running, windowsInstalled: true, appConnectionNeedsRepair: true)
        #expect(status.tone == .warning)
        #expect(MachineStatusPresentation.resolve(state: .running, windowsInstalled: true, appConnectionNeedsRepair: false).tone == .active)
    }

    @Test("power controls offer start or resume when idle and suspend plus shut down when live")
    func powerControls() {
        let idle = MachinePowerControls.resolve(state: .stopped, canStart: true, canStop: false, canSuspend: false, canResume: false)
        #expect(idle.showsStart && idle.startTitle == "Start" && !idle.showsSuspend && !idle.showsShutDown)

        let suspended = MachinePowerControls.resolve(state: .suspended, canStart: true, canStop: true, canSuspend: false, canResume: true)
        #expect(suspended.showsStart && suspended.startTitle == "Resume" && suspended.showsShutDown)

        let running = MachinePowerControls.resolve(state: .running, canStart: false, canStop: true, canSuspend: true, canResume: false)
        #expect(!running.showsStart && running.showsSuspend && running.showsShutDown)

        let noPersistence = MachinePowerControls.resolve(state: .running, canStart: false, canStop: true, canSuspend: false, canResume: false)
        #expect(!noPersistence.showsSuspend)
    }

    @Test("opening configuration selects the requested tab and presents the sheet")
    func openConfigurationSelectsTab() {
        let navigation = ShellNavigation()
        navigation.openConfiguration(.hardware)
        #expect(navigation.presentedSheet == .settings)
        #expect(navigation.configurationTab == .hardware)

        navigation.openWindowsDownload()
        #expect(navigation.presentedSheet == .windowsDownload)
    }

    @Test("the desktop flag and the view mode stay in sync")
    func desktopFlagMatchesViewMode() {
        let navigation = ShellNavigation()
        #expect(navigation.viewMode == .apps)
        navigation.showsWindowsDesktop = true
        #expect(navigation.viewMode == .desktop)
        navigation.viewMode = .apps
        #expect(!navigation.showsWindowsDesktop)
    }

    private func machine(installed: Bool, diskPath: String? = "/vm/disk.img", allocated: Int64? = nil) -> VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: .stopped,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            virtualDiskPath: diskPath,
            virtualDiskAllocatedBytes: allocated,
            installEvidence: VMInstallEvidenceSummary(
                kind: installed ? .guestAgent : .setupReady,
                isInstalled: installed,
                title: "test",
                detail: "test"
            ),
            bootReady: true,
            windowsInstalled: installed,
            detail: "test"
        )
    }

    @Test("restarting the installation is offered only for an unfinished install with a disk")
    func restartInstallationAvailability() {
        #expect(RestartInstallationAvailability.isAvailable(snapshot: machine(installed: false), isBusy: false))
        #expect(!RestartInstallationAvailability.isAvailable(snapshot: machine(installed: true), isBusy: false))
        #expect(!RestartInstallationAvailability.isAvailable(snapshot: machine(installed: false, diskPath: nil), isBusy: false))
        #expect(!RestartInstallationAvailability.isAvailable(snapshot: machine(installed: false), isBusy: true))
        #expect(!RestartInstallationAvailability.isAvailable(snapshot: nil, isBusy: false))
    }

    @Test("the assistant points out an earlier attempt only once Setup wrote to the disk")
    func previousAttemptDetection() {
        #expect(!RestartInstallationAvailability.hasPreviousAttempt(snapshot: machine(installed: false, allocated: 0)))
        #expect(RestartInstallationAvailability.hasPreviousAttempt(snapshot: machine(installed: false, allocated: 10 * 1_024 * 1_024 * 1_024)))
        #expect(!RestartInstallationAvailability.hasPreviousAttempt(snapshot: machine(installed: true, allocated: 10 * 1_024 * 1_024 * 1_024)))
    }

    @Test("asking to restart the installation raises the main window's confirmation")
    func restartRequestRaisesConfirmation() {
        let navigation = ShellNavigation()
        navigation.requestRestartInstallation()
        #expect(navigation.showsRestartInstallationConfirmation)
    }
}

@Suite("Disk write activity")
struct DiskWriteActivityTests {
    @Test("a growing disk counts as active for two minutes, a static one never does")
    func growthMarksActivity() {
        let start = Date(timeIntervalSince1970: 1_000)
        var activity = DiskWriteActivity()
        activity.observe(allocatedBytes: 1_000, at: start)
        #expect(!activity.isActive(asOf: start))

        activity.observe(allocatedBytes: 1_000, at: start.addingTimeInterval(5))
        #expect(!activity.isActive(asOf: start.addingTimeInterval(5)))

        activity.observe(allocatedBytes: 5_000, at: start.addingTimeInterval(10))
        #expect(activity.isActive(asOf: start.addingTimeInterval(100)))
        #expect(!activity.isActive(asOf: start.addingTimeInterval(131)))

        activity.observe(allocatedBytes: nil, at: start.addingTimeInterval(140))
        #expect(activity.lastAllocatedBytes == 5_000)
    }
}
