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

    @Test("app check copy stays product-facing")
    func appCheckCopyStaysProductFacing() {
        let titles = [
            WindowsShellCopy.appCheckStatusTitle(
                recommendedProofKind: "mvp",
                latestProofFileName: nil
            ),
            WindowsShellCopy.appCheckStatusTitle(
                recommendedProofKind: "app-window",
                latestProofFileName: nil
            ),
            WindowsShellCopy.appCheckStatusTitle(
                recommendedProofKind: nil,
                latestProofFileName: "mvp-proof-2026-07-09.json"
            ),
            WindowsShellCopy.appCheckStatusTitle(
                recommendedProofKind: nil,
                latestProofFileName: nil
            )
        ]
        let details = [
            WindowsShellCopy.appCheckDetail(
                canRunMVPProof: true,
                canRunCoherenceProof: true,
                canRunAppWindowProof: true,
                recommendedProofCommand: "veil-vmctl mvp-proof --json",
                latestProofFileName: nil,
                reason: "unused"
            ),
            WindowsShellCopy.appCheckDetail(
                canRunMVPProof: false,
                canRunCoherenceProof: false,
                canRunAppWindowProof: true,
                recommendedProofCommand: "veil-vmctl app-window-proof --json",
                latestProofFileName: nil,
                reason: "unused"
            ),
            WindowsShellCopy.appCheckDetail(
                canRunMVPProof: false,
                canRunCoherenceProof: false,
                canRunAppWindowProof: false,
                recommendedProofCommand: nil,
                latestProofFileName: "mvp-proof-2026-07-09.json",
                reason: "unused"
            )
        ]

        #expect(titles == ["Full Check", "Window Check", "Saved", "Waiting"])
        #expect(details == [
            "Window, input, and clipboard are ready.",
            "Window capture is ready.",
            "Latest app check saved in diagnostics."
        ])

        let visibleText = titles + details
        #expect(visibleText.allSatisfy { !$0.contains("Proof") })
        #expect(visibleText.allSatisfy { !$0.contains("Runtime") })
        #expect(visibleText.allSatisfy { !$0.contains("Guest Agent") })
        #expect(visibleText.allSatisfy { !$0.contains("HWND") })
    }

    @Test("app flow copy stays product-facing")
    func appFlowCopyStaysProductFacing() {
        let titles = [
            WindowsShellCopy.appFlowStatusTitle(
                isPassing: true,
                passingStepCount: 5,
                requiredStepCount: 5
            ),
            WindowsShellCopy.appFlowStatusTitle(
                isPassing: false,
                passingStepCount: 3,
                requiredStepCount: 5
            )
        ]
        let details = [
            WindowsShellCopy.appFlowDetail(
                recommendedAction: "windowsSetup",
                isPassing: false
            ),
            WindowsShellCopy.appFlowDetail(
                recommendedAction: "appCheckEvidence",
                isPassing: false
            ),
            WindowsShellCopy.appFlowDetail(
                recommendedAction: "ready-for-release-card",
                isPassing: true
            )
        ]

        #expect(titles == ["Ready", "3 of 5"])
        #expect(details == [
            "Finish Windows setup before opening apps.",
            "Run Check App to save current app evidence.",
            "Setup, launch, app checks, and close controls are covered."
        ])

        let visibleText = titles + details
        #expect(visibleText.allSatisfy { !$0.contains("Proof") })
        #expect(visibleText.allSatisfy { !$0.contains("Runtime") })
        #expect(visibleText.allSatisfy { !$0.contains("Guest Agent") })
        #expect(visibleText.allSatisfy { !$0.contains("HWND") })
        #expect(visibleText.allSatisfy { !$0.contains("QEMU") })
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
                hasLiveAppConnection: false,
                hasQueuedApp: true,
                queuedAppName: "Notepad",
                openAppWindowCount: 0
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .running,
                windowsInstalled: true,
                hasLiveAppConnection: false,
                hasQueuedApp: true,
                queuedAppName: "Very Long Accounting Workstation",
                openAppWindowCount: 0
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .running,
                windowsInstalled: true,
                hasLiveAppConnection: true,
                hasQueuedApp: false,
                canRestorePreviousApps: true,
                restorableAppName: "Notepad",
                openAppWindowCount: 0
            ),
            WindowsShellCopy.menuStatusTitle(
                runtimeState: .running,
                windowsInstalled: true,
                hasLiveAppConnection: false,
                hasQueuedApp: false,
                canReconnectPreviousApps: true,
                restorableAppName: "Very Long Accounting Workstation",
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
            "Notepad Waiting",
            "Very Long Accounti... Waiting",
            "Notepad Ready",
            "Very Long Ac... Can Reconnect",
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
            WindowsShellCopy.previousAppsRestoreTitle(
                canRestoreNow: true,
                singleAppName: "Notepad"
            ),
            WindowsShellCopy.previousAppsRestoreTitle(
                canRestoreNow: false,
                singleAppName: "Very Long Accounting Workstation"
            ),
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
            "Restore Notepad",
            "Reconnect Very Long Account...",
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

    @Test("menu bar primary action symbols stay app first")
    func menuBarPrimaryActionSymbolsStayAppFirst() {
        let symbolsByAction = Self.menuBarPrimaryActionExpectations.mapValues { $0.symbolName }

        for (actionId, expectedSymbol) in symbolsByAction {
            #expect(
                MenuBarPrimaryActionPresentation.symbolName(
                    for: actionId,
                    fallbackSymbolName: "questionmark.circle"
                ) == expectedSymbol
            )
        }
        #expect(
            MenuBarPrimaryActionPresentation.symbolName(
                for: "unknown.action",
                fallbackSymbolName: "questionmark.circle"
            ) == "questionmark.circle"
        )
    }

    @Test("menu bar primary action routes stay executable")
    func menuBarPrimaryActionRoutesStayExecutable() {
        for (actionId, expectation) in Self.menuBarPrimaryActionExpectations {
            #expect(MenuBarPrimaryActionRoute.resolve(actionId: actionId) == expectation.route)
        }

        #expect(MenuBarPrimaryActionRoute.resolve(actionId: "unknown.action") == nil)
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
        let pendingLaunchStore = JSONPendingLaunchIntentStore(
            directory: directory.appendingPathComponent("pending", isDirectory: true)
        )
        try await intentStore.save(WindowRestoreIntent(appIds: ["winapp_notepad"]))
        let model = HostDashboardModel(
            service: DemoHostDashboardService(),
            restoreIntentStore: intentStore,
            pendingLaunchIntentStore: pendingLaunchStore
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

        let restoreItem = menu.items.first { $0.title == "Reconnect Notepad" }
        let firstAction = try #require(menu.items.dropFirst().first { !$0.isSeparatorItem })
        let restoreIndex = try #require(menu.items.firstIndex { $0.title == "Reconnect Notepad" })
        let openVeilIndex = try #require(menu.items.firstIndex { $0.title == "Open Veil" })
        let restoreItemCount = menu.items.filter { $0.title == "Reconnect Notepad" }.count

        #expect(menu.items.first?.title == "Notepad Can Reconnect")
        #expect(model.canRestoreMirrorSessions == false)
        #expect(model.canReconnectRestoreMirrorSessions)
        #expect(restoreItem?.isEnabled == true)
        #expect(firstAction.title == "Reconnect Notepad")
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

    @Test("Dock menu prioritizes queued Windows app over launcher")
    func dockMenuPrioritizesQueuedWindowsAppOverLauncher() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pendingLaunchStore = JSONPendingLaunchIntentStore(directory: directory)
        let restoreIntentStore = JSONWindowRestoreIntentStore(
            directory: directory.appendingPathComponent("restore", isDirectory: true)
        )
        try await pendingLaunchStore.save(PendingLaunchIntent(appId: "winapp_notepad"))
        let model = HostDashboardModel(
            service: DemoHostDashboardService(),
            restoreIntentStore: restoreIntentStore,
            pendingLaunchIntentStore: pendingLaunchStore
        )
        let vmModel = VMRuntimeModel(service: StubVMRuntimeService())

        await model.loadRestoreIntent()
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

        let firstAction = try #require(menu.items.dropFirst().first { !$0.isSeparatorItem })
        let queuedIndex = try #require(menu.items.firstIndex { $0.title == "Open Windows for Notepad" })
        let openVeilIndex = try #require(menu.items.firstIndex { $0.title == "Open Veil" })
        let queuedItemCount = menu.items.filter { $0.title == "Open Windows for Notepad" }.count

        #expect(menu.items.first?.title == "Notepad Waiting")
        #expect(firstAction.title == "Open Windows for Notepad")
        #expect(queuedIndex < openVeilIndex)
        #expect(queuedItemCount == 1)
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

extension AppRuntimeDockMenuTests {
    private typealias MenuBarPrimaryActionExpectation = (
        route: MenuBarPrimaryActionRoute,
        symbolName: String
    )

    private static let menuBarPrimaryActionExpectations: [String: MenuBarPrimaryActionExpectation] = [
        "dock.openMainWindow": (.openMainWindow, "macwindow"),
        "dock.bringWindowsAppsForward": (.bringWindowsAppsForward, "arrow.up.forward.app"),
        "windowsApps.restorePrevious": (.restorePreviousApps, "arrow.clockwise.square"),
        "windowsApps.reconnectRestore": (.restorePreviousApps, "arrow.clockwise.square"),
        "runtime.recoverDisplay": (.recoverDisplay, "display.trianglebadge.exclamationmark"),
        "runtime.fulfillPendingLaunch": (.fulfillPendingLaunch, "arrow.up.forward.app"),
        "runtime.repairGuestAgentForApp": (.repairAppConnection, "bolt.horizontal.circle"),
        "runtime.startWindowsForApp": (.startWindowsForApp, "play.fill"),
        "runtime.waitAgent": (.waitForAgent, "antenna.radiowaves.left.and.right"),
        "windowsApps.launchSelected": (.launchSelectedApp, "arrow.up.forward.app")
    ]
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
