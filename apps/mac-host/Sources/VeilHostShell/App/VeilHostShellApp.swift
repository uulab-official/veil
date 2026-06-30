import AppKit
import SwiftUI
import VeilHostCore

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let vmConsolePresenter = VMConsoleWindowPresenter(bootRunner: VirtualizationVMRuntimeBooter.shared)
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
    @State private var vmModel = VMRuntimeModel(
        service: LocalVMRuntimeService(bootRunner: VirtualizationVMRuntimeBooter.shared)
    )

    var body: some Scene {
        WindowGroup("Veil", id: "main") {
            ContentView(
                model: model,
                vmModel: vmModel,
                startVMAction: startVMAndShowConsole,
                stopVMAction: stopVMAndCloseConsole
            )
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
                    startVMAndShowConsole()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!vmModel.canStart || vmModel.phase == .loading)

                Button("Stop VM") {
                    stopVMAndCloseConsole()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!vmModel.canStop || vmModel.phase == .loading)

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

    private func startVMAndShowConsole() {
        Task { @MainActor in
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                vmConsolePresenter.showConsoleIfAvailable()
            }
        }
    }

    private func stopVMAndCloseConsole() {
        Task { @MainActor in
            await vmModel.stop()

            if vmModel.snapshot?.state == .stopped {
                vmConsolePresenter.closeConsole()
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
