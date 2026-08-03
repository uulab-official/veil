import Testing
import VeilHostCore
@testable import VeilHostShell

struct RuntimeDisplaySelectionTests {
    @Test("uses the native Apple VM view while Apple Virtualization is running")
    func selectsAppleVirtualMachine() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .appleVirtualization,
                state: .running,
                hasAppleVirtualMachine: true,
                hasCapturedSurface: true
            ) == .appleVirtualMachine
        )
    }

    @Test("keeps QEMU on the captured display surface")
    func selectsQEMUCapturedSurface() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .qemuHypervisor,
                state: .running,
                hasAppleVirtualMachine: true,
                hasCapturedSurface: true
            ) == .capturedSurface
        )
    }

    @Test("does not retain the native VM view after the runtime stops")
    func hidesStoppedAppleVirtualMachine() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .appleVirtualization,
                state: .stopped,
                hasAppleVirtualMachine: true,
                hasCapturedSurface: false
            ) == .placeholder
        )
    }

    @Test("does not present a stale captured surface after the runtime stops")
    func hidesStoppedCapturedSurface() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .qemuHypervisor,
                state: .stopped,
                hasAppleVirtualMachine: false,
                hasCapturedSurface: true
            ) == .placeholder
        )
    }
}

struct RuntimeWorkspacePresentationPolicyTests {
    @Test("shows the app dock in the installed app launcher")
    func showsInstalledAppDock() {
        #expect(
            RuntimeWorkspacePresentationPolicy.showsAppDock(
                hasApps: true,
                hasInstalledWindows: true,
                showsFullDesktop: false
            )
        )
    }

    @Test("hides the app dock over the live Windows desktop")
    func hidesAppDockOverDesktop() {
        #expect(
            !RuntimeWorkspacePresentationPolicy.showsAppDock(
                hasApps: true,
                hasInstalledWindows: true,
                showsFullDesktop: true
            )
        )
    }

    @Test("hides the app dock until both setup and app discovery finish")
    func hidesUnavailableAppDock() {
        #expect(
            !RuntimeWorkspacePresentationPolicy.showsAppDock(
                hasApps: true,
                hasInstalledWindows: false,
                showsFullDesktop: false
            )
        )
        #expect(
            !RuntimeWorkspacePresentationPolicy.showsAppDock(
                hasApps: false,
                hasInstalledWindows: true,
                showsFullDesktop: false
            )
        )
    }
}
