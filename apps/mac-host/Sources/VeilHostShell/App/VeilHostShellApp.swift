import AppKit
import SwiftUI
import VeilHostCore

private enum AppRuntimeBooterFactory {
    static func make() -> QEMUVMRuntimeBooter {
        if ProcessInfo.processInfo.environment["VEIL_USE_NATIVE_QEMU_DISPLAY"] == "1" {
            return QEMUVMRuntimeBooter.shared
        }

        return QEMUVMRuntimeBooter(
            frontmostRunner: {},
            displayMode: .vncLoopback
        )
    }
}

private enum RecommendedProofError: Error, LocalizedError {
    case unsupportedKind(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedKind(let kind):
            "Unsupported recommended proof kind: \(kind)"
        }
    }
}

private struct ShellMultiAppProofReport: Encodable {
    var kind = "windowsMultiAppProof"
    var endpoint: String
    var provedAt: Date
    var proofDirectory: String
    var aggregateReportPath: String
    var appIds: [String]
    var targetAppIds: [String]
    var waitSeconds: Int
    var proofKind: String
    var provedAppCount: Int
    var failedAppCount: Int
    var coverageHealth: String
    var results: [ShellMultiAppProofResult]
    var nextActions: [String]
}

private struct ShellMultiAppProofResult: Encodable {
    var appId: String
    var status: String
    var proofKind: String?
    var proofPath: String?
    var latencyHealth: String?
    var slowestLatencyMeasurement: String?
    var slowestLatencyMilliseconds: Int?
    var latencyBudgetMilliseconds: Int?
    var staleTimeoutMilliseconds: Int?
    var latencyRecommendedAction: String?
    var windowId: String?
    var windowTitle: String?
    var errorMessage: String?
}

private struct ShellMultiAppLatencySummary {
    var health: String
    var slowestMeasurement: String
    var slowestElapsedMilliseconds: Int
    var freshFrameBudgetMilliseconds: Int
    var staleFrameTimeoutMilliseconds: Int
    var recommendedAction: String
}

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let vmRuntimeBooter: QEMUVMRuntimeBooter
    private let windowsAppWindowPresenter = WindowsAppWindowPresenter()
    private let agentTransport: URLSessionWebSocketTransport
    private let windowsNotificationPresenter = WindowsNotificationPresenter(center: MacUserNotificationCenter())
    @State private var model: HostDashboardModel
    @State private var vmModel: VMRuntimeModel
    @State private var displayMessage: String?
    @State private var agentEventTask: Task<Void, Never>?
    @State private var agentReconnectTask: Task<Void, Never>?
    @State private var automaticQuietRuntimeTask: Task<Void, Never>?
    @State private var automaticGuestAgentRecoveryTask: Task<Void, Never>?
    @State private var automaticFrameStreamMaintenanceTask: Task<Void, Never>?
    @State private var automaticGuestAgentRecoveryAttemptedTokens: Set<String> = []
    @State private var latestReviewEvidenceFolder: ReviewEvidenceFolder?

    init() {
        let runtimeBooter = AppRuntimeBooterFactory.make()
        let transport = URLSessionWebSocketTransport(
            url: URL(string: Self.agentURLString)!
        )
        self.vmRuntimeBooter = runtimeBooter
        self.agentTransport = transport
        _model = State(
            initialValue: HostDashboardModel(
                service: FallbackHostDashboardService(
                    primary: VeilHostClient(
                        transport: transport
                    ),
                    fallback: DemoHostDashboardService(),
                    primaryEndpointDescription: Self.agentURLString
                )
            )
        )
        _vmModel = State(
            initialValue: VMRuntimeModel(
                service: LocalVMRuntimeService(bootRunner: runtimeBooter)
            )
        )
        _latestReviewEvidenceFolder = State(initialValue: ReviewEvidenceFolderStore.loadLatest())
    }

    var body: some Scene {
        Window("Veil", id: "main") {
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
                launchWindowsAppAction: launchSelectedWindowsAppWindow,
                fulfillPendingLaunchAction: fulfillPendingWindowsAppWindow,
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
                .frame(minWidth: 1180, idealWidth: 1500, minHeight: 760, idealHeight: 900)
                .task {
                    configureDockMenuBridge()
                    configureWindowsAppWindowCloseBridge()
                    startAgentEventPumpIfNeeded()
                    startAgentReconnectPollerIfNeeded()
                    startAutomaticFrameStreamMaintenanceLoopIfNeeded()

                    await model.loadRestoreIntent()
                    async let hostLoad: Void = model.load()
                    async let vmLoad: Void = vmModel.load()
                    _ = await (hostLoad, vmLoad)
                    let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
                    for launch in restoredLaunches {
                        showWindowsAppWindow(for: launch)
                    }
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
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1440, height: 900)
        .defaultWindowPlacement { _, context in
            let visibleRect = context.defaultDisplay.visibleRect
            let preferredSize = CGSize(width: 1440, height: 900)
            let size = CGSize(
                width: min(preferredSize.width, visibleRect.width * 0.96),
                height: min(preferredSize.height, visibleRect.height * 0.96)
            )
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
                    launchSelectedWindowsAppWindow()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(canRecoverRuntimeDisplay || (!model.canRequestSelectedAppLaunch && !model.canFulfillPendingLaunch))

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
                launchWindowsAppAction: launchSelectedWindowsAppWindow,
                launchWindowsAppByIdAction: launchWindowsAppWindow(appId:),
                fulfillPendingLaunchAction: fulfillPendingWindowsAppWindow,
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
                supportsNativeDisplayWindow: vmRuntimeBooter.supportsNativeDisplayWindow
            )
        }
        .defaultLaunchBehavior(.suppressed)
        .menuBarExtraStyle(.menu)
    }

    private static var agentURLString: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

    private static var shouldStartVMOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--start-vm")
    }

    private func recordGuestAgentInstallEvidenceIfNeeded() async {
        guard model.hasLiveAgentConnection,
              let agentVersion = model.health?.agentVersion,
              vmModel.snapshot?.profileName != nil,
              vmModel.snapshot?.installEvidence.kind != .guestAgent else {
            return
        }

        await vmModel.markGuestAgentConnected(agentVersion: agentVersion)
    }

    private func startAgentEventPumpIfNeeded() {
        guard agentEventTask == nil else {
            return
        }

        agentEventTask = Task { @MainActor in
            // Bounded backoff instead of a fixed 2s retry: a real, sustained guest-agent outage
            // shouldn't spin at the same high rate (and log at the same high rate, per
            // VeilLog.agent.notice in consumeProtocolMessages) forever. Resets to the base interval
            // the moment a message is actually received again.
            let baseRetryDelaySeconds: Double = 2
            let maxRetryDelaySeconds: Double = 10
            var retryDelaySeconds = baseRetryDelaySeconds

            while !Task.isCancelled {
                await model.consumeProtocolMessages(from: agentTransport) { result in
                    switch result {
                    case .handledWindowCreated(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                        syncLauncherWindowVisibility()
                    case .handledWindowUpdated(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                    case .handledWindowFrame(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                    case .handledWindowClosed(let windowId):
                        windowsAppWindowPresenter.closeWindow(windowId: windowId)
                        scheduleAutomaticQuietRuntimeIfNeeded()
                        syncLauncherWindowVisibility()
                    case .handledClipboardText:
                        syncGuestClipboardToPasteboard()
                    case .handledWindowsNotification(let notificationId):
                        presentWindowsNotification(notificationId: notificationId)
                    case .ignored:
                        return
                    }
                }

                if model.phase == .reconnecting {
                    retryDelaySeconds = min(retryDelaySeconds * 2, maxRetryDelaySeconds)
                } else {
                    retryDelaySeconds = baseRetryDelaySeconds
                }
                try? await Task.sleep(for: .seconds(retryDelaySeconds))
            }
        }
    }

    private func startAgentReconnectPollerIfNeeded() {
        guard agentReconnectTask == nil else {
            return
        }

        agentReconnectTask = Task { @MainActor in
            // Same bounded-backoff reasoning as startAgentEventPumpIfNeeded(): a sustained outage
            // shouldn't poll at the base rate forever. Resets the moment there's nothing left to do
            // (either reconnected, or the VM isn't in a state that needs polling at all).
            let baseRetryDelaySeconds: Double = 5
            let maxRetryDelaySeconds: Double = 15
            var retryDelaySeconds = baseRetryDelaySeconds

            while !Task.isCancelled {
                let vmState = vmModel.snapshot?.state
                let shouldPoll = (vmState == .running || vmState == .starting) && !model.hasLiveAgentConnection
                if shouldPoll {
                    scheduleAutomaticGuestAgentRecoveryIfNeeded()

                    let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
                    for launch in restoredLaunches {
                        showWindowsAppWindow(for: launch)
                    }
                    syncLauncherWindowVisibility()

                    var fulfilledLaunch: NotepadLaunchResult?
                    if restoredLaunches.isEmpty {
                        fulfilledLaunch = await model.refreshLiveAgentIfNeeded()
                        if let fulfilledLaunch {
                            showWindowsAppWindow(for: fulfilledLaunch)
                            syncLauncherWindowVisibility()
                        }
                    }
                    await recordGuestAgentInstallEvidenceIfNeeded()

                    let madeProgress = !restoredLaunches.isEmpty || fulfilledLaunch != nil || model.hasLiveAgentConnection
                    retryDelaySeconds = madeProgress
                        ? baseRetryDelaySeconds
                        : min(retryDelaySeconds * 2, maxRetryDelaySeconds)
                } else {
                    retryDelaySeconds = baseRetryDelaySeconds
                }

                try? await Task.sleep(for: .seconds(retryDelaySeconds))
            }
        }
    }

    private func startWindowsAndShowDisplay() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = vmRuntimeBooter.supportsNativeDisplayWindow
                    ? "Windows is running in recovery display mode."
                    : "Windows is running inside the main Veil window. Setup evidence refreshes here."
                scheduleAutomaticGuestAgentRecoveryIfNeeded()
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows display could not start: \(errorMessage)"
            }
        }
    }

    private func stopWindowsAndCloseDisplay() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            await vmModel.stop()

            if vmModel.snapshot?.state == .stopped {
                windowsAppWindowPresenter.closeAll()
                displayMessage = "Windows display closed."
            }
        }
    }

    private func quietWindowsWhenIdle() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            guard model.canQuietRuntimeWhenIdle else {
                displayMessage = model.quietRuntimeStatus().reason
                return
            }

            guard vmModel.canStop && vmModel.phase != .loading else {
                displayMessage = WindowsShellCopy.quietStopWaitingMessage
                return
            }

            await vmModel.stop()
            if vmModel.snapshot?.state == .stopped {
                displayMessage = "Windows is quiet. No Windows app windows are open."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows could not quiet: \(errorMessage)"
            }
        }
    }

    private func scheduleAutomaticQuietRuntimeIfNeeded() {
        guard model.quietRuntimeStatus().willQuietAutomatically else {
            cancelAutomaticQuietRuntime()
            return
        }

        guard vmModel.canStop && vmModel.phase != .loading else {
            cancelAutomaticQuietRuntime()
            return
        }

        automaticQuietRuntimeTask?.cancel()
        let quietRuntime = model.quietRuntimeStatus()
        automaticQuietRuntimeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(quietRuntime.automaticQuietDelaySeconds))
            guard !Task.isCancelled,
                  model.canQuietRuntimeWhenIdle,
                  vmModel.canStop,
                  vmModel.phase != .loading else {
                return
            }

            displayMessage = "All Windows app windows closed. Quieting Windows."
            await vmModel.stop()
            if vmModel.snapshot?.state == .stopped {
                displayMessage = "Windows is quiet. No Windows app windows are open."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows could not quiet: \(errorMessage)"
            }
        }
    }

    private func cancelAutomaticQuietRuntime() {
        automaticQuietRuntimeTask?.cancel()
        automaticQuietRuntimeTask = nil
    }

    private func startAutomaticFrameStreamMaintenanceLoopIfNeeded() {
        guard automaticFrameStreamMaintenanceTask == nil else {
            return
        }

        automaticFrameStreamMaintenanceTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else {
                    return
                }

                await performFrameStreamMaintenance(automatic: true)
            }
        }
    }

    private func launchSelectedWindowsAppWindow() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            if model.apps.isEmpty {
                await model.load()
            }

            if model.canFulfillPendingLaunch {
                await fulfillPendingWindowsAppWindowFromCurrentState()
                return
            }

            await model.launchSelectedApp()

            if model.pendingLaunchAppId != nil,
               !model.hasLiveAgentConnection {
                continuePendingLaunchHandoff()
                return
            }

            guard let result = model.lastLaunch else {
                return
            }

            showWindowsAppWindow(for: result)
            syncLauncherWindowVisibility()
        }
    }

    private func launchWindowsAppWindow(appId: String) {
        model.selectedAppId = appId
        launchSelectedWindowsAppWindow()
    }

    private func fulfillPendingWindowsAppWindow() {
        Task { @MainActor in
            await fulfillPendingWindowsAppWindowFromCurrentState()
        }
    }

    private func fulfillPendingWindowsAppWindowFromCurrentState() async {
        cancelAutomaticQuietRuntime()
        if model.apps.isEmpty {
            await model.load()
        }

        guard model.canFulfillPendingLaunch else {
            if model.pendingLaunchStatus().willLaunchOnAgentReconnect {
                continuePendingLaunchHandoff()
            } else {
                displayMessage = model.pendingLaunchStatus().reason
            }
            return
        }

        guard let result = await model.fulfillPendingLaunch() else {
            displayMessage = model.errorMessage ?? "Queued Windows app could not open."
            return
        }

        displayMessage = "\(result.window.title) opened as a macOS window."
        showWindowsAppWindow(for: result)
        syncLauncherWindowVisibility()
    }

    private func continuePendingLaunchHandoff() {
        let appName = pendingLaunchDisplayName()
        switch vmModel.snapshot?.state {
        case .running, .starting:
            activateMainWindow()
            displayMessage = "Windows is running. Veil is preparing the app connection so \(appName) can open as a Mac window."
            scheduleAutomaticGuestAgentRecoveryIfNeeded()
            if vmRuntimeBooter.supportsNativeDisplayWindow {
                showWindowsDisplay()
            }
        default:
            guard vmModel.canStart else {
                displayMessage = "Veil queued \(appName). Start Windows when setup is available."
                return
            }

            displayMessage = "Starting Windows. Veil will open \(appName) when the app connection is ready."
            startWindowsAndShowDisplay()
        }
    }

    private func scheduleAutomaticGuestAgentRecoveryIfNeeded() {
        guard automaticGuestAgentRecoveryTask == nil,
              !model.hasLiveAgentConnection,
              model.phase != .launching,
              shouldRecoverGuestAgentForPendingApp,
              let recoveryToken = currentGuestAgentRecoveryToken,
              !automaticGuestAgentRecoveryAttemptedTokens.contains(recoveryToken) else {
            return
        }

        automaticGuestAgentRecoveryAttemptedTokens.insert(recoveryToken)
        automaticGuestAgentRecoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))

            guard !Task.isCancelled,
                  !model.hasLiveAgentConnection,
                  shouldRecoverGuestAgentForPendingApp else {
                automaticGuestAgentRecoveryTask = nil
                return
            }

            displayMessage = "Windows is running. Veil is repairing the app connection for \(pendingLaunchDisplayName())."

            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "App connection repair sent. Veil will open \(pendingLaunchDisplayName()) when Windows responds."
                await vmModel.refreshRuntimeEvidence()
            } catch {
                displayMessage = "App connection repair could not start: \(userMessage(for: error))"
            }

            automaticGuestAgentRecoveryTask = nil
        }
    }

    private var shouldRecoverGuestAgentForPendingApp: Bool {
        let hasQueuedLaunch = model.pendingLaunchStatus().willLaunchOnAgentReconnect
            || model.pendingLaunchAppId != nil
        let hasRestoreIntent = !model.restorableAppIds.isEmpty && model.mirrorSessions.isEmpty
        let runtimeIsRunning = vmModel.snapshot?.state == .running
            || vmModel.snapshot?.state == .starting

        return runtimeIsRunning && (hasQueuedLaunch || hasRestoreIntent)
    }

    private var currentGuestAgentRecoveryToken: String? {
        guard let snapshot = vmModel.snapshot,
              snapshot.state == .running || snapshot.state == .starting else {
            return nil
        }

        if let pid = snapshot.latestConsoleLaunch?.pid {
            return "qemu-pid:\(pid)"
        }

        if let pid = snapshot.runningQEMUProcess?.pid {
            return "detected-qemu-pid:\(pid)"
        }

        if let diskPath = snapshot.virtualDiskPath {
            return "disk:\(diskPath)"
        }

        return snapshot.profileName.map { "profile:\($0)" }
    }

    private func pendingLaunchDisplayName() -> String {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return "the queued app"
        }

        return model.apps.first { $0.id == pendingAppId }?.name ?? "the queued app"
    }

    private func restoreWindowsAppWindows() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
            for launch in restoredLaunches {
                showWindowsAppWindow(for: launch)
            }

            // restoreMirroredWindowsAfterReconnect() can come back empty either because there was
            // genuinely nothing to restore, or because every restore attempt failed -- those look
            // identical to the user (no windows reappear) unless the failure reason is surfaced here.
            if restoredLaunches.isEmpty, let errorMessage = model.errorMessage {
                displayMessage = "Could not restore previous Windows apps: \(errorMessage)"
            }

            if restoredLaunches.isEmpty,
               !model.hasLiveAgentConnection,
               model.canReconnectRestoreMirrorSessions {
                continuePreviousAppsRestoreHandoff()
            }

            syncLauncherWindowVisibility()
        }
    }

    private func continuePreviousAppsRestoreHandoff() {
        let handoff = PreviousAppsRestoreHandoffPolicy.action(
            runtimeState: vmModel.snapshot?.state,
            canStartRuntime: vmModel.canStart,
            supportsNativeDisplayWindow: vmRuntimeBooter.supportsNativeDisplayWindow
        )

        switch handoff {
        case .prepareGuestAgentRecovery(let shouldShowDisplay):
            activateMainWindow()
            displayMessage = "Windows is running. Veil is preparing the app connection to reconnect previous apps."
            scheduleAutomaticGuestAgentRecoveryIfNeeded()
            if shouldShowDisplay {
                showWindowsDisplay()
            }
        case .startRuntime:
            Task { @MainActor in
                cancelAutomaticQuietRuntime()
                activateMainWindow()
                displayMessage = "Starting Windows. Veil will reconnect previous apps when the app connection is ready."
                await vmModel.start()

                if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                    displayMessage = "Windows is running. Veil is preparing the app connection to reconnect previous apps."
                    scheduleAutomaticGuestAgentRecoveryIfNeeded()
                } else if let errorMessage = vmModel.errorMessage {
                    displayMessage = "Windows could not start for previous apps: \(errorMessage)"
                }
            }
        case .waitForRuntimeAvailability:
            displayMessage = "Veil found previous Windows apps to reconnect. Start Windows when setup is available."
        }
    }

    private func focusWindowsAppWindow(windowId: String) {
        Task { @MainActor in
            let response = await model.focusMirrorSession(windowId: windowId)
            guard response?.accepted == true,
                  let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                return
            }

            windowsAppWindowPresenter.showWindow(for: session)
            setForegroundWindowsAppMessage(windowId: windowId)
        }
    }

    private func bringAllWindowsAppWindowsToFront() {
        windowsAppWindowPresenter.bringAllToFront()
        if let focusedSession = model.mirrorSessions.last {
            setForegroundWindowsAppMessage(windowId: focusedSession.id)
            focusWindowsAppWindow(windowId: focusedSession.id)
        }
    }

    private func closeWindowsAppWindow(windowId: String) {
        Task { @MainActor in
            let response = await model.closeMirrorSession(windowId: windowId)
            guard response?.accepted == true else {
                return
            }

            windowsAppWindowPresenter.closeWindow(windowId: windowId)
            scheduleAutomaticQuietRuntimeIfNeeded()
            syncLauncherWindowVisibility()
        }
    }

    private func closeAllWindowsAppWindows() {
        Task { @MainActor in
            let responses = await model.closeAllMirrorSessions()
            for response in responses where response.accepted {
                windowsAppWindowPresenter.closeWindow(windowId: response.windowId)
            }
            scheduleAutomaticQuietRuntimeIfNeeded()
            syncLauncherWindowVisibility()
        }
    }

    private func restartStaleFrameStreams() {
        Task { @MainActor in
            await performFrameStreamMaintenance(automatic: false)
        }
    }

    @MainActor
    private func performFrameStreamMaintenance(automatic: Bool) async {
        let result = await model.maintainStaleFrameStreams()
        guard result.didPerformMaintenance else {
            if !automatic {
                displayMessage = "No paused app screens need restart."
            }
            return
        }

        for reopened in result.reopenedWindows {
            windowsAppWindowPresenter.closeWindow(windowId: reopened.requestedWindowId)
            if let session = model.mirrorSessions.first(where: { $0.id == reopened.launch.window.windowId }) {
                windowsAppWindowPresenter.showWindow(for: session)
            }
        }

        for windowId in result.recoveredFrameWindowIds + result.restartedFrameWindowIds {
            if let session = model.mirrorSessions.first(where: { $0.id == windowId }) {
                windowsAppWindowPresenter.showWindow(for: session)
            }
        }

        if !result.reopenedWindows.isEmpty {
            displayMessage = result.reopenedWindows.count == 1
                ? "Reopening \(result.reopenedWindows[0].launch.window.title)."
                : "Reopening \(result.reopenedWindows.count) app windows."
        } else if !result.recoveredFrameWindowIds.isEmpty {
            displayMessage = result.recoveredFrameWindowIds.count == 1
                ? "Recovering app screen."
                : "Recovering \(result.recoveredFrameWindowIds.count) app screens."
        } else if !automatic {
            displayMessage = result.restartedFrameWindowIds.count == 1
                ? "Restarting app screen."
                : "Restarting \(result.restartedFrameWindowIds.count) app screens."
        }

        syncDockTileRuntimeStatus()
        syncLauncherWindowVisibility()
    }

    private func configureDockMenuBridge() {
        appDelegate.reopenHandler = {
            let destination = LauncherReopenPolicy.destination(
                visibleMirroredWindowCount: windowsAppWindowPresenter.visibleWindowIds.count,
                modelRequestsHideLauncher: model.runtimeStatusReport().launcherVisibility.shouldHideMainWindow
            )

            switch destination {
            case .windowsAppWindows:
                bringAllWindowsAppWindowsToFront()
            case .mainWindow:
                activateMainWindow()
            }
        }
        appDelegate.dockMenuProvider = {
            AppRuntimeDockMenuFactory.makeMenu(
                model: model,
                vmModel: vmModel,
                activateMainWindowAction: activateMainWindow,
                bringAllWindowsAppWindowsToFrontAction: bringAllWindowsAppWindowsToFront,
                focusWindowsAppWindowAction: focusWindowsAppWindow(windowId:),
                closeWindowsAppWindowAction: closeWindowsAppWindow(windowId:),
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
                restartStaleFrameStreamsAction: restartStaleFrameStreams,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
                launchWindowsAppByIdAction: launchWindowsAppWindow(appId:),
                fulfillPendingLaunchAction: fulfillPendingWindowsAppWindow,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunch,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
                startVMAction: startWindowsAndShowDisplay,
                stopVMAction: stopWindowsAndCloseDisplay,
                quietWindowsWhenIdleAction: quietWindowsWhenIdle
            )
        }
    }

    private func syncDockTileRuntimeStatus() {
        DockTileRuntimePresenter.update(model.runtimeStatusReport().dockIntegration)
    }

    private func showWindowsAppWindow(for result: NotepadLaunchResult) {
        let session = model.mirrorSessions.first { $0.id == result.window.windowId }
                ?? WindowMirrorSession(
                    window: result.window,
                    connectionMode: model.connectionMode,
                    captureState: .unavailable
                )
        windowsAppWindowPresenter.showWindow(for: session)
        syncLauncherWindowVisibility()
    }

    private func setForegroundWindowsAppMessage(windowId: String) {
        guard let title = model.mirrorSessions.first(where: { $0.id == windowId })?.window.title else {
            return
        }

        displayMessage = "\(title) is frontmost as a macOS window."
    }

    private func syncLauncherWindowVisibility() {
        if shouldHideLauncherWindowForCoherence() {
            MainWindowChrome.hideMainWindow()
        } else {
            MainWindowChrome.showMainWindow()
        }
    }

    private func shouldHideLauncherWindowForCoherence() -> Bool {
        LauncherWindowVisibilityPolicy.shouldHideLauncher(
            visibleMirroredWindowCount: windowsAppWindowPresenter.visibleWindowIds.count,
            modelRequestsHide: model.runtimeStatusReport().launcherVisibility.shouldHideMainWindow
        )
    }

    private func runRecommendedProof() {
        Task { @MainActor in
            activateMainWindow()
            let proofPlan = model.runtimeStatusReport().proofPlan
            guard let proofKind = proofPlan.recommendedProofKind,
                  proofPlan.recommendedProofCommand != nil,
                  let appId = proofPlan.selectedAppId else {
                displayMessage = proofPlan.reason
                return
            }

            if model.apps.isEmpty {
                await model.load()
            }

            displayMessage = "Running \(appCheckDisplayName(for: proofKind)) app check for \(proofAppName(appId: appId))."

            do {
                let url = try await writeRecommendedProof(
                    proofKind: proofKind,
                    appId: appId,
                    reviewEvidenceFolder: latestReviewEvidenceFolder
                )
                displayMessage = "\(appCheckDisplayName(for: proofKind)) app check saved: \(url.path)"
                await model.load()
            } catch {
                displayMessage = "\(appCheckDisplayName(for: proofKind)) app check could not complete: \(userMessage(for: error))"
            }
        }
    }

    private func runMultiAppProof() {
        Task { @MainActor in
            activateMainWindow()
            let proofPlan = model.runtimeStatusReport().proofPlan
            guard proofPlan.recommendedMultiAppProofCommand != nil else {
                displayMessage = "Daily Use app check needs Notepad, Calculator, and Paint to be launchable first."
                return
            }

            if model.apps.isEmpty {
                await model.load()
            }

            displayMessage = "Checking Daily Use apps: Notepad, Calculator, and Paint."

            do {
                let url = try await writeMultiAppProof()
                displayMessage = "Daily Use app check saved: \(url.path)"
                await model.load()
            } catch {
                displayMessage = "Daily Use app check could not complete: \(userMessage(for: error))"
            }
        }
    }

    private func runNotificationProof() {
        Task { @MainActor in
            activateMainWindow()
            let report = model.runtimeStatusReport()
            guard report.notificationBridge.canReceiveNotifications,
                  report.notificationBridge.recommendedAction == "run-notification-proof" else {
                displayMessage = report.notificationBridge.reason
                return
            }

            displayMessage = "Waiting for a Windows notification to prove the Mac notification bridge."

            do {
                let url = try await writeNotificationProof()
                displayMessage = "Windows notification check saved: \(url.path)"
                await model.load()
            } catch {
                displayMessage = "Windows notification check could not complete: \(userMessage(for: error))"
            }
        }
    }

    private func writeRecommendedProof(
        proofKind: String,
        appId: String,
        reviewEvidenceFolder: ReviewEvidenceFolder? = nil
    ) async throws -> URL {
        let transport = URLSessionWebSocketTransport(url: URL(string: Self.agentURLString)!)
        let client = VeilHostClient(transport: transport)
        let directory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.diagnosticTimestamp()
        switch proofKind {
        case "app-window":
            var report = try await client.proveAppWindow(
                appId: appId,
                endpoint: Self.agentURLString,
                eventSource: transport
            )
            let outputURL = directory.appendingPathComponent("app-window-proof-\(stamp).json")
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
            return outputURL
        case "coherence":
            var report = try await client.proveCoherenceAppWindow(
                appId: appId,
                endpoint: Self.agentURLString,
                eventSource: transport
            )
            let outputURL = directory.appendingPathComponent("coherence-proof-\(stamp).json")
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
            return outputURL
        case "mvp":
            var report = try await client.proveMVPAppRuntime(
                appId: appId,
                endpoint: Self.agentURLString,
                eventSource: transport,
                waitSeconds: 30,
                proofTimeoutNanoseconds: 30_000_000_000
            )
            let outputURL = reviewEvidenceFolder?.appCheckProof
                ?? directory.appendingPathComponent("mvp-proof-\(stamp).json")
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
            return outputURL
        default:
            throw RecommendedProofError.unsupportedKind(proofKind)
        }
    }

    private func writeNotificationProof() async throws -> URL {
        let transport = URLSessionWebSocketTransport(url: URL(string: Self.agentURLString)!)
        let client = VeilHostClient(transport: transport)
        let directory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("Notification Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let outputURL = directory.appendingPathComponent("notification-proof-\(Self.diagnosticTimestamp()).json")
        var report = await client.proveWindowsNotificationBridge(
            endpoint: Self.agentURLString,
            eventSource: transport,
            waitSeconds: 30,
            notificationTimeoutNanoseconds: 30_000_000_000
        )
        report.savedProofPath = outputURL.path
        try writeProof(report, to: outputURL)
        return outputURL
    }

    private func writeMultiAppProof() async throws -> URL {
        let appIds = WindowsAppRuntimeProofCoverageDefaults.targetAppIds
        let endpoint = Self.agentURLString
        let diagnosticsDirectory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
        let coherenceProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Coherence Proof", isDirectory: true)
        let recommendedProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: coherenceProofDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recommendedProofDirectory, withIntermediateDirectories: true)

        let stamp = Self.diagnosticTimestamp()
        let aggregateURL = recommendedProofDirectory
            .appendingPathComponent("multi-app-proof-\(stamp).json")
        var results: [ShellMultiAppProofResult] = []

        for appId in appIds {
            let proofURL = coherenceProofDirectory
                .appendingPathComponent("\(Self.proofFileComponent(appId))-coherence-proof-\(stamp).json")
            let transport = URLSessionWebSocketTransport(url: URL(string: endpoint)!)
            let client = VeilHostClient(transport: transport)

            do {
                var proof = try await client.proveCoherenceAppWindow(
                    appId: appId,
                    endpoint: endpoint,
                    eventSource: transport,
                    timeoutNanoseconds: 10_000_000_000
                )
                proof.savedProofPath = proofURL.path
                try writeProof(proof, to: proofURL)

                let latency = Self.multiAppLatencySummary(for: proof)
                results.append(
                    ShellMultiAppProofResult(
                        appId: appId,
                        status: "proved",
                        proofKind: "coherence",
                        proofPath: proofURL.path,
                        latencyHealth: latency.health,
                        slowestLatencyMeasurement: latency.slowestMeasurement,
                        slowestLatencyMilliseconds: latency.slowestElapsedMilliseconds,
                        latencyBudgetMilliseconds: latency.freshFrameBudgetMilliseconds,
                        staleTimeoutMilliseconds: latency.staleFrameTimeoutMilliseconds,
                        latencyRecommendedAction: latency.recommendedAction,
                        windowId: proof.window.windowId,
                        windowTitle: proof.window.title,
                        errorMessage: nil
                    )
                )
            } catch {
                results.append(
                    ShellMultiAppProofResult(
                        appId: appId,
                        status: "failed",
                        proofKind: "coherence",
                        proofPath: nil,
                        latencyHealth: nil,
                        slowestLatencyMeasurement: nil,
                        slowestLatencyMilliseconds: nil,
                        latencyBudgetMilliseconds: nil,
                        staleTimeoutMilliseconds: nil,
                        latencyRecommendedAction: nil,
                        windowId: nil,
                        windowTitle: nil,
                        errorMessage: userMessage(for: error)
                    )
                )
            }
        }

        let provedAppCount = results.filter { $0.status == "proved" }.count
        let failedAppCount = results.count - provedAppCount
        let coverageHealth = provedAppCount == appIds.count
            ? "complete"
            : (provedAppCount > 0 ? "partial" : "missing")
        let report = ShellMultiAppProofReport(
            endpoint: endpoint,
            provedAt: Date(),
            proofDirectory: coherenceProofDirectory.path,
            aggregateReportPath: aggregateURL.path,
            appIds: appIds,
            targetAppIds: appIds,
            waitSeconds: 10,
            proofKind: "coherence",
            provedAppCount: provedAppCount,
            failedAppCount: failedAppCount,
            coverageHealth: coverageHealth,
            results: results,
            nextActions: Self.multiAppProofNextActions(
                coverageHealth: coverageHealth,
                aggregateReportPath: aggregateURL.path,
                failedResults: results.filter { $0.status == "failed" }
            )
        )
        try writeProof(report, to: aggregateURL)
        return aggregateURL
    }

    private func writeProof<T: Encodable>(_ report: T, to outputURL: URL) throws {
        let data = try JSONEncoder.veilDiagnostics.encode(report)
        try data.write(to: outputURL, options: .atomic)
    }

    private func prepareReviewEvidenceFolder() {
        Task { @MainActor in
            activateMainWindow()
            do {
                let folder = try ReviewEvidenceFolderStore.prepare()
                latestReviewEvidenceFolder = folder
                ReviewEvidenceFolderStore.rememberLatest(folder)
                NSWorkspace.shared.open(folder.directory)
                displayMessage = "Review Evidence folder ready: \(folder.directory.path). App checks will save \(folder.appCheckProof.lastPathComponent) there."
            } catch {
                displayMessage = "Review Evidence folder could not be prepared: \(userMessage(for: error))"
            }
        }
    }

    private func appCheckDisplayName(for proofKind: String) -> String {
        switch proofKind {
        case "app-window":
            "Window"
        case "coherence":
            "Input"
        case "mvp":
            "Full"
        default:
            "Recommended"
        }
    }

    private func proofAppName(appId: String) -> String {
        model.apps.first { $0.id == appId }?.name ?? appId
    }

    private static func diagnosticTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func proofFileComponent(_ appId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(appId.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
    }

    private static func multiAppLatencySummary(
        for proof: WindowsAppCoherenceProofReport
    ) -> ShellMultiAppLatencySummary {
        let slowest = [proof.initialFrameLatency, proof.postInputFrameLatency].max {
            $0.elapsedMilliseconds < $1.elapsedMilliseconds
        } ?? proof.postInputFrameLatency
        let health: String
        if slowest.elapsedMilliseconds <= slowest.freshFrameBudgetMilliseconds {
            health = "healthy"
        } else if slowest.elapsedMilliseconds <= slowest.staleFrameTimeoutMilliseconds {
            health = "delayed"
        } else {
            health = "stale"
        }

        return ShellMultiAppLatencySummary(
            health: health,
            slowestMeasurement: slowest.measurement,
            slowestElapsedMilliseconds: slowest.elapsedMilliseconds,
            freshFrameBudgetMilliseconds: slowest.freshFrameBudgetMilliseconds,
            staleFrameTimeoutMilliseconds: slowest.staleFrameTimeoutMilliseconds,
            recommendedAction: slowest.recommendedAction
        )
    }

    private static func multiAppProofNextActions(
        coverageHealth: String,
        aggregateReportPath: String,
        failedResults: [ShellMultiAppProofResult]
    ) -> [String] {
        var actions = [
            "Run `veil-vmctl app-runtime-status --json` to confirm proofArtifacts.multiAppProofCoverageHealth.",
            "Attach `\(aggregateReportPath)` with the saved per-app proof artifacts when filing app-runtime evidence."
        ]
        if coverageHealth != "complete" {
            actions.append("Run `veil-vmctl guest-agent-wait --json --wait-seconds 30` and retry `veil-vmctl multi-app-proof --json --require-complete` after the Windows app connection is live.")
        }
        for result in failedResults {
            actions.append("Retry `veil-vmctl coherence-proof --json --app-id \(result.appId)` to isolate the \(result.appId) failure.")
        }
        return actions
    }

    private func configureWindowsAppWindowCloseBridge() {
        windowsAppWindowPresenter.onUserWindowClose = { windowId in
            Task { @MainActor in
                _ = await model.closeMirrorSession(windowId: windowId)
                scheduleAutomaticQuietRuntimeIfNeeded()
                syncLauncherWindowVisibility()
            }
        }
        windowsAppWindowPresenter.onMouseInput = { windowId, event, x, y in
            Task { @MainActor in
                await model.sendMouseInput(windowId: windowId, event: event, x: x, y: y)
            }
        }
        windowsAppWindowPresenter.onKeyInput = { windowId, event, key, windowsVirtualKey, modifiers in
            Task { @MainActor in
                await model.sendKeyInput(
                    windowId: windowId,
                    event: event,
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            }
        }
        windowsAppWindowPresenter.onFileDrop = { appId, fileName, contentBase64 in
            Task { @MainActor in
                await model.openFile(appId: appId, fileName: fileName, contentBase64: contentBase64)
            }
        }
        windowsAppWindowPresenter.onRestartFrameStream = { windowId in
            Task { @MainActor in
                let sessionBeforeRecovery = model.mirrorSessions.first(where: { $0.id == windowId })
                let assessment = sessionBeforeRecovery.map { WindowFrameStreamAssessment.assess(session: $0) }
                if assessment?.reopenEscalated == true,
                   let result = await model.reopenAppWindow(windowId: windowId) {
                    windowsAppWindowPresenter.closeWindow(windowId: result.requestedWindowId)
                    if let session = model.mirrorSessions.first(where: { $0.id == result.launch.window.windowId }) {
                        windowsAppWindowPresenter.showWindow(for: session)
                    }
                    displayMessage = "Reopening \(result.launch.window.title)."
                    syncLauncherWindowVisibility()
                    return
                }

                let shouldRecover = assessment?.recoveryEscalated == true
                let didRecover: Bool
                if shouldRecover {
                    didRecover = await model.recoverFrameCapture(windowId: windowId)
                } else {
                    didRecover = await model.restartFrameSubscription(windowId: windowId)
                }
                guard didRecover,
                      let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                    return
                }

                windowsAppWindowPresenter.showWindow(for: session)
                displayMessage = shouldRecover
                    ? "Recovering \(session.window.title) screen."
                    : "Restarting \(session.window.title) screen."
            }
        }
        windowsAppWindowPresenter.onPasteShortcut = { windowId, key, windowsVirtualKey, modifiers, text in
            Task { @MainActor in
                await model.sendHostClipboardText(text)
                await model.sendKeyInput(
                    windowId: windowId,
                    event: "keyDown",
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
                await model.sendKeyInput(
                    windowId: windowId,
                    event: "keyUp",
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            }
        }
    }

    @MainActor
    private func syncGuestClipboardToPasteboard() {
        guard let text = model.latestGuestClipboardText else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func showWindowsDisplay() {
        activateMainWindow()
        if vmRuntimeBooter.showConsoleIfRunning() {
            displayMessage = "Recovery display brought forward."
        } else {
            displayMessage = "No recovery display is attached. Windows normally runs inside the main Veil window."
        }
    }

    private func installGuestAgentFromDisplay() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Sending the Veil app connection installer to Windows."
            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "App connection installer sent. Veil will connect when Windows is ready."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()
            } catch {
                displayMessage = "App connection install could not start: \(userMessage(for: error))"
            }
        }
    }

    private func prepareSparsePackageFromDisplay() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()
            displayMessage = "Preparing Windows package identity. Keep the Windows setup display open for prompts."

            do {
                _ = try await vmRuntimeBooter.prepareSparsePackageFromAttachedMedia()
                displayMessage = "Package identity preparation sent. Waiting for the Windows app connection to return."
                await vmModel.refreshRuntimeEvidence()

                let report = await model.waitForLiveAgentConnection(
                    endpoint: Self.agentURLString,
                    timeoutSeconds: 120
                )
                await recordGuestAgentInstallEvidenceIfNeeded()
                await model.load()

                if report.diagnostic.health?.capabilities.packageIdentity == true {
                    displayMessage = "Windows package identity is ready."
                } else if report.status == .connected {
                    displayMessage = "Windows reconnected, but package identity is not ready yet. Check sparse package evidence."
                } else {
                    displayMessage = "Package identity preparation was sent. Windows has not reconnected yet."
                }
            } catch {
                displayMessage = "Package identity preparation could not start: \(userMessage(for: error))"
            }
        }
    }

    private func requestWindowsNotificationConsent() {
        Task { @MainActor in
            activateMainWindow()

            guard model.hasLiveAgentConnection else {
                displayMessage = "Connect the Windows app connection before allowing Windows notifications."
                return
            }

            guard model.health?.capabilities.packageIdentity == true else {
                displayMessage = "Prepare Windows package identity before allowing Windows notifications."
                return
            }

            displayMessage = "Asking Windows to allow Veil notifications."

            do {
                let client = VeilHostClient(
                    transport: URLSessionWebSocketTransport(url: URL(string: Self.agentURLString)!)
                )
                let response = try await client.requestWindowsNotificationListenerConsent()
                await model.load()

                if response.accepted {
                    displayMessage = "Windows notifications are allowed. Run the notification check after a Windows notification appears."
                } else {
                    displayMessage = notificationConsentMessage(for: response.notificationListener)
                }
            } catch {
                displayMessage = "Windows notification access could not be requested: \(userMessage(for: error))"
            }
        }
    }

    private func notificationConsentMessage(for status: WindowsNotificationListenerStatus) -> String {
        switch status.recommendedAction {
        case "request-notification-listener-consent":
            return "Windows has not allowed Veil notifications yet. Try Allow Notifications again from Veil."
        case "enable-notification-listener-settings":
            return "Allow Veil in Windows notification access settings, then run the notification check."
        case "prepare-sparse-package":
            return "Prepare Windows package identity before allowing Windows notifications."
        case "connect-agent":
            return "Connect the Windows app connection before allowing Windows notifications."
        default:
            return status.message ?? "Windows notification access is not ready yet."
        }
    }

    private func waitForGuestAgent() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Checking the Windows app connection."
            let report = await model.waitForLiveAgentConnection(
                endpoint: Self.agentURLString,
                timeoutSeconds: 5
            )
            await recordGuestAgentInstallEvidenceIfNeeded()

            if report.status == .connected {
                displayMessage = "Windows app connection is ready."
                if let fulfilledLaunch = await model.refreshLiveAgentIfNeeded() {
                    showWindowsAppWindow(for: fulfilledLaunch)
                    syncLauncherWindowVisibility()
                }
            } else if let hostForwardProbe = report.diagnostic.hostForwardProbe {
                displayMessage = "Windows app connection is not ready yet (\(hostForwardProbe.status.rawValue))."
            } else {
                displayMessage = "Windows app connection is not ready yet."
            }
        }
    }

    private func repairGuestAgentForAppLaunch() {
        Task { @MainActor in
            cancelAutomaticQuietRuntime()
            activateMainWindow()

            guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
                continuePendingLaunchHandoff()
                return
            }

            let appName = pendingLaunchDisplayName()
            displayMessage = "Repairing the Windows app connection so \(appName) can open as a Mac window."

            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "App connection repair sent. Veil will open \(appName) when Windows responds."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()

                if let fulfilledLaunch = await model.refreshLiveAgentIfNeeded() {
                    showWindowsAppWindow(for: fulfilledLaunch)
                    syncLauncherWindowVisibility()
                }
            } catch {
                displayMessage = "App connection repair could not start: \(userMessage(for: error))"
            }
        }
    }

    private func markWindowsInstalledFromSetup() {
        Task { @MainActor in
            activateMainWindow()
            await vmModel.markWindowsInstalled()
            if vmModel.snapshot?.windowsInstalled == true {
                displayMessage = "Windows is marked installed. Veil will boot from the local disk and leave the installer ISO detached."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows install state could not be updated: \(errorMessage)"
            }
        }
    }

    private func refreshRuntime() {
        Task {
            await vmModel.load()
        }
    }

    private func recoverRuntimeDisplayEvidence() {
        Task { @MainActor in
            activateMainWindow()
            let beforeStatus = vmModel.snapshot?.latestConsoleLaunch?.previewStatus
            displayMessage = "Refreshing the embedded Windows display."
            await vmModel.refreshRuntimeEvidence()

            let afterStatus = vmModel.snapshot?.latestConsoleLaunch?.previewStatus
            if afterStatus == .fresh {
                displayMessage = "Windows display evidence refreshed."
            } else {
                let statusText = afterStatus?.rawValue ?? beforeStatus?.rawValue ?? "unavailable"
                displayMessage = WindowsShellCopy.displayRecoveryStillStaleMessage(statusText: statusText)
            }
        }
    }

    private func refreshApps() {
        Task { @MainActor in
            await model.load()
            await recordGuestAgentInstallEvidenceIfNeeded()
        }
    }

    private func activateMainWindow() {
        Task { @MainActor in
            MainWindowChrome.showMainWindow()
        }
    }

    private func presentWindowsNotification(notificationId: String) {
        guard let notification = model.latestWindowsNotifications.first(where: { $0.notificationId == notificationId }) else {
            return
        }

        Task { @MainActor in
            let result = await windowsNotificationPresenter.present(notification)
            switch result {
            case .scheduled:
                displayMessage = "Windows notification shown on macOS: \(notification.title)"
            case .permissionDenied:
                displayMessage = "Windows notification received, but macOS notifications are not allowed for Veil."
            case .authorizationRequestDeclined:
                displayMessage = "Windows notification received, but notification permission was not granted."
            case .invalidNotification:
                displayMessage = "Windows notification received, but it was missing a title."
            }
        }
    }

    private var canShowWindowsDisplay: Bool {
        vmRuntimeBooter.supportsNativeDisplayWindow
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
    }

    private var canInstallGuestAgent: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && (vmModel.snapshot?.installEvidence.kind != .guestAgent || !model.hasLiveAgentConnection)
    }

    private var canRecoverRuntimeDisplay: Bool {
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            return false
        }

        return vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .stale
            || vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .unavailable
    }

    private var canMarkWindowsInstalled: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && vmModel.snapshot?.installEvidence.isInstalled != true
    }

    private var appRuntimeStatusReport: WindowsAppRuntimeStatusReport {
        model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot)
        )
    }

    private var menuBarSymbolName: String {
        appRuntimeStatusReport.menuBarIntegration.symbolName
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var dockMenuProvider: (() -> NSMenu?)?
    var reopenHandler: (() -> Void)?
    private let launchVerificationReportURL = LaunchVerificationArguments.reportURL(
        from: ProcessInfo.processInfo.arguments
    )
    private var appIconSource: AppIconSource = .fallback

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appIconSource = applyBundledAppIcon()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            MainWindowChrome.showMainWindow()
        }
        scheduleLaunchVerificationReportIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let reopenHandler else {
            return true
        }

        reopenHandler()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockMenuProvider?()
    }

    @MainActor
    private func applyBundledAppIcon() -> AppIconSource {
        guard let iconURL = Bundle.main.url(forResource: "VeilAppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            NSApp.applicationIconImage = fallbackAppIcon()
            return .fallback
        }

        NSApp.applicationIconImage = icon
        return .bundled
    }

    private func scheduleLaunchVerificationReportIfNeeded(attempt: Int = 1) {
        guard launchVerificationReportURL != nil else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }

            MainWindowChrome.showMainWindow()
            let report = MainWindowChrome.launchReport(appIconSource: self.appIconSource)
            if report.meetsLauncherContract || attempt >= 24 {
                self.writeLaunchVerificationReport(report)
            } else {
                self.scheduleLaunchVerificationReportIfNeeded(attempt: attempt + 1)
            }
        }
    }

    private func writeLaunchVerificationReport(_ report: MainWindowLaunchReport) {
        guard let launchVerificationReportURL else {
            return
        }

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(report)
            try FileManager.default.createDirectory(
                at: launchVerificationReportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: launchVerificationReportURL, options: .atomic)
        } catch {
            NSLog("Veil launch verification report could not be written: \(error.localizedDescription)")
        }
    }

    private func fallbackAppIcon() -> NSImage {
        let dimension: CGFloat = 1024
        let size = NSSize(width: dimension, height: dimension)
        let image = NSImage(size: size)
        image.lockFocus()

        defer { image.unlockFocus() }

        let backgroundRect = NSRect(origin: .zero, size: size)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.11, green: 0.44, blue: 0.78, alpha: 1)
        ])
        gradient?.draw(in: backgroundRect, angle: 145)

        let iconRect = NSRect(x: 132, y: 132, width: 760, height: 760)
        let path = NSBezierPath(roundedRect: iconRect, xRadius: 188, yRadius: 188)
        NSColor.white.setFill()
        path.fill()

        let outer = NSBezierPath(roundedRect: iconRect.insetBy(dx: 66, dy: 66), xRadius: 150, yRadius: 150)
        NSColor(calibratedRed: 0.00, green: 0.57, blue: 0.95, alpha: 1).setFill()
        outer.fill()

        let inner = NSBezierPath(roundedRect: iconRect.insetBy(dx: 164, dy: 164), xRadius: 110, yRadius: 110)
        NSColor(calibratedRed: 0.95, green: 0.37, blue: 0.14, alpha: 1).setFill()
        inner.fill()

        let text = "V"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 430, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        let textRect = NSRect(x: 110, y: 320, width: 804, height: 420)
        text.draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attributes)

        return image
    }

}

private struct VeilMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var model: HostDashboardModel
    var vmModel: VMRuntimeModel
    var activateMainWindowAction: () -> Void
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var prepareSparsePackageAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var launchWindowsAppByIdAction: (String) -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var bringAllWindowsAppWindowsToFrontAction: () -> Void
    var focusWindowsAppWindowAction: (String) -> Void
    var closeWindowsAppWindowAction: (String) -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var prepareReviewEvidenceAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var refreshAppsAction: () -> Void
    var refreshRuntimeAction: () -> Void
    var supportsNativeDisplayWindow: Bool

    var body: some View {
        Button(menuBarPrimaryActionTitle, systemImage: menuBarPrimaryActionSymbolName) {
            runMenuBarPrimaryAction()
        }
        .disabled(!menuBarPrimaryAction.primaryActionAvailable)

        if menuBarPrimaryAction.primaryActionId != "dock.openMainWindow" {
            Button("Open Veil", systemImage: "macwindow") {
                openMainWindow()
            }
        }

        Divider()

        Label(runtimeStatusTitle, systemImage: runtimeStatusSymbolName)

        if !model.mirrorSessions.isEmpty {
            Label(runningAppsTitle, systemImage: "rectangle.3.group")
        }

        Divider()

        if !model.mirrorSessions.isEmpty {
            Menu("Running Windows Apps", systemImage: "rectangle.3.group") {
                Button(
                    activeWindowsAppsForwardTitle,
                    systemImage: "arrow.up.forward.app"
                ) {
                    bringAllWindowsAppWindowsToFrontAction()
                }

                Divider()

                ForEach(model.mirrorSessions) { session in
                    Menu(
                        WindowsShellCopy.menuItemTitle(session.window.title),
                        systemImage: "macwindow"
                    ) {
                        Button("Bring to Front", systemImage: "arrow.up.forward.app") {
                            focusWindowsAppWindowAction(session.id)
                        }
                        .disabled(!model.canFocusMirrorSession(windowId: session.id))

                        Button("Close", systemImage: "xmark.circle") {
                            closeWindowsAppWindowAction(session.id)
                        }
                        .disabled(!model.canCloseMirrorSession(windowId: session.id))
                    }
                }

                Divider()

                Button("Close All", systemImage: "xmark.circle.fill") {
                    closeAllWindowsAppWindowsAction()
                }
                .disabled(!model.canCloseAllMirrorSessions)
            }

            Divider()
        }

        if model.apps.isEmpty {
            Button("Load Windows Apps", systemImage: "square.grid.2x2") {
                openMainWindow()
                refreshAppsAction()
            }
            .disabled(model.phase == .loading || model.phase == .launching)
        } else {
            Menu("Windows Apps", systemImage: "square.grid.2x2") {
                ForEach(model.apps) { app in
                    Button(WindowsShellCopy.menuItemTitle(app.name), systemImage: symbolName(for: app)) {
                        if !model.hasLiveAgentConnection {
                            openMainWindow()
                        }
                        launchWindowsAppByIdAction(app.id)
                    }
                    .disabled(canRecoverRuntimeDisplay || !model.canRequestAppLaunch(appId: app.id))
                }
            }
        }

        if shouldShowSecondaryPreviousAppsRestore {
            Button(restorePreviousAppsTitle, systemImage: "arrow.clockwise.square") {
                restoreWindowsAppWindowsAction()
            }
            .disabled(!model.canReconnectRestoreMirrorSessions)
        }

        if let queuedLaunchMenuState, shouldShowSecondaryQueuedLaunch {
            Button(queuedLaunchMenuState.title, systemImage: queuedLaunchMenuState.symbolName) {
                runQueuedLaunchAction(queuedLaunchMenuState)
            }
            .disabled(!queuedLaunchMenuState.isEnabled)
        }

        Button("Check Windows App", systemImage: "checkmark.seal") {
            openMainWindow()
            runRecommendedProofAction()
        }
        .disabled(model.runtimeStatusReport().proofPlan.recommendedProofCommand == nil)

        Button("Check Daily Use Apps", systemImage: "checkmark.seal.fill") {
            openMainWindow()
            runMultiAppProofAction()
        }
        .disabled(model.runtimeStatusReport().proofPlan.recommendedMultiAppProofCommand == nil)

        Button("Prepare Review Evidence", systemImage: "folder.badge.plus") {
            openMainWindow()
            prepareReviewEvidenceAction()
        }

        Divider()

        Button(openWindowsActionTitle, systemImage: "play.fill") {
            openMainWindow()
            startVMAction()
        }
        .disabled(!vmModel.canStart || vmModel.phase == .loading)

        if canShowWindowsDisplay {
            Button("Show Windows Display", systemImage: "display") {
                openMainWindow()
                showWindowsDisplayAction()
            }
        }

        Button("Refresh Display", systemImage: "display.trianglebadge.exclamationmark") {
            openMainWindow()
            recoverRuntimeDisplayAction()
        }
        .disabled(!canRecoverRuntimeDisplay)

        Button("Repair App Connection", systemImage: "person.crop.circle.badge.plus") {
            openMainWindow()
            installGuestAgentAction()
        }
        .disabled(!canInstallGuestAgent)

        Button("Check App Connection", systemImage: "antenna.radiowaves.left.and.right") {
            openMainWindow()
            waitForGuestAgentAction()
        }
        .disabled(!canWaitForGuestAgent)

        Button("Mark Windows Installed", systemImage: "checkmark.seal") {
            openMainWindow()
            markWindowsInstalledAction()
        }
        .disabled(!canMarkWindowsInstalled)

        Button(WindowsShellCopy.closeWindowsActionTitle, systemImage: "stop.fill") {
            openMainWindow()
            stopVMAction()
        }
        .disabled(!vmModel.canStop || vmModel.phase == .loading)

        if model.canQuietRuntimeWhenIdle {
            Button("Quiet Windows", systemImage: "moon.zzz.fill") {
                quietWindowsWhenIdleAction()
            }
            .disabled(!vmModel.canStop || vmModel.phase == .loading)
        }

        Divider()

        Button(WindowsShellCopy.refreshWindowsStatusTitle, systemImage: "arrow.clockwise") {
            refreshRuntimeAction()
        }
        .disabled(vmModel.phase == .loading)

        Divider()

        Button("Quit Veil", systemImage: "power") {
            NSApp.terminate(nil)
        }
    }

    private var canShowWindowsDisplay: Bool {
        supportsNativeDisplayWindow
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
    }

    private var openWindowsActionTitle: String {
        WindowsShellCopy.openWindowsActionTitle(
            windowsInstalled: vmModel.snapshot?.windowsInstalled == true
        )
    }

    private var canInstallGuestAgent: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && (vmModel.snapshot?.installEvidence.kind != .guestAgent || !model.hasLiveAgentConnection)
    }

    private var canWaitForGuestAgent: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && !model.hasLiveAgentConnection
    }

    private var canRecoverRuntimeDisplay: Bool {
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            return false
        }

        return vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .stale
            || vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .unavailable
    }

    private var canRepairQueuedAppLaunch: Bool {
        model.pendingLaunchStatus().willLaunchOnAgentReconnect
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && !model.canFulfillPendingLaunch
    }

    private var queuedLaunchMenuState: AppQueuedLaunchMenuState? {
        guard model.pendingLaunchAppId != nil else {
            return nil
        }

        return AppQueuedLaunchMenuState.make(
            appName: queuedLaunchAppName,
            canRecoverRuntimeDisplay: canRecoverRuntimeDisplay,
            canFulfillPendingLaunch: model.canFulfillPendingLaunch,
            canRepairQueuedAppLaunch: canRepairQueuedAppLaunch,
            canStartWindows: vmModel.canStart,
            runtimeIsLoading: vmModel.phase == .loading
        )
    }

    private var queuedLaunchAppName: String {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return "Windows App"
        }

        return model.apps.first { $0.id == pendingAppId }?.name ?? "Windows App"
    }

    private var canMarkWindowsInstalled: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && vmModel.snapshot?.installEvidence.isInstalled != true
    }

    private var appRuntimeStatusReport: WindowsAppRuntimeStatusReport {
        model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot)
        )
    }

    private var runtimeStatusTitle: String {
        appRuntimeStatusReport.menuBarIntegration.statusTitle
    }

    private var runtimeStatusSymbolName: String {
        appRuntimeStatusReport.menuBarIntegration.symbolName
    }

    private var menuBarPrimaryAction: WindowsAppRuntimeMenuBarIntegrationStatus {
        appRuntimeStatusReport.menuBarIntegration
    }

    private var menuBarPrimaryActionTitle: String {
        menuBarPrimaryAction.primaryActionTitle
    }

    private var menuBarPrimaryActionSymbolName: String {
        MenuBarPrimaryActionPresentation.symbolName(
            for: menuBarPrimaryAction.primaryActionId,
            fallbackSymbolName: runtimeStatusSymbolName
        )
    }

    private var runningAppsTitle: String {
        let count = model.mirrorSessions.count
        return count == 1 ? "1 Windows App Running" : "\(count) Windows Apps Running"
    }

    private var activeWindowsAppsForwardTitle: String {
        WindowsShellCopy.bringWindowsAppsForwardTitle(
            openAppWindowCount: model.mirrorSessions.count,
            singleAppName: activeSingleAppName
        )
    }

    private var activeSingleAppName: String? {
        guard model.mirrorSessions.count == 1,
              let session = model.mirrorSessions.first else {
            return nil
        }

        return model.apps.first { $0.id == session.window.appId }?.name
            ?? session.window.title
    }

    private var restorePreviousAppsTitle: String {
        WindowsShellCopy.previousAppsRestoreTitle(
            canRestoreNow: model.canRestoreMirrorSessions,
            singleAppName: restorableSingleAppName,
            restoreWindowCount: model.restorableWindowCount
        )
    }

    private var shouldPromotePreviousAppsRestore: Bool {
        !model.restorableAppIds.isEmpty && model.mirrorSessions.isEmpty
    }

    private var shouldShowSecondaryPreviousAppsRestore: Bool {
        !model.restorableAppIds.isEmpty && !shouldPromotePreviousAppsRestore
    }

    private var shouldPromoteQueuedLaunch: Bool {
        model.pendingLaunchAppId != nil
            && model.mirrorSessions.isEmpty
            && !shouldPromotePreviousAppsRestore
    }

    private var shouldShowSecondaryQueuedLaunch: Bool {
        model.pendingLaunchAppId != nil && !shouldPromoteQueuedLaunch
    }

    private var restorableSingleAppName: String? {
        guard model.restorableAppIds.count == 1,
              let appId = model.restorableAppIds.first else {
            return nil
        }

        return model.apps.first { $0.id == appId }?.name
    }

    private func runQueuedLaunchAction(_ state: AppQueuedLaunchMenuState) {
        switch state.kind {
        case .recoverRuntimeDisplay:
            openMainWindow()
            recoverRuntimeDisplayAction()
        case .fulfillPendingLaunch:
            fulfillPendingLaunchAction()
        case .repairGuestAgentForAppLaunch:
            openMainWindow()
            repairGuestAgentForAppLaunchAction()
        case .startWindows:
            openMainWindow()
            startVMAction()
        }
    }

    private func runMenuBarPrimaryAction() {
        switch MenuBarPrimaryActionRoute.resolve(actionId: menuBarPrimaryAction.primaryActionId) ?? .openMainWindow {
        case .openMainWindow:
            openMainWindow()
        case .bringWindowsAppsForward:
            bringAllWindowsAppWindowsToFrontAction()
        case .restorePreviousApps:
            restoreWindowsAppWindowsAction()
        case .recoverDisplay:
            openMainWindow()
            recoverRuntimeDisplayAction()
        case .fulfillPendingLaunch:
            fulfillPendingLaunchAction()
        case .repairAppConnection:
            openMainWindow()
            repairGuestAgentForAppLaunchAction()
        case .startWindowsForApp:
            openMainWindow()
            launchWindowsAppAction()
        case .waitForAgent:
            openMainWindow()
            waitForGuestAgentAction()
        case .preparePackageIdentity:
            openMainWindow()
            prepareSparsePackageAction()
        case .requestNotificationConsent:
            openMainWindow()
            requestNotificationConsentAction()
        case .runNotificationProof:
            openMainWindow()
            runNotificationProofAction()
        case .refreshRuntimeStatus:
            openMainWindow()
        case .restartFrameStream:
            restartStaleFrameStreamsAction()
        case .recoverWindowCapture:
            restartStaleFrameStreamsAction()
        case .reopenWindow:
            restartStaleFrameStreamsAction()
        case .launchSelectedApp:
            if !model.hasLiveAgentConnection {
                openMainWindow()
            }
            launchWindowsAppAction()
        case .runRecommendedProof:
            openMainWindow()
            runRecommendedProofAction()
        case .runMultiAppProof:
            openMainWindow()
            runMultiAppProofAction()
        }
    }

    private func openMainWindow() {
        if !MainWindowChrome.hasMainWindow {
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                MainWindowChrome.showMainWindow()
            }
        } else {
            DispatchQueue.main.async {
                MainWindowChrome.showMainWindow()
            }
        }
    }

    private func symbolName(for app: WindowsApp) -> String {
        switch app.iconId {
        case "icon_notepad":
            "note.text"
        case "icon_calculator":
            "plus.forwardslash.minus"
        case "icon_paint":
            "paintpalette"
        default:
            "macwindow"
        }
    }
}

enum MenuBarPrimaryActionRoute: Equatable {
    case openMainWindow
    case bringWindowsAppsForward
    case restorePreviousApps
    case recoverDisplay
    case fulfillPendingLaunch
    case repairAppConnection
    case startWindowsForApp
    case waitForAgent
    case preparePackageIdentity
    case requestNotificationConsent
    case runNotificationProof
    case refreshRuntimeStatus
    case restartFrameStream
    case recoverWindowCapture
    case reopenWindow
    case launchSelectedApp
    case runRecommendedProof
    case runMultiAppProof

    static func resolve(actionId: String) -> MenuBarPrimaryActionRoute? {
        switch actionId {
        case "dock.openMainWindow":
            return .openMainWindow
        case "dock.bringWindowsAppsForward":
            return .bringWindowsAppsForward
        case "windowsApps.restorePrevious", "windowsApps.reconnectRestore":
            return .restorePreviousApps
        case "runtime.recoverDisplay":
            return .recoverDisplay
        case "runtime.fulfillPendingLaunch":
            return .fulfillPendingLaunch
        case "runtime.repairGuestAgentForApp":
            return .repairAppConnection
        case "runtime.startWindowsForApp":
            return .startWindowsForApp
        case "runtime.waitAgent":
            return .waitForAgent
        case "dailyUse.verifyWindowCapture":
            return .refreshRuntimeStatus
        case "windowsApps.restartFrameStream":
            return .restartFrameStream
        case "windowsApps.recoverWindowCapture":
            return .recoverWindowCapture
        case "windowsApps.reopenWindow":
            return .reopenWindow
        case "runtime.prepareSparsePackage":
            return .preparePackageIdentity
        case "dailyUse.requestNotificationConsent":
            return .requestNotificationConsent
        case "dailyUse.verifyNotifications":
            return .runNotificationProof
        case "windowsApps.launchSelected":
            return .launchSelectedApp
        case "proof.recommended":
            return .runRecommendedProof
        case "proof.multiApp", "dailyUse.verifyIntegrations":
            return .runMultiAppProof
        default:
            return nil
        }
    }

    var symbolName: String? {
        switch self {
        case .openMainWindow:
            return "macwindow"
        case .bringWindowsAppsForward:
            return "arrow.up.forward.app"
        case .restorePreviousApps:
            return "arrow.clockwise.square"
        case .recoverDisplay:
            return "display.trianglebadge.exclamationmark"
        case .fulfillPendingLaunch, .launchSelectedApp:
            return "arrow.up.forward.app"
        case .repairAppConnection:
            return "bolt.horizontal.circle"
        case .startWindowsForApp:
            return "play.fill"
        case .waitForAgent:
            return "antenna.radiowaves.left.and.right"
        case .preparePackageIdentity:
            return "shippingbox"
        case .requestNotificationConsent:
            return "bell.badge"
        case .runNotificationProof:
            return "bell.badge.fill"
        case .refreshRuntimeStatus:
            return "arrow.clockwise"
        case .restartFrameStream:
            return "arrow.clockwise"
        case .recoverWindowCapture:
            return "wrench.and.screwdriver"
        case .reopenWindow:
            return "arrow.triangle.2.circlepath"
        case .runRecommendedProof:
            return "checkmark.seal"
        case .runMultiAppProof:
            return "checkmark.seal.fill"
        }
    }
}

enum MenuBarPrimaryActionPresentation {
    static func symbolName(for actionId: String, fallbackSymbolName: String) -> String {
        MenuBarPrimaryActionRoute.resolve(actionId: actionId)?.symbolName ?? fallbackSymbolName
    }
}

struct LauncherWindowVisibilityPolicy {
    static func shouldHideLauncher(
        visibleMirroredWindowCount: Int,
        modelRequestsHide: Bool
    ) -> Bool {
        visibleMirroredWindowCount > 0 || modelRequestsHide
    }
}

enum PreviousAppsRestoreHandoffAction: Equatable {
    case prepareGuestAgentRecovery(shouldShowDisplay: Bool)
    case startRuntime
    case waitForRuntimeAvailability
}

struct PreviousAppsRestoreHandoffPolicy {
    static func action(
        runtimeState: VMRuntimeState?,
        canStartRuntime: Bool,
        supportsNativeDisplayWindow: Bool
    ) -> PreviousAppsRestoreHandoffAction {
        switch runtimeState {
        case .running, .starting:
            return .prepareGuestAgentRecovery(shouldShowDisplay: supportsNativeDisplayWindow)
        default:
            return canStartRuntime ? .startRuntime : .waitForRuntimeAvailability
        }
    }
}

enum LauncherReopenPolicy {
    enum Destination: Equatable {
        case mainWindow
        case windowsAppWindows
    }

    static func destination(
        visibleMirroredWindowCount: Int,
        modelRequestsHideLauncher: Bool
    ) -> Destination {
        guard visibleMirroredWindowCount > 0 else {
            return .mainWindow
        }

        return modelRequestsHideLauncher ? .windowsAppWindows : .mainWindow
    }
}

@MainActor
private enum MainWindowChrome {
    static func configureAndCompactMainWindow() {
        let windows = mainWindows
        guard let window = windows.first else {
            return
        }

        for duplicate in windows.dropFirst() {
            duplicate.close()
        }

        configure(window)
        fitToPreferredSize(window)
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        configureAndCompactMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hideMainWindow() {
        let windows = mainWindows
        guard let window = windows.first else {
            return
        }

        for duplicate in windows.dropFirst() {
            duplicate.close()
        }

        window.orderOut(nil)
    }

    private static var mainWindow: NSWindow? {
        mainWindows.first
    }

    static var hasMainWindow: Bool {
        !mainWindows.isEmpty
    }

    static func launchReport(appIconSource: AppIconSource) -> MainWindowLaunchReport {
        let windows = mainWindows
        let window = windows.first
        return MainWindowLaunchReport(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            activationPolicy: activationPolicyName(NSApp.activationPolicy()),
            mainWindowCount: windows.count,
            visibleMainWindowCount: windows.filter(\.isVisible).count,
            duplicateMainWindowCount: max(0, windows.count - 1),
            isAppActive: NSApp.isActive,
            isMainWindowKey: window?.isKeyWindow ?? false,
            frame: MainWindowFrameReport(window?.frame ?? .zero),
            minWidth: Double(window?.minSize.width ?? .zero),
            minHeight: Double(window?.minSize.height ?? .zero),
            titlebarAppearsTransparent: window?.titlebarAppearsTransparent ?? false,
            hasFullSizeContentView: window?.styleMask.contains(.fullSizeContentView) ?? false,
            appIconSource: appIconSource
        )
    }

    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier?.rawValue == "main"
        }
    }

    private static func configure(_ window: NSWindow) {
        window.minSize = NSSize(width: 1180, height: 760)
        window.maxSize = NSSize(width: 2048, height: 1536)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    }

    private static func fitToPreferredSize(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let preferredSize = NSSize(width: 1440, height: 900)
        let targetSize = NSSize(
            width: min(preferredSize.width, visibleFrame.width * 0.96),
            height: min(preferredSize.height, visibleFrame.height * 0.96)
        )
        let sizeDelta = abs(window.frame.width - targetSize.width) + abs(window.frame.height - targetSize.height)
        guard sizeDelta > 16 else {
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: targetSize), display: true, animate: false)
    }

    private static func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }
}

private struct StandaloneMainWindowRoot: View {
    private let vmRuntimeBooter: QEMUVMRuntimeBooter
    @State private var model: HostDashboardModel
    @State private var vmModel: VMRuntimeModel
    @State private var displayMessage: String?

    init() {
        let runtimeBooter = AppRuntimeBooterFactory.make()
        let transport = URLSessionWebSocketTransport(
            url: URL(string: Self.agentURLString)!
        )
        self.vmRuntimeBooter = runtimeBooter
        _model = State(
            initialValue: HostDashboardModel(
                service: FallbackHostDashboardService(
                    primary: VeilHostClient(transport: transport),
                    fallback: DemoHostDashboardService(),
                    primaryEndpointDescription: Self.agentURLString
                )
            )
        )
        _vmModel = State(
            initialValue: VMRuntimeModel(
                service: LocalVMRuntimeService(bootRunner: runtimeBooter)
            )
        )
    }

    var body: some View {
        ContentView(
            model: model,
            vmModel: vmModel,
            startVMAction: startWindowsAndShowDisplay,
            stopVMAction: stopWindowsAndCloseDisplay,
            markWindowsInstalledAction: markWindowsInstalledFromSetup,
            installGuestAgentAction: installGuestAgentFromDisplay,
            prepareSparsePackageAction: prepareSparsePackageFromDisplay,
            waitForGuestAgentAction: waitForGuestAgent,
            repairGuestAgentForAppLaunchAction: installGuestAgentFromDisplay,
            recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
            launchWindowsAppAction: launchSelectedWindowsApp,
            fulfillPendingLaunchAction: launchSelectedWindowsApp,
            restoreWindowsAppWindowsAction: {},
            closeAllWindowsAppWindowsAction: {},
            restartStaleFrameStreamsAction: {},
            requestNotificationConsentAction: {},
            runNotificationProofAction: {},
            runRecommendedProofAction: {},
            runMultiAppProofAction: {},
            quietWindowsWhenIdleAction: {},
            displayMessage: displayMessage
        )
        .frame(minWidth: 1120, idealWidth: 1440, minHeight: 700, idealHeight: 900)
        .task {
            async let hostLoad: Void = model.load()
            async let vmLoad: Void = vmModel.load()
            _ = await (hostLoad, vmLoad)
            await recordGuestAgentInstallEvidenceIfNeeded()
        }
    }

    private static var agentURLString: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

    private func startWindowsAndShowDisplay() {
        Task { @MainActor in
            displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = vmRuntimeBooter.supportsNativeDisplayWindow
                    ? "Windows is running in recovery display mode."
                    : "Windows is running inside the main Veil window. Setup evidence refreshes here."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows display could not start: \(errorMessage)"
            }
        }
    }

    private func stopWindowsAndCloseDisplay() {
        Task { @MainActor in
            await vmModel.stop()
            if vmModel.snapshot?.state == .stopped {
                displayMessage = "Windows display closed."
            }
        }
    }

    private func showWindowsDisplay() {
        if vmRuntimeBooter.showConsoleIfRunning() {
            displayMessage = "Recovery display brought forward."
        } else {
            displayMessage = "No recovery display is attached. Windows normally runs inside the main Veil window."
        }
    }

    private func installGuestAgentFromDisplay() {
        Task { @MainActor in
            displayMessage = "Sending the Veil app connection installer to Windows."
            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "App connection installer sent. Veil will connect when Windows is ready."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()
            } catch {
                displayMessage = "App connection install could not start: \(userMessage(for: error))"
            }
        }
    }

    private func prepareSparsePackageFromDisplay() {
        Task { @MainActor in
            displayMessage = "Preparing Windows package identity. Keep the Windows setup display open for prompts."
            do {
                _ = try await vmRuntimeBooter.prepareSparsePackageFromAttachedMedia()
                displayMessage = "Package identity preparation sent. Waiting for the Windows app connection to return."
                await vmModel.refreshRuntimeEvidence()

                let report = await model.waitForLiveAgentConnection(
                    endpoint: Self.agentURLString,
                    timeoutSeconds: 120
                )
                await recordGuestAgentInstallEvidenceIfNeeded()
                await model.load()

                if report.diagnostic.health?.capabilities.packageIdentity == true {
                    displayMessage = "Windows package identity is ready."
                } else if report.status == .connected {
                    displayMessage = "Windows reconnected, but package identity is not ready yet. Check sparse package evidence."
                } else {
                    displayMessage = "Package identity preparation was sent. Windows has not reconnected yet."
                }
            } catch {
                displayMessage = "Package identity preparation could not start: \(userMessage(for: error))"
            }
        }
    }

    private func waitForGuestAgent() {
        Task { @MainActor in
            displayMessage = "Checking the Windows app connection."
            let report = await model.waitForLiveAgentConnection(
                endpoint: Self.agentURLString,
                timeoutSeconds: 5
            )
            await recordGuestAgentInstallEvidenceIfNeeded()

            if report.status == .connected {
                displayMessage = "Windows app connection is ready."
            } else if let hostForwardProbe = report.diagnostic.hostForwardProbe {
                displayMessage = "Windows app connection is not ready yet (\(hostForwardProbe.status.rawValue))."
            } else {
                displayMessage = "Windows app connection is not ready yet."
            }
        }
    }

    private func markWindowsInstalledFromSetup() {
        Task { @MainActor in
            await vmModel.markWindowsInstalled()
            if vmModel.snapshot?.windowsInstalled == true {
                displayMessage = "Windows is marked installed. Veil will boot from the local disk and leave the installer ISO detached."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows install state could not be updated: \(errorMessage)"
            }
        }
    }

    private func recoverRuntimeDisplayEvidence() {
        Task { @MainActor in
            displayMessage = "Refreshing the embedded Windows display."
            await vmModel.refreshRuntimeEvidence()
            if vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .fresh {
                displayMessage = "Windows display evidence refreshed."
            } else {
                displayMessage = "Display still needs recovery. Open details or retry after Windows responds."
            }
        }
    }

    private func launchSelectedWindowsApp() {
        Task { @MainActor in
            await model.launchSelectedApp()
        }
    }

    private func recordGuestAgentInstallEvidenceIfNeeded() async {
        guard model.hasLiveAgentConnection,
              let agentVersion = model.health?.agentVersion,
              vmModel.snapshot?.profileName != nil,
              vmModel.snapshot?.installEvidence.kind != .guestAgent else {
            return
        }

        await vmModel.markGuestAgentConnected(agentVersion: agentVersion)
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
