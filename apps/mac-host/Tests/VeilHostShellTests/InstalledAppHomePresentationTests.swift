import Testing
import VeilHostCore
@testable import VeilHostShell

struct InstalledAppHomePresentationTests {
    @Test("installed QEMU Windows without agent evidence offers one optimization action")
    func installedQEMUWindowsOffersOneOptimizationAction() throws {
        let presentation = try #require(
            InstalledWindowsOptimizationPresentation.resolve(
                windowsInstalled: true,
                provider: .qemuHypervisor,
                installEvidenceKind: .profileFlag,
                status: WindowsOptimizationStatus(phase: .idle)
            )
        )

        #expect(presentation.title == "Finish Windows Optimization")
        #expect(presentation.detail.contains("Windows will restart once"))
        #expect(presentation.primaryButtonTitle == "Optimize Windows")
        #expect(presentation.showsCancel == false)
    }

    @Test("healthy guest agent evidence hides redundant optimization")
    func healthyGuestAgentEvidenceHidesRedundantOptimization() {
        let presentation = InstalledWindowsOptimizationPresentation.resolve(
            windowsInstalled: true,
            provider: .qemuHypervisor,
            installEvidenceKind: .guestAgent,
            status: WindowsOptimizationStatus(phase: .idle)
        )

        #expect(presentation == nil)
    }

    @Test("connected agent keeps a display warning when optimization remains partial")
    func connectedAgentKeepsPartialDisplayWarning() throws {
        let presentation = try #require(
            InstalledWindowsOptimizationPresentation.resolve(
                windowsInstalled: true,
                provider: .qemuHypervisor,
                installEvidenceKind: .guestAgent,
                status: WindowsOptimizationStatus(phase: .complete(displayOptimized: false))
            )
        )

        #expect(presentation.title == "Windows apps are connected")
        #expect(presentation.detail.contains("Display optimization still needs attention"))
        #expect(presentation.showsPrimaryAction == false)
    }

    @Test("optimization remains unavailable without QEMU control")
    func optimizationRemainsUnavailableWithoutQEMUControl() {
        let presentation = InstalledWindowsOptimizationPresentation.resolve(
            windowsInstalled: true,
            provider: .appleVirtualization,
            installEvidenceKind: .profileFlag,
            status: WindowsOptimizationStatus(phase: .idle)
        )

        #expect(presentation == nil)
    }

    @Test("optimization consent describes one restart and both integration components")
    func optimizationConsentDescribesOneRestartAndBothComponents() {
        #expect(WindowsOptimizationConsentPolicy.title == "Optimize Windows Automatically?")
        #expect(WindowsOptimizationConsentPolicy.message.contains("UTM Guest Tools"))
        #expect(WindowsOptimizationConsentPolicy.message.contains("Veil guest agent"))
        #expect(WindowsOptimizationConsentPolicy.message.contains("restart once"))
        #expect(WindowsOptimizationConsentPolicy.acceptButtonTitle == "I Agree and Optimize")
    }

    @Test("ready Windows shows an interactive app home")
    func readyHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .running,
            dashboardPhase: .connected,
            hasLiveAgentConnection: true,
            appCount: 3,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .ready)
        #expect(result.title == "Windows Apps")
        #expect(result.detail == "Choose an app to open it in its own Mac window.")
        #expect(result.isGridEnabled)
        #expect(result.recoveryRoute == nil)
    }

    @Test("stopped Windows keeps app tiles available")
    func stoppedHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .stopped,
            dashboardPhase: .idle,
            hasLiveAgentConnection: false,
            appCount: 3,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .stopped)
        #expect(result.isGridEnabled)
        #expect(result.detail == "Windows starts automatically when you open an app.")
    }

    @Test("queued app shows one opening state")
    func queuedHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .starting,
            dashboardPhase: .launching,
            hasLiveAgentConnection: false,
            appCount: 3,
            pendingAppId: "winapp_notepad",
            errorMessage: nil
        )
        let tile = InstalledAppTilePresentation.resolve(
            appId: "winapp_notepad",
            pendingAppId: "winapp_notepad",
            openWindowCount: 0,
            dashboardPhase: .launching
        )

        #expect(result.phase == .starting)
        #expect(!result.isGridEnabled)
        #expect(tile.statusText == "Opening…")
        #expect(tile.showsProgress)
        #expect(tile.accessibilityValue == "Opening")
    }

    @Test("missing catalog offers refresh without invented apps")
    func missingCatalog() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .running,
            dashboardPhase: .connected,
            hasLiveAgentConnection: true,
            appCount: 0,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .catalogUnavailable)
        #expect(result.recoveryRoute == .refresh)
        #expect(result.recoveryTitle == "Check Again")
    }

    @Test("technical failures use safe product copy")
    func safeFailureCopy() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .failed,
            dashboardPhase: .failed,
            hasLiveAgentConnection: false,
            appCount: 3,
            pendingAppId: nil,
            errorMessage: "QEMU failed at /Users/test/vm.img"
        )

        #expect(result.phase == .failure)
        #expect(result.recoveryRoute == .effectiveAction)
        #expect(!result.detail.contains("QEMU"))
        #expect(!result.detail.contains("/Users"))
    }

    @Test("reconnecting with a pending app keeps the selected app context")
    func reconnectingHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .running,
            dashboardPhase: .reconnecting,
            hasLiveAgentConnection: true,
            appCount: 2,
            pendingAppId: "winapp_calculator",
            errorMessage: nil
        )

        #expect(result.phase == .reconnecting)
        #expect(result.detail == "Reconnecting so your selected app can open…")
        #expect(result.recoveryTitle == "Reconnect")
        #expect(result.recoveryRoute == .effectiveAction)
    }

    @Test("loading dashboard reports app list progress")
    func loadingHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .running,
            dashboardPhase: .loading,
            hasLiveAgentConnection: true,
            appCount: 2,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .loading)
        #expect(result.detail == "Checking Windows apps…")
        #expect(!result.isGridEnabled)
    }

    @Test("suspended Windows keeps app tiles available")
    func suspendedHome() {
        let result = InstalledAppHomePresentation.resolve(
            runtimeState: .suspended,
            dashboardPhase: .idle,
            hasLiveAgentConnection: false,
            appCount: 1,
            pendingAppId: nil,
            errorMessage: nil
        )

        #expect(result.phase == .stopped)
        #expect(result.isGridEnabled)
    }

    @Test("unqueued tile reports its open window count")
    func tileWithMultipleWindows() {
        let tile = InstalledAppTilePresentation.resolve(
            appId: "winapp_notepad",
            pendingAppId: nil,
            openWindowCount: 2,
            dashboardPhase: .connected
        )

        #expect(tile.statusText == "2 windows")
        #expect(!tile.showsProgress)
        #expect(tile.accessibilityValue == "2 windows")
    }

    @Test("queued tile remains opening when a window already exists")
    func queuedTileWithOpenWindow() {
        let tile = InstalledAppTilePresentation.resolve(
            appId: "winapp_notepad",
            pendingAppId: "winapp_notepad",
            openWindowCount: 1,
            dashboardPhase: .launching
        )

        #expect(tile.statusText == "Opening…")
        #expect(tile.showsProgress)
        #expect(tile.accessibilityValue == "Opening")
    }
}
