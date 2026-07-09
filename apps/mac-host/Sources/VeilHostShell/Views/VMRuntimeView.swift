import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

struct VMRuntimeView: View {
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
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var displayMessage: String?
    @State private var pathPicker: PathPicker?
    @State private var showsAdvancedDetails = false
    @State private var installSimulation = InstallSimulationState.idle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = model.snapshot {
                WindowsSetupDisplayPanel(
                    snapshot: snapshot,
                    guestAgentInstallEvidence: guestAgentInstallEvidence,
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
                        if canFulfillPendingLaunch {
                            fulfillPendingLaunchAction()
                        } else if canRecoverRuntimeDisplay(for: snapshot) {
                            recoverRuntimeDisplayAction()
                        } else if canRequestWindowsAppLaunch {
                            launchWindowsAppAction()
                        } else if pendingLaunch.willLaunchOnAgentReconnect && canShowDisplay(for: snapshot) {
                            repairGuestAgentForAppLaunchAction()
                        } else if canInstallGuestAgent(for: snapshot) {
                            installGuestAgentAction()
                        } else if model.canStop {
                            stopVMAction()
                        } else if model.canStart {
                            startDisplayHandoffProgress()
                            startVMAction()
                        } else if !snapshot.windowsInstalled && (snapshot.installerMediaPath == nil || needsInstallerPickerAccess(snapshot)) {
                            pathPicker = .installerMedia
                        } else {
                            Task {
                                await model.prepareDefaultVM()
                            }
                        }
                    },
                    stopAction: stopVMAction,
                    markWindowsInstalledAction: markWindowsInstalledAction,
                    installGuestAgentAction: installGuestAgentAction,
                    waitForGuestAgentAction: waitForGuestAgentAction,
                    repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                    recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                    launchWindowsAppAction: launchWindowsAppAction,
                    fulfillPendingLaunchAction: fulfillPendingLaunchAction,
                    restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
                    closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
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
                    quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
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
                        showsAdvancedDetails.toggle()
                    },
                    isShowingDetails: showsAdvancedDetails,
                    installSimulation: installSimulation
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
                    primaryTitle: model.phase == .loading ? "Loading..." : "Choose Windows ISO",
                    primarySymbol: model.phase == .loading ? "arrow.triangle.2.circlepath" : "opticaldisc",
                    secondaryTitle: "Refresh",
                    primaryAction: {
                        pathPicker = .installerMedia
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
        }
        .task(id: model.snapshot?.state) {
            await refreshRuntimeEvidenceWhileRunning()
        }
        .popover(isPresented: $showsAdvancedDetails, arrowEdge: .bottom) {
            if let snapshot = model.snapshot {
                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            setupColumn(snapshot)
                                .frame(minWidth: 380)
                            runtimeDetailColumn(snapshot)
                                .frame(minWidth: 380)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            setupColumn(snapshot)
                            runtimeDetailColumn(snapshot)
                        }
                    }
                    .padding(18)
                }
                .frame(width: 860, height: 560)
            }
        }
    }

    private func canShowDisplay(for snapshot: VMRuntimeSnapshot) -> Bool {
        snapshot.state == .running || snapshot.state == .starting
    }

    private func canInstallGuestAgent(for snapshot: VMRuntimeSnapshot) -> Bool {
        canShowDisplay(for: snapshot)
            && (guestAgentInstallEvidence ?? snapshot.installEvidence).kind != .guestAgent
    }

    private func canRecoverRuntimeDisplay(for snapshot: VMRuntimeSnapshot) -> Bool {
        guard canShowDisplay(for: snapshot) else {
            return false
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

    @ViewBuilder
    private func setupColumn(_ snapshot: VMRuntimeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
                isLoading: model.phase == .loading
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func runtimeDetailColumn(_ snapshot: VMRuntimeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MachineSummaryPanel(snapshot: snapshot)

            RuntimeProvidersPanel(snapshot: snapshot)

            ResourcePlanPanel(snapshot: snapshot)

            DevicePlanPanel(snapshot: snapshot)

            MacIntegrationPanel(snapshot: snapshot)

            if !snapshot.preflightChecks.isEmpty {
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
    private func updateDisplayHandoffProgress(for state: VMRuntimeState?) {
        switch state {
        case .starting:
            installSimulation = .running(stepIndex: 3, progress: 0.66)
        case .running:
            installSimulation = .complete
        case .failed, .stopped:
            installSimulation = .idle
        default:
            break
        }
    }

    private var canOpenWindowsApp: Bool {
        canRequestWindowsAppLaunch || canFulfillPendingLaunch
    }
}

private enum InstallSimulationPhase: Equatable {
    case idle
    case running
    case complete
}

private struct InstallSimulationState: Equatable {
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

private struct SimpleRuntimePanel: View {
    var snapshot: VMRuntimeSnapshot
    var statusText: String
    var canStart: Bool
    var canStop: Bool
    var isLoading: Bool
    var errorMessage: String?
    var diagnosticsURL: URL?
    var displayMessage: String?
    var installSimulation: InstallSimulationState
    var primaryAction: () -> Void
    var chooseISOAction: () -> Void
    var displayAction: () -> Void
    var refreshAction: () -> Void
    var detailsAction: () -> Void
    var resetSimulationAction: () -> Void
    var runtimeTitle: String
    var runtimeSymbol: String
    var runtimeTint: Color

    var body: some View {
        ShellPanel(spacing: 20) {
            HStack(alignment: installSimulation.phase == .idle ? .center : .top, spacing: 22) {
                MachineBadge()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Windows 11 Arm")
                                .font(.largeTitle.weight(.semibold))
                                .lineLimit(1)
                            Text(summaryText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        StatusPill(title: runtimeTitle, symbolName: runtimeSymbol, tint: runtimeTint)
                    }

                    if installSimulation.phase == .idle {
                        setupStrip
                    } else {
                        InstallSimulationProgressView(
                            simulation: installSimulation,
                            resetAction: resetSimulationAction
                        )
                    }

                    if let displayMessage {
                        Label(displayMessage, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    HStack(spacing: 9) {
                        Button(action: primaryAction) {
                            Label(primaryTitle, systemImage: primarySymbol)
                                .frame(minWidth: 176)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(primaryDisabled)

                        if !canStart && !snapshot.windowsInstalled && installSimulation.phase == .idle {
                            Button(action: chooseISOAction) {
                                Label("Choose ISO", systemImage: "opticaldisc")
                            }
                            .disabled(isLoading)

                            Link(destination: Self.microsoftArmDownloadURL) {
                                Label("Get Windows", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(action: refreshAction) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(isLoading || installSimulation.phase == .running)
                        .help("Refresh")

                        Button(action: detailsAction) {
                            Label("Settings", systemImage: "gearshape")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(isLoading)
                        .help("Details")

                        Spacer()
                    }
                }
            }
        }
    }

    private static let microsoftArmDownloadURL = URL(string: "https://www.microsoft.com/en-us/software-download/windows11arm64")!

    private var setupStrip: some View {
        HStack(spacing: 18) {
            SetupStatusItem(
                title: "Windows ISO",
                detail: installerDetail,
                symbolName: "opticaldisc",
                state: installerState
            )
            SetupStatusItem(
                title: "Virtual Disk",
                detail: snapshot.virtualDiskPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not created",
                symbolName: "internaldrive",
                state: snapshot.virtualDiskPath == nil ? .pending : .complete
            )
            SetupStatusItem(
                title: "Auto Install",
                detail: answerFileDetail,
                symbolName: "text.document",
                state: snapshot.automaticInstallMediaPath == nil ? .pending : .complete
            )
            SetupStatusItem(
                title: "Install",
                detail: snapshot.bootReady ? "Can start" : "Needs setup",
                symbolName: "checkmark.seal",
                state: snapshot.bootReady ? .complete : .pending
            )
        }
    }

    private var installerDetail: String {
        if snapshot.windowsInstalled {
            return "Not required after install"
        }

        if let path = snapshot.installerMediaPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return "Not selected"
    }

    private var installerState: SetupStatusState {
        if snapshot.windowsInstalled {
            return .complete
        }

        if snapshot.installerMediaPath != nil {
            return .complete
        }

        return .pending
    }

    private var answerFileDetail: String {
        guard let path = snapshot.automaticInstallMediaPath else {
            return "Not prepared"
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var summaryText: String {
        switch snapshot.state {
        case .unsupported:
            return "This Mac cannot run the current Windows 11 Arm setup."
        case .notConfigured:
            return "Choose a Windows 11 Arm ISO, then prepare Windows."
        case .stopped:
            if installSimulation.phase == .complete {
                return "Windows start handoff finished. Start again if setup did not continue."
            }

            if snapshot.windowsInstalled {
                return "Start installed Windows from this main window."
            }

            return snapshot.bootReady ? "Start Windows setup from this main window." : statusText
        case .starting:
            return "Starting local Windows in the main Veil window."
        case .running:
            return "Windows is running locally. Open a Windows app once the app connection is ready."
        case .suspended:
            return "Windows is paused."
        case .failed:
            return "The last start attempt failed. Open details for diagnostics."
        }
    }

    private var primaryTitle: String {
        if canStop {
            return "Stop"
        }

        if canStart {
            switch installSimulation.phase {
            case .idle:
                return "Start Windows"
            case .running:
                return "Starting..."
            case .complete:
                return "Start Again"
            }
        }

        if !snapshot.windowsInstalled && snapshot.installerMediaPath == nil {
            return "Choose Windows ISO"
        }

        return snapshot.profileName == nil ? "Prepare Windows" : "Continue Setup"
    }

    private var primarySymbol: String {
        if canStop {
            return "stop.fill"
        }

        if canStart {
            return "play.fill"
        }

        if !snapshot.windowsInstalled && snapshot.installerMediaPath == nil {
            return "opticaldisc"
        }

        return "wand.and.stars"
    }

    private var primaryDisabled: Bool {
        if canStop {
            return isLoading || snapshot.state == .unsupported
        }

        return isLoading || snapshot.state == .unsupported || installSimulation.phase == .running
    }

    private var canShowDisplay: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }
}

private struct InstallSimulationProgressView: View {
    var simulation: InstallSimulationState
    var resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer()

                Text("\(Int(simulation.progress * 100))%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: simulation.progress)
                .tint(tint)
                .controlSize(.large)

            stepTimeline

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(simulation.currentStep)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if simulation.phase == .complete {
                    Button(action: resetAction) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset progress")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private var stepTimeline: some View {
        HStack(spacing: 7) {
            ForEach(InstallSimulationState.steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= simulation.stepIndex || simulation.phase == .complete ? tint : Color.secondary.opacity(0.22))
                    .frame(height: 6)
            }
        }
    }

    private var title: String {
        switch simulation.phase {
        case .idle:
            return "Windows preview ready"
        case .running:
            return "Starting Windows preview"
        case .complete:
            return "Windows preview attached"
        }
    }

    private var symbolName: String {
        switch simulation.phase {
        case .idle:
            return "wand.and.stars"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .complete:
            return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch simulation.phase {
        case .idle:
            return .blue
        case .running:
            return .blue
        case .complete:
            return .green
        }
    }
}

private struct MachineBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.blue.gradient)
            VStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 42, weight: .semibold))
                Text("11")
                    .font(.title.bold())
            }
            .foregroundStyle(.white)
        }
        .frame(width: 140, height: 140)
    }
}

private struct RuntimeLandingPanel: View {
    var title: String
    var subtitle: String
    var primaryTitle: String
    var primarySymbol: String
    var secondaryTitle: String
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.32, blue: 0.62),
                            Color(red: 0.06, green: 0.10, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            WindowsDisplayGrid()
                .opacity(0.16)

            VStack(spacing: 18) {
                WindowsLogoMark(size: 86)
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 38, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primarySymbol)
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: secondaryAction) {
                        Label(secondaryTitle, systemImage: secondaryTitle == "Refresh" ? "arrow.clockwise" : "wand.and.stars")
                    }
                    .controlSize(.large)
                }
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct WindowsEmbeddedDisplayPreview: View {
    var image: NSImage?
    var surface: VMConsoleDisplaySurface
    var path: String
    var revisionID: String
    var pointerTapAction: (Double, Double) -> Void
    var keyAction: (String) -> Void
    @State private var rfbDisplayModel = RFBEmbeddedDisplayModel()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black)

            if let renderedImage {
                Image(nsImage: renderedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(displayRevisionID)
            } else {
                WindowsDisplayGrid()
                    .opacity(0.10)
                Image(systemName: surface.kind == .vncLoopback ? "display.and.arrow.down" : "display")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }

            if surface.kind == .vncLoopback {
                VStack {
                    HStack {
                        Label(rfbDisplayModel.statusTitle(for: surface), systemImage: rfbDisplayModel.statusSymbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)
                .allowsHitTesting(false)
            }

            ConsolePreviewInputCaptureView(
                pointerTapAction: pointerTapAction,
                keyAction: keyAction
            )
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .help("Latest Windows display")
        .accessibilityLabel(surface.kind == .vncLoopback ? "Embedded Windows display endpoint" : "Latest Windows display screenshot")
        .accessibilityValue(surface.endpoint ?? path)
        .onAppear {
            rfbDisplayModel.connectIfNeeded(to: surface)
        }
        .onChange(of: surface.endpoint) { _, _ in
            rfbDisplayModel.connectIfNeeded(to: surface)
        }
        .onDisappear {
            rfbDisplayModel.stop()
        }
    }

    private var renderedImage: NSImage? {
        rfbDisplayModel.image ?? image
    }

    private var displayRevisionID: String {
        if let sequence = rfbDisplayModel.frameSequence {
            return "\(surface.endpoint ?? "rfb")#\(sequence)"
        }

        return revisionID
    }
}

private struct ConsolePreviewInputCaptureView: NSViewRepresentable {
    var pointerTapAction: (Double, Double) -> Void
    var keyAction: (String) -> Void

    func makeNSView(context: Context) -> ConsolePreviewInputCaptureNSView {
        let view = ConsolePreviewInputCaptureNSView()
        view.pointerTapAction = pointerTapAction
        view.keyAction = keyAction
        return view
    }

    func updateNSView(_ nsView: ConsolePreviewInputCaptureNSView, context: Context) {
        nsView.pointerTapAction = pointerTapAction
        nsView.keyAction = keyAction
    }
}

private final class ConsolePreviewInputCaptureNSView: NSView {
    var pointerTapAction: ((Double, Double) -> Void)?
    var keyAction: ((String) -> Void)?
    private let keyboardMapper = QEMUConsoleKeyboardInputMapper()

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPointerTap(event)
    }

    override func keyDown(with event: NSEvent) {
        if !sendKey(event) {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              sendKey(event) else {
            return super.performKeyEquivalent(with: event)
        }

        return true
    }

    private func sendPointerTap(_ event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let normalizedX = min(max(point.x / bounds.width, 0), 1)
        let normalizedY = min(max(1 - (point.y / bounds.height), 0), 1)
        pointerTapAction?(Double(normalizedX), Double(normalizedY))
    }

    private func sendKey(_ event: NSEvent) -> Bool {
        guard let key = keyboardMapper.key(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: qemuKeyboardModifiers(from: event)
        ) else {
            return false
        }

        keyAction?(key)
        return true
    }

    private func qemuKeyboardModifiers(from event: NSEvent) -> QEMUConsoleKeyboardModifier {
        let flags = event.modifierFlags
        var modifiers: QEMUConsoleKeyboardModifier = []

        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }

        return modifiers
    }
}

private enum SetupStatusState {
    case complete
    case attention
    case pending
}

private struct SetupStatusItem: View {
    var title: String
    var detail: String
    var symbolName: String
    var state: SetupStatusState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private var tint: Color {
        switch state {
        case .complete:
            return .green
        case .attention:
            return .blue
        case .pending:
            return .secondary
        }
    }
}

private struct QuickActionsPanel: View {
    var snapshot: VMRuntimeSnapshot
    var canStart: Bool
    var canStop: Bool
    var isLoading: Bool
    var startAction: () -> Void
    var stopAction: () -> Void
    var displayAction: () -> Void
    var refreshAction: () -> Void
    var prepareAction: () -> Void
    var createDiskAction: () -> Void
    var diagnosticsAction: () -> Void

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Quick Actions",
                subtitle: "Control Center actions stay visible while unavailable features remain gated.",
                symbolName: "square.grid.3x2"
            )

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 170), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ControlActionTile(
                    title: canStop ? "Stop" : "Start",
                    detail: canStop ? "Shut down Windows on this Mac." : (canStart ? "Start the configured Windows machine." : "Complete setup before starting Windows."),
                    symbolName: canStop ? "stop.fill" : "power",
                    tint: canStop ? .orange : .green,
                    state: (canStart || canStop) ? .ready : .blocked,
                    action: canStop ? stopAction : startAction
                )
                .disabled((!canStart && !canStop) || isLoading)

                ControlActionTile(
                    title: "Prepare Windows",
                    detail: snapshot.profileName == nil ? "Create the local profile, shared folder, install media, and default disk." : "Base Windows resources are ready.",
                    symbolName: "wand.and.stars",
                    tint: .blue,
                    state: snapshot.profileName == nil ? .ready : .partial,
                    action: prepareAction
                )
                .disabled(snapshot.profileName != nil || isLoading)

                ControlActionTile(
                    title: "Refresh",
                    detail: "Reload Windows setup and app connection state.",
                    symbolName: "arrow.clockwise",
                    tint: .blue,
                    state: isLoading ? .partial : .ready,
                    action: refreshAction
                )
                .disabled(isLoading)

                ControlActionTile(
                    title: "Create Disk",
                    detail: snapshot.virtualDiskPath == nil ? "Create the default 128 GB sparse disk." : "Default disk path is configured.",
                    symbolName: "internaldrive",
                    tint: .indigo,
                    state: snapshot.profileName == nil ? .blocked : (snapshot.virtualDiskPath == nil ? .ready : .partial),
                    action: createDiskAction
                )
                .disabled(snapshot.profileName == nil || snapshot.virtualDiskPath != nil || isLoading)

                ControlActionTile(
                    title: "Diagnostics",
                    detail: "Export profile, preflight, and host metadata for troubleshooting.",
                    symbolName: "doc.text.magnifyingglass",
                    tint: .orange,
                    state: .ready,
                    action: diagnosticsAction
                )
                .disabled(isLoading)

                ControlActionTile(
                    title: "Configure",
                    detail: "Advanced Windows settings follow boot validation.",
                    symbolName: "slider.horizontal.3",
                    tint: .blue,
                    state: .planned
                )

                ControlActionTile(
                    title: "Snapshots",
                    detail: "Checkpoints follow persistent Windows boot.",
                    symbolName: "camera.metering.matrix",
                    tint: .purple,
                    state: .planned
                )

                ControlActionTile(
                    title: "Shared Folders",
                    detail: snapshot.profileName == nil ? "Create a profile before sharing." : "Profile boundary is ready.",
                    symbolName: "folder",
                    tint: .teal,
                    state: snapshot.profileName == nil ? .blocked : .planned
                )
            }
        }
    }

    private var canShowDisplay: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }
}

private struct ControlCenterHero: View {
    var snapshot: VMRuntimeSnapshot
    var statusText: String
    var canStart: Bool
    var canStop: Bool
    var isLoading: Bool
    var startAction: () -> Void
    var stopAction: () -> Void
    var displayAction: () -> Void
    var refreshAction: () -> Void
    var runtimeTitle: String
    var runtimeSymbol: String
    var runtimeTint: Color

    var body: some View {
        ShellPanel(spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 34, weight: .semibold))
                        Text("11")
                            .font(.title.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Windows 11 Arm")
                                .font(.title2.weight(.semibold))
                            Text(statusText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        StatusPill(title: runtimeTitle, symbolName: runtimeSymbol, tint: runtimeTint)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 150), spacing: 10)
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        DashboardStat(title: "Architecture", value: snapshot.architecture, symbolName: "cpu", tint: .blue)
                        DashboardStat(title: "Provider", value: providerName(for: snapshot), symbolName: "bolt.horizontal", tint: snapshot.virtualizationAvailable ? .green : .orange)
                        DashboardStat(title: "Install", value: snapshot.bootReady ? "Can Start" : "Blocked", symbolName: snapshot.bootReady ? "checkmark.seal" : "lock", tint: snapshot.bootReady ? .green : .orange)
                        DashboardStat(title: "Profile", value: snapshot.profileName == nil ? "Missing" : "Configured", symbolName: "person.crop.rectangle.stack", tint: snapshot.profileName == nil ? .orange : .green)
                        DashboardStat(title: "Installer", value: installerStatusTitle, symbolName: "opticaldisc", tint: installerStatusTint)
                        DashboardStat(title: "Disk", value: snapshot.virtualDiskPath == nil ? "Missing" : "Selected", symbolName: "externaldrive", tint: snapshot.virtualDiskPath == nil ? .orange : .green)
                    }

                    HStack(spacing: 8) {
                        if canStop {
                            Button(action: stopAction) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)
                        } else if canStart {
                            Button(action: startAction) {
                                Label("Start", systemImage: "power")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)
                        } else {
                            Button(action: startAction) {
                                Label("Start", systemImage: "power")
                            }
                            .disabled(true)
                        }

                        Button(action: refreshAction) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading)

                        Button {} label: {
                            Label("Configure", systemImage: "slider.horizontal.3")
                        }
                        .disabled(true)
                        .help("Advanced configuration panels will follow the boot spike.")
                    }
                }
            }
        }
    }

    private var canShowDisplay: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }

    private var installerStatusTitle: String {
        if snapshot.windowsInstalled {
            return "Detached"
        }

        if snapshot.installerMediaPath != nil {
            return "Selected"
        }

        return "Missing"
    }

    private var installerStatusTint: Color {
        if snapshot.windowsInstalled {
            return .green
        }

        if snapshot.installerMediaPath != nil {
            return .green
        }

        return .orange
    }

    private func providerName(for snapshot: VMRuntimeSnapshot) -> String {
        snapshot.runtimeProvider?.displayName ?? (snapshot.virtualizationAvailable ? "Local" : "Unavailable")
    }
}

private struct WindowsSetupDisplayPanel: View {
    var snapshot: VMRuntimeSnapshot
    var guestAgentInstallEvidence: VMInstallEvidenceSummary?
    var agentDiagnostic: AgentConnectionDiagnostic?
    var statusText: String
    var canStart: Bool
    var canStop: Bool
    var isLoading: Bool
    var errorMessage: String?
    var diagnosticsURL: URL?
    var displayMessage: String?
    var canShowDisplay: Bool
    var prepareAction: () -> Void
    var selectInstallerAction: () -> Void
    var selectDriverAction: () -> Void
    var primaryAction: () -> Void
    var stopAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
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
    var runRecommendedProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var refreshAction: () -> Void
    var consolePointerTapAction: (Double, Double) -> Void
    var consoleKeyAction: (String) -> Void
    var detailsAction: () -> Void
    var isShowingDetails: Bool
    var installSimulation: InstallSimulationState
    @State private var showsAgentDiagnosticPopover = false
    @State private var showsFullDesktop = false

    var body: some View {
        Group {
            if effectiveInstallEvidence.isInstalled {
                installedLauncherStage
            } else {
                installProcessStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: snapshot.state) { _, newState in
            if newState != .running {
                showsFullDesktop = false
            }
        }
    }

    private var installedLauncherStage: some View {
        ZStack(alignment: .bottom) {
            launcherDisplaySurface

            launcherFooter
                .background(.black.opacity(0.18))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(10)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installProcessStage: some View {
        ZStack(alignment: .bottom) {
            installDisplaySurface

            installControlBar
                .background(.black.opacity(0.18))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var installDisplaySurface: some View {
        ZStack {
            if let displaySurface {
                WindowsEmbeddedDisplayPreview(
                    image: displayScreenshotImage,
                    surface: displaySurface,
                    path: snapshot.latestConsoleScreenshotPath ?? "",
                    revisionID: displayScreenshotRevisionID,
                    pointerTapAction: consolePointerTapAction,
                    keyAction: consoleKeyAction
                )
            } else {
                machineDisplay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var launcherDisplaySurface: some View {
        if showsFullDesktop, let displaySurface {
            WindowsEmbeddedDisplayPreview(
                image: displayScreenshotImage,
                surface: displaySurface,
                path: snapshot.latestConsoleScreenshotPath ?? "",
                revisionID: displayScreenshotRevisionID,
                pointerTapAction: consolePointerTapAction,
                keyAction: consoleKeyAction
            )
        } else {
            machineDisplay
        }
    }

    private var installControlBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controlBarTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(controlBarSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            if !canStop && snapshot.state != .starting {
                runtimeSetupMenu
            }

            Button(action: runEffectivePrimaryAction) {
                Label(effectivePrimaryTitle, systemImage: effectivePrimarySymbol)
                    .frame(minWidth: canStop ? 124 : 142)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(effectivePrimaryDisabled)

            runtimeActionButton
            runtimeMoreMenu
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var displayScreenshotImage: NSImage? {
        guard let path = snapshot.latestConsoleScreenshotPath else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }

    private var displaySurface: VMConsoleDisplaySurface? {
        if let surface = snapshot.latestConsoleLaunch?.displaySurface,
           surface.kind != .unavailable {
            return surface
        }

        guard let path = snapshot.latestConsoleScreenshotPath else {
            return nil
        }

        return VMConsoleDisplaySurface(
            kind: .screenshot,
            endpoint: nil,
            screenshotPath: path,
            isLiveCapable: false
        )
    }

    private var displayScreenshotRevisionID: String {
        let path = snapshot.latestConsoleScreenshotPath ?? "missing"
        let refreshedAt = snapshot.latestConsoleLaunch?.consoleScreenshotRefreshedAt?.timeIntervalSince1970 ?? 0
        return "\(path)#\(refreshedAt)"
    }

    private var machineDisplay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(machineHeroGradient)

            VStack(spacing: 16) {
                Spacer(minLength: 8)

                WindowsLogoMark(size: 82)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                VStack(spacing: 4) {
                    Text(machineTitle)
                        .font(.system(size: 34, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(machineSubtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }

                Button(action: runEffectivePrimaryAction) {
                    ZStack {
                        Circle()
                            .fill(effectivePrimaryDisabled ? Color.white.opacity(0.20) : Color.accentColor)
                        Image(systemName: effectivePrimarySymbol)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 74, height: 74)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(effectivePrimaryDisabled ? 0.12 : 0.34), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(effectivePrimaryDisabled)
                .help(effectivePrimaryHelp)

                Text(effectivePrimaryTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if effectiveInstallEvidence.isInstalled {
                    Label(launchOnboardingTitle, systemImage: launchOnboardingSymbolName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(launchOnboarding.canContinueInApp ? 0.88 : 0.68))
                        .lineLimit(1)
                        .help(launchOnboardingHelp)

                    Label(launchOnboardingDetail, systemImage: "arrow.forward.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(launchOnboarding.canContinueInApp ? 0.78 : 0.62))
                        .lineLimit(1)
                        .help(launchOnboarding.reason)

                    Label(launchOnboarding.progressLabel, systemImage: "checklist")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .help("App flow progress")

                    Label(oneScreenUXTitle, systemImage: oneScreenUXSymbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(oneScreenUX.usesSinglePrimarySurfaceFamily
                            && oneScreenUX.canRecoverFromMenuOrDock
                            && oneScreenUX.returnsToLauncherWhenNoAppWindows ? 0.70 : 0.92))
                        .lineLimit(1)
                        .help(oneScreenUX.reason)

                    Label(appAutomationTitle, systemImage: appAutomationSymbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(launchPlan.willOpenAppAutomatically ? 0.70 : 0.92))
                        .lineLimit(1)
                        .help(launchPlan.reason)
                }

                if installSimulation.phase != .idle {
                    AssistantProgressStrip(simulation: installSimulation)
                        .frame(maxWidth: 420)
                        .foregroundStyle(.primary)
                } else if effectiveInstallEvidence.isInstalled {
                    AppRuntimeProgressStrip(items: appOpenFlowItems)
                        .frame(maxWidth: 760)
                } else {
                    ProgressView(value: progressFraction)
                        .tint(progressTint)
                        .frame(maxWidth: 420)
                }

                Spacer(minLength: 8)
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var installPrimaryTitle: String {
        if canFulfillPendingLaunch {
            return "Open \(pendingAppDisplayName)"
        }

        if canRecoverRuntimeDisplay {
            return "Refresh Display"
        }

        if pendingLaunch.willLaunchOnAgentReconnect {
            switch snapshot.state {
            case .running, .starting:
                return "Repair App Connection"
            default:
                return "Continue Opening \(pendingAppDisplayName)"
            }
        }

        if canRequestWindowsAppLaunch {
            return selectedWindowsAppName.map { "Open \($0)" } ?? "Open Windows App"
        }

        if canInstallGuestAgent {
            return "Repair App Connection"
        }

        if canStop {
            return "Stop Windows"
        }

        if canStart {
            return installSimulation.phase == .running ? "Opening..." : installActionTitle
        }

        if snapshot.installerMediaPath == nil || installerNeedsFilePickerAccess {
            return "Choose ISO"
        }

        return snapshot.profileName == nil ? "Prepare Windows" : "Continue Setup"
    }

    private var launcherFooter: some View {
        HStack(spacing: 10) {
            ForEach(metadataItems) { item in
                LauncherMetadataChip(item: item)
            }

            Spacer(minLength: 12)

            horizontalActions
                .frame(minWidth: 300, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var horizontalActions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            runtimeActionButton

            if snapshot.state == .running {
                Button {
                    showsFullDesktop.toggle()
                } label: {
                    Label(
                        showsFullDesktop ? "Hide Desktop" : "Show Desktop",
                        systemImage: showsFullDesktop ? "macwindow" : "display"
                    )
                    .labelStyle(.iconOnly)
                }
                    .help(showsFullDesktop ? "Return to the Windows app launcher" : "Show the full Windows desktop instead of individual app windows")
            }

            runtimeMoreMenu
        }
    }

    @ViewBuilder
    private var runtimeSetupMenu: some View {
        Menu("Setup", systemImage: "gearshape.fill") {
            Button("Choose ISO", systemImage: "opticaldisc") {
                selectInstallerAction()
            }
            .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)

            Button("Choose Drivers", systemImage: "externaldrive.badge.gearshape") {
                selectDriverAction()
            }
            .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)

            Button("Prepare Windows", systemImage: "wand.and.stars") {
                prepareAction()
            }
            .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)
        }
        .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)
        .help("Show setup actions")
    }

    @ViewBuilder
    private var runtimeActionButton: some View {
        if canRecoverRuntimeDisplay {
            Button(action: recoverRuntimeDisplayAction) {
                Label("Refresh Display", systemImage: "display")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)
            .help("Refresh embedded Windows display evidence")
        } else if executablePrimaryNextActionRoute != nil {
            Button(action: runEffectivePrimaryAction) {
                Label(effectivePrimaryTitle, systemImage: effectivePrimarySymbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(effectivePrimaryDisabled)
            .help(effectivePrimaryHelp)
        } else if canOpenWindowsApp {
            Button(action: primaryAction) {
                Label(appDisplayName, systemImage: "macwindow.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)
            .help("Open Windows app")
        } else if canRepairGuestAgentForAppLaunch {
            Button(action: repairGuestAgentForAppLaunchAction) {
                Label("Continue \(pendingAppDisplayName)", systemImage: "bolt.horizontal.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)
            .help("Repair the Windows app connection and continue opening the queued app")
        }
    }

    @ViewBuilder
    private var runtimeMoreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            if canInstallGuestAgent {
                Button("Repair App Connection", systemImage: "app.badge") {
                    installGuestAgentAction()
                }
                .disabled(isLoading)
                .help("Repair the connection used to open Windows apps on your Mac")
            }

            if canWaitForGuestAgent {
                Button("Check App Connection", systemImage: "antenna.radiowaves.left.and.right") {
                    waitForGuestAgentAction()
                }
                .disabled(isLoading)
                .help("Wait for Windows app connection and refresh status")

                if let agentDiagnostic {
                    Button {
                        showsAgentDiagnosticPopover = true
                    } label: {
                        Label("Connection Details", systemImage: "info.circle")
                    }
                    .help("Show Windows app connection details")
                    .popover(isPresented: $showsAgentDiagnosticPopover, arrowEdge: .bottom) {
                        AgentDiagnosticPanel(diagnostic: agentDiagnostic)
                            .frame(width: 360)
                            .padding(14)
                    }
                }
            }

            Button("Refresh", systemImage: "arrow.clockwise") {
                refreshAction()
            }
            .disabled(isLoading)

            Button(isShowingDetails ? "Hide Details" : "Show Details", systemImage: "slider.horizontal.3") {
                detailsAction()
            }
            .disabled(isLoading)

            if !effectiveInstallEvidence.isInstalled {
                Button("Prepare Windows", systemImage: "wand.and.stars") {
                    prepareAction()
                }
                .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)

                Button("Choose ISO", systemImage: "opticaldisc") {
                    selectInstallerAction()
                }
                .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)

                Button("Choose Drivers", systemImage: "externaldrive.badge.gearshape") {
                    selectDriverAction()
                }
                .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)
            }

            if canMarkWindowsInstalled {
                Button("Mark Installed", systemImage: "checkmark.seal") {
                    markWindowsInstalledAction()
                }
                .disabled(isLoading)
            }

            if recommendedProofCommand != nil {
                Button("Check Windows App", systemImage: "checkmark.seal") {
                    runRecommendedProofAction()
                }
                .disabled(isLoading)
                .help("Run the strongest available Windows app check")
            }
        }
    }

    private var selectedInstallerName: String? {
        snapshot.installerMediaPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var selectedDriverName: String? {
        snapshot.driverMediaPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var controlBarTitle: String {
        if canStop {
            return "Windows is open"
        }

        if canStart {
            return "Windows 11"
        }

        return "Set up Windows 11"
    }

    private var controlBarSubtitle: String {
        if canStop {
            return effectiveInstallEvidence.isInstalled
                ? "Installed Windows disk"
                : (selectedInstallerName ?? "Local Windows display")
        }

        if effectiveInstallEvidence.isInstalled {
            return "Installer ISO detached after setup"
        }

        if installerNeedsFilePickerAccess, let selectedInstallerName {
            return "Re-select \(selectedInstallerName)"
        }

        if let selectedInstallerName {
            return selectedInstallerName
        }

        return "Choose a Windows 11 Arm ISO"
    }

    private var effectiveInstallEvidence: VMInstallEvidenceSummary {
        guestAgentInstallEvidence ?? snapshot.installEvidence
    }

    private var canInstallGuestAgent: Bool {
        canShowDisplay && effectiveInstallEvidence.kind != .guestAgent
    }

    private var canWaitForGuestAgent: Bool {
        canShowDisplay && guestAgentInstallEvidence == nil
    }

    private var canMarkWindowsInstalled: Bool {
        canShowDisplay && !effectiveInstallEvidence.isInstalled
    }

    private var installActionTitle: String {
        switch effectiveInstallEvidence.kind {
        case .setupReady:
            "Install Windows"
        default:
            "Install Windows"
        }
    }

    private var virtualDiskSummary: String {
        guard snapshot.virtualDiskPath != nil else {
            return "Not created"
        }

        if let allocatedBytes = snapshot.virtualDiskAllocatedBytes {
            return "\(formattedByteCount(allocatedBytes)) used"
        }

        return resourceName(from: snapshot.virtualDiskPath) ?? "Selected"
    }

    private var isVirtualDiskEmptyForWindowsInstall: Bool {
        guard snapshot.bootReady,
              !effectiveInstallEvidence.isInstalled,
              let allocatedBytes = snapshot.virtualDiskAllocatedBytes else {
            return false
        }

        return allocatedBytes < 1_024 * 1_024 * 1_024
    }

    private var flowItems: [InstallFlowItem] {
        let installerDetail: String
        let installerState: InstallFlowState
        if effectiveInstallEvidence.isInstalled {
            installerDetail = "Installed; ISO no longer required"
            installerState = .complete
        } else if let selectedInstallerName {
            installerDetail = installerNeedsFilePickerAccess ? "Re-select \(selectedInstallerName)" : selectedInstallerName
            installerState = installerNeedsFilePickerAccess ? .current : .complete
        } else {
            installerDetail = "Select the Windows 11 Arm ISO"
            installerState = .current
        }

        return [
            InstallFlowItem(
                title: "Windows ISO",
                detail: installerDetail,
                symbolName: "opticaldisc",
                state: installerState
            ),
            InstallFlowItem(
                title: "Virtual Disk",
                detail: snapshot.virtualDiskPath == nil
                    ? "Create a local 128 GB sparse disk"
                    : URL(fileURLWithPath: snapshot.virtualDiskPath ?? "").lastPathComponent,
                symbolName: "internaldrive",
                state: snapshot.virtualDiskPath == nil ? .pending : .complete
            ),
            InstallFlowItem(
                title: "Installer",
                detail: canShowDisplay
                    ? "Windows display is active in Veil"
                    : (canStart ? "Start Windows Setup" : "Waiting for preparation"),
                symbolName: "display",
                state: canShowDisplay ? .complete : (canStart ? .current : .pending)
            ),
            InstallFlowItem(
                title: "Mac Integration",
                detail: "Install Veil integration after Windows setup",
                symbolName: "macwindow.on.rectangle",
                state: snapshot.state == .running ? .current : .pending
            )
        ]
    }

    private var metadataItems: [LauncherMetadataItem] {
        WindowsShellCopy.installedLauncherMetadata(
            windowsIsRunning: snapshot.state == .running || snapshot.state == .starting,
            windowsCanStart: canStart,
            displayNeedsRefresh: canRecoverRuntimeDisplay,
            appValue: appMetadataValue,
            appTone: appMetadataTone,
            appConnectionReady: canLaunchWindowsApp || canFulfillPendingLaunch,
            appConnectionWaiting: pendingLaunch.isQueued || canRequestWindowsAppLaunch
        )
        .map { status in
            LauncherMetadataItem(
                title: status.title,
                value: status.value,
                symbolName: status.symbolName,
                tint: color(for: status.tone)
            )
        }
    }

    private var appMetadataValue: String {
        guard let activeMirrorSession else {
            if canFulfillPendingLaunch {
                return "Ready"
            }

            if pendingLaunch.willLaunchOnAgentReconnect {
                switch snapshot.state {
                case .running, .starting:
                    return "Connecting"
                default:
                    return "Queued"
                }
            }

            if canLaunchWindowsApp {
                return appDisplayName
            }

            return canRequestWindowsAppLaunch ? "Ready to queue" : "After connection"
        }

        return activeMirrorSession.latestFrame == nil ? "Opening" : "Mac Window"
    }

    private var appMetadataTint: Color {
        color(for: appMetadataTone)
    }

    private var appMetadataTone: WindowsShellStatusTone {
        guard let activeMirrorSession else {
            if canFulfillPendingLaunch {
                return .green
            }

            if pendingLaunch.isQueued {
                return .blue
            }

            if canLaunchWindowsApp {
                return .green
            }

            return canRequestWindowsAppLaunch ? .blue : .secondary
        }

        return activeMirrorSession.latestFrame == nil ? .orange : .green
    }

    private func color(for tone: WindowsShellStatusTone) -> Color {
        switch tone {
        case .green:
            .green
        case .blue:
            .blue
        case .orange:
            .orange
        case .secondary:
            .secondary
        }
    }

    private var appDisplayName: String {
        if pendingLaunch.isQueued {
            return pendingAppDisplayName
        }

        return selectedWindowsAppName ?? "Windows App"
    }

    private var pendingAppDisplayName: String {
        pendingWindowsAppName ?? "Windows App"
    }

    private var machineTitle: String {
        "Windows 11"
    }

    private var machineSubtitle: String {
        if let activeMirrorSession {
            return "\(activeMirrorSession.window.title) is open as a Mac window"
        }

        if canFulfillPendingLaunch {
            return "Open \(pendingAppDisplayName) as a Mac window"
        }

        if pendingLaunch.willLaunchOnAgentReconnect {
            switch snapshot.state {
            case .running, .starting:
                return "\(pendingAppDisplayName) will open when the app connection is ready"
            default:
                return "\(pendingAppDisplayName) is queued. Start Windows to continue"
            }
        }

        if canRequestWindowsAppLaunch {
            return "Open Windows apps from macOS"
        }

        if effectiveInstallEvidence.isInstalled {
            return effectiveInstallEvidence.kind == .guestAgent
                ? "App connection ready"
                : "Connect app integration to open Mac windows"
        }

        if snapshot.bootReady {
            return "Press play to start Windows in this window"
        }

        if installerNeedsFilePickerAccess {
            return "Re-select the ISO to grant macOS file access"
        }

        return "Bring your own Windows 11 Arm installer"
    }

    private var machineHeroGradient: LinearGradient {
        switch snapshot.state {
        case .running:
            LinearGradient(colors: [Color(red: 0.04, green: 0.34, blue: 0.24), Color(red: 0.03, green: 0.18, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .failed, .unsupported:
            LinearGradient(colors: [Color(red: 0.42, green: 0.18, blue: 0.08), Color(red: 0.15, green: 0.12, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [Color(red: 0.02, green: 0.32, blue: 0.62), Color(red: 0.08, green: 0.09, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func resourceName(from path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var primaryTitle: String {
        if canFulfillPendingLaunch {
            return "Open \(pendingAppDisplayName)"
        }

        if canRecoverRuntimeDisplay {
            return "Refresh Display"
        }

        if pendingLaunch.willLaunchOnAgentReconnect {
            switch snapshot.state {
            case .running, .starting:
                return "Repair App Connection"
            default:
                return "Continue Opening \(pendingAppDisplayName)"
            }
        }

        if canRequestWindowsAppLaunch {
            return "Open \(appDisplayName)"
        }

        if canInstallGuestAgent {
            return "Repair App Connection"
        }

        if canStop {
            return "Stop Windows"
        }

        if effectiveInstallEvidence.isInstalled {
            return "Start Windows"
        }

        if canStart {
            return installSimulation.phase == .running ? "Starting..." : "Start Windows"
        }

        if installerNeedsFilePickerAccess {
            return "Choose ISO"
        }

        return snapshot.profileName == nil ? "Prepare Windows" : "Continue Setup"
    }

    private var primarySymbol: String {
        if canRecoverRuntimeDisplay {
            return "display.trianglebadge.exclamationmark"
        }

        if canFulfillPendingLaunch || pendingLaunch.willLaunchOnAgentReconnect {
            return pendingLaunch.willLaunchOnAgentReconnect && !canFulfillPendingLaunch
                ? "bolt.horizontal.circle"
                : "macwindow.badge.plus"
        }

        if canRequestWindowsAppLaunch {
            return "macwindow.badge.plus"
        }

        if canInstallGuestAgent {
            return "person.crop.circle.badge.plus"
        }

        if canStop {
            return "stop.fill"
        }

        if canStart {
            return "play.fill"
        }

        if installerNeedsFilePickerAccess {
            return "opticaldisc"
        }

        return "wand.and.stars"
    }

    private var primaryHint: String {
        if canFulfillPendingLaunch {
            return "Open the queued \(pendingAppDisplayName) launch as a Mac-managed window."
        }

        if pendingLaunch.willLaunchOnAgentReconnect {
            switch snapshot.state {
            case .running, .starting:
                return "Windows is running; Veil is waiting for the app connection before opening \(pendingAppDisplayName)."
            default:
                return "Start Windows, wait for the app connection, then open \(pendingAppDisplayName)."
            }
        }

        if canRequestWindowsAppLaunch {
            return "Launch \(appDisplayName) as a Mac-managed window."
        }

        if canStop {
            return "Stop Windows on this Mac."
        }

        if effectiveInstallEvidence.isInstalled {
            return "Start Windows inside the main Veil window."
        }

        if canStart {
            return "Start Windows Setup inside Veil's embedded display."
        }

        if installerNeedsFilePickerAccess {
            return "Re-select the ISO so Veil can store macOS file access."
        }

        return "Create the profile, disk, shared folder, and install media."
    }

    private var primaryNextActionHelp: String {
        [
            primaryNextAction.reason,
            WindowsShellCopy.primaryActionHandoffDetail(runsInApp: primaryNextAction.runsInApp),
            primaryNextAction.command.map { "Command: \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var executablePrimaryNextActionRoute: LauncherPrimaryNextActionRoute? {
        guard effectiveInstallEvidence.isInstalled else {
            return nil
        }

        guard let route = LauncherPrimaryNextActionRoute.resolve(
            actionId: launchOnboarding.primaryActionId ?? launchOnboarding.currentStepId,
            command: launchOnboarding.primaryCommand,
            runsInApp: launchOnboarding.canContinueInApp
        ) else {
            return nil
        }

        return route
    }

    private var effectivePrimaryTitle: String {
        guard let route = executablePrimaryNextActionRoute else {
            return primaryTitle
        }

        switch route {
        case .launchSelectedApp:
            return selectedWindowsAppName.map { "Open \($0)" } ?? route.buttonTitle
        case .fulfillPendingLaunch:
            return "Open \(pendingAppDisplayName)"
        case .repairAppConnection:
            return "Continue \(pendingWindowsAppName ?? selectedWindowsAppName ?? "App")"
        case .startWindowsForApp:
            return selectedWindowsAppName.map { "Open \($0)" }
                ?? pendingWindowsAppName.map { "Open \($0)" }
                ?? route.buttonTitle
        default:
            return route.buttonTitle
        }
    }

    private var effectivePrimarySymbol: String {
        executablePrimaryNextActionRoute?.symbolName ?? primarySymbol
    }

    private var effectivePrimaryDisabled: Bool {
        if executablePrimaryNextActionRoute != nil {
            return primaryDisabled || !launchOnboarding.canContinueInApp
        }

        return primaryDisabled
    }

    private var effectivePrimaryHelp: String {
        executablePrimaryNextActionRoute == nil ? primaryTitle : launchOnboardingHelp
    }

    private func runEffectivePrimaryAction() {
        guard let route = executablePrimaryNextActionRoute else {
            primaryAction()
            return
        }

        switch route {
        case .launchSelectedApp:
            launchWindowsAppAction()
        case .fulfillPendingLaunch:
            fulfillPendingLaunchAction()
        case .recoverDisplay:
            recoverRuntimeDisplayAction()
        case .waitForAgent:
            waitForGuestAgentAction()
        case .repairAppConnection:
            repairGuestAgentForAppLaunchAction()
        case .startWindows:
            primaryAction()
        case .startWindowsForApp:
            launchWindowsAppAction()
        case .prepareWindows:
            prepareAction()
        case .refreshRuntimeStatus:
            refreshAction()
        case .reconnectPreviousApps:
            restoreWindowsAppWindowsAction()
        case .closeAllWindowsApps:
            closeAllWindowsAppWindowsAction()
        case .quietWindows:
            quietWindowsWhenIdleAction()
        case .runRecommendedProof:
            runRecommendedProofAction()
        }
    }

    private var oneScreenUXTitle: String {
        if primaryNextAction.runsInApp && !oneScreenUX.heroRunsPrimaryAction {
            return "Hero action needs attention"
        }

        if !oneScreenUX.canRecoverFromMenuOrDock {
            return "Recovery needs attention"
        }

        if !oneScreenUX.returnsToLauncherWhenNoAppWindows {
            return "Launcher fallback needs attention"
        }

        if oneScreenUX.mode == "windows-app-windows" {
            let count = oneScreenUX.expectedVisibleSurfaceCount
            return count == 1 ? "One Windows app surface" : "\(count) Windows app surfaces"
        }

        return "One launcher surface"
    }

    private var oneScreenUXSymbolName: String {
        oneScreenUX.usesSinglePrimarySurfaceFamily
            && oneScreenUX.canRecoverFromMenuOrDock
            && oneScreenUX.returnsToLauncherWhenNoAppWindows
            && (!primaryNextAction.runsInApp || oneScreenUX.heroRunsPrimaryAction)
            ? "rectangle.on.rectangle"
            : "exclamationmark.triangle"
    }

    private var launchOnboardingTitle: String {
        WindowsShellCopy.launchOnboardingTitle(
            state: launchOnboarding.state,
            canContinueInApp: launchOnboarding.canContinueInApp
        )
    }

    private var launchOnboardingDetail: String {
        WindowsShellCopy.launchOnboardingDetail(
            currentStepTitle: launchOnboarding.currentStepTitle,
            pendingLiveProof: launchOnboarding.pendingLiveProof
        )
    }

    private var launchOnboardingSymbolName: String {
        WindowsShellCopy.launchOnboardingSymbolName(
            state: launchOnboarding.state,
            canContinueInApp: launchOnboarding.canContinueInApp
        )
    }

    private var launchOnboardingHelp: String {
        [
            launchOnboarding.reason,
            WindowsShellCopy.launchOnboardingHandoffDetail(
                state: launchOnboarding.state,
                canContinueInApp: launchOnboarding.canContinueInApp
            ),
            launchOnboarding.primaryCommand.map { "Command: \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var appAutomationTitle: String {
        if launchPlan.willOpenAppAutomatically {
            return launchPlan.canLaunchSelectedAppNow ? "App opens now" : "App opens automatically"
        }

        if launchPlan.recommendedAction == "prepare-local-runtime" {
            return "Setup needed before app opens"
        }

        return "App open needs attention"
    }

    private var appAutomationSymbolName: String {
        launchPlan.willOpenAppAutomatically ? "bolt.circle" : "exclamationmark.triangle"
    }

    private var installerNeedsFilePickerAccess: Bool {
        snapshot.preflightChecks.contains { check in
            check.id == "installer-media" && check.detail.contains("Re-select it with the file picker")
        }
    }

    private var primaryDisabled: Bool {
        isLoading
            || snapshot.state == .unsupported
            || installSimulation.phase == .running
    }

    private var progressFraction: Double {
        if installSimulation.phase == .running {
            return installSimulation.progress
        }

        if effectiveInstallEvidence.isInstalled {
            let completed = appOpenFlowItems.filter { $0.state == .complete }.count
            return Double(completed) / Double(appOpenFlowItems.count)
        }

        let completed = flowItems.filter { $0.state == .complete }.count
        return Double(completed) / Double(flowItems.count)
    }

    private var phaseTint: Color {
        switch snapshot.state {
        case .running:
            .green
        case .starting:
            .blue
        case .stopped:
            snapshot.bootReady ? .green : .orange
        case .failed, .unsupported:
            .orange
        case .notConfigured, .suspended:
            .secondary
        }
    }

    private var progressTint: Color {
        installSimulation.phase == .running ? .blue : phaseTint
    }

    private var canOpenWindowsApp: Bool {
        canRequestWindowsAppLaunch || canFulfillPendingLaunch
    }

    private var canRepairGuestAgentForAppLaunch: Bool {
        pendingLaunch.willLaunchOnAgentReconnect
            && !canFulfillPendingLaunch
            && (snapshot.state == .running || snapshot.state == .starting)
    }

    private var canRecoverRuntimeDisplay: Bool {
        guard canShowDisplay else {
            return false
        }

        return snapshot.latestConsoleLaunch?.previewStatus == .stale
            || snapshot.latestConsoleLaunch?.previewStatus == .unavailable
    }

    private var appOpenFlowItems: [InstallFlowItem] {
        [
            InstallFlowItem(
                title: "Windows",
                detail: snapshot.state == .running || snapshot.state == .starting
                    ? "Running locally"
                    : "Start Windows",
                symbolName: "play.rectangle",
                state: snapshot.state == .running || snapshot.state == .starting ? .complete : .current
            ),
            InstallFlowItem(
                title: "App Connection",
                detail: agentFlowDetail,
                symbolName: "bolt.horizontal.circle",
                state: agentFlowState
            ),
            InstallFlowItem(
                title: "App Window",
                detail: activeMirrorSession?.window.title
                    ?? (pendingLaunch.isQueued ? pendingAppDisplayName : appDisplayName),
                symbolName: "macwindow",
                state: appWindowFlowState
            ),
            InstallFlowItem(
                title: "App Check",
                detail: proofGateDetail,
                symbolName: "checkmark.seal",
                state: proofGateState
            )
        ]
    }

    private var agentFlowDetail: String {
        if canLaunchWindowsApp || canFulfillPendingLaunch {
            return "Connected"
        }

        if pendingLaunch.isQueued {
            return "Waiting for reconnect"
        }

        if canRequestWindowsAppLaunch {
            return snapshot.state == .running || snapshot.state == .starting
                ? "Repair before launch"
                : "Start before launch"
        }

        return "Waiting for app catalog"
    }

    private var agentFlowState: InstallFlowState {
        if canLaunchWindowsApp || canFulfillPendingLaunch {
            return .complete
        }

        if pendingLaunch.isQueued || canRequestWindowsAppLaunch {
            return snapshot.state == .running || snapshot.state == .starting ? .current : .pending
        }

        return .pending
    }

    private var appWindowFlowState: InstallFlowState {
        if activeMirrorSession != nil {
            return .complete
        }

        if canLaunchWindowsApp || canFulfillPendingLaunch {
            return .current
        }

        if pendingLaunch.isQueued || canRequestWindowsAppLaunch {
            return .pending
        }

        return .pending
    }

    private var proofGateState: InstallFlowState {
        guard recommendedProofCommand != nil else {
            return activeMirrorSession != nil ? .current : .pending
        }

        return recommendedProofKind == "mvp" ? .complete : .current
    }

    private var proofGateDetail: String {
        guard recommendedProofCommand != nil else {
            return activeMirrorSession != nil ? "Ready to check" : "Waiting for app"
        }

        switch recommendedProofKind {
        case "mvp":
            return "Full app check ready"
        case "coherence":
            return "Input check ready"
        case "app-window":
            return "Window check ready"
        default:
            return "App check ready"
        }
    }
}

private struct WindowsLogoMark: View {
    var size: CGFloat

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
            }
            GridRow {
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct WindowsDisplayGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let spacing: CGFloat = 42
                var x: CGFloat = spacing
                while x < proxy.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    x += spacing
                }

                var y: CGFloat = spacing
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct InstallStatusSummary: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 168, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct InstallRecoveryActionsPanel: View {
    var actions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Recovery Steps", systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(.white.opacity(0.16), in: Circle())

                        Text(action)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct WindowsDisplayLaunchEvidenceStrip: View {
    var evidence: VMConsoleLaunchEvidence

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 26, height: 26)
                .background(.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(previewTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(previewTint)

                Text(displaySummary)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let pid = evidence.pid {
                Text("PID \(pid)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .help(helpText)
    }

    private var displaySummary: String {
        let logName = URL(fileURLWithPath: evidence.processLogPath).lastPathComponent
        let liveEndpoint = evidence.vncHost.flatMap { host in
            evidence.vncPort.map { "\(host):\($0)" }
        }
        if let refreshedAt = evidence.consoleScreenshotRefreshedAt {
            let refreshed = refreshedAt.formatted(date: .omitted, time: .shortened)
            if let liveEndpoint {
                return "Preview refreshed \(refreshed) · VNC \(liveEndpoint)"
            }
            return "Preview refreshed \(refreshed) · \(logName)"
        }

        let startedAt = evidence.startedAt.formatted(date: .omitted, time: .shortened)
        if let liveEndpoint {
            return "\(evidence.provider) live endpoint \(liveEndpoint) · started \(startedAt)"
        }
        return "\(evidence.provider) started \(startedAt) · \(logName)"
    }

    private var previewTitle: String {
        switch evidence.previewStatus {
        case .fresh:
            return "Preview Live"
        case .stale:
            return "Preview Stale"
        case .unavailable:
            return "Preview Pending"
        }
    }

    private var previewTint: Color {
        switch evidence.previewStatus {
        case .fresh:
            return .green
        case .stale:
            return .orange
        case .unavailable:
            return .secondary
        }
    }

    private var helpText: String {
        [
            "Log: \(evidence.processLogPath)",
            "Monitor: \(evidence.monitorSocketPath)",
            evidence.qmpSocketPath.map { "QMP: \($0)" },
            evidence.vncHost.flatMap { host in evidence.vncPort.map { "VNC: \(host):\($0)" } },
            evidence.consoleScreenshotPath.map { "Screenshot: \($0)" },
            "Preview status: \(evidence.previewStatus.rawValue)",
            evidence.consoleScreenshotRefreshedAt.map { "Screenshot refreshed: \($0.formatted(date: .abbreviated, time: .standard))" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

private struct LauncherMetadataItem: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var symbolName: String
    var tint: Color
}

private struct LauncherMetadataChip: View {
    var item: LauncherMetadataItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 24, height: 24)
                .background(item.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: 138, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct AssistantProgressStrip: View {
    var simulation: InstallSimulationState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(simulation.currentStep, systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int(simulation.progress * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: simulation.progress)
                .tint(.blue)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AppRuntimeProgressStrip: View {
    var items: [InstallFlowItem]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: item.state))
                        .frame(width: 22, height: 22)
                        .background(tint(for: item.state).opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(item.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(backgroundOpacity(for: item.state)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
            }
        }
    }

    private func tint(for state: InstallFlowState) -> Color {
        switch state {
        case .complete:
            return .green
        case .current:
            return .blue
        case .pending:
            return .white.opacity(0.58)
        }
    }

    private func backgroundOpacity(for state: InstallFlowState) -> Double {
        switch state {
        case .complete:
            return 0.14
        case .current:
            return 0.18
        case .pending:
            return 0.08
        }
    }
}

private enum InstallFlowState {
    case complete
    case current
    case pending
}

private struct InstallFlowItem: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbolName: String
    var state: InstallFlowState
}

private struct DevicePlanPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Device Plan",
                subtitle: "Local runtime devices Veil will attach at boot.",
                symbolName: "cpu"
            )

            if let deviceSummary = snapshot.deviceSummary {
                ResourcePlanRow(
                    title: "Boot",
                    value: "\(deviceSummary.platform) platform with \(deviceSummary.bootLoader) boot.",
                    symbolName: "power",
                    state: .ready
                )
                ResourcePlanRow(
                    title: "Storage",
                    value: storageValue(for: deviceSummary.storageDevices),
                    symbolName: "externaldrive.connected.to.line.below",
                    state: snapshot.virtualDiskPath == nil ? .blocked : .partial
                )
                ResourcePlanRow(
                    title: "Network",
                    value: "\(deviceSummary.networkMode) shared networking.",
                    symbolName: "network",
                    state: .ready
                )
                ResourcePlanRow(
                    title: "Graphics",
                    value: "\(deviceSummary.graphics.widthInPixels)x\(deviceSummary.graphics.heightInPixels) Apple Virtio scanout; Windows installer display is still experimental.",
                    symbolName: "display",
                    state: .partial
                )
                ResourcePlanRow(
                    title: "Input",
                    value: deviceSummary.inputDevices.joined(separator: ", "),
                    symbolName: "keyboard",
                    state: .ready
                )
            } else {
                ResourcePlanRow(
                    title: "Devices",
                    value: "Create a VM profile to inspect the boot device plan.",
                    symbolName: "rectangle.stack.badge.plus",
                    state: .blocked
                )
            }
        }
    }

    private func storageValue(for storageDevices: [VMRuntimeStorageDeviceSummary]) -> String {
        let readableDevices = storageDevices.map { device in
            "\(device.role): \(device.attachment)\(device.readOnly ? " read-only" : " writable")"
        }
        return readableDevices.joined(separator: "; ")
    }
}

private struct ResourcePlanPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Resource Plan",
                subtitle: "The local Windows resource model Veil applies and hardens through the boot spike.",
                symbolName: "gauge.with.dots.needle.50percent"
            )

            ResourcePlanRow(
                title: "CPU",
                value: cpuValue,
                symbolName: "cpu",
                state: snapshot.cpuCount == nil ? (snapshot.virtualizationAvailable ? .planned : .blocked) : .ready
            )
            ResourcePlanRow(
                title: "Memory",
                value: memoryValue,
                symbolName: "memorychip",
                state: snapshot.memoryMB == nil ? .planned : .ready
            )
            ResourcePlanRow(
                title: "Embedded Display",
                value: "Retina-scaled desktop and seamless app windows are planned.",
                symbolName: "display",
                state: .planned
            )
            ResourcePlanRow(
                title: "Storage",
                value: storageValue,
                symbolName: "internaldrive",
                state: snapshot.virtualDiskPath == nil ? .blocked : .partial
            )
        }
    }

    private var cpuValue: String {
        guard snapshot.virtualizationAvailable else {
            return "Host virtualization unavailable"
        }

        guard let cpuCount = snapshot.cpuCount else {
            return "Adaptive CPU profile will be applied during VM preparation."
        }

        return "\(cpuCount) vCPU configured on the local runtime provider."
    }

    private var memoryValue: String {
        guard let memoryMB = snapshot.memoryMB else {
            return "Adaptive memory cap will be applied during VM preparation."
        }

        return "\(formatGigabytes(memoryMB)) GB adaptive memory cap configured."
    }

    private var storageValue: String {
        guard let diskGB = snapshot.diskGB else {
            return "128 GB sparse disk profile will be applied during VM preparation."
        }

        if snapshot.virtualDiskPath == nil {
            return "\(diskGB) GB sparse disk profile configured; create or select a disk before boot."
        }

        return "\(diskGB) GB sparse virtual disk profile selected."
    }

    private func formatGigabytes(_ memoryMB: Int) -> String {
        let gigabytes = Double(memoryMB) / 1_024
        if gigabytes.rounded() == gigabytes {
            return String(Int(gigabytes))
        }

        return String(format: "%.1f", gigabytes)
    }
}

private struct SetupAssistantPanel: View {
    var snapshot: VMRuntimeSnapshot
    var createProfileAction: () -> Void
    var prepareAction: () -> Void
    var selectInstallerAction: () -> Void
    var selectDiskAction: () -> Void
    var createDiskAction: () -> Void
    var isLoading: Bool

    private var items: [SetupItem] {
        [
            SetupItem(
                title: "VM Profile",
                detail: snapshot.profileName ?? "Create a default Windows 11 Arm profile.",
                symbolName: "rectangle.stack.badge.person.crop",
                isComplete: snapshot.profileName != nil
            ),
            SetupItem(
                title: "Installer Media",
                detail: installerMediaDetail,
                symbolName: "opticaldisc",
                isComplete: snapshot.windowsInstalled || snapshot.installerMediaPath != nil
            ),
            SetupItem(
                title: "Virtual Disk",
                detail: snapshot.virtualDiskPath ?? "Select or create the virtual disk path.",
                symbolName: "externaldrive",
                isComplete: snapshot.virtualDiskPath != nil
            ),
            SetupItem(
                title: "Preflight",
                detail: snapshot.bootReady ? "All local checks are passing." : snapshot.detail,
                symbolName: "checklist",
                isComplete: snapshot.bootReady
            )
        ]
    }

    private var completedCount: Int {
        items.filter(\.isComplete).count
    }

    private var installerMediaDetail: String {
        if snapshot.windowsInstalled {
            return "Windows is installed; installer media is no longer required."
        }

        if let path = snapshot.installerMediaPath {
            return path
        }

        return "Choose a Windows 11 Arm ISO. Veil will not scan Downloads automatically."
    }

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Install Assistant",
                subtitle: "A compact path from profile creation to Windows 11 Arm boot readiness.",
                symbolName: "wand.and.stars"
            )

            SetupProgressBar(completed: completedCount, total: items.count)

            ForEach(items) { item in
                SetupItemRow(item: item)
            }

            HStack(spacing: 8) {
                if snapshot.profileName == nil {
                    Button(action: prepareAction) {
                        Label("Prepare", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Button(action: createProfileAction) {
                        Label("Profile Only", systemImage: "plus.circle")
                    }
                    .disabled(isLoading)
                }

                if !snapshot.windowsInstalled {
                    Button(action: selectInstallerAction) {
                        Label("Installer", systemImage: "opticaldisc")
                    }
                    .disabled(snapshot.profileName == nil || isLoading)
                }

                Button(action: selectDiskAction) {
                    Label("Disk", systemImage: "externaldrive")
                }
                .disabled(snapshot.profileName == nil || isLoading)

                if snapshot.profileName != nil && snapshot.virtualDiskPath == nil {
                    Button(action: createDiskAction) {
                        Label("Create Disk", systemImage: "internaldrive")
                    }
                    .disabled(isLoading)
                }

                Spacer()
            }
        }
    }
}

private struct MachineSummaryPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            HStack(alignment: .center) {
                ShellPanelHeader(
                    title: "Machine Summary",
                    subtitle: "Control Center identity and managed resources.",
                    symbolName: "rectangle.stack"
                )

                Spacer()

                StatusPill(
                    title: snapshot.profileName == nil ? "New" : "Managed",
                    symbolName: snapshot.profileName == nil ? "plus.circle" : "checkmark.circle.fill",
                    tint: snapshot.profileName == nil ? .secondary : .green
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ShellMetricRow(label: "Machine", value: "Windows 11 Arm")
                ShellMetricRow(label: "Profile", value: snapshot.profileName ?? "Not configured")
                ShellMetricRow(label: "CPU", value: snapshot.cpuCount.map { "\($0) vCPU" } ?? "Adaptive")
                ShellMetricRow(label: "Memory", value: snapshot.memoryMB.map { "\(formatGigabytes($0)) GB cap" } ?? "Adaptive")
                ShellMetricRow(label: "Disk Size", value: snapshot.diskGB.map { "\($0) GB" } ?? "Adaptive")
                ShellMetricRow(label: "Installer", value: installerResourceName, monospaced: snapshot.installerMediaPath != nil)
                ShellMetricRow(label: "Disk", value: resourceName(from: snapshot.virtualDiskPath), monospaced: snapshot.virtualDiskPath != nil)
                ShellMetricRow(label: "Runtime", value: snapshot.detail)
            }
        }
    }

    private func resourceName(from path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "Not selected"
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var installerResourceName: String {
        if snapshot.windowsInstalled {
            return "Not required after install"
        }

        if let selected = snapshot.installerMediaPath {
            return resourceName(from: selected)
        }

        return "Not selected"
    }

    private func formatGigabytes(_ memoryMB: Int) -> String {
        let gigabytes = Double(memoryMB) / 1_024
        if gigabytes.rounded() == gigabytes {
            return String(Int(gigabytes))
        }

        return String(format: "%.1f", gigabytes)
    }
}

private struct RuntimeProvidersPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Runtime Providers",
                subtitle: "Local engines available for the Windows boot path.",
                symbolName: "bolt.horizontal"
            )

            if snapshot.runtimeProviders.isEmpty {
                ResourcePlanRow(
                    title: "Providers",
                    value: "Refresh runtime status to inspect local providers.",
                    symbolName: "questionmark.circle",
                    state: .planned
                )
            } else {
                ForEach(snapshot.runtimeProviders, id: \.kind) { provider in
                    ResourcePlanRow(
                        title: provider.displayName,
                        value: providerDetail(provider),
                        symbolName: symbolName(for: provider),
                        state: state(for: provider)
                    )
                }
            }
        }
    }

    private func providerDetail(_ provider: VMRuntimeProviderSummary) -> String {
        if let executableVersion = provider.executableVersion {
            return "\(provider.mode), \(provider.acceleration), \(executableVersion)"
        }

        if let executablePath = provider.executablePath {
            return "\(provider.mode), \(provider.acceleration), \(URL(fileURLWithPath: executablePath).lastPathComponent)"
        }

        return "\(provider.mode), \(provider.acceleration)"
    }

    private func symbolName(for provider: VMRuntimeProviderSummary) -> String {
        switch provider.kind {
        case .appleVirtualization:
            "apple.logo"
        case .qemuHypervisor:
            "shippingbox"
        }
    }

    private func state(for provider: VMRuntimeProviderSummary) -> IntegrationState {
        switch provider.status {
        case .active:
            .ready
        case .planned:
            .planned
        case .unavailable:
            .blocked
        }
    }
}

private struct MacIntegrationPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Mac Integration",
                subtitle: "The Coherence-style bridge Veil is building toward.",
                symbolName: "macwindow"
            )

            IntegrationStatusRow(
                title: "Windows Apps on Mac",
                detail: "Launch flow is wired through the agent protocol.",
                symbolName: "app",
                state: .partial
            )
            IntegrationStatusRow(
                title: "Window Tracking",
                detail: "Agent window events can identify launched app windows.",
                symbolName: "rectangle.3.group",
                state: .partial
            )
            IntegrationStatusRow(
                title: "Clipboard",
                detail: "Protocol support exists; shell controls are still planned.",
                symbolName: "doc.on.clipboard",
                state: .planned
            )
            IntegrationStatusRow(
                title: "Shared Folders",
                detail: snapshot.profileName == nil ? "Create a profile to prepare shared folder paths." : "Profile owns the future shared folder boundary.",
                symbolName: "folder",
                state: snapshot.profileName == nil ? .blocked : .planned
            )
            IntegrationStatusRow(
                title: "Seamless App Mode",
                detail: "Parallels-style app blending will follow VM boot and window capture.",
                symbolName: "rectangle.on.rectangle",
                state: snapshot.bootReady ? .planned : .blocked
            )
        }
    }
}

private struct SetupItem: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbolName: String
    var isComplete: Bool
}

private struct SetupItemRow: View {
    var item: SetupItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? .green : .secondary)
                .frame(width: 22)

            Image(systemName: item.symbolName)
                .foregroundStyle(item.isComplete ? .green : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}

private enum PathPicker: Identifiable {
    case installerMedia
    case driverMedia
    case virtualDisk

    var id: String {
        switch self {
        case .installerMedia:
            "installerMedia"
        case .driverMedia:
            "driverMedia"
        case .virtualDisk:
            "virtualDisk"
        }
    }
}

private struct PreflightCheckRow: View {
    var check: VMPreflightCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                Text(check.detail)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .font(.callout)
    }

    private var symbolName: String {
        switch check.state {
        case .passed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle"
        }
    }

    private var symbolColor: Color {
        switch check.state {
        case .passed:
            .green
        case .failed:
            .red
        }
    }
}

private struct InstallationStepRow: View {
    var step: VMInstallationStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                Text(step.detail)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .font(.callout)
    }

    private var symbolName: String {
        switch step.state {
        case .complete:
            "checkmark.circle.fill"
        case .pending:
            "clock"
        case .blocked:
            "exclamationmark.circle"
        }
    }

    private var symbolColor: Color {
        switch step.state {
        case .complete:
            .green
        case .pending:
            .secondary
        case .blocked:
            .orange
        }
    }
}
