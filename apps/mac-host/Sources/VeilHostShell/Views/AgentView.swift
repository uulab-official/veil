import SwiftUI
import VeilHostCore

struct AgentView: View {
    var health: AgentHealthResponse?
    var connectionMode: HostConnectionMode
    var connectionDetail: String?
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agent")
                .font(.headline)

            if let health {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    MetricRow(label: "Mode", value: connectionMode == .demo ? "Demo" : "Agent")
                    if let connectionDetail {
                        MetricRow(label: "Connection", value: connectionDetail)
                    }
                    MetricRow(label: "Version", value: health.agentVersion)
                    MetricRow(label: "OS", value: health.os)
                    MetricRow(label: "User", value: health.session.user)
                    MetricRow(label: "Interactive", value: health.session.interactive ? "Yes" : "No")
                    MetricRow(label: "App Launch", value: health.capabilities.appLaunch ? "Available" : "Unavailable")
                    MetricRow(label: "Window Tracking", value: health.capabilities.windowTracking ? "Available" : "Unavailable")
                    MetricRow(label: "Window Capture", value: health.capabilities.windowCapture ? "Available" : "Unavailable")
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Agent Unavailable",
                    systemImage: "network.slash",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No Agent Data",
                    systemImage: "network",
                    description: Text("Refresh the agent to load status and capabilities.")
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
