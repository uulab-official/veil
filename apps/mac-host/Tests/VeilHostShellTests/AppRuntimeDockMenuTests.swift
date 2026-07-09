import AppKit
import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct AppRuntimeDockMenuTests {
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
        #expect(model.canRestoreMirrorSessions == false)
        #expect(model.canReconnectRestoreMirrorSessions)
        #expect(restoreItem?.isEnabled == true)
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
                title: "Start Windows for Notepad",
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
                title: "Start Windows for Notepad",
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
        #expect(longNameState.title == "Start Windows for Very Long...")
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
