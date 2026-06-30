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
                    url: URL(string: Self.agentURLString)!
                )
            ),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: Self.agentURLString
        )
    )
    @State private var vmModel = VMRuntimeModel(service: LocalVMRuntimeService())

    var body: some Scene {
        WindowGroup("Veil", id: "main") {
            ContentView(model: model, vmModel: vmModel)
                .frame(minWidth: 1040, idealWidth: 1180, minHeight: 680, idealHeight: 760)
                .task {
                    async let hostLoad: Void = model.load()
                    async let vmLoad: Void = vmModel.load()
                    _ = await (hostLoad, vmLoad)
                }
        }
        .defaultSize(width: 1180, height: 760)
        .defaultWindowPlacement { _, context in
            let visibleRect = context.defaultDisplay.visibleRect
            let size = CGSize(
                width: min(1180, visibleRect.width),
                height: min(760, visibleRect.height)
            )
            return WindowPlacement(size: size)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh All") {
                    Task {
                        async let hostLoad: Void = model.load()
                        async let vmLoad: Void = vmModel.load()
                        _ = await (hostLoad, vmLoad)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Refresh Runtime") {
                    Task {
                        await vmModel.load()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Start VM") {
                    Task {
                        await vmModel.start()
                    }
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!vmModel.canStart || vmModel.phase == .loading)

                Button("Launch Notepad") {
                    Task {
                        await model.launchNotepad()
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private static var agentURLString: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
