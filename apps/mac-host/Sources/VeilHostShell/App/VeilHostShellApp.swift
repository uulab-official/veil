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
    let secureDesktopWindowPresenter = SecureDesktopWindowPresenter()
    let agentTransport: URLSessionWebSocketTransport?
    let agentConnectionPlan: AppGuestAgentConnectionPlan
    let windowsNotificationPresenter = WindowsNotificationPresenter(center: MacUserNotificationCenter())
    @State var model: HostDashboardModel
    @State var vmModel: VMRuntimeModel
    @State var displayMessage: String?
    @State var shellNavigation = ShellNavigation()
    @State var agentEventTask: Task<Void, Never>?
    @State var frameChannelTask: Task<Void, Never>?
    @State var agentReconnectTask: Task<Void, Never>?
    @State var automaticQuietRuntimeTask: Task<Void, Never>?
    /// Set when the user closed the last app window, on the Mac or in Windows; cleared when a window opens.
    /// Automatic quiet only follows that. Windows dropped because the agent restarted, for example during a
    /// tools update, once left zero windows on reconnect and Veil shut Windows down with apps still open in it.
    @State var lastAppWindowClosedByUser = false
    /// The Veil window stays away after the user closed the last Windows app, until they bring it back.
    /// Separate from `lastAppWindowClosedByUser`, which also lets Windows quiet down and must not be undone
    /// just because the window was reopened.
    @State var launcherDismissedWithLastApp = false
    @State var automaticGuestAgentRecoveryTask: Task<Void, Never>?
    @State var automaticRuntimeConnectionRecoveryTask: Task<Void, Never>?
    @State var automaticFrameStreamMaintenanceTask: Task<Void, Never>?
    @State var memoryBalloonTask: Task<Void, Never>?
    @State var automaticGuestAgentRecoveryAttemptedTokens: Set<String> = []
    @State var automaticRuntimeConnectionRecoveryCooldownUntil: [String: Date] = [:]
    @State var hasObservedLiveAgentConnection = false
    @State var latestReviewEvidenceFolder: ReviewEvidenceFolder?
    @State var oneClickAppLaunchGate = OneClickAppLaunchTaskGate<OneClickAppLaunchOutcome<WindowsAppLaunchResult>>()
    @State var oneClickAppWindowPresentationGate = OneClickAppWindowPresentationGate()
    @State var oneClickAppFrameMutationGate = OneClickAppFrameMutationGate()
    let automaticRestoreMaximumAttempts = 3
    /// Read directly by the paste path and the guest pump through ``ClipboardSharingPreferences``; these only
    /// drive the Apps menu switches. See `docs/protocol.md` "Host controls".
    @AppStorage(ClipboardSharingPreferences.sharingEnabledKey) var clipboardSharingEnabled = true
    @AppStorage(ClipboardSharingPreferences.filePasteEnabledKey) var clipboardFilePasteEnabled = true
    @AppStorage(ClipboardSharingPreferences.guestFileCopyEnabledKey) var clipboardGuestFileCopyEnabled = true
    @State var guestStateSync = GuestStateSyncCoordinator()
    @State var macHostStateObserver = MacHostStateObserver()
    @AppStorage(GuestStateSyncSettings.matchMacAppearanceKey) var matchMacAppearanceInWindows = true
    @AppStorage(GuestStateSyncSettings.reduceVisualEffectsKey) var reduceWindowsVisualEffects = true

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
            suspendVMAction: suspendWindows,
            restartInstallationAction: restartWindowsInstallation,
            startDiscardingSavedSessionAction: startWindowsDiscardingSavedSession,
            markWindowsInstalledAction: markWindowsInstalledFromSetup,
            installGuestAgentAction: installGuestAgentFromDisplay,
            prepareSparsePackageAction: prepareSparsePackageFromDisplay,
            waitForGuestAgentAction: waitForGuestAgent,
            repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunch,
            recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
            showWindowsDisplayAction: showWindowsDisplay,
            launchWindowsAppAction: runOneClickSelectedApp,
            launchWindowsAppByIdAction: runOneClickAppLaunch(appId:),
            fulfillPendingLaunchAction: runOneClickPendingLaunch,
            restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
            closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
            restartStaleFrameStreamsAction: restartStaleFrameStreams,
            requestNotificationConsentAction: requestWindowsNotificationConsent,
            runNotificationProofAction: runNotificationProof,
            runRecommendedProofAction: runRecommendedProof,
            runMultiAppProofAction: runMultiAppProof,
            quietWindowsWhenIdleAction: quietWindowsWhenIdle,
            updateGuestToolsAction: { updateGuestTools() },
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
                configureShortcutIntentBridge()
                configureWindowsAppWindowCloseBridge()
                startAgentReconnectPollerIfNeeded()
                startAutomaticFrameStreamMaintenanceLoopIfNeeded()
                startMemoryBalloonLoopIfNeeded()

                await model.loadRestoreIntent()
                async let hostLoad: Void = model.load()
                async let vmLoad: Void = vmModel.load()
                _ = await (hostLoad, vmLoad)
                // After the loads: a veil:// URL that cold-launched Veil is checked against whether Windows is
                // installed, which is unknown until the VM model has loaded.
                configureVeilURLBridge()
                noteLiveAgentConnectionIfPresent()
                // The event channel is intentionally started after the overview. Otherwise an
                // early discovery event can create a placeholder window before the model knows
                // that this is a capture-capable live agent.
                startAgentEventPumpIfNeeded()
                // Started after the health response has landed, since the capability decides whether
                // the endpoint exists at all.
                startFrameChannelPumpIfNeeded()
                startMacHostStateObservation()
                startGuestImeModeSync()
                await flushGuestStateSync()
                await restorePreviousWindowsAppWindowAfterLaunchIfNeeded()
                syncLauncherWindowVisibility()
                await recordGuestAgentInstallEvidenceIfNeeded()

                if StartupBehaviorPolicy.startsWindowsOnLaunch(
                    snapshot: vmModel.snapshot,
                    launchArgumentRequested: Self.shouldStartVMOnLaunch,
                    canRunWindows: AppWindowEngineStatus.resolve(
                        bootProvider: vmRuntimeBooter.provider,
                        providers: vmModel.snapshot?.runtimeProviders ?? []
                    ).canRunWindows
                ) {
                    startWindowsAndShowDisplay()
                }
                syncDockTileRuntimeStatus()
            }
            .onChange(of: model.mirrorSessions.count) { previousCount, count in
                if count > previousCount {
                    lastAppWindowClosedByUser = false
                    launcherDismissedWithLastApp = false
                }
                syncDockTileRuntimeStatus()
                scheduleAutomaticQuietRuntimeIfNeeded()
                syncLauncherWindowVisibility()
                if count > previousCount {
                    syncWindowsAppLaunchers()
                }
            }
            .onChange(of: model.apps) {
                // A guest that reports an icon or a new name after the window opened refreshes its launcher.
                syncWindowsAppLaunchers()
            }
            .onChange(of: vmModel.snapshot?.state) { oldState, newState in
                syncDockTileRuntimeStatus()
                scheduleAutomaticQuietRuntimeIfNeeded()
                noteGuestRuntimeStateChange(from: oldState, to: newState)
            }
            .onChange(of: matchMacAppearanceInWindows) { _, isOn in
                matchMacAppearanceSettingChanged(isOn: isOn)
            }
            .onChange(of: reduceWindowsVisualEffects) { _, _ in
                // The coordinator sees the new value differs from what Windows confirmed and sends it.
                Task { @MainActor in await flushGuestStateSync() }
            }
            .onChange(of: vmModel.phase) {
                scheduleAutomaticQuietRuntimeIfNeeded()
            }
            .onChange(of: shellNavigation.viewMode) { _, mode in
                applyViewMode(mode)
                syncSecureDesktopWindow()
                Task { @MainActor in await syncGuestImeMode() }
            }
            .environment(\.appRuntimeProvider, vmRuntimeBooter.provider)
            .environment(shellNavigation)
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
            SidebarCommands()
            ToolbarCommands()
            NewGuestVMCommands()

            CommandGroup(before: .sidebar) {
                Button("Windows Apps as Mac Windows") {
                    shellNavigation.viewMode = .apps
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Windows Desktop") {
                    shellNavigation.viewMode = .desktop
                }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(vmModel.snapshot?.installEvidence.isInstalled != true)

                if canShowWindowsDisplay {
                    Button("Open Desktop in Separate Window") {
                        showWindowsDisplay()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                }

                Button("Share a Mac Folder with Windows…") {
                    HostFolderSharing.shared.chooseFolder()
                    Task { @MainActor in await flushGuestStateSync() }
                }

                Button("Stop Sharing the Mac Folder") {
                    HostFolderSharing.shared.setFolder(nil)
                    Task { @MainActor in await flushGuestStateSync() }
                }

                Button("Refresh Display") {
                    recoverRuntimeDisplayEvidence()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!canRecoverRuntimeDisplay)

                Divider()

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

                Divider()
            }

            CommandMenu("Actions") {
                Button(vmModel.canResume ? "Resume Windows" : "Start Windows") {
                    startWindowsAndShowDisplay()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!vmModel.canStart || vmModel.phase == .loading || !AppWindowEngineStatus.resolve(
                    bootProvider: vmRuntimeBooter.provider,
                    providers: vmModel.snapshot?.runtimeProviders ?? []
                ).canRunWindows)

                Button("Suspend Windows") {
                    suspendWindows()
                }
                .disabled(!vmModel.canSuspend || vmModel.phase == .loading)

                Button("Shut Down Windows") {
                    stopWindowsAndCloseDisplay()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!vmModel.canStop || vmModel.phase == .loading)

                Button("Restart Windows Installation…") {
                    shellNavigation.requestRestartInstallation()
                }
                .disabled(!RestartInstallationAvailability.isAvailable(
                    snapshot: vmModel.snapshot,
                    isBusy: vmModel.phase == .loading
                ))

                Divider()

                Button("Configure…") {
                    shellNavigation.openConfiguration()
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
                .disabled(vmModel.snapshot == nil)

                Divider()

                Button("Repair App Connection") {
                    installGuestAgentFromDisplay()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!canInstallGuestAgent)

                // Always reachable, not only from the banner that appears when the bundled tools are newer.
                Button("Update Tools") {
                    updateGuestTools()
                }
                .disabled(vmModel.snapshot?.state != .running || vmModel.phase == .loading)

                Button("Mark Windows Installed") {
                    markWindowsInstalledFromSetup()
                }
                .disabled(!canMarkWindowsInstalled)

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

            CommandMenu("Apps") {
                Button(model.selectedApp.map { "Open \($0.name)" } ?? "Open Windows App") {
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

                Divider()

                ForEach(model.apps) { app in
                    Button(app.name) {
                        runOneClickAppLaunch(appId: app.id)
                    }
                    .disabled(vmModel.snapshot?.installEvidence.isInstalled != true)
                }

                Divider()

                Button("Bring All Windows App Windows to Front") {
                    bringAllWindowsAppWindowsToFront()
                }
                .disabled(model.mirrorSessions.isEmpty)

                Button("Close All Windows App Windows") {
                    closeAllWindowsAppWindows()
                }
                .disabled(model.mirrorSessions.isEmpty)

                Divider()

                Toggle("Share Clipboard with Windows", isOn: $clipboardSharingEnabled)
                Toggle("Copy Files into Windows on Paste", isOn: $clipboardFilePasteEnabled)
                    .disabled(!clipboardSharingEnabled)
                Toggle("Copy Files from Windows", isOn: $clipboardGuestFileCopyEnabled)
                    .disabled(!clipboardSharingEnabled)
            }
        }
    }

    var body: some Scene {
        mainWindowScene

        Window("New Virtual Machine", id: NewGuestVMView.windowID) {
            NewGuestVMView()
        }
        .windowResizability(.contentSize)

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

