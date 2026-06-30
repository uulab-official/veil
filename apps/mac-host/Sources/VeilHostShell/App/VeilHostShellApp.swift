import AppKit
import SwiftUI
import VeilHostCore

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = HostDashboardModel(
        service: FallbackHostDashboardService(
            primary: VeilHostClient(
                transport: URLSessionWebSocketTransport(
                    url: URL(string: ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444")!
                )
            ),
            fallback: DemoHostDashboardService()
        )
    )
    @State private var vmModel = VMRuntimeModel(service: LocalVMRuntimeService())

    var body: some Scene {
        WindowGroup("Veil", id: "main") {
            ContentView(model: model, vmModel: vmModel)
                .frame(minWidth: 920, minHeight: 560)
                .task {
                    async let hostLoad: Void = model.load()
                    async let vmLoad: Void = vmModel.load()
                    _ = await (hostLoad, vmLoad)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
