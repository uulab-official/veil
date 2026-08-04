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

struct InstalledWorkspacePresentationPolicyTests {
    @Test("installed workspace defaults to the app home")
    func defaultsToAppHome() {
        #expect(!InstalledWorkspacePresentationPolicy.initiallyShowsDesktop)
    }

    @Test("desktop closes when its display is unavailable")
    func closesUnavailableDesktop() {
        #expect(
            !InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
                requested: true,
                runtimeState: .stopped,
                hasDesktopDisplay: true
            )
        )
        #expect(
            !InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
                requested: true,
                runtimeState: .running,
                hasDesktopDisplay: false
            )
        )
    }

    @Test("desktop remains visible only after a valid request")
    func keepsValidDesktopRequest() {
        #expect(
            InstalledWorkspacePresentationPolicy.shouldKeepDesktopVisible(
                requested: true,
                runtimeState: .running,
                hasDesktopDisplay: true
            )
        )
    }
}
