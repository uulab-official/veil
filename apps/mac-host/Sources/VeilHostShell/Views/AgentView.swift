import SwiftUI
import VeilHostCore

struct AgentView: View {
    var health: AgentHealthResponse?
    var connectionMode: HostConnectionMode
    var connectionDetail: String?
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
            } else if let errorMessage {
                ShellPanel {
                    ContentUnavailableView(
                        "Agent Unavailable",
                        systemImage: "network.slash",
                        description: Text(errorMessage)
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
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
