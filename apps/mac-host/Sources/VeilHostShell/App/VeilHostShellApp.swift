import SwiftUI
import VeilHostCore

@main
struct VeilHostShellApp: App {
    @State private var model = HostDashboardModel(
        service: VeilHostClient(
            transport: URLSessionWebSocketTransport(
                url: URL(string: ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444")!
            )
        )
    )

    var body: some Scene {
        WindowGroup("Veil", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 920, minHeight: 560)
                .task {
                    await model.load()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Agent") {
                    Task {
                        await model.load()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Launch Notepad") {
                    Task {
                        await model.launchNotepad()
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}
