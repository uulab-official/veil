import AppKit
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct QEMUConsoleWindowPresenterTests {
    @Test("opens one reusable VMware-style Windows desktop window")
    func opensOneReusableDesktopWindow() throws {
        _ = NSApplication.shared
        let presenter = QEMUConsoleWindowPresenter()
        defer { presenter.closeConsole() }

        let surface = VMConsoleDisplaySurface(
            kind: .vncLoopback,
            endpoint: "127.0.0.1:5901",
            screenshotPath: nil,
            isLiveCapable: true
        )

        presenter.showConsole(
            surface: surface,
            screenshotPath: nil,
            pointerTapAction: { _, _ in },
            keyAction: { _ in }
        )
        presenter.showConsole(
            surface: surface,
            screenshotPath: nil,
            pointerTapAction: { _, _ in },
            keyAction: { _ in }
        )

        let windows = NSApp.windows.filter {
            $0.identifier?.rawValue == "windows-desktop-console"
        }
        let window = try #require(windows.first)

        #expect(windows.count == 1)
        #expect(window.title == "Windows 11")
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.contentMinSize.width == 800)
        #expect(window.contentMinSize.height == 500)
    }
}
