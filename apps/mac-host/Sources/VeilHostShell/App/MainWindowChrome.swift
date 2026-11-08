import AppKit
import SwiftUI
import VeilHostCore

@MainActor
enum MainWindowChrome {
    private static var fallbackWindowController: NSWindowController?
    private static var registeredMainWindowContent: AnyView?

    static func registerMainWindowContent(_ content: AnyView) {
        registeredMainWindowContent = content
    }

    static func configureAndCompactMainWindow() {
        let windows = mainWindows
        guard let window = windows.first ?? createFallbackMainWindow() else {
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
        activateApplication()
        mainWindow?.makeKeyAndOrderFront(nil)
        // AppKit can accept the activation request before the scene's window has become key.
        // Repeat it after ordering the window so a Finder/Dock launch reliably lands in the
        // Veil window instead of leaving a visible but background launcher.
        activateApplication()
    }

    static func hideMainWindow() {
        let windows = mainWindows
        guard let window = windows.first else {
            return
        }

        for duplicate in windows.dropFirst() {
            duplicate.close()
        }

        window.orderOut(nil)
    }

    private static var mainWindow: NSWindow? {
        mainWindows.first
    }

    static var hasMainWindow: Bool {
        !mainWindows.isEmpty
    }

    static func launchReport(appIconSource: AppIconSource) -> MainWindowLaunchReport {
        let windows = mainWindows
        let window = windows.first
        return MainWindowLaunchReport(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            activationPolicy: activationPolicyName(NSApp.activationPolicy()),
            mainWindowCount: windows.count,
            visibleMainWindowCount: windows.filter(\.isVisible).count,
            duplicateMainWindowCount: max(0, windows.count - 1),
            isAppActive: NSApp.isActive,
            isMainWindowKey: window?.isKeyWindow ?? false,
            frame: MainWindowFrameReport(window?.frame ?? .zero),
            minWidth: Double(window?.minSize.width ?? .zero),
            minHeight: Double(window?.minSize.height ?? .zero),
            titlebarAppearsTransparent: window?.titlebarAppearsTransparent ?? false,
            hasFullSizeContentView: window?.styleMask.contains(.fullSizeContentView) ?? false,
            appIconSource: appIconSource
        )
    }

    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier?.rawValue == "main"
        }
    }

    private static func createFallbackMainWindow() -> NSWindow? {
        if let controller = fallbackWindowController,
           let window = controller.window {
            if !window.isVisible {
                controller.showWindow(nil)
            }
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: MainWindowLayout.preferredSize.width,
                    height: MainWindowLayout.preferredSize.height
                )
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.title = "Veil"
        let rootView = registeredMainWindowContent ?? AnyView(StandaloneMainWindowRoot())
        window.contentViewController = NSHostingController(rootView: rootView)

        let controller = NSWindowController(window: window)
        fallbackWindowController = controller
        controller.showWindow(nil)
        return window
    }

    private static func configure(_ window: NSWindow) {
        let visibleSize = window.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size
            ?? MainWindowLayout.preferredSize
        window.minSize = MainWindowLayout.minimumSize(for: visibleSize)
        window.maxSize = NSSize(width: 2048, height: 1536)
        // The SwiftUI toolbar and navigation title are the Parallels-style machine toolbar, so the
        // window keeps both; only the titlebar background is blended into the content.
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    }

    private static func activateApplication() {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private static func fitToPreferredSize(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let targetSize = MainWindowLayout.fittedSize(for: visibleFrame.size)
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

    private static func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }
}

struct StandaloneMainWindowRoot: View {
    let vmRuntimeBooter: AppRuntimeBooter
    let qemuConsoleWindowPresenter = QEMUConsoleWindowPresenter()
    let agentConnectionPlan: AppGuestAgentConnectionPlan
    @State var model: HostDashboardModel
    @State var vmModel: VMRuntimeModel
    @State var displayMessage: String?
    @State var shellNavigation = ShellNavigation()

    init() {
        let runtimeBooter = AppRuntimeBooterFactory.make()
        let connectionPlan = AppGuestAgentConnectionPlan.resolve(provider: runtimeBooter.provider)
        let transport = connectionPlan.endpointURL.map { URLSessionWebSocketTransport(url: $0) }
        self.vmRuntimeBooter = runtimeBooter
        self.agentConnectionPlan = connectionPlan
        _model = State(
            initialValue: HostDashboardModel(
                service: HostDashboardServiceMode.resolve().makeService(
                    transport: transport,
                    connectionPlan: connectionPlan
                ),
                initialApps: KnownWindowsAppCatalog.apps
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
            suspendVMAction: suspendWindows,
            restartInstallationAction: restartWindowsInstallation,
            markWindowsInstalledAction: markWindowsInstalledFromSetup,
            installGuestAgentAction: installGuestAgentFromDisplay,
            prepareSparsePackageAction: prepareSparsePackageFromDisplay,
            waitForGuestAgentAction: waitForGuestAgent,
            repairGuestAgentForAppLaunchAction: installGuestAgentFromDisplay,
            recoverRuntimeDisplayAction: recoverRuntimeDisplayEvidence,
            showWindowsDisplayAction: showWindowsDisplay,
            launchWindowsAppAction: launchSelectedWindowsApp,
            launchWindowsAppByIdAction: { appId in
                model.selectedAppId = appId
                launchSelectedWindowsApp()
            },
            fulfillPendingLaunchAction: launchSelectedWindowsApp,
            restoreWindowsAppWindowsAction: {},
            closeAllWindowsAppWindowsAction: {},
            restartStaleFrameStreamsAction: {},
            requestNotificationConsentAction: {},
            runNotificationProofAction: {},
            runRecommendedProofAction: {},
            runMultiAppProofAction: {},
            quietWindowsWhenIdleAction: {},
            displayMessage: displayMessage
        )
        .frame(
            minWidth: MainWindowLayout.minimumSupportedSize.width,
            idealWidth: MainWindowLayout.preferredSize.width,
            minHeight: MainWindowLayout.minimumSupportedSize.height,
            idealHeight: MainWindowLayout.preferredSize.height
        )
        .environment(\.appRuntimeProvider, vmRuntimeBooter.provider)
        .environment(shellNavigation)
        .task {
            async let hostLoad: Void = model.load()
            async let vmLoad: Void = vmModel.load()
            _ = await (hostLoad, vmLoad)
            await recordGuestAgentInstallEvidenceIfNeeded()
        }
    }

    var agentURLString: String {
        agentConnectionPlan.endpoint
    }

    func startWindowsAndShowDisplay() {
        Task { @MainActor in
            await vmModel.refreshRuntimeEvidence()

            // Resumes rather than cold boots when a suspended session exists. `canStart` is also true for
            // a suspended VM, so calling start() here would discard the session.
            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = "Windows is already running. Connecting to its desktop."
            } else if vmModel.canResume {
                displayMessage = "Resuming your Windows session."
                await vmModel.resume()
            } else {
                displayMessage = "Starting Windows locally. Veil stays in this main window while setup runs."
                await vmModel.start()
            }

            // Windows shows up in the main window; the separate desktop window is opt-in.
            if vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting {
                displayMessage = "Windows is running in this window."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = String(localized: "Windows display could not start: \(errorMessage)")
            }
        }
    }

    func restartWindowsInstallation() {
        Task { @MainActor in
            if vmModel.canStop {
                await vmModel.stop()
            }
            guard await vmModel.restartWindowsInstallation() else {
                displayMessage = vmModel.errorMessage.map { String(localized: "Veil could not restart the installation: \($0)") }
                return
            }
            displayMessage = "Windows Setup is starting over."
            if AppWindowEngineStatus.resolve(
                bootProvider: vmRuntimeBooter.provider,
                providers: vmModel.snapshot?.runtimeProviders ?? []
            ).canRunWindows {
                startWindowsAndShowDisplay()
            }
        }
    }

    func suspendWindows() {
        Task { @MainActor in
            await vmModel.suspend()
        }
    }

    func stopWindowsAndCloseDisplay() {
        Task { @MainActor in
            await vmModel.stop()
            qemuConsoleWindowPresenter.closeConsole()
            if vmModel.snapshot?.state == .stopped {
                displayMessage = "Windows display closed."
            }
        }
    }

    func showWindowsDisplay() {
        Task { @MainActor in
            let didShow = await presentWindowsDesktopWhenReady()
            if didShow {
                displayMessage = "Windows desktop brought forward."
            } else {
                displayMessage = "The Windows desktop is not ready yet. Start Windows or refresh the display."
            }
        }
    }

    @MainActor
    func presentWindowsDesktopWhenReady(timeoutSeconds: Double = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline, !Task.isCancelled {
            await vmModel.refreshRuntimeEvidence()

            if presentWindowsDesktopIfAvailable() {
                return true
            }

            guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
                return false
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return false
    }

    @MainActor
    private func presentWindowsDesktopIfAvailable() -> Bool {
        if vmRuntimeBooter.provider == .appleVirtualization {
            return vmRuntimeBooter.showConsoleIfRunning()
        }

        guard let snapshot = vmModel.snapshot,
              snapshot.state == .running || snapshot.state == .starting,
              let surface = snapshot.latestConsoleLaunch?.displaySurface,
              surface.kind != .unavailable else {
            return false
        }

        return qemuConsoleWindowPresenter.showConsole(
            surface: surface,
            screenshotPath: snapshot.latestConsoleScreenshotPath,
            pointerTapAction: { normalizedX, normalizedY in
                Task {
                    await vmModel.sendConsolePointerTap(
                        normalizedX: normalizedX,
                        normalizedY: normalizedY
                    )
                }
            },
            keyAction: { key in
                Task {
                    await vmModel.sendConsoleKey(key)
                }
            },
            displayResizeAction: { width, height in
                Task { @MainActor in
                    _ = await model.resizeDisplay(width: width, height: height)
                }
            },
            commandKeyMapping: snapshot.commandKeyMapping ?? .default
        )
    }

    func installGuestAgentFromDisplay() {
        Task { @MainActor in
            displayMessage = "Sending the Veil app connection installer to Windows."
            do {
                _ = try await vmRuntimeBooter.installCurrentGuestTools(vmModel: vmModel)
                displayMessage = "App connection installer sent. Veil will connect when Windows is ready."
                await vmModel.refreshRuntimeEvidence()
                await recordGuestAgentInstallEvidenceIfNeeded()
            } catch {
                displayMessage = String(localized: "App connection install could not start: \(userMessage(for: error))")
            }
        }
    }

    func prepareSparsePackageFromDisplay() {
        Task { @MainActor in
            displayMessage = "Preparing Windows package identity. Keep the Windows setup display open for prompts."
            do {
                _ = try await vmRuntimeBooter.prepareSparsePackageFromAttachedMedia()
                displayMessage = "Package identity preparation sent. Waiting for the Windows app connection to return."
                await vmModel.refreshRuntimeEvidence()

                let report = await model.waitForLiveAgentConnection(
                    endpoint: agentURLString,
                    timeoutSeconds: 120
                )
                await recordGuestAgentInstallEvidenceIfNeeded()
                await model.load()

                if report.diagnostic.health?.capabilities.packageIdentity == true {
                    displayMessage = "Windows package identity is ready."
                } else if report.status == .connected {
                    displayMessage = "Windows reconnected, but package identity is not ready yet. Check sparse package evidence."
                } else {
                    displayMessage = "Package identity preparation was sent. Windows has not reconnected yet."
                }
            } catch {
                displayMessage = String(localized: "Package identity preparation could not start: \(userMessage(for: error))")
            }
        }
    }

    func waitForGuestAgent() {
        Task { @MainActor in
            displayMessage = "Checking the Windows app connection."
            let report = await model.waitForLiveAgentConnection(
                endpoint: agentURLString,
                timeoutSeconds: 5
            )
            await recordGuestAgentInstallEvidenceIfNeeded()

            if report.status == .connected {
                displayMessage = "Windows app connection is ready."
            } else if let hostForwardProbe = report.diagnostic.hostForwardProbe {
                displayMessage = String(localized: "Windows app connection is not ready yet (\(hostForwardProbe.status.rawValue)).")
            } else {
                displayMessage = "Windows app connection is not ready yet."
            }
        }
    }

    func markWindowsInstalledFromSetup() {
        Task { @MainActor in
            await vmModel.markWindowsInstalled()
            if vmModel.snapshot?.windowsInstalled == true {
                displayMessage = "Windows is marked installed. Veil will boot from the local disk and leave the installer ISO detached."
            } else if let errorMessage = vmModel.errorMessage {
                displayMessage = String(localized: "Windows install state could not be updated: \(errorMessage)")
            }
        }
    }

    func recoverRuntimeDisplayEvidence() {
        Task { @MainActor in
            displayMessage = "Refreshing the embedded Windows display."
            await vmModel.refreshRuntimeEvidence()
            if vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .fresh {
                displayMessage = "Windows display evidence refreshed."
            } else {
                displayMessage = "Display still needs recovery. Open details or retry after Windows responds."
            }
        }
    }

    private func launchSelectedWindowsApp() {
        Task { @MainActor in
            await model.launchSelectedApp()
        }
    }

    func recordGuestAgentInstallEvidenceIfNeeded() async {
        if model.hasLiveAgentConnection,
           let virtioGPUDriverInstalled = model.health?.capabilities.virtioGpuDisplay {
            await vmModel.recordVirtioGPUDriverInstalled(virtioGPUDriverInstalled)
        }
        guard model.hasLiveAgentConnection,
              let agentVersion = model.health?.agentVersion,
              vmModel.snapshot?.profileName != nil,
              vmModel.snapshot?.installEvidence.kind != .guestAgent else {
            return
        }

        await vmModel.markGuestAgentConnected(agentVersion: agentVersion)
    }

    func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
