import AppKit
import SwiftUI
import VeilHostCore

/// Bridges the presenter's geometry controller to whichever live RFB display model
/// is mounted in the desktop window. The bus outlives SwiftUI view recreation, so a
/// settled resize target is never lost when the preview hierarchy is rebuilt.
final class DesktopResizeCommandBus: @unchecked Sendable {
    private let lock = NSLock()
    private var performer: ((Int, Int) -> Void)?
    private var pendingTarget: (width: Int, height: Int)?

    func setPerformer(_ performer: ((Int, Int) -> Void)?) {
        lock.lock()
        self.performer = performer
        let pendingTarget = performer == nil ? nil : self.pendingTarget
        if performer != nil {
            self.pendingTarget = nil
        }
        lock.unlock()

        if let pendingTarget, let performer {
            performer(pendingTarget.width, pendingTarget.height)
        }
    }

    func request(width: Int, height: Int) {
        lock.lock()
        let performer = self.performer
        if performer == nil {
            pendingTarget = (width, height)
        }
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
        keyAction: @escaping (String) -> Void,
        displayResizeAction: ((Int, Int) -> Void)? = nil,
        commandKeyMapping: VMCommandKeyMapping = .default
    ) -> Bool {
        let screenshot = screenshotPath.flatMap(NSImage.init(contentsOfFile:))
        let rootView = WindowsEmbeddedDisplayPreview(
            image: screenshot,
            surface: surface,
            path: screenshotPath ?? "",
            revisionID: screenshotPath ?? surface.endpoint ?? "windows-desktop",
            resizeBus: resizeBus,
            displayResizeAction: displayResizeAction,
            pointerTapAction: pointerTapAction,
            keyAction: keyAction,
            commandKeyMapping: commandKeyMapping
        )
        .background(Color.black)

        if let window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.contentMinSize = NSSize(width: 800, height: 500)
            normalizeWindowFrame(window)
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
        normalizeWindowFrame(window)
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

        guard let target = RFBDesktopSizePolicy.target(
            contentSizeInPoints: contentSize,
            backingScaleFactor: DisplayResolutionPreference.guestPixelsPerPoint(
                screenScale: window.screen?.backingScaleFactor
            )
        ) else {
            return
        }

        guard RFBDesktopSizePolicy.isSignificantChange(from: lastResizeTarget, to: target) else {
            return
        }

        lastResizeTarget = target
        VeilLog.runtime.debug(
            "Console window resize settled at \(Int(contentSize.width))x\(Int(contentSize.height))pt -> guest \(target.widthInPixels)x\(target.heightInPixels)"
        )
        resizeBus.request(width: target.widthInPixels, height: target.heightInPixels)
    }

    /// Autosaved AppKit frames can outlive an older preview layout and restore a
    /// practically invisible window (for example 80×120). Never let that turn the
    /// live Windows desktop into a thumbnail; restore a usable console frame while
    /// preserving a normal user-resized frame.
    private func normalizeWindowFrame(_ window: NSWindow) {
        let minimumFrame = NSSize(width: 800, height: 500)
        guard window.frame.width < minimumFrame.width || window.frame.height < minimumFrame.height else {
            return
        }

        window.setContentSize(NSSize(width: 1280, height: 800))
    }
}
