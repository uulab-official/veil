import SwiftUI
import VeilHostCore

struct AppsView: View {
    var apps: [WindowsApp]
    @Binding var selectedAppId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShellPanel {
                HStack(alignment: .center) {
                    ShellPanelHeader(
                        title: "Available Windows Apps",
                        subtitle: "Choose an app and launch it from the toolbar.",
                        symbolName: "square.grid.2x2"
                    )

                    Spacer()

                    StatusPill(
                        title: "\(apps.count) Apps",
                        symbolName: "rectangle.stack",
                        tint: apps.isEmpty ? .secondary : .blue
                    )
                }
            }

            if apps.isEmpty {
                ShellPanel {
                    ContentUnavailableView(
                        "No Apps Loaded",
                        systemImage: "square.grid.2x2",
                        description: Text("Refresh the agent to load available Windows apps.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(apps) { app in
                        WindowsAppCard(
                            app: app,
                            isSelected: selectedAppId == app.id
                        ) {
                            selectedAppId = app.id
                        }
                    }
                }

                if let selectedApp = apps.first(where: { $0.id == selectedAppId }) {
                    ShellPanel {
                        ShellPanelHeader(
                            title: selectedApp.name,
                            subtitle: selectedApp.publisher,
                            symbolName: "info.circle"
                        )

                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                            ShellMetricRow(label: "App ID", value: selectedApp.id, monospaced: true)
                            ShellMetricRow(label: "Executable", value: selectedApp.exePath, monospaced: true)
                            ShellMetricRow(label: "Icon", value: selectedApp.iconId, monospaced: true)
                        }
                    }
                }
            }
        }
    }
}

private struct WindowsAppCard: View {
    var app: WindowsApp
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(app.publisher)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text(app.exePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(app.name)")
    }

    private var tint: Color {
        switch app.id {
        case "winapp_notepad":
            .blue
        case "winapp_calculator":
            .green
        case "winapp_paint":
            .orange
        default:
            .teal
        }
    }

    private var symbolName: String {
        switch app.id {
        case "winapp_notepad":
            "note.text"
        case "winapp_calculator":
            "plus.forwardslash.minus"
        case "winapp_paint":
            "paintpalette"
        default:
            "app.window"
        }
    }
}
