import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

struct VMRuntimeView: View {
    @Bindable var model: VMRuntimeModel
    var guestAgentInstallEvidence: VMInstallEvidenceSummary?
    var canLaunchWindowsApp: Bool
    var selectedWindowsAppName: String?
    var activeMirrorSession: WindowMirrorSession?
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var installGuestAgentAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var recordAppFrameProofAction: () -> Void
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
                        if canLaunchWindowsApp {
                            launchWindowsAppAction()
                        } else if model.canStop {
                            stopVMAction()
                        } else if model.canStart {
                            startDisplayHandoffProgress()
                            startVMAction()
                        } else if snapshot.installerMediaPath == nil || needsInstallerPickerAccess(snapshot) {
                            pathPicker = .installerMedia
                        } else {
                            Task {
                                await model.prepareDefaultVM()
                            }
                        }
                    },
                    displayAction: showWindowsDisplayAction,
                    stopAction: stopVMAction,
                    installGuestAgentAction: installGuestAgentAction,
                    canLaunchWindowsApp: canLaunchWindowsApp,
                    selectedWindowsAppName: selectedWindowsAppName,
                    activeMirrorSession: activeMirrorSession,
                    recordAppFrameProofAction: recordAppFrameProofAction,
                    refreshAction: {
                        Task {
                            await model.load()
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
                        ? "Opening the local Windows runtime."
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

    private func refreshRuntimeEvidenceWhileRunning() async {
        while !Task.isCancelled {
            guard model.snapshot?.state == .running || model.snapshot?.state == .starting else {
                return
            }

            if model.phase != .loading {
                await model.refreshRuntimeEvidence()
            }

            try? await Task.sleep(for: .seconds(3))
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
        "Checking Windows ISO",
        "Validating local VM profile",
        "Starting local Windows",
        "Attaching local display",
        "Opening Windows display",
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

                        if !canStart && installSimulation.phase == .idle {
                            Button(action: chooseISOAction) {
                                Label("Choose ISO", systemImage: "opticaldisc")
                            }
                            .disabled(isLoading)

                            Link(destination: Self.microsoftArmDownloadURL) {
                                Label("Get Windows", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        if canShowDisplay {
                            Button(action: displayAction) {
                                Label("Native Display", systemImage: "display")
                            }
                            .disabled(isLoading)
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
        if let path = snapshot.installerMediaPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return "Not selected"
    }

    private var installerState: SetupStatusState {
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
            return "This Mac cannot run the current local Windows Arm runtime."
        case .notConfigured:
            return "Choose a Windows 11 Arm ISO, then prepare Windows."
        case .stopped:
            if installSimulation.phase == .complete {
                return "Windows start handoff finished. Start again if setup did not continue."
            }

            return snapshot.bootReady ? "Start Windows setup from this main window." : statusText
        case .starting:
            return "Starting local Windows. Native QEMU display is temporary until embedded display lands."
        case .running:
            return "Windows is running locally. Open a Windows app once the guest agent connects."
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

        if snapshot.installerMediaPath == nil {
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

        if snapshot.installerMediaPath == nil {
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
            return "Windows display ready"
        case .running:
            return "Opening Windows display"
        case .complete:
            return "Windows display opened"
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

private struct WindowsDisplayScreenshotPreview: View {
    var image: NSImage
    var path: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black)

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .help("Latest Windows display")
        .accessibilityLabel("Latest Windows display screenshot")
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
                    detail: canStop ? "Shut down the local Windows runtime." : (canStart ? "Boot the configured Windows machine." : "Complete setup before booting."),
                    symbolName: canStop ? "stop.fill" : "power",
                    tint: canStop ? .orange : .green,
                    state: (canStart || canStop) ? .ready : .blocked,
                    action: canStop ? stopAction : startAction
                )
                .disabled((!canStart && !canStop) || isLoading)

                ControlActionTile(
                    title: "Native Display",
                    detail: canShowDisplay ? "Open the temporary native QEMU display." : "Display evidence appears after Windows starts.",
                    symbolName: "display",
                    tint: .blue,
                    state: canShowDisplay ? .ready : .blocked,
                    action: displayAction
                )
                .disabled(!canShowDisplay || isLoading)

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
                    detail: "Reload runtime capability and profile state.",
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
                    detail: "Advanced runtime settings follow boot validation.",
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

                        if canShowDisplay {
                            Button(action: displayAction) {
                                Label("Native Display", systemImage: "display")
                            }
                            .disabled(isLoading)
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
        if snapshot.installerMediaPath != nil {
            return "Selected"
        }

        return "Missing"
    }

    private var installerStatusTint: Color {
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
    var displayAction: () -> Void
    var stopAction: () -> Void
    var installGuestAgentAction: () -> Void
    var canLaunchWindowsApp: Bool
    var selectedWindowsAppName: String?
    var activeMirrorSession: WindowMirrorSession?
    var recordAppFrameProofAction: () -> Void
    var refreshAction: () -> Void
    var detailsAction: () -> Void
    var isShowingDetails: Bool
    var installSimulation: InstallSimulationState

    var body: some View {
        Group {
            if effectiveInstallEvidence.isInstalled {
                installedLauncherStage
            } else {
                installProcessStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let displayScreenshotImage {
                WindowsDisplayScreenshotPreview(
                    image: displayScreenshotImage,
                    path: snapshot.latestConsoleScreenshotPath ?? ""
                )
            } else {
                machineDisplay
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var launcherDisplaySurface: some View {
        if let activeMirrorSession {
            mirroredAppDisplay(session: activeMirrorSession)
        } else {
            machineDisplay
        }
    }

    private func mirroredAppDisplay(session: WindowMirrorSession) -> some View {
        ZStack(alignment: .topLeading) {
            WindowsAppFrameSurface(session: session, cornerRadius: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("WINDOWS APP")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Text(session.window.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                Text(mirroredAppFrameStatus(for: session))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(16)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private func mirroredAppFrameStatus(for session: WindowMirrorSession) -> String {
        guard let timing = session.frameTiming else {
            return session.latestFrame == nil ? "Waiting for first frame" : "Mirroring live frame"
        }

        if let interval = timing.latestFrameIntervalMilliseconds {
            return "Live frame \(timing.receivedFrameCount) · \(interval) ms"
        }

        return "First frame received"
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
                Button(action: selectInstallerAction) {
                    Label("Choose ISO", systemImage: "opticaldisc")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Choose ISO")

                Button(action: selectDriverAction) {
                    Label("Choose Drivers", systemImage: "externaldrive.badge.gearshape")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Choose driver ISO")

                Button(action: prepareAction) {
                    Label("Prepare", systemImage: "wand.and.stars")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Prepare Windows")
            }

            Button(action: detailsAction) {
                Label(isShowingDetails ? "Hide Details" : "Details", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .help("Details")

            if canInstallGuestAgent {
                Button(action: installGuestAgentAction) {
                    Label("Install Agent", systemImage: "person.crop.circle.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Install Veil guest agent")
            }

            if canStop {
                Button(action: stopAction) {
                    Label("Stop Windows", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Stop Windows")
            }

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .disabled(isLoading)
            .help("Refresh")

            Button(action: primaryAction) {
                Label(installPrimaryTitle, systemImage: primarySymbol)
                    .frame(minWidth: canStop ? 124 : 142)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(primaryDisabled)

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

    private var machineDisplay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(machineHeroGradient)

            WindowsDisplayGrid()
                .opacity(0.16)

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

                Button(action: primaryAction) {
                    ZStack {
                        Circle()
                            .fill(primaryDisabled ? Color.white.opacity(0.20) : Color.accentColor)
                        Image(systemName: primarySymbol)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 74, height: 74)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(primaryDisabled ? 0.12 : 0.34), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(primaryDisabled)
                .help(primaryTitle)

                Text(primaryTitle)
                    .font(.headline.weight(.semibold))

                if installSimulation.phase != .idle {
                    AssistantProgressStrip(simulation: installSimulation)
                        .frame(maxWidth: 420)
                        .foregroundStyle(.primary)
                } else {
                    ProgressView(value: progressFraction)
                        .tint(progressTint)
                        .frame(maxWidth: 420)
                }

                Spacer(minLength: 8)
            }
            .foregroundStyle(.white)
            .padding(24)

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayEyebrow)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(displayStatus)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    Spacer()
                }
                Spacer()
            }
            .padding(24)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var displayEyebrow: String {
        switch snapshot.state {
        case .running:
            "WINDOWS DISPLAY"
        case .starting:
            "OPENING WINDOWS"
        default:
            "WINDOWS 11"
        }
    }

    private var displayStatus: String {
        switch snapshot.state {
        case .running:
            "Windows is running locally."
        case .starting:
            "Opening the local display."
        case .failed:
            "Start failed. Open details."
        default:
            primaryHint
        }
    }

    private var installPrimaryTitle: String {
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
                .frame(width: 236)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var horizontalActions: some View {
        HStack(spacing: 8) {
            Button(action: prepareAction) {
                Label("Prepare", systemImage: "wand.and.stars")
                    .labelStyle(.iconOnly)
            }
            .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)
            .help("Prepare Windows")

            Button(action: selectInstallerAction) {
                Label("Choose ISO", systemImage: "opticaldisc")
                    .labelStyle(.iconOnly)
            }
            .disabled(isLoading || snapshot.state == .running || snapshot.state == .starting)
            .help("Choose ISO")

            Spacer(minLength: 4)

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .disabled(isLoading)
            .help("Refresh")

            if canInstallGuestAgent {
                Button(action: installGuestAgentAction) {
                    Label("Install Agent", systemImage: "person.crop.circle.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Install Veil guest agent")
            }

            if canLaunchWindowsApp || activeMirrorSession != nil {
                Button(action: recordAppFrameProofAction) {
                    Label("Record App Frame Proof", systemImage: "checkmark.seal")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                .help("Record app launch and first frame proof")
            }

            Button(action: detailsAction) {
                Label(isShowingDetails ? "Hide Details" : "Details", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .help("Show setup details")
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
            return selectedInstallerName ?? "Local Windows display"
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

    private var agentSummary: String {
        guestAgentInstallEvidence?.title ?? "After setup"
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
        if let selectedInstallerName {
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
                    ? "Native QEMU display available"
                    : (canStart ? "Open Windows Setup" : "Waiting for preparation"),
                symbolName: "display",
                state: canShowDisplay ? .complete : (canStart ? .current : .pending)
            ),
            InstallFlowItem(
                title: "Mac Integration",
                detail: "Install the Veil guest agent after Windows setup",
                symbolName: "macwindow.on.rectangle",
                state: snapshot.state == .running ? .current : .pending
            )
        ]
    }

    private var metadataItems: [LauncherMetadataItem] {
        [
            LauncherMetadataItem(
                title: "ISO",
                value: selectedInstallerName ?? "Missing",
                symbolName: "opticaldisc",
                tint: snapshot.installerMediaPath != nil && !installerNeedsFilePickerAccess ? .green : .orange
            ),
            LauncherMetadataItem(
                title: "Disk",
                value: resourceName(from: snapshot.virtualDiskPath) ?? "Missing",
                symbolName: "internaldrive",
                tint: snapshot.virtualDiskPath == nil ? .orange : .green
            ),
            LauncherMetadataItem(
                title: "Windows",
                value: effectiveInstallEvidence.isInstalled
                    ? (snapshot.state == .running ? "Running" : "Start")
                    : (snapshot.bootReady ? "Install" : "Setup"),
                symbolName: "play.rectangle",
                tint: snapshot.state == .running ? .green : .blue
            ),
            LauncherMetadataItem(
                title: "Apps",
                value: appMetadataValue,
                symbolName: "macwindow",
                tint: appMetadataTint
            )
        ]
    }

    private var appMetadataValue: String {
        guard let activeMirrorSession else {
            return canLaunchWindowsApp ? appDisplayName : "After agent"
        }

        return activeMirrorSession.latestFrame == nil ? "Waiting" : "Mirroring"
    }

    private var appMetadataTint: Color {
        guard let activeMirrorSession else {
            return canLaunchWindowsApp ? .green : .secondary
        }

        return activeMirrorSession.latestFrame == nil ? .orange : .green
    }

    private var appDisplayName: String {
        selectedWindowsAppName ?? "Windows App"
    }

    private var machineTitle: String {
        "Windows 11"
    }

    private var machineSubtitle: String {
        if canLaunchWindowsApp {
            return "Open Windows apps from macOS"
        }

        if effectiveInstallEvidence.isInstalled {
            return effectiveInstallEvidence.kind == .guestAgent
                ? "Guest agent connected"
                : "Run it locally on this Mac"
        }

        if snapshot.bootReady {
            return "Press play to open the Windows display"
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
        if canLaunchWindowsApp {
            return "Open \(appDisplayName)"
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
        if canLaunchWindowsApp {
            return "macwindow.badge.plus"
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
        if canLaunchWindowsApp {
            return "Launch \(appDisplayName) as a Mac-managed window."
        }

        if canStop {
            return "Stop the current local Windows runtime."
        }

        if effectiveInstallEvidence.isInstalled {
            return "Open the Windows display."
        }

        if canStart {
            return "Start Windows and open the local display."
        }

        if installerNeedsFilePickerAccess {
            return "Re-select the ISO so Veil can store macOS file access."
        }

        return "Create the profile, disk, shared folder, and install media."
    }

    private var installerNeedsFilePickerAccess: Bool {
        snapshot.preflightChecks.contains { check in
            check.id == "installer-media" && check.detail.contains("Re-select it with the file picker")
        }
    }

    private var primaryDisabled: Bool {
        isLoading || snapshot.state == .unsupported || installSimulation.phase == .running
    }

    private var progressFraction: Double {
        if installSimulation.phase == .running {
            return installSimulation.progress
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
                Text("Last Evidence")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

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
        let startedAt = evidence.startedAt.formatted(date: .omitted, time: .shortened)
        return "\(evidence.provider) started \(startedAt) · \(logName)"
    }

    private var helpText: String {
        [
            "Log: \(evidence.processLogPath)",
            "Monitor: \(evidence.monitorSocketPath)",
            evidence.qmpSocketPath.map { "QMP: \($0)" },
            evidence.consoleScreenshotPath.map { "Screenshot: \($0)" }
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
                isComplete: snapshot.installerMediaPath != nil
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

                Button(action: selectInstallerAction) {
                    Label("Installer", systemImage: "opticaldisc")
                }
                .disabled(snapshot.profileName == nil || isLoading)

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
