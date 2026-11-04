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
}
