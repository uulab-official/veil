import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

struct VMRuntimeView: View {
    @Bindable var model: VMRuntimeModel
    @State private var pathPicker: PathPicker?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("VM Runtime")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.phase == .loading)
            }

            if let snapshot = model.snapshot {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    MetricRow(label: "Status", value: model.statusText)
                    MetricRow(label: "Capability", value: model.capabilitySummary)
                    MetricRow(label: "Architecture", value: snapshot.architecture)
                    MetricRow(label: "macOS 15+", value: snapshot.minimumOSSupported ? "Yes" : "No")
                    MetricRow(label: "Profile", value: snapshot.profileName ?? "Not configured")
                    MetricRow(label: "Installer Media", value: snapshot.installerMediaPath ?? "Not selected")
                    MetricRow(label: "Virtual Disk", value: snapshot.virtualDiskPath ?? "Not selected")
                    MetricRow(label: "Detail", value: snapshot.detail)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if !model.canStart {
                        Text("VM start is disabled until a Windows 11 Arm profile, installer media, and virtual disk path are configured.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }

                    HStack {
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
                ContentUnavailableView(
                    "VM Runtime Unavailable",
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "VM Runtime Not Loaded",
                    systemImage: "desktopcomputer",
                    description: Text("Refresh to inspect local VM runtime capabilities.")
                )
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

private struct MetricRow: View {
    var label: String
    var value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}
