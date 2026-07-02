import SwiftUI
import VeilHostCore

struct WindowsAppBridgePanel: View {
    @Bindable var model: HostDashboardModel
    var launchAction: () -> Void

    var body: some View {
        ShellPanel(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ShellPanelHeader(
                    title: "Windows Apps On Mac",
                    subtitle: "Open a tracked Windows app as its own macOS window.",
                    symbolName: "macwindow.on.rectangle"
                )

                Spacer()

                StatusPill(
                    title: statusTitle,
                    symbolName: statusSymbol,
                    tint: statusTint
                )
            }

            HStack(alignment: .center, spacing: 12) {
                Picker("Windows App", selection: $model.selectedAppId) {
                    ForEach(model.apps) { app in
                        Text(app.name).tag(Optional(app.id))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .disabled(model.apps.isEmpty || model.phase == .loading || model.phase == .launching)

                Button(action: launchAction) {
                    Label(primaryTitle, systemImage: "macwindow.badge.plus")
                        .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canLaunchSelectedApp || model.phase == .loading || model.phase == .launching)

                if let lastSession = model.mirrorSessions.last {
                    Label("\(lastSession.window.title) mapped", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else {
                    Label("No mirrored app window yet", systemImage: "circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                CoherenceMetric(
                    title: "HWND Sessions",
                    value: "\(model.mirrorSessions.count)",
                    symbolName: "rectangle.3.group",
                    tint: model.mirrorSessions.isEmpty ? .secondary : .green
                )
                CoherenceMetric(
                    title: "Capture",
                    value: captureValue,
                    symbolName: "viewfinder",
                    tint: captureTint
                )
                CoherenceMetric(
                    title: "Input",
                    value: model.health?.capabilities.input == true ? "Ready" : "Planned",
                    symbolName: "keyboard",
                    tint: model.health?.capabilities.input == true ? .green : .secondary
                )
                CoherenceMetric(
                    title: "Clipboard",
                    value: model.health?.capabilities.clipboardText == true ? "Ready" : "Planned",
                    symbolName: "doc.on.clipboard",
                    tint: model.health?.capabilities.clipboardText == true ? .green : .secondary
                )
            }
        }
    }

    private var primaryTitle: String {
        if model.phase == .launching {
            return "Opening..."
        }

        return "Open As Mac Window"
    }

    private var captureValue: String {
        if model.mirrorSessions.contains(where: { $0.captureState == .streaming }) {
            return "Streaming"
        }

        if model.mirrorSessions.contains(where: { $0.captureState == .pending }) {
            return "Pending"
        }

        return model.health?.capabilities.windowCapture == true ? "Available" : "Planned"
    }

    private var captureTint: Color {
        if model.mirrorSessions.contains(where: { $0.captureState == .streaming }) {
            return .green
        }

        if model.mirrorSessions.contains(where: { $0.captureState == .pending }) {
            return .orange
        }

        return model.health?.capabilities.windowCapture == true ? .green : .secondary
    }

    private var statusTitle: String {
        switch model.connectionMode {
        case .agent:
            return model.health == nil ? "Agent Pending" : "Agent"
        case .demo:
            return "Demo"
        }
    }

    private var statusSymbol: String {
        switch model.connectionMode {
        case .agent:
            return model.health == nil ? "network.slash" : "bolt.horizontal.circle"
        case .demo:
            return "play.rectangle"
        }
    }

    private var statusTint: Color {
        switch model.connectionMode {
        case .agent:
            return model.health == nil ? .secondary : .green
        case .demo:
            return .orange
        }
    }
}

private struct CoherenceMetric: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
