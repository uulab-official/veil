import SwiftUI
import VeilHostCore

struct AppsView: View {
    var apps: [WindowsApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Windows Apps")
                .font(.headline)

            if apps.isEmpty {
                ContentUnavailableView(
                    "No Apps Loaded",
                    systemImage: "square.grid.2x2",
                    description: Text("Refresh the agent to load available Windows apps.")
                )
            } else {
                Table(apps) {
                    TableColumn("Name") { app in
                        Text(app.name)
                    }
                    TableColumn("Publisher") { app in
                        Text(app.publisher)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Executable") { app in
                        Text(app.exePath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
