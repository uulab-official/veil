import AppKit
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct WindowsAppWindowPresenterTests {
    @Test("keeps launcher hidden while any mirrored Windows app window is visible")
    func keepsLauncherHiddenWhileMirroredWindowIsVisible() {
        #expect(
            LauncherWindowVisibilityPolicy.shouldHideLauncher(
                visibleMirroredWindowCount: 1,
                modelRequestsHide: false
            )
        )
        #expect(
            LauncherWindowVisibilityPolicy.shouldHideLauncher(
                visibleMirroredWindowCount: 1,
                modelRequestsHide: true
            )
        )
        #expect(
            LauncherWindowVisibilityPolicy.shouldHideLauncher(
                visibleMirroredWindowCount: 0,
                modelRequestsHide: true
            )
        )
        #expect(
            LauncherWindowVisibilityPolicy.shouldHideLauncher(
                visibleMirroredWindowCount: 0,
                modelRequestsHide: false
            ) == false
        )
    }

    @Test("mirrors several Windows apps side by side as separate macOS windows")
    func mirrorsSeveralWindowsAppsSideBySide() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Untitled - Notepad"))

        #expect(presenter.visibleWindowIds == ["hwnd:0001"])
        #expect(presenter.foregroundWindowId == "hwnd:0001")

        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_calculator", title: "Calculator"))
        presenter.showWindow(for: session(windowId: "hwnd:0003", appId: "winapp_paint", title: "Paint"))

        // Each app keeps its own window rather than superseding the previous one. The most recently
        // presented window is frontmost, and window order is the foreground stack.
        #expect(presenter.visibleWindowIds == ["hwnd:0001", "hwnd:0002", "hwnd:0003"])
        #expect(presenter.foregroundWindowId == "hwnd:0003")
    }

    @Test("re-presenting a tracked window does not create a duplicate")
    func rePresentingTrackedWindowDoesNotDuplicate() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Untitled - Notepad"))
        // Frame events, window updates, and reconnect races all re-present the same session many
        // times a second. One macOS window per HWND is the invariant that survived lifting the
        // single-window limit.
        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notes.txt - Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notes.txt - Notepad"))

        #expect(presenter.visibleWindowIds == ["hwnd:0001"])
    }

    @Test("a background window's frames never steal focus from the active window")
    func backgroundWindowFramesNeverStealFocus() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_calculator", title: "Calculator"))

        #expect(presenter.foregroundWindowId == "hwnd:0002")

        // Frames, window updates, and reconnect races all re-present a session several times a second.
        // Before concurrent windows existed this was harmless because there was only ever one window to
        // raise. With two, raising on every refresh would yank the background window in front of
        // whatever the user is typing in.
        for _ in 1...30 {
            let backgroundSession = session(
                windowId: "hwnd:0001",
                appId: "winapp_notepad",
                title: "Notepad Updated"
            )
            presenter.showWindow(for: backgroundSession)
            #expect(presenter.foregroundWindowId == "hwnd:0002")
        }

        #expect(presenter.foregroundWindowId == "hwnd:0002")
        #expect(presenter.visibleWindowIds == ["hwnd:0001", "hwnd:0002"])
    }

    @Test("repeated frame updates never resize or re-center an existing app window")
    func repeatedFrameUpdatesPreserveWindowGeometry() throws {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        let windowId = "hwnd:stable"
        presenter.showWindow(
            for: session(
                windowId: windowId,
                appId: "winapp_notepad",
                title: "Notepad",
                bounds: WindowBounds(x: 80, y: 80, width: 960, height: 640)
            )
        )
        let window = try #require(mirroredWindow(withId: windowId))
        let userFrame = NSRect(x: 96, y: 112, width: 960, height: 600)
        window.setFrame(userFrame, display: false)

        for _ in 1...30 {
            presenter.showWindow(
                for: session(
                    windowId: windowId,
                    appId: "winapp_notepad",
                    title: "Notepad Updated",
                    bounds: WindowBounds(x: 10, y: 10, width: 1200, height: 800)
                )
            )
            #expect(NSEqualRects(window.frame, userFrame))
        }
    }

    @Test("an explicit focus or launch does bring a window forward")
    func explicitFocusBringsWindowForward() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_calculator", title: "Calculator"))

        presenter.showWindow(
            for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notepad"),
            bringToFront: true
        )

        #expect(presenter.foregroundWindowId == "hwnd:0001")
        #expect(presenter.visibleWindowIds == ["hwnd:0002", "hwnd:0001"])
    }

    @Test("cascades additional windows instead of stacking them exactly")
    func cascadesAdditionalWindows() {
        let visibleFrame = HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900)
        let bounds = WindowBounds(x: 0, y: 0, width: 960, height: 640)

        let first = WindowsAppWindowPlacement.initialFrame(
            for: bounds,
            visibleFrame: visibleFrame,
            existingWindowCount: 0
        )
        let second = WindowsAppWindowPlacement.initialFrame(
            for: bounds,
            visibleFrame: visibleFrame,
            existingWindowCount: 1
        )

        // This cascade existed before concurrent windows did, but `existingWindowCount` was always 0
        // because a second window was never created, so it had never actually run.
        #expect(first.x != second.x)
        #expect(first.y != second.y)
        #expect(first.width == second.width)
        #expect(first.height == second.height)
    }

    @Test("clears foreground tracking when Windows app windows close")
    func clearsForegroundTrackingWhenWindowsAppWindowsClose() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Untitled - Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_calculator", title: "Calculator"))

        presenter.closeWindow(windowId: "hwnd:0002")

        #expect(presenter.visibleWindowIds == ["hwnd:0001"])
        #expect(presenter.foregroundWindowId == "hwnd:0001")

        presenter.closeAll()

        #expect(presenter.visibleWindowIds.isEmpty)
        #expect(presenter.foregroundWindowId == nil)
    }

    @Test("tracks manually focused Windows app windows")
    func tracksManuallyFocusedWindowsAppWindows() throws {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_calculator", title: "Calculator"))

        let notepadWindow = try #require(mirroredWindow(withId: "hwnd:0001"))
        presenter.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: notepadWindow))

        // Focusing an older window moves it to the end of the order without closing the other, so
        // `visibleWindowIds` reads oldest-to-frontmost.
        #expect(presenter.foregroundWindowId == "hwnd:0001")
        #expect(presenter.visibleWindowIds == ["hwnd:0002", "hwnd:0001"])
    }

    @Test("refreshing an existing Windows app window preserves the Mac window frame")
    func refreshingExistingWindowsAppWindowPreservesMacWindowFrame() throws {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(
            for: session(
                windowId: "hwnd:frame-preserve",
                appId: "winapp_frame_preserve",
                title: "Notepad",
                bounds: WindowBounds(x: 80, y: 80, width: 960, height: 640)
            )
        )
        let window = try #require(mirroredWindow(withId: "hwnd:frame-preserve"))
        let userFrame = NSRect(x: 120, y: 140, width: 820, height: 520)
        window.setFrame(userFrame, display: false)

        presenter.showWindow(
            for: session(
                windowId: "hwnd:frame-preserve",
                appId: "winapp_frame_preserve",
                title: "Notepad - Updated",
                bounds: WindowBounds(x: 10, y: 10, width: 1200, height: 800)
            )
        )

        #expect(NSEqualRects(window.frame, userFrame))
        #expect(window.title == "Notepad - Updated")
        #expect(presenter.visibleWindowIds == ["hwnd:frame-preserve"])
    }

    @Test("reports one final content size after a mirrored window live resize ends")
    func reportsFinalContentSizeAfterLiveResizeEnds() throws {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        var resizeEvents: [(String, Int, Int)] = []
        presenter.onWindowResize = { windowId, width, height in
            resizeEvents.append((windowId, width, height))
        }

        let windowId = "hwnd:resize"
        presenter.showWindow(
            for: session(
                windowId: windowId,
                appId: "winapp_notepad",
                title: "Notepad",
                bounds: WindowBounds(x: 80, y: 80, width: 960, height: 640)
            )
        )
        let window = try #require(mirroredWindow(withId: windowId))
        window.setContentSize(NSSize(width: 1_440, height: 960))

        presenter.windowDidEndLiveResize(
            Notification(name: NSWindow.didEndLiveResizeNotification, object: window)
        )

        #expect(resizeEvents.count == 1)
        #expect(resizeEvents.first?.0 == windowId)
        #expect(resizeEvents.first?.1 == 1_440)
        #expect(resizeEvents.first?.2 == 960)
    }

    @Test("restore policy deminiaturizes minimized Windows app windows")
    func restorePolicyDeminiaturizesMinimizedWindowsAppWindows() {
        let window = RestorePolicyTestWindow(isMiniaturizedForTest: true)

        MacWindowRestorePolicy.restoreToFront(window)

        #expect(window.deminiaturizeCallCount == 1)
        #expect(window.makeKeyAndOrderFrontCallCount == 1)
    }

    @Test("restore policy fronts visible Windows app windows without deminiaturizing")
    func restorePolicyFrontsVisibleWindowsAppWindowsWithoutDeminiaturizing() {
        let window = RestorePolicyTestWindow(isMiniaturizedForTest: false)

        MacWindowRestorePolicy.restoreToFront(window)

        #expect(window.deminiaturizeCallCount == 0)
        #expect(window.makeKeyAndOrderFrontCallCount == 1)
    }

    @Test("Dock reopen uses visible mirrored windows before hidden launcher state")
    func dockReopenUsesVisibleMirroredWindowsBeforeHiddenLauncherState() {
        #expect(
            LauncherReopenPolicy.destination(
                visibleMirroredWindowCount: 1,
                modelRequestsHideLauncher: true
            ) == .windowsAppWindows
        )
        #expect(
            LauncherReopenPolicy.destination(
                visibleMirroredWindowCount: 0,
                modelRequestsHideLauncher: true
            ) == .mainWindow
        )
        #expect(
            LauncherReopenPolicy.destination(
                visibleMirroredWindowCount: 1,
                modelRequestsHideLauncher: false
            ) == .mainWindow
        )
    }

    @Test("app delegate handles reopen without default duplicate window")
    func appDelegateHandlesReopenWithoutDefaultDuplicateWindow() {
        let delegate = AppDelegate()
        var handledCount = 0
        delegate.reopenHandler = {
            handledCount += 1
        }

        let shouldContinueDefaultReopen = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        #expect(handledCount == 1)
        #expect(shouldContinueDefaultReopen == false)
    }

    @Test("app delegate does not restore an empty launcher state")
    func appDelegateDoesNotRestoreEmptyLauncherState() {
        let delegate = AppDelegate()

        #expect(delegate.applicationShouldRestoreState(NSApplication.shared) == false)
        #expect(delegate.applicationShouldSaveState(NSApplication.shared) == false)
    }

    @Test("creates a recoverable launcher when SwiftUI has not materialized its scene")
    func createsRecoverableLauncherWhenSwiftUISceneIsMissing() {
        _ = NSApplication.shared

        MainWindowChrome.showMainWindow()
        defer {
            MainWindowChrome.hideMainWindow()
            NSApp.windows
                .filter { $0.identifier?.rawValue == "main" }
                .forEach { $0.close() }
        }

        let launcherWindows = NSApp.windows.filter { $0.identifier?.rawValue == "main" }
        let launcher = launcherWindows.first
        #expect(launcherWindows.count == 1)
        #expect(launcher?.isVisible == true)
        #expect(launcher?.titlebarAppearsTransparent == true)
        #expect(launcher?.styleMask.contains(.fullSizeContentView) == true)
        #expect(launcher?.minSize.width ?? 0 >= MainWindowLayout.minimumSupportedSize.width)
        #expect(launcher?.minSize.height ?? 0 >= MainWindowLayout.minimumSupportedSize.height)
    }

    @Test("launch verification arguments accept separated and inline report paths")
    func launchVerificationArgumentsAcceptReportPaths() throws {
        let separated = try #require(
            LaunchVerificationArguments.reportURL(
                from: ["veil-host-shell", "--launch-verification-report", "/tmp/veil-launch.json"]
            )
        )
        #expect(separated.path == "/tmp/veil-launch.json")

        let inline = try #require(
            LaunchVerificationArguments.reportURL(
                from: ["veil-host-shell", "--launch-verification-report=/tmp/veil-inline.json"]
            )
        )
        #expect(inline.path == "/tmp/veil-inline.json")
        #expect(LaunchVerificationArguments.reportURL(from: ["veil-host-shell"]) == nil)
        #expect(
            LaunchVerificationArguments.reportURL(
                from: ["veil-host-shell", "--launch-verification-report"]
            ) == nil
        )
    }

    @Test("launch verification contract requires one visible branded main window")
    func launchVerificationContractRequiresOneVisibleBrandedMainWindow() {
        let passingReport = MainWindowLaunchReport(
            bundleIdentifier: "org.uulab.veil.host-shell",
            activationPolicy: "regular",
            mainWindowCount: 1,
            visibleMainWindowCount: 1,
            duplicateMainWindowCount: 0,
            isAppActive: true,
            isMainWindowKey: true,
            frame: MainWindowFrameReport(NSRect(x: 10, y: 20, width: 1440, height: 900)),
            minWidth: Double(MainWindowLayout.preferredMinimumSize.width),
            minHeight: Double(MainWindowLayout.preferredMinimumSize.height),
            titlebarAppearsTransparent: true,
            hasFullSizeContentView: true,
            appIconSource: .bundled
        )

        #expect(passingReport.meetsLauncherContract)

        var backgroundFocusReport = passingReport
        backgroundFocusReport.isAppActive = false
        backgroundFocusReport.isMainWindowKey = false
        #expect(backgroundFocusReport.meetsLauncherContract)

        var duplicateWindowReport = passingReport
        duplicateWindowReport.mainWindowCount = 2
        duplicateWindowReport.duplicateMainWindowCount = 1
        #expect(duplicateWindowReport.meetsLauncherContract == false)

        var smallWindowReport = passingReport
        smallWindowReport.frame = MainWindowFrameReport(NSRect(x: 10, y: 20, width: 780, height: 520))
        #expect(smallWindowReport.meetsLauncherContract == false)

        var fallbackIconReport = passingReport
        fallbackIconReport.appIconSource = .fallback
        #expect(fallbackIconReport.meetsLauncherContract == false)
    }

    @Test("main window layout fits regular and compact displays")
    func mainWindowLayoutFitsVisibleDisplay() {
        #expect(
            MainWindowLayout.fittedSize(for: CGSize(width: 1512, height: 982))
                == MainWindowLayout.preferredSize
        )

        let compactMinimum = MainWindowLayout.minimumSize(for: CGSize(width: 1024, height: 640))
        #expect(compactMinimum.width == 900)
        #expect(abs(compactMinimum.height - 614.4) < 0.001)

        let compactFitted = MainWindowLayout.fittedSize(for: CGSize(width: 1024, height: 640))
        #expect(abs(compactFitted.width - 983.04) < 0.001)
        #expect(abs(compactFitted.height - 614.4) < 0.001)
    }

    @Test("presents separate document windows for the same app")
    func presentsSeparateDocumentWindowsForTheSameApp() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        var callbackWindowIds: [String] = []
        presenter.onUserWindowClose = { windowId in
            callbackWindowIds.append(windowId)
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_notepad", title: "Notepad - Edited"))

        #expect(presenter.visibleWindowIds == ["hwnd:0001", "hwnd:0002"])
        #expect(callbackWindowIds.isEmpty)

        presenter.closeWindow(windowId: "hwnd:0001")

        #expect(presenter.visibleWindowIds == ["hwnd:0002"])
        #expect(callbackWindowIds.isEmpty)
    }

    private func session(
        windowId: String,
        appId: String,
        title: String,
        bounds: WindowBounds = WindowBounds(x: 80, y: 80, width: 960, height: 640)
    ) -> WindowMirrorSession {
        WindowMirrorSession(
            window: WindowCreatedEvent(
                windowId: windowId,
                processId: 4912,
                appId: appId,
                title: title,
                bounds: bounds,
                state: "normal",
                focused: true
            ),
            connectionMode: .agent,
            captureState: .pending
        )
    }

    private func mirroredWindow(withId windowId: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == windowId }
    }
}

@MainActor
private final class RestorePolicyTestWindow: NSWindow {
    var isMiniaturizedForTest: Bool
    var deminiaturizeCallCount = 0
    var makeKeyAndOrderFrontCallCount = 0

    init(isMiniaturizedForTest: Bool) {
        self.isMiniaturizedForTest = isMiniaturizedForTest
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
    }

    override var isMiniaturized: Bool {
        isMiniaturizedForTest
    }

    override func deminiaturize(_ sender: Any?) {
        deminiaturizeCallCount += 1
        isMiniaturizedForTest = false
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }
}
