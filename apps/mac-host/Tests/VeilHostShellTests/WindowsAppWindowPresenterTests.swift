import AppKit
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct WindowsAppWindowPresenterTests {
    @Test("tracks the foreground Windows app window")
    func tracksForegroundWindowsAppWindow() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", title: "Untitled - Notepad"))

        #expect(presenter.visibleWindowIds == ["hwnd:0001"])
        #expect(presenter.foregroundWindowId == "hwnd:0001")

        presenter.showWindow(for: session(windowId: "hwnd:0002", title: "Calculator"))

        #expect(presenter.visibleWindowIds == ["hwnd:0001", "hwnd:0002"])
        #expect(presenter.foregroundWindowId == "hwnd:0002")

        presenter.showWindow(for: session(windowId: "hwnd:0001", title: "Notes.txt - Notepad"))

        #expect(presenter.visibleWindowIds == ["hwnd:0002", "hwnd:0001"])
        #expect(presenter.foregroundWindowId == "hwnd:0001")
    }

    @Test("clears foreground tracking when Windows app windows close")
    func clearsForegroundTrackingWhenWindowsAppWindowsClose() {
        _ = NSApplication.shared
        let presenter = WindowsAppWindowPresenter()
        defer {
            presenter.closeAll()
        }

        presenter.showWindow(for: session(windowId: "hwnd:0001", title: "Untitled - Notepad"))
        presenter.showWindow(for: session(windowId: "hwnd:0002", title: "Calculator"))

        presenter.closeWindow(windowId: "hwnd:0002")

        #expect(presenter.visibleWindowIds == ["hwnd:0001"])
        #expect(presenter.foregroundWindowId == "hwnd:0001")

        presenter.closeAll()

        #expect(presenter.visibleWindowIds.isEmpty)
        #expect(presenter.foregroundWindowId == nil)
    }

    private func session(windowId: String, title: String) -> WindowMirrorSession {
        WindowMirrorSession(
            window: WindowCreatedEvent(
                windowId: windowId,
                processId: 4912,
                appId: "winapp_notepad",
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
