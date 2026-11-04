import AppKit
import SwiftUI
import VeilHostCore

enum AppRuntimeBooterFactory {
    static func make() -> AppRuntimeBooter {
        AppRuntimeBooter.make()
    }
}

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let vmRuntimeBooter: AppRuntimeBooter
    let qemuConsoleWindowPresenter = QEMUConsoleWindowPresenter()
    let windowsAppWindowPresenter = WindowsAppWindowPresenter()
    let agentTransport: URLSessionWebSocketTransport?
    let agentConnectionPlan: AppGuestAgentConnectionPlan
    let windowsNotificationPresenter = WindowsNotificationPresenter(center: MacUserNotificationCenter())
    @State var model: HostDashboardModel
    @State var vmModel: VMRuntimeModel
    @State var displayMessage: String?
    @State var agentEventTask: Task<Void, Never>?
    @State var frameChannelTask: Task<Void, Never>?
    @State var agentReconnectTask: Task<Void, Never>?
    @State var automaticQuietRuntimeTask: Task<Void, Never>?
    @State var automaticGuestAgentRecoveryTask: Task<Void, Never>?
    @State var automaticRuntimeConnectionRecoveryTask: Task<Void, Never>?
    @State var automaticFrameStreamMaintenanceTask: Task<Void, Never>?
    @State var automaticGuestAgentRecoveryAttemptedTokens: Set<String> = []
    @State var automaticRuntimeConnectionRecoveryCooldownUntil: [String: Date] = [:]
    @State var hasObservedLiveAgentConnection = false
    @State var latestReviewEvidenceFolder: ReviewEvidenceFolder?
    @State var oneClickAppLaunchGate = OneClickAppLaunchTaskGate<OneClickAppLaunchOutcome<WindowsAppLaunchResult>>()
    let automaticRestoreMaximumAttempts = 3

    init() {
        let runtimeBooter = AppRuntimeBooterFactory.make()
        let connectionPlan = AppGuestAgentConnectionPlan.resolve(provider: runtimeBooter.provider)
        let transport = connectionPlan.endpointURL.map { URLSessionWebSocketTransport(url: $0) }
        self.vmRuntimeBooter = runtimeBooter
        self.agentTransport = transport
        self.agentConnectionPlan = connectionPlan
        _model = State(
            initialValue: HostDashboardModel(
                service: HostDashboardServiceMode.resolve().makeService(
                    transport: transport,
                    connectionPlan: connectionPlan
                ),
                initialApps: KnownWindowsAppCatalog.apps
            )
        )
        _vmModel = State(
            initialValue: VMRuntimeModel(
                service: LocalVMRuntimeService(bootRunner: runtimeBooter)
            )
        )
        _latestReviewEvidenceFolder = State(initialValue: ReviewEvidenceFolderStore.loadLatest())
    }

    private var mainWindowContent: some View {
        ContentView(
            model: model,
            vmModel: vmModel,
            startVMAction: startWindowsAndShowDisplay,
            stopVMAction: stopWindowsAndCloseDisplay,
            markWindowsInstalledAction: markWindowsInstalledFromSetup,
            installGuestAgentAction: installGuestAgentFromDisplay,
            prepareSparsePackageAction: prepareSparsePackageFromDisplay,
            waitForGuestAgentAction: waitForGuestAgent,
            repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunch,
            recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
            showWindowsDisplayAction: showWindowsDisplay,
            launchWindowsAppAction: runOneClickSelectedApp,
            fulfillPendingLaunchAction: runOneClickPendingLaunch,
            restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
            closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
            restartStaleFrameStreamsAction: restartStaleFrameStreams,
            requestNotificationConsentAction: requestWindowsNotificationConsent,
            runNotificationProofAction: runNotificationProof,
            runRecommendedProofAction: runRecommendedProof,
            runMultiAppProofAction: runMultiAppProof,
            quietWindowsWhenIdleAction: quietWindowsWhenIdle,
            displayMessage: displayMessage
        )
            .frame(
                minWidth: MainWindowLayout.minimumSupportedSize.width,
                idealWidth: 1500,
                minHeight: MainWindowLayout.minimumSupportedSize.height,
                idealHeight: 900
            )
            .task {
                configureDockMenuBridge()
                configureWindowsAppWindowCloseBridge()
                startAgentReconnectPollerIfNeeded()
                startAutomaticFrameStreamMaintenanceLoopIfNeeded()

                await model.loadRestoreIntent()
                async let hostLoad: Void = model.load()
                async let vmLoad: Void = vmModel.load()
                _ = await (hostLoad, vmLoad)
                noteLiveAgentConnectionIfPresent()
                // The event channel is intentionally started after the overview. Otherwise an
                // early discovery event can create a placeholder window before the model knows
                // that this is a capture-capable live agent.
                startAgentEventPumpIfNeeded()
                // Started after the health response has landed, since the capability decides whether
                // the endpoint exists at all.
                startFrameChannelPumpIfNeeded()
                await restorePreviousWindowsAppWindowAfterLaunchIfNeeded()
                syncLauncherWindowVisibility()
                await recordGuestAgentInstallEvidenceIfNeeded()

                if Self.shouldStartVMOnLaunch {
                    startWindowsAndShowDisplay()
                }
                syncDockTileRuntimeStatus()
            }
            .onChange(of: model.mirrorSessions.count) {
                syncDockTileRuntimeStatus()
                scheduleAutomaticQuietRuntimeIfNeeded()
                syncLauncherWindowVisibility()
            }
            .onChange(of: vmModel.snapshot?.state) {
                syncDockTileRuntimeStatus()
                scheduleAutomaticQuietRuntimeIfNeeded()
            }
            .onChange(of: vmModel.phase) {
                scheduleAutomaticQuietRuntimeIfNeeded()
            }
    }

    private var mainWindowScene: some Scene {
        let content = mainWindowContent
        MainWindowChrome.registerMainWindowContent(AnyView(content))

        return Window("Veil", id: "main") {
            content
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1440, height: 900)
        .defaultWindowPlacement { _, context in
            let visibleRect = context.defaultDisplay.visibleRect
            let size = MainWindowLayout.fittedSize(for: visibleRect.size)
            return WindowPlacement(size: size)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh All") {
                    Task {
                        async let hostLoad: Void = model.load()
                        async let vmLoad: Void = vmModel.load()
                        _ = await (hostLoad, vmLoad)
                        await recordGuestAgentInstallEvidenceIfNeeded()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Refresh Windows") {
                    Task {
                        await vmModel.load()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Start Windows") {
                    startWindowsAndShowDisplay()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!vmModel.canStart || vmModel.phase == .loading)

                Button("Stop Windows") {
                    stopWindowsAndCloseDisplay()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!vmModel.canStop || vmModel.phase == .loading)

                if canShowWindowsDisplay {
                    Button("Show Windows Display") {
                        showWindowsDisplay()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                }

                Button("Refresh Display") {
                    recoverRuntimeDisplayEvidence()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!canRecoverRuntimeDisplay)

                Button("Repair App Connection") {
                    installGuestAgentFromDisplay()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!canInstallGuestAgent)

                Button("Mark Windows Installed") {
                    markWindowsInstalledFromSetup()
                }
                .disabled(!canMarkWindowsInstalled)

                Button("Open Windows App") {
                    runOneClickSelectedApp()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(
                    !WindowsAppLaunchCommandPolicy.isEnabled(
                        canRequestLaunch: model.canRequestSelectedAppLaunch,
                        canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                        hasRecoverableRuntimeDisplay: canRecoverRuntimeDisplay,
                        hasLiveAgentConnection: model.hasLiveAgentConnection
                    )
                )

                Button("Check Windows App") {
                    runRecommendedProof()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.runtimeStatusReport().proofPlan.recommendedProofCommand == nil)

                Button("Prepare Review Evidence") {
                    prepareReviewEvidenceFolder()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    var body: some Scene {
        mainWindowScene

        MenuBarExtra("Veil", systemImage: menuBarSymbolName) {
            VeilMenuBarMenu(
                model: model,
                vmModel: vmModel,
                activateMainWindowAction: activateMainWindow,
                startVMAction: startWindowsAndShowDisplay,
                stopVMAction: stopWindowsAndCloseDisplay,
                showWindowsDisplayAction: showWindowsDisplay,
                markWindowsInstalledAction: markWindowsInstalledFromSetup,
                installGuestAgentAction: installGuestAgentFromDisplay,
                prepareSparsePackageAction: prepareSparsePackageFromDisplay,
                waitForGuestAgentAction: waitForGuestAgent,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunch,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
                launchWindowsAppAction: runOneClickSelectedApp,
                launchWindowsAppByIdAction: runOneClickAppLaunch(appId:),
                fulfillPendingLaunchAction: runOneClickPendingLaunch,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
                bringAllWindowsAppWindowsToFrontAction: bringAllWindowsAppWindowsToFront,
                focusWindowsAppWindowAction: focusWindowsAppWindow(windowId:),
                closeWindowsAppWindowAction: closeWindowsAppWindow(windowId:),
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
                restartStaleFrameStreamsAction: restartStaleFrameStreams,
                requestNotificationConsentAction: requestWindowsNotificationConsent,
                runNotificationProofAction: runNotificationProof,
                runRecommendedProofAction: runRecommendedProof,
                runMultiAppProofAction: runMultiAppProof,
                prepareReviewEvidenceAction: prepareReviewEvidenceFolder,
                quietWindowsWhenIdleAction: quietWindowsWhenIdle,
                refreshAppsAction: refreshApps,
                refreshRuntimeAction: refreshRuntime,
                supportsNativeDisplayWindow: canShowWindowsDisplay
            )
        }
        .defaultLaunchBehavior(.suppressed)
        .menuBarExtraStyle(.menu)
    }

    var agentURLString: String {
        agentConnectionPlan.endpoint
    }

    private static var shouldStartVMOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--start-vm")
    }

}

// This selector is not surfaced consistently by the macOS SDK overlay, so keep it in an extension
// to avoid Swift's optional-protocol near-match warning while still disabling empty AppKit restoration.
extension AppDelegate {
    @objc(applicationShouldSaveState:)
    func applicationShouldSaveState(_ app: NSApplication) -> Bool {
        false
    }
}

