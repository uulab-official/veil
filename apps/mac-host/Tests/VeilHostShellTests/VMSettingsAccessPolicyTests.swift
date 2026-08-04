import Testing
import VeilHostCore
@testable import VeilHostShell

struct VMSettingsAccessPolicyTests {
    @Test("setup diagnostics routes each available evidence source")
    func setupDiagnosticsRoutes() {
        #expect(WindowsSetupDiagnosticsRoute.resolve(
            hasExportedDiagnostics: true,
            hasAgentDiagnostic: true
        ) == .exportedFile)
        #expect(WindowsSetupDiagnosticsRoute.resolve(
            hasExportedDiagnostics: false,
            hasAgentDiagnostic: true
        ) == .agentConnectionDetails)
        #expect(WindowsSetupDiagnosticsRoute.resolve(
            hasExportedDiagnostics: false,
            hasAgentDiagnostic: false
        ) == .unavailable)
    }

    @Test("setup assistant exposes only the next primary action")
    func setupAssistantPrimaryAction() {
        #expect(SetupAssistantPrimaryAction.resolve(
            hasProfile: false,
            hasInstaller: false,
            hasDisk: false,
            isBootReady: false
        ) == .prepareWindows)
        #expect(SetupAssistantPrimaryAction.resolve(
            hasProfile: true,
            hasInstaller: false,
            hasDisk: true,
            isBootReady: false
        ) == .chooseInstaller)
        #expect(SetupAssistantPrimaryAction.resolve(
            hasProfile: true,
            hasInstaller: true,
            hasDisk: false,
            isBootReady: false
        ) == .createDisk)
        #expect(SetupAssistantPrimaryAction.resolve(
            hasProfile: true,
            hasInstaller: true,
            hasDisk: true,
            isBootReady: false
        ) == .reviewReadiness)
        #expect(SetupAssistantPrimaryAction.resolve(
            hasProfile: true,
            hasInstaller: true,
            hasDisk: true,
            isBootReady: true
        ) == .ready)
        #expect(SetupAssistantPrimaryAction.prepareWindows.title == "Prepare Windows")
        #expect(SetupAssistantPrimaryAction.chooseInstaller.title == "Choose Windows ISO")
        #expect(SetupAssistantPrimaryAction.createDisk.title == "Create Windows Disk")
    }

    @Test("groups Windows settings into focused Mac-style categories")
    func settingsSections() {
        #expect(VMSettingsSection.allCases == [.setup, .runtime, .integration])
        #expect(VMSettingsSection.setup.title == "Setup")
        #expect(VMSettingsSection.runtime.symbolName == "desktopcomputer")
        #expect(VMSettingsSection.integration.subtitle.contains("Mac app windows"))
    }

    @Test("allows resource changes while Windows is stopped")
    func allowsStoppedResourceChanges() {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: .stopped, isLoading: false)

        #expect(policy.canChangeResources)
        #expect(policy.guidance == nil)
    }

    @Test("locks resource changes while Windows is running or starting", arguments: [VMRuntimeState.running, .starting])
    func locksActiveRuntime(state: VMRuntimeState) {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: state, isLoading: false)

        #expect(!policy.canChangeResources)
        #expect(policy.guidance?.contains("Stop Windows") == true)
    }

    @Test("protects suspended session resources")
    func locksSuspendedRuntime() {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: .suspended, isLoading: false)

        #expect(!policy.canChangeResources)
        #expect(policy.guidance?.contains("suspended session") == true)
    }

    @Test("locks settings during an in-flight operation")
    func locksLoadingState() {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: .stopped, isLoading: true)

        #expect(!policy.canChangeResources)
        #expect(policy.guidance?.contains("current Windows operation") == true)
    }
}
