import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

enum SetupStatusState {
    case complete
    case attention
    case pending
}

struct SetupStatusItem: View {
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

struct QuickActionsPanel: View {
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

struct ControlCenterHero: View {
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
