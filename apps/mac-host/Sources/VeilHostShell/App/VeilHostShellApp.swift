import AppKit
import SwiftUI
import VeilHostCore

private struct AppFrameProofRecord: Codable {
    var kind = "veilAppFrameProof"
    var generatedAt: Date
    var endpoint: String
    var launchResult: NotepadLaunchResult
    var frame: WindowFrameEvent
    var frameTiming: WindowFrameTiming?
    var frameImagePath: String?
}

private enum AppRuntimeBooterFactory {
    static func make() -> QEMUVMRuntimeBooter {
        if ProcessInfo.processInfo.environment["VEIL_USE_NATIVE_QEMU_DISPLAY"] == "1" {
            return QEMUVMRuntimeBooter.shared
        }

        return QEMUVMRuntimeBooter(
            frontmostRunner: {},
            displayMode: .vncLoopback
        )
    }
}

@main
struct VeilHostShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let vmRuntimeBooter: QEMUVMRuntimeBooter
    private let windowsAppWindowPresenter = WindowsAppWindowPresenter()
    private let agentTransport: URLSessionWebSocketTransport
    @State private var model: HostDashboardModel
    @State private var vmModel: VMRuntimeModel
    @State private var displayMessage: String?
    @State private var agentEventTask: Task<Void, Never>?
    @State private var agentReconnectTask: Task<Void, Never>?

    init() {
        let runtimeBooter = AppRuntimeBooterFactory.make()
        let transport = URLSessionWebSocketTransport(
            url: URL(string: Self.agentURLString)!
        )
        self.vmRuntimeBooter = runtimeBooter
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
        _vmModel = State(
            initialValue: VMRuntimeModel(
                service: LocalVMRuntimeService(bootRunner: runtimeBooter)
            )
        )
    }

    var body: some Scene {
        Window("Veil", id: "main") {
            ContentView(
                model: model,
                vmModel: vmModel,
                startVMAction: startWindowsAndShowDisplay,
                stopVMAction: stopWindowsAndCloseDisplay,
                markWindowsInstalledAction: markWindowsInstalledFromSetup,
                installGuestAgentAction: installGuestAgentFromDisplay,
                launchWindowsAppAction: launchSelectedWindowsAppWindow,
                recordAppFrameProofAction: recordAppFrameProof,
                displayMessage: displayMessage
            )
                .frame(minWidth: 1120, idealWidth: 1440, minHeight: 700, idealHeight: 900)
                .task {
                    configureDockMenuBridge()
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
                    if !restoredLaunches.isEmpty {
                        hideMainWindowForCoherenceIfNeeded()
                    }
                    await recordGuestAgentInstallEvidenceIfNeeded()

                    if Self.shouldStartVMOnLaunch {
                        startWindowsAndShowDisplay()
                    }
                    syncDockTileRuntimeStatus()
                }
                .onChange(of: model.mirrorSessions.count) {
                    syncDockTileRuntimeStatus()
                }
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1440, height: 900)
        .defaultWindowPlacement { _, context in
            let visibleRect = context.defaultDisplay.visibleRect
            let preferredSize = CGSize(width: 1440, height: 900)
            let size = CGSize(
                width: min(preferredSize.width, visibleRect.width * 0.96),
                height: min(preferredSize.height, visibleRect.height * 0.96)
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

                Button("Refresh Windows") {
                    Task {
                        await vmModel.load()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Start Windows") {
                    startWindowsAndShowDisplay()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!vmModel.canStart || vmModel.phase == .loading)

                Button("Stop Windows") {
                    stopWindowsAndCloseDisplay()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!vmModel.canStop || vmModel.phase == .loading)

                if canShowWindowsDisplay {
                    Button("Open Recovery Display") {
                        showWindowsDisplay()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                }

                Button("Install Guest Agent") {
                    installGuestAgentFromDisplay()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!canInstallGuestAgent)

                Button("Mark Windows Installed") {
                    markWindowsInstalledFromSetup()
                }
                .disabled(!canMarkWindowsInstalled)

                Button("Open Windows App") {
                    launchSelectedWindowsAppWindow()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canRequestSelectedAppLaunch)

                Button("Record App Frame Proof") {
                    recordAppFrameProof()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.canRequestSelectedAppLaunch && model.mirrorSessions.isEmpty)
            }
        }

        MenuBarExtra("Veil", systemImage: menuBarSymbolName) {
            VeilMenuBarMenu(
                model: model,
                vmModel: vmModel,
                activateMainWindowAction: activateMainWindow,
                startVMAction: startWindowsAndShowDisplay,
                stopVMAction: stopWindowsAndCloseDisplay,
                showWindowsDisplayAction: showWindowsDisplay,
                markWindowsInstalledAction: markWindowsInstalledFromSetup,
                installGuestAgentAction: installGuestAgentFromDisplay,
                launchWindowsAppAction: launchSelectedWindowsAppWindow,
                launchWindowsAppByIdAction: launchWindowsAppWindow(appId:),
                restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
                focusWindowsAppWindowAction: focusWindowsAppWindow(windowId:),
                closeWindowsAppWindowAction: closeWindowsAppWindow(windowId:),
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
                recordAppFrameProofAction: recordAppFrameProof,
                quietWindowsWhenIdleAction: quietWindowsWhenIdle,
                refreshAppsAction: refreshApps,
                refreshRuntimeAction: refreshRuntime,
                supportsNativeDisplayWindow: vmRuntimeBooter.supportsNativeDisplayWindow
            )
        }
        .defaultLaunchBehavior(.suppressed)
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
                    case .handledWindowCreated(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                        hideMainWindowForCoherenceIfNeeded()
                    case .handledWindowUpdated(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                    case .handledWindowFrame(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        windowsAppWindowPresenter.showWindow(for: session)
                    case .handledWindowClosed(let windowId):
                        windowsAppWindowPresenter.closeWindow(windowId: windowId)
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
                    if !restoredLaunches.isEmpty {
                        hideMainWindowForCoherenceIfNeeded()
                    }

                    if restoredLaunches.isEmpty,
                       let fulfilledLaunch = await model.refreshLiveAgentIfNeeded() {
                        showWindowsAppWindow(for: fulfilledLaunch)
                        hideMainWindowForCoherenceIfNeeded()
                    }
                    await recordGuestAgentInstallEvidenceIfNeeded()
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func startWindowsAndShowDisplay() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = vmRuntimeBooter.supportsNativeDisplayWindow
                    ? "Windows is running in recovery display mode."
                    : "Windows is running inside the main Veil window. Setup evidence refreshes here."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows display could not start: \(errorMessage)"
            }
        }
    }

    private func stopWindowsAndCloseDisplay() {
        Task { @MainActor in
            activateMainWindow()
            await vmModel.stop()

            if vmModel.snapshot?.state == .stopped {
                windowsAppWindowPresenter.closeAll()
                displayMessage = "Windows display closed."
            }
        }
    }

    private func quietWindowsWhenIdle() {
        Task { @MainActor in
            guard model.canQuietRuntimeWhenIdle else {
                displayMessage = model.quietRuntimeStatus().reason
                return
            }

            guard vmModel.canStop && vmModel.phase != .loading else {
                displayMessage = "Windows app windows are closed. Runtime stop will be available after the local VM state refreshes."
                return
            }

            await vmModel.stop()
            if vmModel.snapshot?.state == .stopped {
                displayMessage = "Windows is quiet. No Windows app windows are open."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows could not quiet: \(errorMessage)"
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
                displayMessage = "Starting Windows. Veil will open the app when the guest agent connects."
                startWindowsAndShowDisplay()
                return
            }

            guard let result = model.lastLaunch else {
                return
            }

            showWindowsAppWindow(for: result)
            hideMainWindowForCoherenceIfNeeded()
        }
    }

    private func launchWindowsAppWindow(appId: String) {
        model.selectedAppId = appId
        launchSelectedWindowsAppWindow()
    }

    private func restoreWindowsAppWindows() {
        Task { @MainActor in
            let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
            for launch in restoredLaunches {
                showWindowsAppWindow(for: launch)
            }
            hideMainWindowForCoherenceIfNeeded()
        }
    }

    private func focusWindowsAppWindow(windowId: String) {
        Task { @MainActor in
            let response = await model.focusMirrorSession(windowId: windowId)
            guard response?.accepted == true,
                  let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                return
            }

            windowsAppWindowPresenter.showWindow(for: session)
        }
    }

    private func bringAllWindowsAppWindowsToFront() {
        windowsAppWindowPresenter.bringAllToFront()
        if let focusedSession = model.mirrorSessions.last {
            focusWindowsAppWindow(windowId: focusedSession.id)
        }
    }

    private func closeWindowsAppWindow(windowId: String) {
        Task { @MainActor in
            let response = await model.closeMirrorSession(windowId: windowId)
            guard response?.accepted == true else {
                return
            }

            windowsAppWindowPresenter.closeWindow(windowId: windowId)
        }
    }

    private func closeAllWindowsAppWindows() {
        Task { @MainActor in
            let responses = await model.closeAllMirrorSessions()
            for response in responses where response.accepted {
                windowsAppWindowPresenter.closeWindow(windowId: response.windowId)
            }
        }
    }

    private func configureDockMenuBridge() {
        appDelegate.reopenHandler = {
            if model.mirrorSessions.isEmpty {
                activateMainWindow()
            } else {
                bringAllWindowsAppWindowsToFront()
            }
        }
        appDelegate.dockMenuProvider = {
            AppRuntimeDockMenuFactory.makeMenu(
                model: model,
                vmModel: vmModel,
                activateMainWindowAction: activateMainWindow,
                bringAllWindowsAppWindowsToFrontAction: bringAllWindowsAppWindowsToFront,
                focusWindowsAppWindowAction: focusWindowsAppWindow(windowId:),
                closeWindowsAppWindowAction: closeWindowsAppWindow(windowId:),
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindows,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindows,
                launchWindowsAppByIdAction: launchWindowsAppWindow(appId:),
                startVMAction: startWindowsAndShowDisplay,
                stopVMAction: stopWindowsAndCloseDisplay,
                quietWindowsWhenIdleAction: quietWindowsWhenIdle
            )
        }
    }

    private func syncDockTileRuntimeStatus() {
        DockTileRuntimePresenter.update(model.runtimeStatusReport().dockIntegration)
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

    private func hideMainWindowForCoherenceIfNeeded() {
        guard model.connectionMode == .agent else {
            return
        }

        MainWindowChrome.hideMainWindow()
    }

    private func recordAppFrameProof() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Recording Windows app launch and first-frame proof."

            if model.apps.isEmpty {
                await model.load()
            }

            if model.lastLaunch == nil {
                await model.launchSelectedApp()
            }

            guard let result = model.lastLaunch else {
                if model.pendingLaunchAppId != nil,
                   !model.hasLiveAgentConnection,
                   vmModel.canStart {
                    displayMessage = "Windows will start first. Run proof recording again after the guest agent connects."
                    startWindowsAndShowDisplay()
                } else {
                    displayMessage = "App frame proof could not start: \(model.errorMessage ?? "No Windows app launch result.")"
                }
                return
            }

            showWindowsAppWindow(for: result)

            guard let frame = await waitForFirstFrame(windowId: result.window.windowId) else {
                displayMessage = "App frame proof timed out waiting for the first frame from \(result.window.title)."
                return
            }
            let frameTiming = model.mirrorSessions.first(where: { $0.id == result.window.windowId })?.frameTiming

            do {
                let url = try writeAppFrameProof(launchResult: result, frame: frame, frameTiming: frameTiming)
                displayMessage = "App frame proof saved: \(url.path)"
            } catch {
                displayMessage = "App frame proof could not be saved: \(userMessage(for: error))"
            }
        }
    }

    private func waitForFirstFrame(windowId: String, timeoutSeconds: Double = 10) async -> WindowFrameEvent? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let frame = model.mirrorSessions.first(where: { $0.id == windowId })?.latestFrame {
                return frame
            }

            try? await Task.sleep(for: .milliseconds(150))
        }

        return nil
    }

    private func writeAppFrameProof(
        launchResult: NotepadLaunchResult,
        frame: WindowFrameEvent,
        frameTiming: WindowFrameTiming?
    ) throws -> URL {
        let directory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("App Frame Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.diagnosticTimestamp()
        let imageURL = directory.appendingPathComponent("app-frame-\(stamp).png")
        if let data = frame.encodedPayloadData {
            try data.write(to: imageURL, options: .atomic)
        }

        let proof = AppFrameProofRecord(
            generatedAt: Date(),
            endpoint: Self.agentURLString,
            launchResult: launchResult,
            frame: frame,
            frameTiming: frameTiming,
            frameImagePath: FileManager.default.fileExists(atPath: imageURL.path) ? imageURL.path : nil
        )
        let outputURL = directory.appendingPathComponent("app-frame-proof-\(stamp).json")
        let data = try JSONEncoder.veilDiagnostics.encode(proof)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func diagnosticTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
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

    private func showWindowsDisplay() {
        activateMainWindow()
        if vmRuntimeBooter.showConsoleIfRunning() {
            displayMessage = "Recovery display brought forward."
        } else {
            displayMessage = "No recovery display is attached. Windows normally runs inside the main Veil window."
        }
    }

    private func installGuestAgentFromDisplay() {
        Task { @MainActor in
            activateMainWindow()
            displayMessage = "Sending the Veil guest agent installer to Windows."
            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "Guest agent installer sent. Veil will connect when the Windows agent starts."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()
            } catch {
                displayMessage = "Guest agent install could not start: \(userMessage(for: error))"
            }
        }
    }

    private func markWindowsInstalledFromSetup() {
        Task { @MainActor in
            activateMainWindow()
            await vmModel.markWindowsInstalled()
            if vmModel.snapshot?.windowsInstalled == true {
                displayMessage = "Windows is marked installed. Veil will boot from the local disk and leave the installer ISO detached."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows install state could not be updated: \(errorMessage)"
            }
        }
    }

    private func refreshRuntime() {
        Task {
            await vmModel.load()
        }
    }

    private func refreshApps() {
        Task { @MainActor in
            await model.load()
            await recordGuestAgentInstallEvidenceIfNeeded()
        }
    }

    private func activateMainWindow() {
        Task { @MainActor in
            MainWindowChrome.showMainWindow()
        }
    }

    private var canShowWindowsDisplay: Bool {
        vmRuntimeBooter.supportsNativeDisplayWindow
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
    }

    private var canInstallGuestAgent: Bool {
        canShowWindowsDisplay && vmModel.snapshot?.installEvidence.kind != .guestAgent
    }

    private var canMarkWindowsInstalled: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && vmModel.snapshot?.installEvidence.isInstalled != true
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

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var dockMenuProvider: (() -> NSMenu?)?
    var reopenHandler: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyBundledAppIcon()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            MainWindowChrome.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenHandler?()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockMenuProvider?()
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

    var model: HostDashboardModel
    var vmModel: VMRuntimeModel
    var activateMainWindowAction: () -> Void
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var launchWindowsAppByIdAction: (String) -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var focusWindowsAppWindowAction: (String) -> Void
    var closeWindowsAppWindowAction: (String) -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var recordAppFrameProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var refreshAppsAction: () -> Void
    var refreshRuntimeAction: () -> Void
    var supportsNativeDisplayWindow: Bool

    var body: some View {
        Button("Open Veil", systemImage: "macwindow") {
            openMainWindow()
        }

        Divider()

        Label(runtimeStatusTitle, systemImage: runtimeStatusSymbolName)

        if !model.mirrorSessions.isEmpty {
            Label(runningAppsTitle, systemImage: "rectangle.3.group")
        }

        Divider()

        if !model.mirrorSessions.isEmpty {
            Menu("Running Windows Apps", systemImage: "rectangle.3.group") {
                ForEach(model.mirrorSessions) { session in
                    Menu(session.window.title, systemImage: "macwindow") {
                        Button("Bring to Front", systemImage: "arrow.up.forward.app") {
                            focusWindowsAppWindowAction(session.id)
                        }
                        .disabled(!model.canFocusMirrorSession(windowId: session.id))

                        Button("Close", systemImage: "xmark.circle") {
                            closeWindowsAppWindowAction(session.id)
                        }
                        .disabled(!model.canCloseMirrorSession(windowId: session.id))
                    }
                }

                Divider()

                Button("Close All", systemImage: "xmark.circle.fill") {
                    closeAllWindowsAppWindowsAction()
                }
                .disabled(!model.canCloseAllMirrorSessions)
            }

            Divider()
        }

        if model.apps.isEmpty {
            Button("Load Windows Apps", systemImage: "square.grid.2x2") {
                openMainWindow()
                refreshAppsAction()
            }
            .disabled(model.phase == .loading || model.phase == .launching)
        } else {
            Menu("Windows Apps", systemImage: "square.grid.2x2") {
                ForEach(model.apps) { app in
                    Button(app.name, systemImage: symbolName(for: app)) {
                        if !model.hasLiveAgentConnection {
                            openMainWindow()
                        }
                        launchWindowsAppByIdAction(app.id)
                    }
                    .disabled(!model.canRequestAppLaunch(appId: app.id))
                }
            }
        }

        if !model.restorableAppIds.isEmpty {
            Button("Restore Previous Apps", systemImage: "arrow.clockwise.square") {
                restoreWindowsAppWindowsAction()
            }
            .disabled(!model.canRestoreMirrorSessions)
        }

        Button("Record App Proof", systemImage: "checkmark.seal") {
            openMainWindow()
            recordAppFrameProofAction()
        }
        .disabled(!model.canRequestSelectedAppLaunch && model.mirrorSessions.isEmpty)

        Divider()

        Button("Start Windows", systemImage: "play.fill") {
            openMainWindow()
            startVMAction()
        }
        .disabled(!vmModel.canStart || vmModel.phase == .loading)

        if canShowWindowsDisplay {
            Button("Open Recovery Display", systemImage: "display") {
                openMainWindow()
                showWindowsDisplayAction()
            }
        }

        Button("Install Guest Agent", systemImage: "person.crop.circle.badge.plus") {
            openMainWindow()
            installGuestAgentAction()
        }
        .disabled(!canInstallGuestAgent)

        Button("Mark Windows Installed", systemImage: "checkmark.seal") {
            openMainWindow()
            markWindowsInstalledAction()
        }
        .disabled(!canMarkWindowsInstalled)

        Button("Stop Windows", systemImage: "stop.fill") {
            openMainWindow()
            stopVMAction()
        }
        .disabled(!vmModel.canStop || vmModel.phase == .loading)

        if model.canQuietRuntimeWhenIdle {
            Button("Quiet Windows", systemImage: "moon.zzz.fill") {
                quietWindowsWhenIdleAction()
            }
            .disabled(!vmModel.canStop || vmModel.phase == .loading)
        }

        Divider()

        Button("Refresh Windows", systemImage: "arrow.clockwise") {
            refreshRuntimeAction()
        }
        .disabled(vmModel.phase == .loading)

        Divider()

        Button("Quit Veil", systemImage: "power") {
            NSApp.terminate(nil)
        }
    }

    private var canShowWindowsDisplay: Bool {
        supportsNativeDisplayWindow
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
    }

    private var canInstallGuestAgent: Bool {
        canShowWindowsDisplay && vmModel.snapshot?.installEvidence.kind != .guestAgent
    }

    private var canMarkWindowsInstalled: Bool {
        (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && vmModel.snapshot?.installEvidence.isInstalled != true
    }

    private var runtimeStatusTitle: String {
        switch vmModel.snapshot?.state {
        case .running:
            "Windows Running"
        case .starting:
            "Windows Starting"
        case .suspended:
            "Windows Suspended"
        case .failed:
            "Windows Needs Attention"
        case .unsupported:
            "Windows Unsupported"
        case .notConfigured:
            "Windows Not Configured"
        case .stopped, nil:
            "Windows Stopped"
        }
    }

    private var runtimeStatusSymbolName: String {
        switch vmModel.snapshot?.state {
        case .running:
            "play.circle.fill"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .suspended:
            "pause.circle"
        case .failed, .unsupported:
            "exclamationmark.triangle"
        case .notConfigured:
            "plus.circle"
        case .stopped, nil:
            "stop.circle"
        }
    }

    private var runningAppsTitle: String {
        let count = model.mirrorSessions.count
        return count == 1 ? "1 Windows App Running" : "\(count) Windows Apps Running"
    }

    private func openMainWindow() {
        openWindow(id: "main")
        activateMainWindowAction()
        DispatchQueue.main.async {
            MainWindowChrome.showMainWindow()
        }
    }

    private func symbolName(for app: WindowsApp) -> String {
        switch app.iconId {
        case "icon_notepad":
            "note.text"
        case "icon_calculator":
            "plus.forwardslash.minus"
        case "icon_paint":
            "paintpalette"
        default:
            "macwindow"
        }
    }
}

@MainActor
private enum MainWindowChrome {
    static func configureAndCompactMainWindow() {
        let windows = mainWindows
        guard let window = windows.first else {
            return
        }

        for duplicate in windows.dropFirst() {
            duplicate.close()
        }

        configure(window)
        fitToPreferredSize(window)
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        configureAndCompactMainWindow()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    private static var mainWindow: NSWindow? {
        mainWindows.first
    }

    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier?.rawValue == "main" || window.title == "Veil"
        }
    }

    private static func configure(_ window: NSWindow) {
        window.minSize = NSSize(width: 1120, height: 700)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private static func fitToPreferredSize(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let preferredSize = NSSize(width: 1440, height: 900)
        let targetSize = NSSize(
            width: min(preferredSize.width, visibleFrame.width * 0.96),
            height: min(preferredSize.height, visibleFrame.height * 0.96)
        )
        let sizeDelta = abs(window.frame.width - targetSize.width) + abs(window.frame.height - targetSize.height)
        guard sizeDelta > 16 else {
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: targetSize), display: true, animate: false)
    }
}

private struct StandaloneMainWindowRoot: View {
    private let vmRuntimeBooter: QEMUVMRuntimeBooter
    @State private var model: HostDashboardModel
    @State private var vmModel: VMRuntimeModel
    @State private var displayMessage: String?

    init() {
        let runtimeBooter = AppRuntimeBooterFactory.make()
        let transport = URLSessionWebSocketTransport(
            url: URL(string: Self.agentURLString)!
        )
        self.vmRuntimeBooter = runtimeBooter
        _model = State(
            initialValue: HostDashboardModel(
                service: FallbackHostDashboardService(
                    primary: VeilHostClient(transport: transport),
                    fallback: DemoHostDashboardService(),
                    primaryEndpointDescription: Self.agentURLString
                )
            )
        )
        _vmModel = State(
            initialValue: VMRuntimeModel(
                service: LocalVMRuntimeService(bootRunner: runtimeBooter)
            )
        )
    }

    var body: some View {
        ContentView(
            model: model,
            vmModel: vmModel,
            startVMAction: startWindowsAndShowDisplay,
            stopVMAction: stopWindowsAndCloseDisplay,
            markWindowsInstalledAction: markWindowsInstalledFromSetup,
            installGuestAgentAction: installGuestAgentFromDisplay,
            launchWindowsAppAction: launchSelectedWindowsApp,
            recordAppFrameProofAction: {},
            displayMessage: displayMessage
        )
        .frame(minWidth: 1120, idealWidth: 1440, minHeight: 700, idealHeight: 900)
        .task {
            async let hostLoad: Void = model.load()
            async let vmLoad: Void = vmModel.load()
            _ = await (hostLoad, vmLoad)
            await recordGuestAgentInstallEvidenceIfNeeded()
        }
    }

    private static var agentURLString: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

    private func startWindowsAndShowDisplay() {
        Task { @MainActor in
            displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
            await vmModel.start()

            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = vmRuntimeBooter.supportsNativeDisplayWindow
                    ? "Windows is running in recovery display mode."
                    : "Windows is running inside the main Veil window. Setup evidence refreshes here."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows display could not start: \(errorMessage)"
            }
        }
    }

    private func stopWindowsAndCloseDisplay() {
        Task { @MainActor in
            await vmModel.stop()
            if vmModel.snapshot?.state == .stopped {
                displayMessage = "Windows display closed."
            }
        }
    }

    private func showWindowsDisplay() {
        if vmRuntimeBooter.showConsoleIfRunning() {
            displayMessage = "Recovery display brought forward."
        } else {
            displayMessage = "No recovery display is attached. Windows normally runs inside the main Veil window."
        }
    }

    private func installGuestAgentFromDisplay() {
        Task { @MainActor in
            displayMessage = "Sending the Veil guest agent installer to Windows."
            do {
                _ = try await vmRuntimeBooter.installGuestAgentFromAttachedMedia()
                displayMessage = "Guest agent installer sent. Veil will connect when the Windows agent starts."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()
            } catch {
                displayMessage = "Guest agent install could not start: \(userMessage(for: error))"
            }
        }
    }

    private func markWindowsInstalledFromSetup() {
        Task { @MainActor in
            await vmModel.markWindowsInstalled()
            if vmModel.snapshot?.windowsInstalled == true {
                displayMessage = "Windows is marked installed. Veil will boot from the local disk and leave the installer ISO detached."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = "Windows install state could not be updated: \(errorMessage)"
            }
        }
    }

    private func launchSelectedWindowsApp() {
        Task { @MainActor in
            await model.launchSelectedApp()
        }
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

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
