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

    @Test("tracks the foreground Windows app window")
    func tracksForegroundWindowsAppWindow() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", appId: "winapp_notepad", title: "Untitled - Notepad"))

        #expect(presenter.visibleWindowIds == ["hwnd:0001"])
        #expect(presenter.foregroundWindowId == "hwnd:0001")

        presenter.showWindow(for: session(windowId: "hwnd:0002", appId: "winapp_notepad", title: "Notes.txt - Notepad"))

        #expect(presenter.visibleWindowIds == ["hwnd:0002"])
        #expect(presenter.foregroundWindowId == "hwnd:0002")

        presenter.showWindow(for: session(windowId: "hwnd:0003", appId: "winapp_calculator", title: "Calculator"))

        #expect(presenter.visibleWindowIds == ["hwnd:0002", "hwnd:0003"])
        #expect(presenter.foregroundWindowId == "hwnd:0003")
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

    @Test("closes programmatic windows without emitting user-close callback")
    func closesProgrammaticWindowsWithoutUserCloseCallback() {
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

        #expect(presenter.visibleWindowIds == ["hwnd:0002"])
        #expect(callbackWindowIds.isEmpty)

        presenter.closeWindow(windowId: "hwnd:0002")

        #expect(presenter.visibleWindowIds.isEmpty)
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
