import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct VMRuntimeView: View {
    @Environment(\.appRuntimeProvider) private var appRuntimeProvider
    @Bindable var model: VMRuntimeModel
    var guestAgentInstallEvidence: VMInstallEvidenceSummary?
    var agentDiagnostic: AgentConnectionDiagnostic?
    var canLaunchWindowsApp: Bool
    var canRequestWindowsAppLaunch: Bool
    var selectedWindowsAppName: String?
    var pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    var canFulfillPendingLaunch: Bool
    var pendingWindowsAppName: String?
    var activeMirrorSession: WindowMirrorSession?
    var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    var primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
    var oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    var launchOnboarding: WindowsAppRuntimeLaunchOnboardingStatus
    var recommendedProofKind: String?
    var recommendedProofCommand: String?
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var prepareSparsePackageAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var displayResizeAction: ((Int, Int) -> Void)?
    var displayMessage: String?
    @Binding var showsFullDesktop: Bool
    @Environment(ShellNavigation.self) private var navigation
    @State private var pathPicker: PathPicker?
    @State private var installSimulation = InstallSimulationState.idle
    @State private var showsStopConfirmation = false
    /// Timestamp owned by this host launch attempt, not the persisted console record.
    /// A nil value intentionally hides elapsed time when the app opens on an already-starting VM.
    @State private var runtimeStartAt: Date?

    var body: some View {
        @Bindable var navigation = navigation
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = model.snapshot, showsInstallationAssistant(for: snapshot) {
                InstallationAssistantView(
                    snapshot: snapshot,
                    isLoading: model.phase == .loading,
                    errorMessage: model.errorMessage,
                    diagnosticsURL: model.diagnosticsURL,
                    installerNeedsPickerAccess: needsInstallerPickerAccess(snapshot),
                    prepareDownloadedISO: prepareDownloadedISO,
                    chooseInstallerAction: {
                        // The download view may still be tearing down; let it finish before the picker.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            pathPicker = .installerAndStart
                        }
                    },
                    prepareAction: {
                        Task {
                            await model.prepareDefaultVM()
                        }
                    },
                    installAction: beginStartAction,
                    configureAction: { tab in
                        navigation.openConfiguration(tab)
                    },
                    refreshAction: {
                        Task {
                            await model.load()
                        }
                    },
                    saveAccountName: { name in
                        await model.updateWindowsAccountName(name)
                    }
                )
            } else if let snapshot = model.snapshot {
                WindowsSetupDisplayPanel(
                    snapshot: snapshot,
                    runtimeStartAt: runtimeStartAt,
                    guestAgentInstallEvidence: validGuestAgentEvidence(for: snapshot),
                    agentDiagnostic: agentDiagnostic,
                    statusText: model.statusText,
                    canStart: model.canStart,
                    canStop: model.canStop,
                    isLoading: model.phase == .loading,
                    errorMessage: model.errorMessage,
                    diagnosticsURL: model.diagnosticsURL,
                    displayMessage: displayMessage,
                    canShowDisplay: canShowDisplay(for: snapshot),
                    prepareAction: {
                        Task {
                            await model.prepareDefaultVM()
                        }
                    },
                    selectInstallerAction: {
                        pathPicker = .installerMedia
                    },
                    selectDriverAction: {
                        pathPicker = .driverMedia
                    },
                    primaryAction: {
                        let installEvidence = validGuestAgentEvidence(for: snapshot) ?? snapshot.installEvidence
                        let windowsReadyForApps = installEvidence.isInstalled

                        if WindowsRuntimeReadiness.shouldBlockAgentRepair(snapshot: snapshot) {
                            if canRecoverRuntimeDisplay(for: snapshot) {
                                recoverRuntimeDisplayAction()
                            } else {
                                requestStopAction()
                            }
                        } else if windowsReadyForApps && canFulfillPendingLaunch {
                            // A live guest agent is sufficient for the app path. The embedded
                            // console preview may be stale while HWND capture is healthy, so
                            // display recovery must never block a native app window launch.
                            fulfillPendingLaunchAction()
                        } else if WindowsAppLaunchCommandPolicy.prefersLaunchAsHero(
                            windowsInstalled: windowsReadyForApps,
                            hasSelectedApp: selectedWindowsAppName != nil
                        ) {
                            launchWindowsAppAction()
                        } else if windowsReadyForApps
                            && canRequestWindowsAppLaunch {
                            launchWindowsAppAction()
                        } else if windowsReadyForApps && pendingLaunch.willLaunchOnAgentReconnect && canShowDisplay(for: snapshot) {
                            repairGuestAgentForAppLaunchAction()
                        } else if windowsReadyForApps && canInstallGuestAgent(for: snapshot) {
                            installGuestAgentAction()
                        } else if canRecoverRuntimeDisplay(for: snapshot) {
                            recoverRuntimeDisplayAction()
                        } else if model.canStop {
                            requestStopAction()
                        } else if model.canStart {
                            beginStartAction()
                        } else if !snapshot.windowsInstalled && (snapshot.installerMediaPath == nil || needsInstallerPickerAccess(snapshot)) {
                            navigation.openWindowsDownload()
                        } else {
                            Task {
                                await model.prepareDefaultVM()
                            }
                        }
                    },
                    stopAction: requestStopAction,
                    markWindowsInstalledAction: markWindowsInstalledAction,
                    installGuestAgentAction: installGuestAgentAction,
                    prepareSparsePackageAction: prepareSparsePackageAction,
                    waitForGuestAgentAction: waitForGuestAgentAction,
                    repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                    recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                    showWindowsDisplayAction: showWindowsDisplayAction,
                    launchWindowsAppAction: launchWindowsAppAction,
                    fulfillPendingLaunchAction: fulfillPendingLaunchAction,
                    restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
                    closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
                    restartStaleFrameStreamsAction: restartStaleFrameStreamsAction,
                    requestNotificationConsentAction: requestNotificationConsentAction,
                    runNotificationProofAction: runNotificationProofAction,
                    canLaunchWindowsApp: canLaunchWindowsApp,
                    canRequestWindowsAppLaunch: canRequestWindowsAppLaunch,
                    selectedWindowsAppName: selectedWindowsAppName,
                    pendingLaunch: pendingLaunch,
                    canFulfillPendingLaunch: canFulfillPendingLaunch,
                    pendingWindowsAppName: pendingWindowsAppName,
                    activeMirrorSession: activeMirrorSession,
                    launchPlan: launchPlan,
                    primaryNextAction: primaryNextAction,
                    oneScreenUX: oneScreenUX,
                    launchOnboarding: launchOnboarding,
                    recommendedProofKind: recommendedProofKind,
                    recommendedProofCommand: recommendedProofCommand,
                    runRecommendedProofAction: runRecommendedProofAction,
                    runMultiAppProofAction: runMultiAppProofAction,
                    quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
                    displayResizeAction: displayResizeAction,
                    refreshAction: {
                        Task {
                            await model.load()
                        }
                    },
                    consolePointerTapAction: { normalizedX, normalizedY in
                        Task {
                            await model.sendConsolePointerTap(
                                normalizedX: normalizedX,
                                normalizedY: normalizedY
                            )
                        }
                    },
                    consoleKeyAction: { key in
                        Task {
                            await model.sendConsoleKey(key)
                        }
                    },
                    detailsAction: {
                        navigation.openConfiguration()
                    },
                    installSimulation: installSimulation,
                    showsFullDesktop: $showsFullDesktop
                )
            } else if let errorMessage = model.errorMessage {
                RuntimeLandingPanel(
                    title: "Windows 11",
                    subtitle: errorMessage,
                    primaryTitle: "Try Again",
                    primarySymbol: "arrow.clockwise",
                    secondaryTitle: "Set Up",
                    primaryAction: {
                        Task {
                            await model.load()
                        }
                    },
                    secondaryAction: {
                        Task {
                            await model.prepareDefaultVM()
                        }
                    }
                )
            } else {
                RuntimeLandingPanel(
                    title: "Windows 11",
                    subtitle: model.phase == .loading
                        ? "Opening Windows on this Mac."
                        : "Install and run Windows locally on this Mac.",
                    primaryTitle: model.phase == .loading ? "Loading..." : "Download Windows 11",
                    primarySymbol: model.phase == .loading ? "arrow.triangle.2.circlepath" : "arrow.down.circle",
                    secondaryTitle: "Refresh",
                    primaryAction: {
                        navigation.openWindowsDownload()
                    },
                    secondaryAction: {
                        Task {
                            await model.load()
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: Binding(
                get: { pathPicker != nil },
                set: { isPresented in
                    if !isPresented {
                        pathPicker = nil
                    }
                }
            ),
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handlePathImport(result)
        }
        .onChange(of: model.snapshot?.state) { _, state in
            updateDisplayHandoffProgress(for: state)
            if state != .starting {
                runtimeStartAt = nil
            }
        }
        .task(id: model.snapshot?.state) {
            await refreshRuntimeEvidenceWhileRunning()
        }
        .sheet(item: $navigation.presentedSheet) { destination in
            switch destination {
            case .settings:
                VMSettingsSheet(model: model, selectedTab: $navigation.configurationTab) { snapshot, policy, tab in
                    configurationContent(snapshot, tab: tab, canChangeResources: policy.canChangeResources)
                }
            case .windowsDownload:
                WindowsDownloadSheet(
                    prepareDownloadedISO: prepareDownloadedISO,
                    useExistingISO: {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            pathPicker = .installerAndStart
                        }
                    },
                    prefetchesDriverMedia: model.snapshot?.driverMediaPath == nil
                )
            }
        }
        .confirmationDialog(
            "Stop Windows?",
            isPresented: $showsStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Windows", role: .destructive) {
                stopVMAction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(stopConfirmationMessage)
        }
    }

    private func requestStopAction() {
        if WindowsRuntimeStopConfirmation.needsConfirmation(
            hasMirroredWindowsApp: activeMirrorSession != nil,
            hasQueuedLaunch: pendingLaunch.isQueued
        ) {
            showsStopConfirmation = true
        } else {
            stopVMAction()
        }
    }

    private var stopConfirmationMessage: String {
        WindowsRuntimeStopConfirmation.message(
            hasMirroredWindowsApp: activeMirrorSession != nil,
            hasQueuedLaunch: pendingLaunch.isQueued
        )
    }

    private func canShowDisplay(for snapshot: VMRuntimeSnapshot) -> Bool {
        snapshot.state == .running || snapshot.state == .starting
    }

    func canInstallGuestAgent(for snapshot: VMRuntimeSnapshot) -> Bool {
        canShowDisplay(for: snapshot)
            && !WindowsRuntimeReadiness.shouldBlockAgentRepair(snapshot: snapshot)
            && (validGuestAgentEvidence(for: snapshot) ?? snapshot.installEvidence).kind != .guestAgent
    }

    /// A guest health response is not a local VM installation record. Do not let a
    /// stale/demo agent response make the shell look like Windows is installed when
    /// the local profile and disk are absent.
    private func validGuestAgentEvidence(for snapshot: VMRuntimeSnapshot) -> VMInstallEvidenceSummary? {
        guard snapshot.profileName != nil else {
            return nil
        }

        return guestAgentInstallEvidence
    }

    func canRecoverRuntimeDisplay(for snapshot: VMRuntimeSnapshot) -> Bool {
        guard canShowDisplay(for: snapshot) else {
            return false
        }

        if WindowsRuntimeReadiness.shouldBlockAgentRepair(snapshot: snapshot) {
            return true
        }

        return snapshot.latestConsoleLaunch?.previewStatus == .stale
            || snapshot.latestConsoleLaunch?.previewStatus == .unavailable
    }

    private func refreshRuntimeEvidenceWhileRunning() async {
        while !Task.isCancelled {
            guard model.snapshot?.state == .running || model.snapshot?.state == .starting else {
                return
            }

            if model.phase != .loading {
                await model.refreshRuntimeEvidence()
            }

            let refreshInterval: Duration = model.snapshot?.latestConsoleScreenshotPath == nil
                ? .seconds(3)
                : .seconds(1)
            try? await Task.sleep(for: refreshInterval)
        }
    }

    private func needsInstallerPickerAccess(_ snapshot: VMRuntimeSnapshot) -> Bool {
        snapshot.preflightChecks.contains { check in
            check.id == "installer-media" && check.detail.contains("Re-select it with the file picker")
        }
    }

    /// The assistant owns every step before Windows Setup first boots. Once the machine is live,
    /// even mid-setup, the Windows display takes over.
    private func showsInstallationAssistant(for snapshot: VMRuntimeSnapshot) -> Bool {
        let installEvidence = validGuestAgentEvidence(for: snapshot) ?? snapshot.installEvidence
        guard !installEvidence.isInstalled else {
            return false
        }

        switch snapshot.state {
        case .notConfigured, .stopped, .failed, .unsupported:
            return true
        case .starting, .running, .suspended:
            return false
        }
    }

    @ViewBuilder
    private func configurationContent(
        _ snapshot: VMRuntimeSnapshot,
        tab: MachineConfigurationTab,
        canChangeResources: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch tab {
            case .general:
                MachineSummaryPanel(snapshot: snapshot)
                StartupBehaviorPanel(snapshot: snapshot) { autoStart, suspendOnQuit in
                    Task {
                        await model.updateStartupBehavior(autoStart: autoStart, suspendOnQuit: suspendOnQuit)
                    }
                }
                RuntimeProvidersPanel(snapshot: snapshot)
            case .hardware:
                HardwareEditorPanel(snapshot: snapshot, canChangeResources: canChangeResources) { cpuCount, memoryMB in
                    Task {
                        await model.updateHardware(cpuCount: cpuCount, memoryMB: memoryMB)
                    }
                }
                ResourcePlanPanel(snapshot: snapshot)
                DevicePlanPanel(snapshot: snapshot)
            case .installation:
                SetupAssistantPanel(
                    snapshot: snapshot,
                    createProfileAction: {
                        Task {
                            await model.createDefaultProfile()
                        }
                    },
                    prepareAction: {
                        Task {
                            await model.prepareDefaultVM()
                        }
                    },
                    selectInstallerAction: {
                        pathPicker = .installerMedia
                    },
                    selectDiskAction: {
                        pathPicker = .virtualDisk
                    },
                    createDiskAction: {
                        Task {
                            await model.createDefaultVirtualDisk()
                        }
                    },
                    isLoading: model.phase == .loading,
                    canChangeResources: canChangeResources
                )

                if !snapshot.installationSteps.isEmpty {
                    ShellPanel(spacing: 10) {
                        ShellPanelHeader(
                            title: "Windows Setup",
                            subtitle: "Profile readiness steps for Arm Windows installation.",
                            symbolName: "checklist"
                        )

                        ForEach(snapshot.installationSteps) { step in
                            InstallationStepRow(step: step)
                        }
                    }
                }
            case .integration:
                MacIntegrationPanel(snapshot: snapshot)
            case .diagnostics:
                if snapshot.preflightChecks.isEmpty {
                    ContentUnavailableView(
                        "No Preflight Checks",
                        systemImage: "stethoscope",
                        description: Text("Checks appear once a Windows profile exists.")
                    )
                } else {
                    ShellPanel(spacing: 10) {
                        ShellPanelHeader(
                            title: "Preflight",
                            subtitle: "Local checks that must pass before VM start.",
                            symbolName: "stethoscope"
                        )

                        ForEach(snapshot.preflightChecks) { check in
                            PreflightCheckRow(check: check)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func handlePathImport(_ result: Result<[URL], any Error>) {
        guard let picker = pathPicker else {
            return
        }

        pathPicker = nil

        guard case .success(let urls) = result,
              let url = urls.first else {
            return
        }

        let path = url.path
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        let currentInstaller = model.snapshot?.installerMediaPath
        let currentDriver = model.snapshot?.driverMediaPath
        let currentDisk = model.snapshot?.virtualDiskPath

        Task {
            defer {
                if didStartSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            switch picker {
            case .installerMedia:
                await model.updateProfilePaths(
                    installerMediaPath: path,
                    driverMediaPath: currentDriver,
                    virtualDiskPath: currentDisk
                )
            case .installerAndStart:
                let isReadyToStart = await model.prepareWindowsInstallation(
                    installerMediaPath: path,
                    driverMediaPath: await driverMediaPathForInstall(current: currentDriver),
                    virtualDiskPath: currentDisk
                )
                guard isReadyToStart else {
                    return
                }

                beginWindowsSetupIfEngineCanRunIt()
            case .driverMedia:
                await model.updateProfilePaths(
                    installerMediaPath: currentInstaller,
                    driverMediaPath: path,
                    virtualDiskPath: currentDisk
                )
            case .virtualDisk:
                await model.updateProfilePaths(
                    installerMediaPath: currentInstaller,
                    driverMediaPath: currentDriver,
                    virtualDiskPath: path
                )
            }
        }
    }

    @MainActor
    private func prepareDownloadedISO(_ url: URL) async -> Bool {
        let isReadyToStart = await model.prepareWindowsInstallation(
            installerMediaPath: url.path,
            driverMediaPath: await driverMediaPathForInstall(current: model.snapshot?.driverMediaPath),
            virtualDiskPath: model.snapshot?.virtualDiskPath
        )
        guard isReadyToStart else {
            return false
        }

        beginWindowsSetupIfEngineCanRunIt()
        return true
    }

    /// A driver ISO the user chose stays; otherwise the install gets Fedora's virtio-win ISO, which
    /// the download sheet has usually fetched already. Without it Windows still installs, on
    /// `usb-net` and with no guest network, so a failed driver download is logged, not fatal.
    private func driverMediaPathForInstall(current: String?) async -> String? {
        if let current, !current.isEmpty {
            return current
        }

        do {
            return try await VirtioWinDriverMediaProvider.shared.ensureMedia().path
        } catch {
            VeilLog.runtime.error(
                "VirtIO driver media unavailable; installing without guest network drivers: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The prepared VM is a success either way; without an engine that runs Windows the assistant
    /// stays on its Install page, which explains what to install instead of booting a black display.
    @MainActor
    private func beginWindowsSetupIfEngineCanRunIt() {
        guard windowsEngineStatus.canRunWindows else {
            return
        }

        beginStartAction()
    }

    private var windowsEngineStatus: AppWindowEngineStatus {
        AppWindowEngineStatus.resolve(
            bootProvider: appRuntimeProvider,
            providers: model.snapshot?.runtimeProviders ?? []
        )
    }

    private func diagnosticsDirectory() -> URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    }

    @MainActor
    private func startDisplayHandoffProgress() {
        guard installSimulation.phase != .running else {
            return
        }

        installSimulation = .running(stepIndex: 2, progress: 0.42)
    }

    @MainActor
    private func beginStartAction() {
        runtimeStartAt = Date()
        startDisplayHandoffProgress()
        startVMAction()
    }

    @MainActor
    private func updateDisplayHandoffProgress(for state: VMRuntimeState?) {
        switch state {
        case .starting:
            installSimulation = .running(stepIndex: 3, progress: 0.66)
        case .running:
            // The handoff is over once Windows runs; a bar left at 100% "Checking Windows Setup
            // boot" read as a setup that never finished on a machine that is already installed.
            installSimulation = .idle
        case .failed, .stopped:
            installSimulation = .idle
        default:
            break
        }
    }

    var canOpenWindowsApp: Bool {
        canRequestWindowsAppLaunch || canFulfillPendingLaunch
    }
}

enum InstallSimulationPhase: Equatable {
    case idle
    case running
    case complete
}

struct InstallSimulationState: Equatable {
    var phase: InstallSimulationPhase
    var stepIndex: Int
    var progress: Double

    static let steps = [
        "Checking boot media",
        "Validating local VM profile",
        "Starting local Windows",
        "Attaching embedded preview",
        "Refreshing setup evidence",
        "Checking Windows Setup boot"
    ]

    static let idle = InstallSimulationState(phase: .idle, stepIndex: 0, progress: 0)
    static let complete = InstallSimulationState(phase: .complete, stepIndex: steps.count - 1, progress: 1)

    static func running(stepIndex: Int, progress: Double) -> InstallSimulationState {
        InstallSimulationState(
            phase: .running,
            stepIndex: min(max(stepIndex, 0), steps.count - 1),
            progress: min(max(progress, 0), 1)
        )
    }

    var currentStep: String {
        Self.steps[stepIndex]
    }
}

