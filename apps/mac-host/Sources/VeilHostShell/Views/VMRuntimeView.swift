import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

struct VMRuntimeView: View {
    @Bindable var model: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showVMConsoleAction: () -> Void
    var consoleMessage: String?
    @State private var pathPicker: PathPicker?
    @State private var showsAdvancedDetails = false
    @State private var installSimulation = InstallSimulationState.idle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = model.snapshot {
                SimpleRuntimePanel(
                    snapshot: snapshot,
                    statusText: model.statusText,
                    canStart: model.canStart,
                    canStop: model.canStop,
                    isLoading: model.phase == .loading,
                    consoleMessage: consoleMessage,
                    installSimulation: installSimulation,
                    primaryAction: {
                        if model.canStop {
                            stopVMAction()
                        } else if model.canStart {
                            startInstallSimulation()
                        } else {
                            Task {
                                await model.prepareDefaultVM()
                            }
                        }
                    },
                    chooseISOAction: {
                        pathPicker = .installerMedia
                    },
                    consoleAction: showVMConsoleAction,
                    refreshAction: {
                        Task {
                            await model.load()
                        }
                    },
                    detailsAction: {
                        showsAdvancedDetails.toggle()
                    },
                    resetSimulationAction: {
                        installSimulation = .idle
                    },
                    runtimeTitle: runtimeTitle(for: snapshot.state),
                    runtimeSymbol: runtimeSymbol(for: snapshot.state),
                    runtimeTint: runtimeTint(for: snapshot.state)
                )

                if model.errorMessage != nil || model.diagnosticsURL != nil {
                    ShellPanel(spacing: 8) {
                        if let errorMessage = model.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }

                        if let diagnosticsURL = model.diagnosticsURL {
                            Label("Diagnostics saved to \(diagnosticsURL.path)", systemImage: "doc.text.magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }

                if showsAdvancedDetails {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            setupColumn(snapshot)
                                .frame(minWidth: 430)
                            runtimeDetailColumn(snapshot)
                                .frame(minWidth: 430)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            setupColumn(snapshot)
                            runtimeDetailColumn(snapshot)
                        }
                    }
                    .transition(.opacity)
                }
            } else if let errorMessage = model.errorMessage {
                ShellPanel {
                    ContentUnavailableView(
                        "VM Runtime Unavailable",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text(errorMessage)
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            } else {
                ShellPanel {
                    ContentUnavailableView(
                        "VM Runtime Not Loaded",
                        systemImage: "desktopcomputer",
                        description: Text("Refresh to inspect local VM runtime capabilities.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
        }
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
    }

    private func canShowConsole(for snapshot: VMRuntimeSnapshot) -> Bool {
        snapshot.state == .running || snapshot.state == .starting
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
    private func runtimeTitle(for state: VMRuntimeState) -> String {
        switch state {
        case .unsupported:
            "Unsupported"
        case .notConfigured:
            "Not Configured"
        case .stopped:
            "Stopped"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .suspended:
            "Suspended"
        case .failed:
            "Failed"
        }
    }

    private func runtimeSymbol(for state: VMRuntimeState) -> String {
        switch state {
        case .unsupported:
            "xmark.octagon"
        case .notConfigured:
            "wrench.and.screwdriver"
        case .stopped:
            "stop.circle"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .running:
            "play.circle.fill"
        case .suspended:
            "pause.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func runtimeTint(for state: VMRuntimeState) -> Color {
        switch state {
        case .unsupported, .failed:
            .orange
        case .notConfigured, .stopped, .suspended:
            .secondary
        case .starting:
            .blue
        case .running:
            .green
        }
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
        let currentInstaller = model.snapshot?.installerMediaPath
        let currentDisk = model.snapshot?.virtualDiskPath

        Task {
            switch picker {
            case .installerMedia:
                await model.updateProfilePaths(
                    installerMediaPath: path,
                    virtualDiskPath: currentDisk
                )
            case .virtualDisk:
                await model.updateProfilePaths(
                    installerMediaPath: currentInstaller,
                    virtualDiskPath: path
                )
            }
        }
    }

    private func diagnosticsDirectory() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("Veil Diagnostics", isDirectory: true)
    }

    @MainActor
    private func startInstallSimulation() {
        guard installSimulation.phase != .running else {
            return
        }

        Task { @MainActor in
            installSimulation = .running(stepIndex: 0, progress: 0.04)

            for index in InstallSimulationState.steps.indices {
                installSimulation = .running(stepIndex: index, progress: Double(index) / Double(InstallSimulationState.steps.count))
                try? await Task.sleep(for: .milliseconds(850))
                installSimulation = .running(stepIndex: index, progress: Double(index + 1) / Double(InstallSimulationState.steps.count))
            }

            installSimulation = .complete
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
        "Creating unattended setup plan",
        "Booting installer",
        "Copying Windows files",
        "Applying configuration",
        "Restarting virtual machine",
        "Preparing Veil guest tools",
        "Ready for Windows apps"
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
    var consoleMessage: String?
    var installSimulation: InstallSimulationState
    var primaryAction: () -> Void
    var chooseISOAction: () -> Void
    var consoleAction: () -> Void
    var refreshAction: () -> Void
    var detailsAction: () -> Void
    var resetSimulationAction: () -> Void
    var runtimeTitle: String
    var runtimeSymbol: String
    var runtimeTint: Color

    var body: some View {
        ShellPanel(spacing: 20) {
            HStack(alignment: .center, spacing: 22) {
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

                    setupStrip

                    if installSimulation.phase != .idle {
                        InstallSimulationProgressView(
                            simulation: installSimulation,
                            resetAction: resetSimulationAction
                        )
                    }

                    if let consoleMessage {
                        Label(consoleMessage, systemImage: "info.circle")
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

                        if canShowConsole {
                            Button(action: consoleAction) {
                                Label("Console", systemImage: "display")
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
                title: "Ready",
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

        if let path = snapshot.discoveredInstallerMediaPath {
            return "\(URL(fileURLWithPath: path).lastPathComponent) found"
        }

        return "Not selected"
    }

    private var installerState: SetupStatusState {
        if snapshot.installerMediaPath != nil {
            return .complete
        }

        if snapshot.discoveredInstallerMediaPath != nil {
            return .attention
        }

        return .pending
    }

    private var summaryText: String {
        switch snapshot.state {
        case .unsupported:
            return "This Mac cannot run the current local Windows Arm runtime."
        case .notConfigured:
            return snapshot.discoveredInstallerMediaPath == nil
                ? "Download or choose a Windows 11 Arm ISO, then prepare the VM."
                : "Windows ISO found. Prepare the VM to attach it and create the disk."
        case .stopped:
            if installSimulation.phase == .complete {
                return "Simulated Windows install is complete. Guest agent work comes next."
            }

            return snapshot.bootReady ? "Windows is not installed yet. Simulate the automatic setup flow." : statusText
        case .starting:
            return "Starting Windows Setup. The installer opens in the VM console."
        case .running:
            return "Windows Setup is running in the VM console."
        case .suspended:
            return "The VM is suspended."
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
                return "Simulate Auto Install"
            case .running:
                return "Installing..."
            case .complete:
                return "Run Again"
            }
        }

        return snapshot.profileName == nil ? "Prepare VM" : "Continue Setup"
    }

    private var primarySymbol: String {
        if canStop {
            return "stop.fill"
        }

        if canStart {
            return "play.fill"
        }

        return "wand.and.stars"
    }

    private var primaryDisabled: Bool {
        isLoading || snapshot.state == .unsupported || installSimulation.phase == .running
    }

    private var canShowConsole: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }
}

private struct InstallSimulationProgressView: View {
    var simulation: InstallSimulationState
    var resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbolName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer()

                Text("\(Int(simulation.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: simulation.progress)
                .tint(tint)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(simulation.currentStep)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if simulation.phase == .complete {
                    Button(action: resetAction) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset simulation")
                }
            }
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private var title: String {
        switch simulation.phase {
        case .idle:
            return "Automatic install ready"
        case .running:
            return "Automatic install simulation"
        case .complete:
            return "Simulated install complete"
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
    var consoleAction: () -> Void
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
                    detail: canStop ? "Shut down the running VM process." : (canStart ? "Boot the configured Windows machine." : "Complete setup before booting."),
                    symbolName: canStop ? "stop.fill" : "power",
                    tint: canStop ? .orange : .green,
                    state: (canStart || canStop) ? .ready : .blocked,
                    action: canStop ? stopAction : startAction
                )
                .disabled((!canStart && !canStop) || isLoading)

                ControlActionTile(
                    title: "Console",
                    detail: canShowConsole ? "Open the Windows installer display." : "Console appears after the VM starts.",
                    symbolName: "display",
                    tint: .blue,
                    state: canShowConsole ? .ready : .blocked,
                    action: consoleAction
                )
                .disabled(!canShowConsole || isLoading)

                ControlActionTile(
                    title: "Prepare VM",
                    detail: snapshot.profileName == nil ? "Create profile, find Downloads ISO, shared folder, and default disk." : "Base VM resources are ready.",
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
                    detail: "Advanced VM settings follow the boot spike.",
                    symbolName: "slider.horizontal.3",
                    tint: .blue,
                    state: .planned
                )

                ControlActionTile(
                    title: "Snapshots",
                    detail: "Checkpoints follow persistent VM boot.",
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

    private var canShowConsole: Bool {
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
    var consoleAction: () -> Void
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
                        DashboardStat(title: "Boot Ready", value: snapshot.bootReady ? "Ready" : "Blocked", symbolName: snapshot.bootReady ? "checkmark.seal" : "lock", tint: snapshot.bootReady ? .green : .orange)
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

                        if canShowConsole {
                            Button(action: consoleAction) {
                                Label("Console", systemImage: "display")
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

    private var canShowConsole: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }

    private var installerStatusTitle: String {
        if snapshot.installerMediaPath != nil {
            return "Selected"
        }

        if snapshot.discoveredInstallerMediaPath != nil {
            return "Found"
        }

        return "Missing"
    }

    private var installerStatusTint: Color {
        if snapshot.installerMediaPath != nil {
            return .green
        }

        if snapshot.discoveredInstallerMediaPath != nil {
            return .blue
        }

        return .orange
    }

    private func providerName(for snapshot: VMRuntimeSnapshot) -> String {
        snapshot.runtimeProvider?.displayName ?? (snapshot.virtualizationAvailable ? "Local" : "Unavailable")
    }
}

private struct WindowsSetupDisplayPanel: View {
    var snapshot: VMRuntimeSnapshot
    var consoleMessage: String?
    var isLoading: Bool
    var canStart: Bool
    var canShowConsole: Bool
    var prepareAction: () -> Void
    var selectInstallerAction: () -> Void
    var startAction: () -> Void
    var consoleAction: () -> Void

    var body: some View {
        ShellPanel(spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    installPreview
                        .frame(width: 390)
                    installContent
                }

                VStack(alignment: .leading, spacing: 16) {
                    installPreview
                    installContent
                }
            }
        }
    }

    private var installPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.03, green: 0.04, blue: 0.06),
                            Color(red: 0.10, green: 0.11, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Install Windows 11")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Arm64 local runtime")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.66))
                    }

                    Spacer()

                    Image(systemName: previewSymbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(phaseTint)
                }

                HStack(spacing: 10) {
                    WindowsPane(color: Color(red: 0.08, green: 0.55, blue: 1.00))
                    WindowsPane(color: Color(red: 0.12, green: 0.78, blue: 0.72))
                }
                HStack(spacing: 10) {
                    WindowsPane(color: Color(red: 1.00, green: 0.44, blue: 0.28))
                    WindowsPane(color: Color(red: 1.00, green: 0.72, blue: 0.20))
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(previewTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(progressText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    ProgressView(value: progressFraction)
                        .tint(phaseTint)

                    Text(previewSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 268)
    }

    private var installContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows Installation Assistant")
                        .font(.title3.weight(.semibold))
                    Text(phaseDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                StatusPill(title: phaseTitle, symbolName: phaseSymbol, tint: phaseTint)
            }

            if let consoleMessage {
                Label(consoleMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            if let discoveredInstallerName {
                Label("Found \(discoveredInstallerName) in Downloads. Auto Prepare will attach it to the VM profile.", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 154), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                Link(destination: Self.microsoftArmDownloadURL) {
                    Label("Get Windows 11", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)

                Button(action: prepareAction) {
                    Label("Auto Prepare", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                Button(action: selectInstallerAction) {
                    Label("Choose ISO", systemImage: "opticaldisc")
                }
                .disabled(isLoading)

                Button(action: startAction) {
                    Label("Install Windows", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart || isLoading)

                Button(action: consoleAction) {
                    Label("Open Console", systemImage: "display")
                }
                .disabled(!canShowConsole || isLoading)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(flowItems) { item in
                    InstallFlowRow(item: item)
                }
            }

            Text("Windows media and licenses stay user-provided; Veil only links official download pages and attaches local files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private static let microsoftArmDownloadURL = URL(string: "https://www.microsoft.com/en-us/software-download/windows11arm64")!

    private var selectedInstallerName: String? {
        snapshot.installerMediaPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var discoveredInstallerName: String? {
        guard snapshot.installerMediaPath == nil else {
            return nil
        }

        return snapshot.discoveredInstallerMediaPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var flowItems: [InstallFlowItem] {
        let installerDetail: String
        let installerState: InstallFlowState
        if let selectedInstallerName {
            installerDetail = selectedInstallerName
            installerState = .complete
        } else if let discoveredInstallerName {
            installerDetail = "Found \(discoveredInstallerName). Auto Prepare will attach it."
            installerState = .current
        } else {
            installerDetail = "Download the Arm64 ISO from Microsoft or keep it in Downloads."
            installerState = .current
        }

        return [
            InstallFlowItem(
                title: "Get Windows",
                detail: installerDetail,
                symbolName: "arrow.down.circle",
                state: installerState
            ),
            InstallFlowItem(
                title: "Prepare Mac VM",
                detail: snapshot.virtualDiskPath == nil
                    ? "Create profile, shared folder, adaptive resources, and sparse disk."
                    : "Profile, disk, and shared folder are configured.",
                symbolName: "macbook",
                state: snapshot.virtualDiskPath == nil ? (snapshot.profileName == nil ? .pending : .current) : .complete
            ),
            InstallFlowItem(
                title: "Install Windows",
                detail: canShowConsole
                    ? "Continue setup inside the VM Console window."
                    : (canStart ? "Ready to boot the installer." : "Waiting for setup readiness."),
                symbolName: "display",
                state: canShowConsole ? .complete : (canStart ? .current : .pending)
            ),
            InstallFlowItem(
                title: "Finish Integration",
                detail: "Accept Microsoft setup terms, then install the Veil guest agent.",
                symbolName: "sparkles",
                state: snapshot.state == .running ? .current : .pending
            )
        ]
    }

    private var phaseTitle: String {
        if isLoading && snapshot.state == .starting {
            return "Starting"
        }

        switch snapshot.state {
        case .unsupported:
            return "Unsupported"
        case .notConfigured:
            return "No Profile"
        case .stopped:
            return snapshot.bootReady ? "Ready" : "Blocked"
        case .starting:
            return "Starting"
        case .running:
            return "Console Live"
        case .suspended:
            return "Suspended"
        case .failed:
            return "Failed"
        }
    }

    private var phaseDetail: String {
        if isLoading && snapshot.state == .starting {
            return "Veil is starting the local Windows VM. The installer display opens in a separate VM Console window as soon as Virtualization.framework exposes the screen."
        }

        switch snapshot.state {
        case .unsupported:
            return "This Mac cannot run the current local Windows Arm VM path."
        case .notConfigured:
            if let discoveredInstallerName {
                return "Found \(discoveredInstallerName) in Downloads. Auto Prepare will create the profile, attach the ISO, and prepare the blank disk."
            }

            return "Prepare a Windows 11 Arm profile. Veil will auto-detect a matching ISO in Downloads when one is available."
        case .stopped:
            return snapshot.bootReady
                ? "Ready to boot the Windows installer. Press Start Windows Setup; Veil will open the VM Console window automatically."
                : snapshot.detail
        case .starting:
            return "Windows setup is starting. If the console did not appear, press Open VM Console after a moment."
        case .running:
            return "The Windows installer display is attached to the VM Console window. Use that window for the setup screen."
        case .suspended:
            return "The VM is suspended. Resume support is still being hardened for the boot spike."
        case .failed:
            return "The last VM start failed. Export diagnostics or check the setup/preflight panels below."
        }
    }

    private var consoleHint: String {
        if canShowConsole {
            return "The Windows installer is shown in the separate console window."
        }

        if canStart {
            return "Console appears after the VM starts."
        }

        return "Complete the setup steps below before the console can open."
    }

    private var previewTitle: String {
        switch snapshot.state {
        case .running:
            "Console Open"
        case .starting:
            "Starting Display"
        case .stopped where snapshot.bootReady:
            "Ready To Boot"
        case .failed:
            "Needs Attention"
        default:
            "Setup Waiting"
        }
    }

    private var previewSubtitle: String {
        switch snapshot.state {
        case .running:
            "Continue Windows setup in the VM Console."
        case .starting:
            "Attaching the local Windows display."
        case .stopped where snapshot.bootReady:
            "Ready to boot the installer."
        default:
            "Download, prepare, install, then integrate."
        }
    }

    private var progressFraction: Double {
        let completed = flowItems.filter { $0.state == .complete }.count
        return Double(completed) / Double(flowItems.count)
    }

    private var progressText: String {
        "\(flowItems.filter { $0.state == .complete }.count)/\(flowItems.count)"
    }

    private var previewSymbol: String {
        switch snapshot.state {
        case .running:
            "display"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .failed:
            "exclamationmark.triangle"
        case .stopped where snapshot.bootReady:
            "play.circle.fill"
        default:
            "display"
        }
    }

    private var phaseSymbol: String {
        switch snapshot.state {
        case .running:
            "display"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .stopped where snapshot.bootReady:
            "checkmark.circle.fill"
        case .failed, .unsupported:
            "exclamationmark.triangle"
        default:
            "clock"
        }
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
}

private struct WindowsPane: View {
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.gradient)
            .frame(height: 52)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
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

private struct InstallFlowRow: View {
    var item: InstallFlowItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusTint)
                .frame(width: 28, height: 28)
                .background(statusTint.opacity(0.12), in: Circle())

            Image(systemName: item.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusTint)
                .frame(width: 22, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var statusSymbol: String {
        switch item.state {
        case .complete:
            "checkmark"
        case .current:
            "arrow.right"
        case .pending:
            "circle"
        }
    }

    private var statusTint: Color {
        switch item.state {
        case .complete:
            .green
        case .current:
            .blue
        case .pending:
            .secondary
        }
    }
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
                subtitle: "The VM resource model Veil applies and hardens through the boot spike.",
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
                title: "Display",
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

        if let path = snapshot.discoveredInstallerMediaPath {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return "Found \(filename) in Downloads. Auto Prepare will attach it."
        }

        return "Auto-detects a Windows Arm ISO in Downloads, or choose one manually."
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
                        Label("Auto Prepare", systemImage: "wand.and.stars")
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
                ShellMetricRow(label: "Installer", value: installerResourceName, monospaced: snapshot.installerMediaPath != nil || snapshot.discoveredInstallerMediaPath != nil)
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

        if let discovered = snapshot.discoveredInstallerMediaPath {
            return "\(resourceName(from: discovered)) found"
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
    case virtualDisk

    var id: String {
        switch self {
        case .installerMedia:
            "installerMedia"
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
