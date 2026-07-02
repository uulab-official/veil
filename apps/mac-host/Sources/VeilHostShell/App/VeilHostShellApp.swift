import AppKit
import SwiftUI
import VeilHostCore

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let vmRuntimeBooter = QEMUVMRuntimeBooter.shared
    private let windowsAppWindowPresenter = WindowsAppWindowPresenter()
    private let agentTransport: URLSessionWebSocketTransport
    @State private var model: HostDashboardModel
    @State private var vmModel = VMRuntimeModel(
        service: LocalVMRuntimeService(bootRunner: QEMUVMRuntimeBooter.shared)
    )
    @State private var consoleMessage: String?
    @State private var agentEventTask: Task<Void, Never>?
    @State private var agentReconnectTask: Task<Void, Never>?

    init() {
        let transport = URLSessionWebSocketTransport(
            url: URL(string: Self.agentURLString)!
        )
        self.agentTransport = transport
        _model = State(
            initialValue: HostDashboardModel(
                service: FallbackHostDashboardService(
                    primary: VeilHostClient(
                        transport: transport
                    ),
                    fallback: DemoHostDashboardService(),
                    primaryEndpointDescription: Self.agentURLString
                )
            )
        )
    }

    var body: some Scene {
        Window("Veil", id: "main") {
            ContentView(
                model: model,
                vmModel: vmModel,
                startVMAction: startVMAndShowConsole,
                stopVMAction: stopVMAndCloseConsole,
                showVMConsoleAction: showVMConsole,
                launchWindowsAppAction: launchSelectedWindowsAppWindow,
                consoleMessage: consoleMessage
            )
                .frame(minWidth: 960, idealWidth: 1000, minHeight: 530, idealHeight: 560)
                .task {
                    configureWindowsAppWindowCloseBridge()
                    startAgentEventPumpIfNeeded()
                    startAgentReconnectPollerIfNeeded()

                    await model.loadRestoreIntent()
                    async let hostLoad: Void = model.load()
                    async let vmLoad: Void = vmModel.load()
                    _ = await (hostLoad, vmLoad)
                    let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
                    for launch in restoredLaunches {
                        showWindowsAppWindow(for: launch)
                    }
                    await recordGuestAgentInstallEvidenceIfNeeded()

                    if Self.shouldStartVMOnLaunch {
                        startVMAndShowConsole()
                    }
                }
        }
        .defaultSize(width: 1000, height: 560)
        .defaultWindowPlacement { _, context in
            let visibleRect = context.defaultDisplay.visibleRect
            let preferredSize = CGSize(width: 1000, height: 560)
            let size = CGSize(
                width: min(preferredSize.width, max(min(960, visibleRect.width), visibleRect.width * 0.68)),
                height: min(preferredSize.height, max(min(530, visibleRect.height), visibleRect.height * 0.58))
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
                        await recordGuestAgentInstallEvidenceIfNeeded()
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

        MenuBarExtra("Veil", systemImage: menuBarSymbolName) {
            VeilMenuBarMenu(
                vmModel: vmModel,
                activateMainWindowAction: activateMainWindow,
                startVMAction: startVMAndShowConsole,
                stopVMAction: stopVMAndCloseConsole,
                showVMConsoleAction: showVMConsole,
                refreshRuntimeAction: refreshRuntime
            )
        }
        .menuBarExtraStyle(.menu)
    }

    private static var agentURLString: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

    private static var shouldStartVMOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--start-vm")
    }

    private func recordGuestAgentInstallEvidenceIfNeeded() async {
        guard model.hasLiveAgentConnection,
              let agentVersion = model.health?.agentVersion,
              vmModel.snapshot?.profileName != nil,
              vmModel.snapshot?.installEvidence.kind != .guestAgent else {
            return
        }

        await vmModel.markGuestAgentConnected(agentVersion: agentVersion)
    }

    private func startAgentEventPumpIfNeeded() {
        guard agentEventTask == nil else {
            return
        }

        agentEventTask = Task { @MainActor in
            while !Task.isCancelled {
                await model.consumeProtocolMessages(from: agentTransport) { result in
                    switch result {
                    case .handledWindowFrame(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                    case .handledClipboardText:
                        syncGuestClipboardToPasteboard()
                    case .ignored:
                        return
                    }
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startAgentReconnectPollerIfNeeded() {
        guard agentReconnectTask == nil else {
            return
        }

        agentReconnectTask = Task { @MainActor in
            while !Task.isCancelled {
                let vmState = vmModel.snapshot?.state
                let shouldPoll = (vmState == .running || vmState == .starting) && !model.hasLiveAgentConnection
                if shouldPoll {
                    let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
                    for launch in restoredLaunches {
                        showWindowsAppWindow(for: launch)
                    }

                    if restoredLaunches.isEmpty,
                       let fulfilledLaunch = await model.refreshLiveAgentIfNeeded() {
                        showWindowsAppWindow(for: fulfilledLaunch)
                    }
                    await recordGuestAgentInstallEvidenceIfNeeded()
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func startVMAndShowConsole() {
        Task { @MainActor in
            activateMainWindow()
            consoleMessage = "Opening the local QEMU Windows console."
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                if vmRuntimeBooter.showConsoleIfRunning() {
                    consoleMessage = "QEMU Console is open. If it lands in UEFI Shell, the Windows boot recipe still needs work."
                } else {
                    consoleMessage = "Windows runtime is starting, but the QEMU display is not frontmost yet. Try Show Console again after a moment."
                }
            } else if let errorMessage = vmModel.errorMessage {
                consoleMessage = "Windows console could not start: \(errorMessage)"
            }
        }
    }

    private func stopVMAndCloseConsole() {
        Task { @MainActor in
            activateMainWindow()
            await vmModel.stop()

            if vmModel.snapshot?.state == .stopped {
                windowsAppWindowPresenter.closeAll()
                consoleMessage = "Windows console closed."
            }
        }
    }

    private func launchSelectedWindowsAppWindow() {
        Task { @MainActor in
            if model.apps.isEmpty {
                await model.load()
            }

            await model.launchSelectedApp()

            if model.pendingLaunchAppId != nil,
               !model.hasLiveAgentConnection,
               vmModel.canStart {
                consoleMessage = "Starting Windows. Veil will open the app when the guest agent connects."
                startVMAndShowConsole()
                return
            }

            guard let result = model.lastLaunch else {
                return
            }

            showWindowsAppWindow(for: result)
        }
    }

    private func showWindowsAppWindow(for result: NotepadLaunchResult) {
        let session = model.mirrorSessions.first { $0.id == result.window.windowId }
                ?? WindowMirrorSession(
                    window: result.window,
                    connectionMode: model.connectionMode,
                    captureState: .unavailable
                )
        windowsAppWindowPresenter.showWindow(for: session)
    }

    private func configureWindowsAppWindowCloseBridge() {
        windowsAppWindowPresenter.onUserWindowClose = { windowId in
            Task { @MainActor in
                _ = await model.closeMirrorSession(windowId: windowId)
            }
        }
        windowsAppWindowPresenter.onMouseInput = { windowId, event, x, y in
            Task { @MainActor in
                await model.sendMouseInput(windowId: windowId, event: event, x: x, y: y)
            }
        }
        windowsAppWindowPresenter.onKeyInput = { windowId, event, key, windowsVirtualKey, modifiers in
            Task { @MainActor in
                await model.sendKeyInput(
                    windowId: windowId,
                    event: event,
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            }
        }
        windowsAppWindowPresenter.onPasteShortcut = { windowId, key, windowsVirtualKey, modifiers, text in
            Task { @MainActor in
                await model.sendHostClipboardText(text)
                await model.sendKeyInput(
                    windowId: windowId,
                    event: "keyDown",
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
                await model.sendKeyInput(
                    windowId: windowId,
                    event: "keyUp",
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            }
        }
    }

    @MainActor
    private func syncGuestClipboardToPasteboard() {
        guard let text = model.latestGuestClipboardText else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func showVMConsole() {
        activateMainWindow()
        if vmRuntimeBooter.showConsoleIfRunning() {
            consoleMessage = "QEMU Console is open. If it lands in UEFI Shell, the Windows boot recipe still needs work."
        } else {
            consoleMessage = "No active QEMU display is attached yet. Start Windows first, then open the console."
        }
    }

    private func refreshRuntime() {
        Task {
            await vmModel.load()
        }
    }

    private func activateMainWindow() {
        Task { @MainActor in
            MainWindowChrome.showMainWindow()
        }
    }

    private var canShowVMConsole: Bool {
        vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    }

    private var menuBarSymbolName: String {
        switch vmModel.snapshot?.state {
        case .running:
            "display"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .failed, .unsupported:
            "exclamationmark.triangle"
        default:
            "play.rectangle"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyBundledAppIcon()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            MainWindowChrome.configureAndCompactMainWindow()
        }
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

private struct VeilMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var vmModel: VMRuntimeModel
    var activateMainWindowAction: () -> Void
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showVMConsoleAction: () -> Void
    var refreshRuntimeAction: () -> Void

    var body: some View {
        Button("Open Veil", systemImage: "macwindow") {
            openMainWindow()
        }

        Divider()

        Button("Start Windows", systemImage: "play.fill") {
            openMainWindow()
            startVMAction()
        }
        .disabled(!vmModel.canStart || vmModel.phase == .loading)

        Button("Show Console", systemImage: "display") {
            openMainWindow()
            showVMConsoleAction()
        }
        .disabled(!canShowVMConsole)

        Button("Stop Windows", systemImage: "stop.fill") {
            openMainWindow()
            stopVMAction()
        }
        .disabled(!vmModel.canStop || vmModel.phase == .loading)

        Divider()

        Button("Refresh Runtime", systemImage: "arrow.clockwise") {
            refreshRuntimeAction()
        }
        .disabled(vmModel.phase == .loading)

        Divider()

        Button("Quit Veil", systemImage: "power") {
            NSApp.terminate(nil)
        }
    }

    private var canShowVMConsole: Bool {
        vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    }

    private func openMainWindow() {
        openWindow(id: "main")
        activateMainWindowAction()
        DispatchQueue.main.async {
            MainWindowChrome.showMainWindow()
        }
    }
}

@MainActor
private enum MainWindowChrome {
    static func configureAndCompactMainWindow() {
        guard let window = mainWindow else {
            return
        }

        configure(window)
        compact(window)
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        configureAndCompactMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Veil" }
    }

    private static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private static func compact(_ window: NSWindow) {
        let targetSize = NSSize(width: 1000, height: 560)
        guard window.frame.height > targetSize.height + 40 else {
            return
        }

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: targetSize), display: true, animate: false)
    }
}
