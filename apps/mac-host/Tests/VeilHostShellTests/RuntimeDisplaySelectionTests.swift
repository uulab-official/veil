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
    @Test("installed Windows with a live app connection defaults to the app launcher")
    func installedWindowsDefaultsToLauncher() {
        #expect(
            RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
                windowsInstalled: true,
                runtimeState: .running,
                hasDesktopDisplay: true,
                hasLiveAppConnection: true
            ) == false
        )
    }

    @Test("installed Windows without the app connection shows its desktop, like a Parallels VM window")
    func installedWindowsWithoutConnectionShowsDesktop() {
        #expect(
            RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
                windowsInstalled: true,
                runtimeState: .running,
                hasDesktopDisplay: true,
                hasLiveAppConnection: false
            )
        )
        #expect(
            !RuntimeWorkspacePresentationPolicy.defaultShowsFullDesktop(
                windowsInstalled: true,
                runtimeState: .stopped,
                hasDesktopDisplay: false
            )
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

    @Test("a desktop Veil chose gives way to apps only while the app connection is up")
    func returnsToAppsWhenTheConnectionIsBack() {
        // Windows that kept their frames through a dropped connection: no first frame will arrive, so the
        // connection coming back is what returns to apps.
        #expect(
            RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: true,
                hasFirstAppFrame: true,
                hasLiveAppConnection: true
            )
        )
        #expect(
            !RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: true,
                hasFirstAppFrame: true,
                hasLiveAppConnection: false
            )
        )
        #expect(
            !RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: true,
                hasFirstAppFrame: false,
                hasLiveAppConnection: true
            )
        )
    }

    @Test("with no Windows app open, the app connection alone leaves the desktop Veil chose")
    func noAppWindowsReturnToApps() {
        #expect(
            RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: true,
                hasFirstAppFrame: false,
                hasAppWindows: false,
                hasLiveAppConnection: true
            )
        )
        #expect(
            !RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: true,
                hasFirstAppFrame: false,
                hasAppWindows: false,
                hasLiveAppConnection: false
            )
        )
        #expect(
            !RuntimeWorkspacePresentationPolicy.shouldReturnToApps(
                windowsInstalled: false,
                hasFirstAppFrame: false,
                hasAppWindows: false,
                hasLiveAppConnection: true
            )
        )
    }

    @Test("a dropped app connection leaves open app windows on screen instead of showing the desktop")
    func droppedConnectionKeepsAppWindows() {
        #expect(
            RuntimeWorkspacePresentationPolicy.keepsAppWindows(
                showsApps: true,
                windowsInstalled: true,
                hasAppWindows: true
            )
        )
        // Nothing is open, so the desktop is the only thing there is to show.
        #expect(
            !RuntimeWorkspacePresentationPolicy.keepsAppWindows(
                showsApps: true,
                windowsInstalled: true,
                hasAppWindows: false
            )
        )
        // The desktop is already showing.
        #expect(
            !RuntimeWorkspacePresentationPolicy.keepsAppWindows(
                showsApps: false,
                windowsInstalled: true,
                hasAppWindows: true
            )
        )
        // Windows Setup has no apps to keep.
        #expect(
            !RuntimeWorkspacePresentationPolicy.keepsAppWindows(
                showsApps: true,
                windowsInstalled: false,
                hasAppWindows: true
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
