import SwiftUI
import VeilHostCore

struct LaunchView: View {
    var result: NotepadLaunchResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let result {
                ShellPanel {
                    HStack {
                        ShellPanelHeader(
                            title: result.window.title,
                            subtitle: "The Windows app accepted launch and reported a window.",
                            symbolName: "macwindow.on.rectangle"
                        )

                        Spacer()

                        StatusPill(
                            title: result.launch.accepted ? "Accepted" : "Rejected",
                            symbolName: result.launch.accepted ? "checkmark.circle.fill" : "xmark.circle",
                            tint: result.launch.accepted ? .green : .orange
                        )
                    }
                }

                ShellPanel {
                    ShellPanelHeader(
                        title: "Window",
                        subtitle: "Agent-reported window identity and placement.",
                        symbolName: "rectangle.inset.filled"
                    )

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        ShellMetricRow(label: "Window ID", value: result.window.windowId, monospaced: true)
                        ShellMetricRow(label: "Process", value: String(result.launch.processId), monospaced: true)
                        ShellMetricRow(label: "State", value: result.window.state)
                        ShellMetricRow(label: "Bounds", value: boundsText(for: result.window.bounds), monospaced: true)
                        ShellMetricRow(label: "Focused", value: result.window.focused ? "Yes" : "No")
                    }
                }
            } else {
                ShellPanel {
                    ContentUnavailableView(
                        "Nothing Launched",
                        systemImage: "macwindow.on.rectangle",
                        description: Text("Launch Notepad to verify a Windows app opens as a Mac window.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
        }
    }

    private func boundsText(for bounds: WindowBounds) -> String {
        "\(bounds.width)x\(bounds.height) @ \(bounds.x),\(bounds.y)"
    }
}
