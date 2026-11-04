import Testing
import VeilHostCore

@testable import VeilHostShell

@Suite("App window engine status")
struct AppWindowEngineStatusTests {
    private func qemu(_ status: VMRuntimeProviderStatus) -> VMRuntimeProviderSummary {
        VMRuntimeProviderSummary(
            kind: .qemuHypervisor,
            displayName: "QEMU/HVF",
            mode: "Local compatibility provider",
            acceleration: "HVF",
            isServerBacked: false,
            status: status,
            detail: ""
        )
    }

    @Test("booting with QEMU needs no notice")
    func qemuBootIsReady() {
        #expect(AppWindowEngineStatus.resolve(bootProvider: .qemu, providers: [qemu(.active)], environment: [:]) == .ready)
    }

    @Test("Apple Virtualization without QEMU asks for the install")
    func missingQEMUNeedsInstall() {
        #expect(AppWindowEngineStatus.resolve(bootProvider: .appleVirtualization, providers: [qemu(.planned)], environment: [:]) == .needsInstall)
    }

    @Test("QEMU installed after launch asks for a relaunch")
    func lateQEMUNeedsRelaunch() {
        #expect(AppWindowEngineStatus.resolve(bootProvider: .appleVirtualization, providers: [qemu(.active)], environment: [:]) == .needsRelaunch)
    }

    @Test("an explicit provider override is respected")
    func explicitOverrideIsReady() {
        let environment = [AppRuntimeProviderSelection.environmentKey: "apple"]
        #expect(AppWindowEngineStatus.resolve(bootProvider: .appleVirtualization, providers: [qemu(.planned)], environment: environment) == .ready)
    }

    @Test("an unknown boot provider shows nothing")
    func unknownProviderIsReady() {
        #expect(AppWindowEngineStatus.resolve(bootProvider: nil, providers: [], environment: [:]) == .ready)
    }

    @Test("only a provider that runs Windows may start Windows Setup")
    func onlyReadyEngineRunsWindows() {
        #expect(AppWindowEngineStatus.ready.canRunWindows)
        #expect(!AppWindowEngineStatus.needsInstall.canRunWindows)
        #expect(!AppWindowEngineStatus.needsRelaunch.canRunWindows)
    }
}
