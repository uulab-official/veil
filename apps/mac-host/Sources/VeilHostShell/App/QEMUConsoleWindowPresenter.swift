import AppKit
import SwiftUI
import VeilHostCore

@MainActor
final class QEMUConsoleWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    @discardableResult
    func showConsole(
        surface: VMConsoleDisplaySurface,
        screenshotPath: String?,
        pointerTapAction: @escaping (Double, Double) -> Void,
        keyAction: @escaping (String) -> Void
    ) -> Bool {
        let screenshot = screenshotPath.flatMap(NSImage.init(contentsOfFile:))
        let rootView = WindowsEmbeddedDisplayPreview(
            image: screenshot,
            surface: surface,
            path: screenshotPath ?? "",
            revisionID: screenshotPath ?? surface.endpoint ?? "windows-desktop",
            pointerTapAction: pointerTapAction,
            keyAction: keyAction
        )
        .background(Color.black)

        if let window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.contentMinSize = NSSize(width: 800, height: 500)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("windows-desktop-console")
        window.title = "Windows 11"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.backgroundColor = .black
        window.contentViewController = NSHostingController(rootView: rootView)
        window.contentMinSize = NSSize(width: 800, height: 500)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        return true
    }

    func closeConsole() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window {
            window = nil
        }
    }
}
