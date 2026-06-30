import SwiftUI
import VeilHostCore

struct VMRuntimeView: View {
    @Bindable var model: VMRuntimeModel

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
                    MetricRow(label: "Detail", value: snapshot.detail)
                }

                if !model.canStart {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("VM start is disabled until a Windows 11 Arm profile is configured.")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        if snapshot.state == .notConfigured {
                            Button {
                                Task {
                                    await model.createDefaultProfile()
                                }
                            } label: {
                                Label("Create Default Profile", systemImage: "plus.circle")
                            }
                            .disabled(model.phase == .loading)
                        }
                    }
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
