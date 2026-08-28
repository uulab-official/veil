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

struct WindowsDisplayAvailabilityPolicyTests {
    @Test("offers a QEMU desktop window when a captured display is live")
    func offersCapturedQEMUDesktop() {
        #expect(
            WindowsDisplayAvailabilityPolicy.canShowDesktop(
                runtimeState: .running,
                supportsNativeDisplayWindow: false,
                hasCapturedSurface: true
            )
        )
        #expect(
            WindowsDisplayAvailabilityPolicy.canShowDesktop(
                runtimeState: .stopped,
                supportsNativeDisplayWindow: false,
                hasCapturedSurface: true
            ) == false
        )
    }
}

struct WindowsDisplayAspectRatioPolicyTests {
    @Test("preserves the live guest framebuffer aspect ratio")
    func preservesGuestFramebufferAspectRatio() {
        #expect(
            WindowsDisplayAspectRatioPolicy.resolve(
                pixelWidth: 600,
                pixelHeight: 393
            ) == 600.0 / 393.0
        )
        #expect(
            WindowsDisplayAspectRatioPolicy.resolve(
                pixelWidth: 0,
                pixelHeight: 0
            ) == 16.0 / 9.0
        )
    }
}

struct RuntimeWorkspacePresentationPolicyTests {
    @Test("installed Windows defaults to the app launcher even when a desktop display exists")
    func installedWindowsDefaultsToLauncher() {
        #expect(
            RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
                windowsInstalled: true,
                runtimeState: .running,
                hasDesktopDisplay: true
            ) == false
        )
    }

    @Test("Windows Setup keeps the recovery display visible")
    func setupKeepsDesktopVisible() {
        #expect(
            RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
                windowsInstalled: false,
                runtimeState: .running,
                hasDesktopDisplay: true
            )
        )
    }

    @Test("the first app frame returns the workspace to apps")
    func firstFrameReturnsToApps() {
        #expect(
            RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: true,
                hasFirstAppFrame: true
            )
        )
    }

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
