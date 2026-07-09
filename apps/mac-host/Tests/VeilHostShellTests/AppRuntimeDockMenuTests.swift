import AppKit
import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct AppRuntimeDockMenuTests {
    @Test("shell copy keeps first-run and recovery messages app-first")
    func shellCopyKeepsFirstRunAndRecoveryMessagesAppFirst() {
        #expect(
            WindowsShellCopy.headerSubtitle(
                hasLiveAppConnection: false,
                runtimeState: nil,
                windowsInstalled: false
            ) == "Set up Windows apps on this Mac"
        )
        #expect(
            WindowsShellCopy.headerSubtitle(
                hasLiveAppConnection: false,
                runtimeState: .stopped,
                windowsInstalled: true
            ) == "Ready to open Windows apps"
        )
        #expect(
            WindowsShellCopy.headerSubtitle(
                hasLiveAppConnection: true,
                runtimeState: .running,
                windowsInstalled: true
            ) == "Windows apps open on your Mac"
        )

        let visibleMessages = [
            WindowsShellCopy.headerSubtitle(
                hasLiveAppConnection: false,
                runtimeState: nil,
                windowsInstalled: false
            ),
            WindowsShellCopy.headerSubtitle(
                hasLiveAppConnection: false,
                runtimeState: .stopped,
                windowsInstalled: true
            ),
            WindowsShellCopy.quietStopWaitingMessage,
            WindowsShellCopy.displayRecoveryStillStaleMessage(statusText: "stale")
        ]

        #expect(visibleMessages.allSatisfy { !$0.contains("runtime") })
        #expect(visibleMessages.allSatisfy { !$0.contains("VM") })
        #expect(visibleMessages.allSatisfy { !$0.contains("QEMU") })
        #expect(visibleMessages.allSatisfy { !$0.contains("agent") })
    }

    @Test("installed launcher metadata focuses on apps not setup media")
    func installedLauncherMetadataFocusesOnAppsNotSetupMedia() {
        let metadata = WindowsShellCopy.installedLauncherMetadata(
            windowsIsRunning: true,
            windowsCanStart: false,
            displayNeedsRefresh: false,
            appValue: "Notepad",
            appTone: .green,
            appConnectionReady: true,
            appConnectionWaiting: false
        )

        #expect(metadata.map(\.title) == ["Windows", "App", "Display", "Connection"])
        #expect(metadata.map(\.value) == ["Running", "Notepad", "Available", "Ready"])
        #expect(metadata.map(\.symbolName) == ["play.rectangle", "macwindow", "display", "bolt.horizontal.circle"])
        #expect(!metadata.map(\.title).contains("ISO"))
        #expect(!metadata.map(\.title).contains("Disk"))

        let visibleText = metadata.flatMap { [$0.title, $0.value] }
        #expect(visibleText.allSatisfy { !$0.contains("runtime") })
        #expect(visibleText.allSatisfy { !$0.contains("VM") })
        #expect(visibleText.allSatisfy { !$0.contains("QEMU") })
        #expect(visibleText.allSatisfy { !$0.contains("agent") })
    }

    @Test("menu status titles stay app first")
    func menuStatusTitlesStayAppFirst() {
        let titles = [
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .stopped,
                windowsInstalled: true,
                hasLiveAppConnection: false,
                hasQueuedApp: false,
                openAppWindowCount: 0
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .running,
                windowsInstalled: true,
                hasLiveAppConnection: true,
                hasQueuedApp: false,
                openAppWindowCount: 0
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .running,
                windowsInstalled: true,
                hasLiveAppConnection: false,
                hasQueuedApp: true,
                openAppWindowCount: 0
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .running,
                windowsInstalled: true,
                hasLiveAppConnection: true,
                hasQueuedApp: false,
                openAppWindowCount: 2
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .notConfigured,
                windowsInstalled: false,
                hasLiveAppConnection: false,
                hasQueuedApp: false,
                openAppWindowCount: 0
            )
        ]

        #expect(titles == [
            "Ready to Open Apps",
            "Apps Ready",
            "App Waiting to Open",
            "2 Windows Apps Open",
            "Set Up Windows"
        ])
        #expect(titles.allSatisfy { $0.count <= 30 })
        #expect(titles.allSatisfy { !$0.contains("Stopped") })
        #expect(titles.allSatisfy { !$0.contains("Running") })
        #expect(titles.allSatisfy { !$0.contains("Runtime") })
        #expect(titles.allSatisfy { !$0.contains("VM") })
        #expect(titles.allSatisfy { !$0.contains("Agent") })
    }

    @Test("Windows power action titles stay product-like")
    func windowsPowerActionTitlesStayProductLike() {
        let titles = [
            WindowsShellCopy.openWindowsActionTitle(windowsInstalled: true),
            WindowsShellCopy.openWindowsActionTitle(windowsInstalled: false),
            WindowsShellCopy.closeWindowsActionTitle,
            WindowsShellCopy.refreshWindowsStatusTitle,
            WindowsShellCopy.previousAppsRestoreTitle(canRestoreNow: true),
            WindowsShellCopy.previousAppsRestoreTitle(canRestoreNow: false),
            WindowsShellCopy.bringWindowsAppsForwardTitle(openAppWindowCount: 1),
            WindowsShellCopy.bringWindowsAppsForwardTitle(
                openAppWindowCount: 1,
                singleAppName: "Notepad"
            ),
            WindowsShellCopy.bringWindowsAppsForwardTitle(
                openAppWindowCount: 1,
                singleAppName: "Very Long Accounting Workstation"
            ),
            WindowsShellCopy.bringWindowsAppsForwardTitle(openAppWindowCount: 2)
        ]

        #expect(titles == [
            "Open Windows",
            "Set Up Windows",
            "Close Windows",
            "Refresh Status",
            "Restore Previous Apps",
            "Reconnect Previous Apps",
            "Bring Windows App Forward",
            "Bring Notepad Forward",
            "Bring Very Long Acc... Forward",
            "Bring Windows Apps Forward"
        ])
        #expect(titles.allSatisfy { $0.count <= 30 })
        #expect(titles.allSatisfy { !$0.contains("Runtime") })
        #expect(titles.allSatisfy { !$0.contains("VM") })
        #expect(titles.allSatisfy { !$0.contains("Agent") })
    }

    @Test("menu item titles stay compact")
    func menuItemTitlesStayCompact() {
        let longTitle = "Very Long Accounting Workstation Window Title"
        let titles = [
            WindowsShellCopy.menuItemTitle(longTitle),
            WindowsShellCopy.prefixedMenuItemTitle(prefix: "Open", title: longTitle),
            WindowsShellCopy.prefixedMenuItemTitle(prefix: "Focus", title: longTitle),
            WindowsShellCopy.prefixedMenuItemTitle(prefix: "Close", title: longTitle),
            WindowsShellCopy.suffixedMenuItemTitle(prefix: "Bring", title: longTitle, suffix: "Forward"),
            WindowsShellCopy.menuItemTitle("   ")
        ]

        #expect(titles.allSatisfy { $0.count <= 30 })
        #expect(titles[0].hasSuffix("..."))
        #expect(titles[1].hasPrefix("Open "))
        #expect(titles[2].hasPrefix("Focus "))
        #expect(titles[3].hasPrefix("Close "))
        #expect(titles[4].hasPrefix("Bring "))
        #expect(titles[4].hasSuffix(" Forward"))
        #expect(titles[5] == "Windows App")
        #expect(titles.allSatisfy { !$0.contains("Runtime") })
        #expect(titles.allSatisfy { !$0.contains("VM") })
        #expect(titles.allSatisfy { !$0.contains("Agent") })
    }

    @Test("maps reconnect restore handoff to recovery start or wait states")
    func mapsReconnectRestoreHandoffToRecoveryStartOrWaitStates() {
        #expect(
            PreviousAppsRestoreHandoffPolicy.action(
                runtimeState: .running,
                canStartRuntime: false,
                supportsNativeDisplayWindow: true
            ) == .prepareGuestAgentRecovery(shouldShowDisplay: true)
        )
        #expect(
            PreviousAppsRestoreHandoffPolicy.action(
                runtimeState: .starting,
                canStartRuntime: false,
                supportsNativeDisplayWindow: false
            ) == .prepareGuestAgentRecovery(shouldShowDisplay: false)
        )
        #expect(
            PreviousAppsRestoreHandoffPolicy.action(
                runtimeState: .stopped,
                canStartRuntime: true,
                supportsNativeDisplayWindow: true
            ) == .startRuntime
        )
        #expect(
            PreviousAppsRestoreHandoffPolicy.action(
                runtimeState: .failed,
                canStartRuntime: false,
                supportsNativeDisplayWindow: true
            ) == .waitForRuntimeAvailability
        )
    }

    @Test("shows reconnect restore action when previous app intent exists without live agent")
    func showsReconnectRestoreActionWithoutLiveAgent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        try await intentStore.save(WindowRestoreIntent(appIds: ["winapp_notepad"]))
        let model = HostDashboardModel(
            service: DemoHostDashboardService(),
            restoreIntentStore: intentStore
        )
        let vmModel = VMRuntimeModel(service: StubVMRuntimeService())

        await model.loadRestoreIntent()
        await model.load()

        let menu = AppRuntimeDockMenuFactory.makeMenu(
            model: model,
            vmModel: vmModel,
            activateMainWindowAction: {},
            bringAllWindowsAppWindowsToFrontAction: {},
            focusWindowsAppWindowAction: { _ in },
            closeWindowsAppWindowAction: { _ in },
            closeAllWindowsAppWindowsAction: {},
            restoreWindowsAppWindowsAction: {},
            launchWindowsAppByIdAction: { _ in },
            fulfillPendingLaunchAction: {},
            repairGuestAgentForAppLaunchAction: {},
            recoverRuntimeDisplayAction: {},
            startVMAction: {},
            stopVMAction: {},
            quietWindowsWhenIdleAction: {}
        )

        let restoreItem = menu.items.first { $0.title == "Reconnect Previous Apps" }
        let firstAction = try #require(menu.items.dropFirst().first { !$0.isSeparatorItem })
        let restoreIndex = try #require(menu.items.firstIndex { $0.title == "Reconnect Previous Apps" })
        let openVeilIndex = try #require(menu.items.firstIndex { $0.title == "Open Veil" })
        let restoreItemCount = menu.items.filter { $0.title == "Reconnect Previous Apps" }.count

        #expect(model.canRestoreMirrorSessions == false)
        #expect(model.canReconnectRestoreMirrorSessions)
        #expect(restoreItem?.isEnabled == true)
        #expect(firstAction.title == "Reconnect Previous Apps")
        #expect(restoreIndex < openVeilIndex)
        #expect(restoreItemCount == 1)
    }

    @Test("Dock menu starts with app-first status")
    func dockMenuStartsWithAppFirstStatus() async throws {
        let model = HostDashboardModel(service: DemoHostDashboardService())
        let vmModel = VMRuntimeModel(service: StubVMRuntimeService())

        await model.load()
        await vmModel.load()

        let menu = AppRuntimeDockMenuFactory.makeMenu(
            model: model,
            vmModel: vmModel,
            activateMainWindowAction: {},
            bringAllWindowsAppWindowsToFrontAction: {},
            focusWindowsAppWindowAction: { _ in },
            closeWindowsAppWindowAction: { _ in },
            closeAllWindowsAppWindowsAction: {},
            restoreWindowsAppWindowsAction: {},
            launchWindowsAppByIdAction: { _ in },
            fulfillPendingLaunchAction: {},
            repairGuestAgentForAppLaunchAction: {},
            recoverRuntimeDisplayAction: {},
            startVMAction: {},
            stopVMAction: {},
            quietWindowsWhenIdleAction: {}
        )

        #expect(menu.items.first?.title == "Ready to Open Apps")
        #expect(menu.items.first?.isEnabled == false)
        #expect(menu.items.dropFirst().first?.isSeparatorItem == true)
        #expect(menu.items.dropFirst(2).first?.title == "Open Veil")
        #expect(menu.items.first?.title.count ?? 0 <= 30)
        #expect(menu.items.first?.title.contains("Runtime") == false)
        #expect(menu.items.first?.title.contains("VM") == false)
        #expect(menu.items.first?.title.contains("Agent") == false)
    }

    @Test("Dock menu prioritizes open Windows app windows over launcher")
    func dockMenuPrioritizesOpenWindowsAppWindowsOverLauncher() async throws {
        let model = HostDashboardModel(service: DemoHostDashboardService())
        let vmModel = VMRuntimeModel(service: StubVMRuntimeService())

        await model.load()
        await vmModel.load()
        let result = await model.launchApp(appId: "winapp_notepad")
        try #require(result != nil)

        let menu = AppRuntimeDockMenuFactory.makeMenu(
            model: model,
            vmModel: vmModel,
            activateMainWindowAction: {},
            bringAllWindowsAppWindowsToFrontAction: {},
            focusWindowsAppWindowAction: { _ in },
            closeWindowsAppWindowAction: { _ in },
            closeAllWindowsAppWindowsAction: {},
            restoreWindowsAppWindowsAction: {},
            launchWindowsAppByIdAction: { _ in },
            fulfillPendingLaunchAction: {},
            repairGuestAgentForAppLaunchAction: {},
            recoverRuntimeDisplayAction: {},
            startVMAction: {},
            stopVMAction: {},
            quietWindowsWhenIdleAction: {}
        )

        let firstAction = try #require(menu.items.dropFirst().first { !$0.isSeparatorItem })
        let bringIndex = try #require(menu.items.firstIndex { $0.title == "Bring Notepad Forward" })
        let openVeilIndex = try #require(menu.items.firstIndex { $0.title == "Open Veil" })

        #expect(menu.items.first?.title == "1 Windows App Open")
        #expect(firstAction.title == "Bring Notepad Forward")
        #expect(bringIndex < openVeilIndex)
    }

    @Test("maps queued app Dock menu item to the next product action")
    func mapsQueuedAppDockMenuItemToNextProductAction() {
        #expect(
            AppQueuedLaunchMenuState.make(
                appName: "Notepad",
                canRecoverRuntimeDisplay: true,
                canFulfillPendingLaunch: false,
                canRepairQueuedAppLaunch: false,
                canStartWindows: true,
                runtimeIsLoading: false
            ) == AppQueuedLaunchMenuState(
                title: "Refresh Display",
                kind: .recoverRuntimeDisplay,
                isEnabled: true
            )
        )

        #expect(
            AppQueuedLaunchMenuState.make(
                appName: "Notepad",
                canRecoverRuntimeDisplay: false,
                canFulfillPendingLaunch: true,
                canRepairQueuedAppLaunch: false,
                canStartWindows: false,
                runtimeIsLoading: false
            ) == AppQueuedLaunchMenuState(
                title: "Open Queued Notepad",
                kind: .fulfillPendingLaunch,
                isEnabled: true
            )
        )

        #expect(
            AppQueuedLaunchMenuState.make(
                appName: "Notepad",
                canRecoverRuntimeDisplay: false,
                canFulfillPendingLaunch: false,
                canRepairQueuedAppLaunch: true,
                canStartWindows: false,
                runtimeIsLoading: false
            ) == AppQueuedLaunchMenuState(
                title: "Continue Notepad",
                kind: .repairGuestAgentForAppLaunch,
                isEnabled: true
            )
        )

        #expect(
            AppQueuedLaunchMenuState.make(
                appName: "Notepad",
                canRecoverRuntimeDisplay: false,
                canFulfillPendingLaunch: false,
                canRepairQueuedAppLaunch: false,
                canStartWindows: true,
                runtimeIsLoading: false
            ) == AppQueuedLaunchMenuState(
                title: "Open Windows for Notepad",
                kind: .startWindows,
                isEnabled: true
            )
        )

        #expect(
            AppQueuedLaunchMenuState.make(
                appName: "Notepad",
                canRecoverRuntimeDisplay: false,
                canFulfillPendingLaunch: false,
                canRepairQueuedAppLaunch: false,
                canStartWindows: true,
                runtimeIsLoading: true
            ) == AppQueuedLaunchMenuState(
                title: "Open Windows for Notepad",
                kind: .startWindows,
                isEnabled: false
            )
        )

        let longNameState = AppQueuedLaunchMenuState.make(
            appName: "Very Long Accounting Workstation",
            canRecoverRuntimeDisplay: false,
            canFulfillPendingLaunch: false,
            canRepairQueuedAppLaunch: false,
            canStartWindows: true,
            runtimeIsLoading: false
        )
        #expect(longNameState.title.count <= 30)
        #expect(longNameState.title == "Open Windows for Very Long...")
        #expect(longNameState.symbolName == "play.fill")
    }
}

private struct StubVMRuntimeService: VMRuntimeService {
    func loadSnapshot() async throws -> VMRuntimeSnapshot { snapshot }
    func prepareDefaultVM() async throws -> VMRuntimeSnapshot { snapshot }
    func createDefaultProfile() async throws -> VMRuntimeSnapshot { snapshot }
    func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot { snapshot }
    func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot { snapshot }
    func markWindowsInstalled() async throws -> VMRuntimeSnapshot { snapshot }
    func markGuestAgentConnected(agentVersion: String) async throws -> VMRuntimeSnapshot { snapshot }
    func start() async throws -> VMRuntimeSnapshot { snapshot }
    func stop() async throws -> VMRuntimeSnapshot { snapshot }
    func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord {
        QEMUPointerTapRecord(
            qmpSocketPath: "/tmp/veil-test-qmp.sock",
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            absoluteX: 0,
            absoluteY: 0,
            commands: [],
            terminationStatus: nil,
            didLaunchSender: false,
            sentAt: Date()
        )
    }
    func sendConsoleKey(_ key: String) async throws -> QEMUKeySendRecord {
        QEMUKeySendRecord(
            monitorSocketPath: "/tmp/veil-test-monitor.sock",
            keys: [key],
            results: [],
            sentAt: Date()
        )
    }
    func exportDiagnostics(to directory: URL) async throws -> URL { directory }

    private var snapshot: VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: .stopped,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Default",
            bootReady: true,
            windowsInstalled: true,
            detail: "Stub runtime"
        )
    }
}
