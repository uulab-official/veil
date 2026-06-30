import SwiftUI
import VeilHostCore

struct LaunchView: View {
    var result: NotepadLaunchResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last Launch")
                .font(.headline)

            if let result {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    MetricRow(label: "App", value: result.window.title)
                    MetricRow(label: "Window", value: result.window.windowId)
                    MetricRow(label: "Process", value: String(result.launch.processId))
                    MetricRow(label: "State", value: result.window.state)
                    MetricRow(label: "Bounds", value: "\(result.window.bounds.width)x\(result.window.bounds.height)")
                }
            } else {
                ContentUnavailableView(
                    "Nothing Launched",
                    systemImage: "macwindow.on.rectangle",
                    description: Text("Launch Notepad to verify the host-to-agent app flow.")
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
