import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

struct VMRuntimeView: View {
    @Bindable var model: VMRuntimeModel
    @State private var pathPicker: PathPicker?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = model.snapshot {
                ShellPanel {
                    HStack(alignment: .center) {
                        ShellPanelHeader(
                            title: "Runtime Status",
                            subtitle: snapshot.detail,
                            symbolName: "desktopcomputer"
                        )

                        Spacer()

                        StatusPill(
                            title: runtimeTitle(for: snapshot.state),
                            symbolName: runtimeSymbol(for: snapshot.state),
                            tint: runtimeTint(for: snapshot.state)
                        )
                    }

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        ShellMetricRow(label: "Status", value: model.statusText)
                        ShellMetricRow(label: "Capability", value: model.capabilitySummary)
                        ShellMetricRow(label: "Architecture", value: snapshot.architecture, monospaced: true)
                        ShellMetricRow(label: "macOS 15+", value: snapshot.minimumOSSupported ? "Yes" : "No")
                    }
                }

                ShellPanel {
                    ShellPanelHeader(
                        title: "Windows 11 Arm Profile",
                        subtitle: "Configure the VM profile before boot orchestration is enabled.",
                        symbolName: "rectangle.stack.badge.person.crop"
                    )

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        ShellMetricRow(label: "Profile", value: snapshot.profileName ?? "Not configured")
                        ShellMetricRow(label: "Installer Media", value: snapshot.installerMediaPath ?? "Not selected", monospaced: true)
                        ShellMetricRow(label: "Virtual Disk", value: snapshot.virtualDiskPath ?? "Not selected", monospaced: true)
                    }

                    HStack(spacing: 8) {
                        if snapshot.state == .notConfigured {
                            createDefaultProfileButton
                        }

                        if snapshot.profileName != nil {
                            Button {
                                pathPicker = .installerMedia
                            } label: {
                                Label("Select Installer", systemImage: "opticaldisc")
                            }
                            .disabled(model.phase == .loading)

                            Button {
                                pathPicker = .virtualDisk
                            } label: {
                                Label("Select Disk", systemImage: "externaldrive")
                            }
                            .disabled(model.phase == .loading)
                        }

                        Spacer()
                    }
                }

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

                ShellPanel {
                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }

                    if !model.canStart {
                        Text("VM start is disabled until a Windows 11 Arm profile, installer media, and virtual disk path are configured.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }

                    HStack {
                        Button {
                            Task {
                                await model.start()
                            }
                        } label: {
                            Label("Start VM", systemImage: "play.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canStart || model.phase == .loading)

                        Button {
                            Task {
                                await model.load()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.phase == .loading)

                        Spacer()
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
    }

    private var createDefaultProfileButton: some View {
        Button {
            Task {
                await model.createDefaultProfile()
            }
        } label: {
            Label("Create Default Profile", systemImage: "plus.circle")
        }
        .disabled(model.phase == .loading)
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
