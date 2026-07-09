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

    private func session(windowId: String, appId: String, title: String) -> WindowMirrorSession {
        WindowMirrorSession(
            window: WindowCreatedEvent(
                windowId: windowId,
                processId: 4912,
                appId: appId,
                title: title,
                bounds: WindowBounds(x: 80, y: 80, width: 960, height: 640),
                state: "normal",
                focused: true
            ),
            connectionMode: .agent,
            captureState: .pending
        )
    }
}
