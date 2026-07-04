import SwiftUI
import VeilHostCore

struct AgentView: View {
    var health: AgentHealthResponse?
    var connectionMode: HostConnectionMode
    var connectionDetail: String?
    var agentDiagnostic: AgentConnectionDiagnostic?
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let health {
                ShellPanel {
                    HStack {
                        ShellPanelHeader(
                            title: connectionMode == .demo ? "Demo Agent" : "Windows Agent",
                            subtitle: connectionMode == .demo
                                ? "Built-in sample data is active until a Windows agent is reachable."
                                : "Live agent telemetry is connected.",
                            symbolName: connectionMode == .demo ? "play.rectangle" : "bolt.horizontal.circle"
                        )

                        Spacer()

                        StatusPill(
                            title: connectionMode == .demo ? "Demo" : "Live",
                            symbolName: connectionMode == .demo ? "sparkles" : "checkmark.circle.fill",
                            tint: connectionMode == .demo ? .orange : .green
                        )
                    }
                }

                ShellPanel {
                    ShellPanelHeader(
                        title: "Session",
                        subtitle: connectionDetail,
                        symbolName: "person.crop.circle.badge.checkmark"
                    )

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        ShellMetricRow(label: "Version", value: health.agentVersion)
                        ShellMetricRow(label: "OS", value: health.os)
                        ShellMetricRow(label: "User", value: health.session.user)
                        ShellMetricRow(label: "Interactive", value: health.session.interactive ? "Yes" : "No")
                    }
                }

                ShellPanel {
                    ShellPanelHeader(
                        title: "Capabilities",
                        subtitle: "Protocol features exposed by the current Windows agent.",
                        symbolName: "switch.2"
                    )

                    FlowPills {
                        CapabilityPill(title: "App List", isEnabled: health.capabilities.appList)
                        CapabilityPill(title: "App Launch", isEnabled: health.capabilities.appLaunch)
                        CapabilityPill(title: "Window Tracking", isEnabled: health.capabilities.windowTracking)
                        CapabilityPill(title: "Window Capture", isEnabled: health.capabilities.windowCapture)
                        CapabilityPill(title: "Input", isEnabled: health.capabilities.input)
                        CapabilityPill(title: "Clipboard", isEnabled: health.capabilities.clipboardText)
                    }
                }

                if let agentDiagnostic {
                    AgentDiagnosticPanel(diagnostic: agentDiagnostic)
                }
            } else if let errorMessage {
                ShellPanel {
                    ContentUnavailableView(
                        "Agent Unavailable",
                        systemImage: "network.slash",
                        description: Text(errorMessage)
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }

                if let agentDiagnostic {
                    AgentDiagnosticPanel(diagnostic: agentDiagnostic)
                }
            } else {
                ShellPanel {
                    ContentUnavailableView(
                        "No Agent Data",
                        systemImage: "network",
                        description: Text("Refresh the agent to load status and capabilities.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
        }
    }
}

private struct AgentDiagnosticPanel: View {
    var diagnostic: AgentConnectionDiagnostic

    var body: some View {
        ShellPanel(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ShellPanelHeader(
                    title: "Connection Check",
                    subtitle: diagnostic.endpoint,
                    symbolName: diagnostic.status == .connected ? "checkmark.circle" : "exclamationmark.triangle"
                )

                Spacer()

                StatusPill(
                    title: diagnostic.status == .connected ? "Connected" : "Needs Action",
                    symbolName: diagnostic.status == .connected ? "checkmark.circle.fill" : "wrench.and.screwdriver",
                    tint: diagnostic.status == .connected ? .green : .orange
                )
            }

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(primaryActions.enumerated()), id: \.offset) { _, action in
                    Label(action, systemImage: "chevron.right.circle")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            DisclosureGroup("Advanced details") {
                VStack(alignment: .leading, spacing: 8) {
                    if let errorMessage = diagnostic.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    ForEach(Array(diagnostic.nextActions.enumerated()), id: \.offset) { _, action in
                        Text(action)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        switch diagnostic.status {
        case .connected:
            "Windows is reachable. Open a Windows app to verify the window bridge."
        case .unavailable:
            "Veil can start Windows, but the macOS app cannot talk to the Windows guest agent yet."
        }
    }

    private var primaryActions: [String] {
        switch diagnostic.status {
        case .connected:
            [
                "Open Notepad from Apps to verify window mirroring.",
                "Use input and clipboard checks after the window appears."
            ]
        case .unavailable:
            [
                "Keep the Windows desktop open.",
                "Run Install Veil Agent.cmd from the Veil Shared drive.",
                "Run Repair Veil Agent Connectivity.cmd if the forwarded port opens but health still times out.",
                "If it still does not connect, run Collect Veil Agent Diagnostics.cmd in Windows."
            ]
        }
    }
}

private struct FlowPills<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 124), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
