import AppKit
import SwiftUI
import VeilHostCore

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let vmConsolePresenter = VMConsoleWindowPresenter(bootRunner: VirtualizationVMRuntimeBooter.shared)
    private let windowsAppWindowPresenter = WindowsAppWindowPresenter()
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
    @State private var consoleMessage: String?

    var body: some Scene {
        WindowGroup("Veil", id: "main") {
            ContentView(
                model: model,
                vmModel: vmModel,
                startVMAction: startVMAndShowConsole,
                stopVMAction: stopVMAndCloseConsole,
                showVMConsoleAction: showVMConsole,
                launchWindowsAppAction: launchSelectedWindowsAppWindow,
                consoleMessage: consoleMessage
            )
                .frame(minWidth: 1180, idealWidth: 1360, minHeight: 740, idealHeight: 860)
                .task {
                    async let hostLoad: Void = model.load()
                    async let vmLoad: Void = vmModel.load()
                    _ = await (hostLoad, vmLoad)

                    if Self.shouldStartVMOnLaunch {
                        startVMAndShowConsole()
                    }
                }
        }
        .defaultSize(width: 1360, height: 860)
        .defaultWindowPlacement { _, context in
            let visibleRect = context.defaultDisplay.visibleRect
            let preferredSize = CGSize(width: 1360, height: 860)
            let size = CGSize(
                width: min(preferredSize.width, max(min(1180, visibleRect.width), visibleRect.width * 0.90)),
                height: min(preferredSize.height, max(min(740, visibleRect.height), visibleRect.height * 0.86))
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

                Button("Show VM Console") {
                    showVMConsole()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!canShowVMConsole)

                Button("Open Windows App Window") {
                    launchSelectedWindowsAppWindow()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private static var agentURLString: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

    private static var shouldStartVMOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--start-vm")
    }

    private func startVMAndShowConsole() {
        Task { @MainActor in
            consoleMessage = "Starting Windows setup. The VM Console window will open as soon as Veil receives a local display."
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                if vmConsolePresenter.showConsoleIfAvailable() {
                    consoleMessage = "VM Console is open. Windows setup appears in that separate display window."
                } else {
                    consoleMessage = "Windows runtime is starting, but the display is not attached yet. Try Show Console again after a moment."
                }
            } else if let errorMessage = vmModel.errorMessage {
                consoleMessage = "Windows setup could not start: \(errorMessage)"
            }
        }
    }

    private func stopVMAndCloseConsole() {
        Task { @MainActor in
            await vmModel.stop()

            if vmModel.snapshot?.state == .stopped {
                vmConsolePresenter.closeConsole()
                windowsAppWindowPresenter.closeAll()
                consoleMessage = "Windows setup console closed."
            }
        }
    }

    private func launchSelectedWindowsAppWindow() {
        Task { @MainActor in
            if model.apps.isEmpty {
                await model.load()
            }

            await model.launchSelectedApp()

            guard let result = model.lastLaunch else {
                return
            }

            windowsAppWindowPresenter.showWindow(
                for: result.window,
                connectionMode: model.connectionMode,
                supportsCapture: model.health?.capabilities.windowCapture == true
            )
        }
    }

    private func showVMConsole() {
        if vmConsolePresenter.showConsoleIfAvailable() {
            consoleMessage = "VM Console is open. Windows setup appears in that separate display window."
        } else {
            consoleMessage = "No active Windows display is attached yet. Start the VM first, then open the console."
        }
    }

    private var canShowVMConsole: Bool {
        vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyBundledAppIcon()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func applyBundledAppIcon() {
        guard let iconURL = Bundle.main.url(forResource: "VeilAppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = icon
    }
}
