import AppKit
import SwiftUI
import VeilHostCore

/// Bridges the presenter's geometry controller to whichever live RFB display model
/// is mounted in the desktop window. The bus outlives SwiftUI view recreation, so a
/// settled resize target is never lost when the preview hierarchy is rebuilt.
final class DesktopResizeCommandBus: @unchecked Sendable {
    private let lock = NSLock()
    private var performer: ((Int, Int) -> Void)?

    func setPerformer(_ performer: ((Int, Int) -> Void)?) {
        lock.lock()
        self.performer = performer
        lock.unlock()
    }

    func request(width: Int, height: Int) {
        lock.lock()
        let performer = self.performer
        lock.unlock()
        performer?(width, height)
    }
}

@MainActor
final class QEMUConsoleWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let resizeBus = DesktopResizeCommandBus()
    private var resizeDebounceTask: Task<Void, Never>?
    private var lastResizeTarget: RFBDesktopResizeTarget?

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
            resizeBus: resizeBus,
            pointerTapAction: pointerTapAction,
            keyAction: keyAction
        )
        .background(Color.black)

        if let window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.contentMinSize = NSSize(width: 800, height: 500)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            scheduleResizeRequest()
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
        window.setFrameAutosaveName("WindowsDesktopConsole")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        scheduleResizeRequest()
        return true
    }

    func closeConsole() {
        resizeDebounceTask?.cancel()
        resizeDebounceTask = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window {
            resizeDebounceTask?.cancel()
            resizeDebounceTask = nil
            window = nil
        }
    }

    // MARK: - Desktop resize geometry

    /// Coalesces transient geometry notifications and emits one bounded target after
    /// the user pauses or finishes dragging. Full-screen transitions produce many
    /// notifications; the debounce waits for them to settle.
    func windowDidResize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }

        scheduleResizeRequest()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }

        scheduleResizeRequest()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }

        scheduleResizeRequest()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }

        scheduleResizeRequest()
    }

    private func scheduleResizeRequest() {
        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }

            self?.emitResizeRequest()
        }
    }

    private func emitResizeRequest() {
        guard let window,
              let contentView = window.contentView else {
            return
        }

        var contentSize = window.contentLayoutRect.size
        if contentSize.width <= 0 || contentSize.height <= 0 {
            contentSize = contentView.bounds.size
        }

        let backingScaleFactor = window.screen?.backingScaleFactor ?? 1
        guard let target = RFBDesktopSizePolicy.target(
            contentSizeInPoints: contentSize,
            backingScaleFactor: backingScaleFactor
        ) else {
            return
        }

        guard RFBDesktopSizePolicy.isSignificantChange(from: lastResizeTarget, to: target) else {
            return
        }

        lastResizeTarget = target
        resizeBus.request(width: target.widthInPixels, height: target.heightInPixels)
    }
}
