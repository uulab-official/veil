import AppKit
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct QEMUConsoleWindowPresenterTests {
    @Test("queues a settled resize until the RFB preview is mounted")
    func queuesResizeUntilPreviewMounts() {
        let bus = DesktopResizeCommandBus()
        var received: [(Int, Int)] = []

        bus.request(width: 1920, height: 1080)
        #expect(received.isEmpty)

        bus.setPerformer { width, height in
            received.append((width, height))
        }
        #expect(received.count == 1)
        #expect(received[0].0 == 1920)
        #expect(received[0].1 == 1080)

        bus.request(width: 2560, height: 1440)
        #expect(received.count == 2)
        #expect(received[1].0 == 2560)
        #expect(received[1].1 == 1440)
    }

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
        #expect(window.frame.width >= 800)
        #expect(window.frame.height >= 500)
    }
}
