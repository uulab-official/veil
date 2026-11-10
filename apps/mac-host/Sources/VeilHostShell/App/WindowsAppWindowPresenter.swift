import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

@MainActor
final class WindowsAppWindowPresenter: NSObject, NSWindowDelegate {
    private var windowsById: [String: NSWindow] = [:]
    private var windowOrder: [String] = []
    private var suppressedCloseWindowIds: Set<String> = []
    private var identitiesById: [String: WindowsAppWindowIdentity] = [:]
    /// Windows that have shown at least one frame. Only these are paused while the desktop hides them.
    private var windowsWithFirstFrame: Set<String> = []
    private var otherWindowKeyObserver: NSObjectProtocol?
#if DEBUG
    private var debugCommandObserver: NSObjectProtocol?
#endif
    /// When each zooming window's animation ends. Guest updates arriving before then must not touch the frame.
    private var zoomEndsAt: [String: Date] = [:]
    /// When each window last reported a size during a live resize, so the guest follows without being flooded.
    private var lastLiveResizeReportAt: [String: Date] = [:]
    /// How often a window being dragged to a new size tells Windows to follow.
    private static let liveResizeReportInterval: TimeInterval = 0.12
    private(set) var foregroundWindowId: String?
    /// Whether the full Windows desktop is showing instead, which keeps every mirrored window off screen.
    private(set) var isHiddenForDesktop = false
    /// Windows that were in the Dock when the desktop took over, so returning puts them back there.
    private var minimizedBeforeDesktop: Set<String> = []

    var onUserWindowClose: ((String) -> Void)?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    /// Window id, guest x and y, and scroll amounts in Windows wheel units (x right, y up).
    var onScrollInput: ((String, Int, Int, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onTextInput: ((String, String) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], HostPasteboardContent) -> Void)?
    /// `(appId, windowId, fileName, contentBase64)`. Carries the window id so a failure that only Windows
    /// can report can still be shown on the window the file was dropped onto.
    var onFileDrop: ((String, String, String, String) -> Void)?
    /// Called when a dragged file was not sent. Separate from `onFileDrop` because a refusal has to reach
    /// the user: macOS has already played its accept animation by the time most refusals are known.
    var onDropRefused: ((WindowsAppFileDropRefusal) -> Void)?
    /// Reads the composited surface for a window. Supplied by the app, which owns the model that owns the
    /// compositor.
    var compositedImageProvider: ((String) -> CGImage?)?
    /// Reads the model's current session for a window. The hosting view is rebuilt only when a frame or
    /// window update arrives, so without this the stream badge would judge liveness from that snapshot and
    /// call an idle window paused even while `window.frame.unchanged` heartbeats keep it fresh.
    var sessionProvider: ((String) -> WindowMirrorSession?)?
    /// Resolves the current app identity for window chrome. The catalog can refresh after reconnects, so
    /// this is deliberately a provider rather than a snapshot held by the presenter.
    var appIdentityProvider: ((String) -> WindowsAppWindowIdentity)?
    var onRestartFrameStream: ((String) -> Void)?
    /// `(windowId, isVisible)`. Fires when a mirrored window is minimized or restored, so frame streaming can
    /// stop for a window that cannot show anything.
    var onWindowVisibilityChange: ((String, Bool) -> Void)?
    /// `(windowId, contentWidth, contentHeight)`. Fires once after the user finishes resizing a mirrored
    /// window so the real Windows HWND can follow without sending one request per drag event.
    /// Window id, content width and height in points, and the size of the Mac screen the window is on.
    var onWindowResize: ((String, Int, Int, CGSize?) -> Void)?
    /// A mirrored window became the Mac's key window.
    var onWindowBecameKey: ((String) -> Void)?

    var visibleWindowIds: [String] {
        windowOrder.filter { windowsById[$0] != nil }
    }

    /// Presents a mirrored window, creating it if needed.
    ///
    /// - Parameter bringToFront: Whether to raise and activate the window. Defaults to `false` because
    ///   most calls are content refreshes driven by incoming frames, window updates, and reconnect
    ///   races — several times a second per window. Raising on those would make every frame for a
    ///   background window steal focus from whatever the user is actually working in. Only a
    ///   deliberate launch, restore, or focus action should raise a window that already exists.
    ///   Newly created windows are always raised, since an app the user just opened has to appear.
    func showWindow(for session: WindowMirrorSession, bringToFront: Bool = false) {
        if session.latestFrame != nil {
            windowsWithFirstFrame.insert(session.id)
        }
        if let window = windowsById[session.id] {
            // The desktop shows this app already; raising its Mac window would put it on screen twice.
            updateExistingWindow(window, for: session, bringToFront: bringToFront && !isHiddenForDesktop)
            return
        }

        // Several Windows apps can be mirrored side by side, each as its own macOS window. Runaway
        // window creation is prevented upstream instead of by a count limit here: the host model only
        // tracks HWNDs from an explicit launch or restore, and `updateWindowState(_:)` refuses to
        // create a session for a window the user never asked for. Guest discovery and reconnect races
        // therefore cannot multiply windows, while a deliberate second app launch can open one.
        //
        // Placement below cascades off `windowsById.count`, so window two does not land exactly on
        // top of window one.
        if session.window.isPopup {
            showPopup(for: session)
            return
        }

        let window = NSWindow(
            contentRect: frame(for: session.window.bounds, existingWindowCount: windowsById.count),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(session.id)
        window.delegate = self
        window.isReleasedWhenClosed = false
        configure(window, for: session)
        window.contentView = hostingView(
            for: session
        )
        windowsById[session.id] = window
        guard !isHiddenForDesktop else {
            // Opened while the desktop shows Windows: kept off screen until apps mode returns. Its stream keeps
            // running until the first frame arrives: Veil opens on the desktop while the app connection comes
            // up and returns to apps mode on that first frame, so pausing here left every window hidden.
            rememberWindowId(session.id)
            if session.latestFrame != nil {
                onWindowVisibilityChange?(session.id, false)
            }
            return
        }
        present(window, windowId: session.id)
    }

    /// Shows a Windows popup, such as Paint's text formatting bar or a menu, the way it looks in Windows: a
    /// borderless, transparent overlay at its place on the owning app window, moving with that window, and
    /// never taking key focus from it. As an ordinary Mac window it had a shadow, rounded corners, and a black
    /// slab wherever the popup's own window is transparent.
    private func showPopup(for session: WindowMirrorSession) {
        let owner = popupOwner(for: session)
        let panel = NSPanel(
            contentRect: popupFrame(for: session, owner: owner),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier(session.id)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        configurePopup(panel, for: session)
        panel.contentView = hostingView(for: session)
        windowsById[session.id] = panel
        rememberWindowId(session.id)
        guard !isHiddenForDesktop else {
            if session.latestFrame != nil {
                onWindowVisibilityChange?(session.id, false)
            }
            return
        }

        if let owner {
            owner.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    private func configurePopup(_ panel: NSWindow, for session: WindowMirrorSession) {
        panel.title = session.window.title
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.managed, .fullScreenAuxiliary]
    }

    /// The window a popup belongs to: the one Windows names as its owner, or else the front window of the same
    /// app, since some popups are owned by a hidden helper window rather than the app window the user sees.
    private func popupOwner(for session: WindowMirrorSession) -> NSWindow? {
        if let ownerWindowId = session.window.ownerWindowId,
           let owner = windowsById[ownerWindowId],
           !(owner is NSPanel) {
            return owner
        }

        return visibleWindowIds.reversed().lazy.compactMap { windowId -> NSWindow? in
            guard windowId != session.id,
                  let window = self.windowsById[windowId],
                  !(window is NSPanel),
                  self.sessionProvider?(windowId)?.window.appId == session.window.appId else {
                return nil
            }
            return window
        }.first
    }

    /// Places the popup at the same offset from its owner's top-left as in Windows. Mirrored windows draw the
    /// guest bitmap unscaled from their top-left, so guest logical units and Mac points line up.
    private func popupFrame(for session: WindowMirrorSession, owner: NSWindow?) -> NSRect {
        let bounds = session.window.bounds
        let size = NSSize(width: max(1, bounds.width), height: max(1, bounds.height))
        guard let owner,
              let ownerId = owner.identifier?.rawValue,
              let ownerBounds = sessionProvider?(ownerId)?.window.bounds else {
            let fallback = frame(for: bounds, existingWindowCount: windowsById.count)
            return NSRect(origin: fallback.origin, size: size)
        }

        let ownerFrame = owner.frame
        let left = ownerFrame.minX + CGFloat(bounds.x - ownerBounds.x)
        let top = ownerFrame.maxY - CGFloat(bounds.y - ownerBounds.y)
        return NSRect(x: left, y: top - size.height, width: size.width, height: size.height)
    }

    /// Takes every mirrored window off screen while the full Windows desktop is shown, the way Parallels
    /// leaves Coherence. Windows stay open in the guest; only their frame streams pause, through the same
    /// path minimizing uses. Minimized windows leave the Dock too, so one cannot be restored behind the
    /// desktop's back, and they are remembered so `showAllAfterDesktop()` puts them back there.
    func hideAllForDesktop() {
        guard !isHiddenForDesktop else {
            return
        }
        isHiddenForDesktop = true

        for windowId in visibleWindowIds {
            guard let window = windowsById[windowId] else {
                continue
            }
            if window.isMiniaturized {
                // Already paused when it was minimized.
                minimizedBeforeDesktop.insert(windowId)
            } else if windowsWithFirstFrame.contains(windowId) {
                // A window still waiting for its first frame keeps streaming; see `showWindow`.
                onWindowVisibilityChange?(windowId, false)
            }
            window.orderOut(nil)
        }
    }

    /// Brings back the windows `hideAllForDesktop()` took off screen, in their previous stacking order, and
    /// resumes their frame streams. Windows that were minimized go back to the Dock still paused.
    func showAllAfterDesktop() {
        guard isHiddenForDesktop else {
            return
        }
        isHiddenForDesktop = false
        let minimized = minimizedBeforeDesktop
        minimizedBeforeDesktop.removeAll()

        for windowId in visibleWindowIds {
            guard let window = windowsById[windowId] else {
                continue
            }
            if minimized.contains(windowId) {
                window.miniaturize(nil)
            } else {
                window.orderFront(nil)
                onWindowVisibilityChange?(windowId, true)
            }
        }
        if let front = visibleWindowIds.last(where: { !minimized.contains($0) }),
           let window = windowsById[front] {
            window.makeKeyAndOrderFront(nil)
            foregroundWindowId = front
        }
    }

    /// Whether a mirrored window is actually on screen, as opposed to tracked but hidden or minimized.
    func isWindowOnScreen(windowId: String) -> Bool {
        windowsById[windowId]?.isVisible == true
    }

    func closeAll() {
        suppressedCloseWindowIds.formUnion(windowsById.keys)
        for window in windowsById.values {
            window.close()
        }
        windowsById.removeAll()
        windowOrder.removeAll()
        identitiesById.removeAll()
        windowsWithFirstFrame.removeAll()
        foregroundWindowId = nil
        minimizedBeforeDesktop.removeAll()
        WindowsAppDockIcon.showInDock(nil)
    }

    func closeWindow(windowId: String, suppressWindowCloseCallback: Bool = true) {
        guard let window = windowsById[windowId] else {
            return
        }

        if suppressWindowCloseCallback {
            suppressedCloseWindowIds.insert(windowId)
        }
        window.close()
        windowsById[windowId] = nil
        forgetWindowId(windowId)
    }

    func bringAllToFront() {
        guard !windowsById.isEmpty, !isHiddenForDesktop else {
            return
        }

        for windowId in visibleWindowIds {
            if let window = windowsById[windowId] {
                MacWindowRestorePolicy.restoreToFront(window)
            }
        }
        foregroundWindowId = visibleWindowIds.last
        QuietLaunch.activateApplication()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowId = window.identifier?.rawValue else {
            return
        }

        windowsById[windowId] = nil
        forgetWindowId(windowId)

        if suppressedCloseWindowIds.remove(windowId) == nil {
            onUserWindowClose?(windowId)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowId = window.identifier?.rawValue,
              windowsById[windowId] != nil else {
            return
        }

        rememberWindowId(windowId)
        foregroundWindowId = windowId
        WindowsAppDockIcon.showInDock(identitiesById[windowId])
        observeOtherWindowsBecomingKey()
        onWindowBecameKey?(windowId)
    }

#if DEBUG
    /// Development builds only: lets a script drive the front mirrored window without touching the user's
    /// mouse, for checking zoom and resize behavior against a live guest.
    /// `zoom` and `minimize` use the same AppKit paths as the Windows caption buttons; `resize` steps the
    /// window to `width` x `height` the way an edge drag reports sizes while it moves.
    func installDebugCommandObserver() {
        guard debugCommandObserver == nil else {
            return
        }
        debugCommandObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("org.uulab.veil.debug.mirroredWindow"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let action = notification.userInfo?["action"] as? String
            let width = (notification.userInfo?["width"] as? String).flatMap(Double.init)
            let height = (notification.userInfo?["height"] as? String).flatMap(Double.init)
            MainActor.assumeIsolated {
                if action == "dump-icons" {
                    Self.dumpDebugIcons(window: self?.foregroundWindowId.flatMap { self?.windowsById[$0] })
                    return
                }
                self?.performDebugCommand(action: action, width: width, height: height)
            }
        }
    }

    private static func inputCaptureView(in view: NSView) -> InputCaptureNSView? {
        if let inputView = view as? InputCaptureNSView {
            return inputView
        }
        return view.subviews.lazy.compactMap(inputCaptureView(in:)).first
    }

    /// Delivered straight to the input view rather than through `NSWindow.sendEvent`, which would first
    /// activate Veil and take focus from whatever the user is working in.
    private static func postDebugMouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) {
        guard let contentView = window.contentView,
              let inputView = contentView.hitTest(point) as? InputCaptureNSView,
              let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ) else {
            return
        }
        switch type {
        case .leftMouseDown:
            inputView.mouseDown(with: event)
        case .leftMouseDragged:
            inputView.mouseDragged(with: event)
        default:
            inputView.mouseUp(with: event)
        }
    }

    /// Writes the current Dock icon and the front window's minimized icon as PNGs to the temporary directory,
    /// since neither can be screenshotted without capturing the user's whole screen.
    private static func dumpDebugIcons(window: NSWindow?) {
        let directory = FileManager.default.temporaryDirectory
        let images: [(String, NSImage?)] = [
            ("veil-dock-icon.png", NSApp.applicationIconImage),
            ("veil-miniwindow-icon.png", window?.miniwindowImage)
        ]
        for (name, image) in images {
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                continue
            }
            try? png.write(to: directory.appendingPathComponent(name))
        }
        VeilLog.window.notice("Debug icons written to \(directory.path, privacy: .public)")
    }

    private func performDebugCommand(action: String?, width: Double?, height: Double?) {
        guard let windowId = foregroundWindowId ?? visibleWindowIds.last,
              let window = windowsById[windowId] else {
            return
        }
        VeilLog.window.notice("Debug command \(action ?? "nil", privacy: .public) on \(windowId, privacy: .public)")

        switch action {
        case "zoom":
            window.performZoom(nil)
        case "minimize":
            window.performMiniaturize(nil)
        case "restore":
            MacWindowRestorePolicy.restoreToFront(window)
        case "draw":
            // A stroke across the middle of the window, delivered as real AppKit events to the window so it
            // takes the same hit-testing and input path as the user's mouse.
            guard let contentView = window.contentView else {
                return
            }
            let bounds = contentView.bounds
            let points = (0...20).map { step in
                NSPoint(
                    x: bounds.midX - 120 + Double(step) * 12,
                    y: bounds.midY + 40 * sin(Double(step) / 3)
                )
            }
            Task { @MainActor in
                for (index, point) in points.enumerated() {
                    let type: NSEvent.EventType = index == 0 ? .leftMouseDown : .leftMouseDragged
                    Self.postDebugMouseEvent(type, at: point, in: window)
                    try? await Task.sleep(for: .milliseconds(30))
                }
                Self.postDebugMouseEvent(.leftMouseUp, at: points[points.count - 1], in: window)
            }
        case "scroll":
            // Straight to the scroll callback at the window's center, so the user's pointer stays put.
            guard let session = sessionProvider?(windowId) ?? nil,
                  let frame = session.latestFrame else {
                return
            }
            let deltaY = Int(height ?? -360)
            Task { @MainActor in
                for _ in 0..<12 {
                    onScrollInput?(windowId, frame.width / 2, frame.height / 2, 0, deltaY / 12)
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        case "undo":
            if let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "z",
                charactersIgnoringModifiers: "z",
                isARepeat: false,
                keyCode: 6
            ),
               let inputView = window.contentView.flatMap(Self.inputCaptureView(in:)) {
                _ = inputView.performKeyEquivalent(with: event)
            }
        case "resize":
            guard let width, let height, let contentView = window.contentView else {
                return
            }
            let start = contentView.bounds.size
            Task { @MainActor in
                let steps = 10
                for step in 1...steps {
                    let fraction = Double(step) / Double(steps)
                    window.setContentSize(NSSize(
                        width: start.width + (width - start.width) * fraction,
                        height: start.height + (height - start.height) * fraction
                    ))
                    reportContentSize(contentView.bounds.size, windowId: windowId, screen: window.screen)
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        default:
            break
        }
    }
#endif

    /// Veil's own windows (the launcher, settings, the desktop) take the Dock icon back from a Windows app.
    private func observeOtherWindowsBecomingKey() {
        guard otherWindowKeyObserver == nil else {
            return
        }
        otherWindowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let windowId = (notification.object as? NSWindow)?.identifier?.rawValue
            MainActor.assumeIsolated {
                guard let self, windowId.map({ self.windowsById[$0] == nil }) ?? true else {
                    return
                }
                WindowsAppDockIcon.showInDock(nil)
            }
        }
    }

    /// A minimized window shows nothing, so nothing should be produced for it.
    ///
    /// Until this existed, minimizing a mirrored window left the guest capturing, comparing, PNG-encoding, and
    /// sending its pixels, and the host decoding and compositing every frame — for a window collapsed into the
    /// Dock. With three apps open and two minimized, most of the frame pipeline's cost was going to windows
    /// nobody could see.
    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowId = window.identifier?.rawValue,
              windowsById[windowId] != nil else {
            return
        }

        onWindowVisibilityChange?(windowId, false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowId = window.identifier?.rawValue,
              windowsById[windowId] != nil else {
            return
        }

        onWindowVisibilityChange?(windowId, true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowId = window.identifier?.rawValue,
              windowsById[windowId] != nil,
              let contentView = window.contentView else {
            return
        }

        lastLiveResizeReportAt[windowId] = nil
        reportContentSize(contentView.bounds.size, windowId: windowId, screen: window.screen)
    }

    /// Keeps the Windows app resizing along with the Mac window while its edge is dragged, instead of
    /// stretching the old bitmap until the drag ends, which is how Parallels Coherence windows behave.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.inLiveResize,
              let windowId = window.identifier?.rawValue,
              windowsById[windowId] != nil,
              let contentView = window.contentView else {
            return
        }

        let now = Date()
        if let last = lastLiveResizeReportAt[windowId],
           now.timeIntervalSince(last) < Self.liveResizeReportInterval {
            return
        }
        lastLiveResizeReportAt[windowId] = now
        reportContentSize(contentView.bounds.size, windowId: windowId, screen: window.screen)
    }

    /// Zooming, from the Windows maximize button or a caption double-click, is not a live resize. The target
    /// size is sent as the animation starts, so Windows redraws at the new size while the Mac window grows.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard let windowId = window.identifier?.rawValue,
              windowsById[windowId] != nil else {
            return true
        }

        zoomEndsAt[windowId] = Date().addingTimeInterval(window.animationResizeTime(newFrame) + 0.3)
        reportContentSize(window.contentRect(forFrameRect: newFrame).size, windowId: windowId, screen: window.screen)
        return true
    }

    /// AppKit reports content dimensions in points. They intentionally map to the logical dimensions used by
    /// window.created/window.updated; the Windows agent applies its own per-monitor DPI when converting the
    /// request to physical pixels.
    private func reportContentSize(_ size: NSSize, windowId: String, screen: NSScreen?) {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else {
            return
        }

        onWindowResize?(windowId, width, height, screen?.frame.size)
    }

    /// Whether the user is resizing the window right now. Guest updates then leave its frame and shape alone:
    /// pinning the frame from mid-animation snapped a zoomed window back to its old size.
    private func isBeingResized(_ window: NSWindow, windowId: String) -> Bool {
        if window.inLiveResize {
            return true
        }
        guard let end = zoomEndsAt[windowId] else {
            return false
        }
        if end > Date() {
            return true
        }
        zoomEndsAt[windowId] = nil
        return false
    }

    private func present(_ window: NSWindow, windowId: String) {
        rememberWindowId(windowId)
        foregroundWindowId = windowId
        if QuietLaunch.isActive {
            window.orderBack(nil)
            return
        }
        MacWindowRestorePolicy.restoreToFront(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateExistingWindow(
        _ window: NSWindow,
        for session: WindowMirrorSession,
        bringToFront: Bool
    ) {
        if session.window.isPopup {
            configurePopup(window, for: session)
            if let existingView = window.contentView as? NSHostingView<WindowsAppMirrorView> {
                existingView.rootView = mirrorView(for: session)
            }
            let owner = window.parent ?? popupOwner(for: session)
            let target = popupFrame(for: session, owner: owner)
            if !NSEqualRects(window.frame, target) {
                window.setFrame(target, display: true, animate: false)
            }
            return
        }

        let preservedFrame = window.frame
        let isBeingResized = isBeingResized(window, windowId: session.id)
        configure(window, for: session, appliesResizeConstraints: !isBeingResized)
        // Every frame tile lands here. Building a new hosting view each time rebuilt the whole SwiftUI tree
        // and the input view on the main thread, which held mouse events back about 200 ms apiece while an
        // app was redrawing and could swap the input view out from under a drag. The existing hosting view
        // only gets the new session.
        if let existingView = window.contentView as? NSHostingView<WindowsAppMirrorView> {
            existingView.rootView = mirrorView(for: session)
        } else {
            window.contentView = hostingView(for: session)
        }
        if !isBeingResized, !NSEqualRects(window.frame, preservedFrame) {
            window.setFrame(preservedFrame, display: true, animate: false)
        }

        guard bringToFront else {
            // Content is swapped in place. The window keeps its position in the foreground order, so a
            // frame arriving for a background window cannot pull it in front of the user's active one.
            return
        }

        present(window, windowId: session.id)
    }

    private func rememberWindowId(_ windowId: String) {
        windowOrder.removeAll { $0 == windowId }
        windowOrder.append(windowId)
    }

    private func forgetWindowId(_ windowId: String) {
        windowOrder.removeAll { $0 == windowId }
        minimizedBeforeDesktop.remove(windowId)
        windowsWithFirstFrame.remove(windowId)
        identitiesById[windowId] = nil
        if windowsById.isEmpty {
            WindowsAppDockIcon.showInDock(nil)
        }
        zoomEndsAt[windowId] = nil
        lastLiveResizeReportAt[windowId] = nil
        if foregroundWindowId == windowId {
            foregroundWindowId = visibleWindowIds.last
        }
    }

    /// Tells the user a dragged file was not sent, on the window they dropped it onto.
    ///
    /// Records the refusal on the model and shows it. Deliberately not routed through
    /// `HostDashboardModel.errorMessage`: the only view that reads that field is `AgentView`, which is never
    /// instantiated, so a refusal sent there would be shown nowhere at all — and if it ever were shown, it
    /// would appear as an "Agent Unavailable" panel, which is the wrong diagnosis for a file being the wrong
    /// size.
    private func presentDropRefusal(_ refusal: WindowsAppFileDropRefusal, windowId: String) {
        onDropRefused?(refusal)
        showDropRefusal(refusal, windowId: windowId)
    }

    /// Shows a refusal that has already been recorded.
    ///
    /// Separate from ``presentDropRefusal`` because refusals arrive from two directions. The host decides
    /// some of them before the guest is contacted, and Windows reports the rest — those are recorded by
    /// `HostDashboardModel.openFile` on the way back, so recording them a second time here would be
    /// redundant.
    func showDropRefusal(_ refusal: WindowsAppFileDropRefusal, windowId: String) {
        showWindowsAppMessage(
            title: "Veil could not open that in Windows",
            detail: refusal.message,
            windowId: windowId
        )
    }

    /// Tells the user something about a mirrored window, on that window.
    ///
    /// The general form of ``showDropRefusal``. Used for any action the user took inside a mirrored window
    /// that Veil could not complete, so those messages never have to fall back on model state with no
    /// display surface.
    ///
    /// A sheet rather than a macOS notification, deliberately. Everything reported here is the immediate
    /// result of a gesture the user just made, and a notification can be silently suppressed by a permission
    /// decision made months ago — which would put these messages straight back into the silent-failure class
    /// they exist to leave.
    func showWindowsAppMessage(title: String, detail: String, windowId: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")

        // Attached to the window the gesture happened in, so the message appears where the user was looking.
        // If that window has since closed, an app-modal alert still beats losing the explanation.
        if let window = windowsById[windowId] {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// What loading one dropped file produced.
    ///
    /// Every case carries plain values and nothing else. That is the point: it can cross back to the main actor
    /// without dragging a closure or a SwiftUI view with it, which is what let the six separate main-actor hops
    /// this replaced collapse into one.
    private enum DroppedFileOutcome: Sendable {
        case ready(fileName: String, contentBase64: String)
        case refused(WindowsAppFileDropRefusal)
    }

    /// Reads each dropped file off the main actor and delivers the result back on it.
    ///
    /// Reading a file up to the size cap and base64-encoding it would block the UI on the main actor, so the work
    /// has to happen elsewhere. The hop back captures only this presenter — a `@MainActor` class, and therefore
    /// Sendable — plus strings and one `Sendable` outcome. That is the same shape as the `[weak self]` hop already
    /// used in `VeilHostShellApp`, rather than capturing view callbacks the way the first version did.
    ///
    /// Independent per file: nothing coordinates across the batch, so each refusal is reported the moment it is
    /// known and one bad file cannot take the others down with it.
    private func loadDroppedFiles(_ providers: [NSItemProvider], windowId: String, appId: String) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let outcome = Self.droppedFileOutcome(for: item)
                DispatchQueue.main.async { [weak self] in
                    self?.deliver(outcome, windowId: windowId, appId: appId)
                }
            }
        }
    }

    /// Turns a loaded pasteboard item into either a sendable file or a refusal.
    ///
    /// `nonisolated` and free of any reference to the presenter, so it runs on whatever queue the item provider
    /// calls back on. Also the reason drag-and-drop's rules are now reachable outside a closure at all.
    nonisolated private static func droppedFileOutcome(for item: (any NSSecureCoding)?) -> DroppedFileOutcome {
        guard let data = item as? Data,
              let url = URL(dataRepresentation: data, relativeTo: nil) else {
            return .refused(.unreadableItem)
        }

        let fileName = url.lastPathComponent
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize

        // Checked before reading, so an oversized file costs a stat rather than a full read plus a base64 copy
        // of itself.
        if let refusal = WindowsAppFileDropPolicy.refusal(forFileNamed: fileName, byteCount: byteCount) {
            return .refused(refusal)
        }

        guard let fileContent = try? Data(contentsOf: url) else {
            return .refused(.unreadableFile(fileName: fileName))
        }

        // The size check passed a moment ago, so an empty read means the file changed underneath us.
        guard !fileContent.isEmpty else {
            return .refused(.emptyFile(fileName: fileName))
        }

        // Rewritten to something Windows accepts. macOS allows `: * ? " < > | \` in a name and the guest refuses
        // them, so a legal Mac file would otherwise be rejected for a reason invisible on the user's own machine.
        // The guest validates independently and stays the security boundary.
        guard let safeFileName = WindowsAppFileDropPolicy.windowsSafeFileName(for: fileName) else {
            return .refused(.unusableFileName(fileName: fileName))
        }

        return .ready(fileName: safeFileName, contentBase64: fileContent.base64EncodedString())
    }

    private func deliver(_ outcome: DroppedFileOutcome, windowId: String, appId: String) {
        switch outcome {
        case .ready(let fileName, let contentBase64):
            onFileDrop?(appId, windowId, fileName, contentBase64)
        case .refused(let refusal):
            presentDropRefusal(refusal, windowId: windowId)
        }
    }

    private func hostingView(
        for session: WindowMirrorSession
    ) -> NSHostingView<WindowsAppMirrorView> {
        NSHostingView(rootView: mirrorView(for: session))
    }

    private func mirrorView(for session: WindowMirrorSession) -> WindowsAppMirrorView {
        WindowsAppMirrorView(
            session: session,
            onMouseInput: { [weak self] windowId, event, x, y in
                self?.onMouseInput?(windowId, event, x, y)
            },
            onScrollInput: { [weak self] windowId, x, y, deltaX, deltaY in
                self?.onScrollInput?(windowId, x, y, deltaX, deltaY)
            },
            onKeyInput: { [weak self] windowId, event, key, windowsVirtualKey, modifiers in
                self?.onKeyInput?(windowId, event, key, windowsVirtualKey, modifiers)
            },
            onTextInput: { [weak self] windowId, text in
                self?.onTextInput?(windowId, text)
            },
            onPasteShortcut: { [weak self] windowId, key, windowsVirtualKey, modifiers, content in
                self?.onPasteShortcut?(windowId, key, windowsVirtualKey, modifiers, content)
            },
            onDropProviders: { [weak self] providers in
                self?.loadDroppedFiles(
                    providers,
                    windowId: session.id,
                    appId: session.window.appId
                )
            },
            onDropRefused: { [weak self] refusal in
                self?.presentDropRefusal(refusal, windowId: session.id)
            },
            onRestartFrameStream: { [weak self] windowId in
                self?.onRestartFrameStream?(windowId)
            },
            compositedImageProvider: { [weak self] windowId in
                self?.compositedImageProvider?(windowId)
            },
            sessionProvider: { [weak self] windowId in
                self?.sessionProvider?(windowId)
            }
        )
    }

    private func configure(
        _ window: NSWindow,
        for session: WindowMirrorSession,
        appliesResizeConstraints: Bool = true
    ) {
        let identity = appIdentityProvider?(session.window.appId)
            ?? WindowsAppWindowIdentity.resolve(appId: session.window.appId, apps: [])
        window.title = session.window.title
        if appliesResizeConstraints {
            applyResizeConstraints(to: window, for: session)
        }
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.backgroundColor = .black
        window.isOpaque = true
        // The guest bitmap already starts with the Windows app's own title bar, so that caption is the only
        // one shown, as in Parallels Coherence. Stacking a macOS titlebar on top doubled the title and the
        // window buttons. The Mac window stays `.titled` for its shadow, rounded corners, resizing, and the
        // Window menu; the input view turns presses in the Windows caption into the matching Mac actions.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.toolbar = nil
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        identitiesById[session.id] = identity
        window.miniwindowImage = WindowsAppDockIcon.image(for: identity)
        if foregroundWindowId == session.id, window.isKeyWindow {
            WindowsAppDockIcon.showInDock(identity)
        }
    }

    /// Keeps a mirrored window at least as large as Windows allows, re-applied whenever guest bounds change.
    private func applyResizeConstraints(to window: NSWindow, for session: WindowMirrorSession) {
        let minimumSize = WindowsAppWindowPlacement.minimumContentSize(for: session.window.bounds)
        window.contentMinSize = NSSize(width: minimumSize.width, height: minimumSize.height)

        // Free resizing, like any Mac window. The guest window follows every size the Mac reports, and the
        // frame surface draws content unscaled from the top-left while it catches up, so there is no stretched
        // bitmap to protect with an aspect lock. Setting the increments is what clears an aspect ratio:
        // `contentResizeIncrements` pairs with the content-space ratio a previous version of Veil set.
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
    }

    private func frame(for bounds: WindowBounds, existingWindowCount: Int) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = WindowsAppWindowPlacement.initialFrame(
            for: bounds,
            visibleFrame: HostVisibleFrameGeometry(
                x: Double(visibleFrame.origin.x),
                y: Double(visibleFrame.origin.y),
                width: Double(visibleFrame.width),
                height: Double(visibleFrame.height)
            ),
            existingWindowCount: existingWindowCount
        )

        return NSRect(
            x: frame.x,
            y: frame.y,
            width: frame.width,
            height: frame.height
        )
    }
}

@MainActor
enum MacWindowRestorePolicy {
    static func restoreToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

// The drag-and-drop size cap lives in `WindowsAppFileDropPolicy` in VeilHostCore, together with the wording
// for every refusal, so the rules are testable without a window server and the messages cannot drift from the
// checks that produce them. It is a non-isolated enum of `static` members, which is what lets both this view
// (for the synchronous batch check) and the presenter's non-isolated loader read it.
//
// This view deliberately does no file I/O. It decides only what it can decide synchronously — how many files
// were dropped — and hands the providers to the presenter, which owns reading them off the main actor.

private struct WindowsAppMirrorView: View {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void
    var onScrollInput: (String, Int, Int, Int, Int) -> Void
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onTextInput: (String, String) -> Void
    var onPasteShortcut: (String, String, Int, [String], HostPasteboardContent) -> Void
    /// Called synchronously on the main actor with the accepted providers. Loading them is the presenter's job.
    var onDropProviders: ([NSItemProvider]) -> Void
    var onDropRefused: (WindowsAppFileDropRefusal) -> Void
    var onRestartFrameStream: (String) -> Void
    var compositedImageProvider: (String) -> CGImage?
    var sessionProvider: (String) -> WindowMirrorSession?
    @State private var isTargetedForDrop = false

    var body: some View {
        ZStack {
            WindowsAppFrameSurface(
                session: session,
                restartFrameStreamAction: onRestartFrameStream,
                compositedImageProvider: compositedImageProvider,
                sessionProvider: sessionProvider
            )

            InputCaptureView(
                session: session,
                onMouseInput: onMouseInput,
                onScrollInput: onScrollInput,
                onKeyInput: onKeyInput,
                onTextInput: onTextInput,
                onPasteShortcut: onPasteShortcut
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 4)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(session.window.isPopup ? Color.clear : Color.black)
        .ignoresSafeArea()
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop, perform: handleDrop)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else {
            return false
        }

        // The count is known synchronously, so an oversized batch is rejected outright. Returning `false`
        // here means macOS never plays the accept animation, which is the only moment a drop can be
        // declined without having to explain it afterwards.
        if let refusal = WindowsAppFileDropPolicy.refusal(forFileCount: fileProviders.count) {
            onDropRefused(refusal)
            return false
        }

        // Every dropped file, not just the first. Silently sending one of five was its own small lie.
        //
        // Handed to the presenter rather than loaded here. Reading a file up to the size cap and base64-encoding
        // it must not happen on the main actor, and doing that from inside a SwiftUI view meant an escaping
        // closure capturing the view's callbacks — six of them by the time every refusal was reported. The
        // presenter is a `@MainActor` class, so it can own the hop back with a capture the language is happy
        // about.
        onDropProviders(fileProviders)
        return true
    }

}

private struct InputCaptureView: NSViewRepresentable {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void
    var onScrollInput: (String, Int, Int, Int, Int) -> Void
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onTextInput: (String, String) -> Void
    var onPasteShortcut: (String, String, Int, [String], HostPasteboardContent) -> Void

    func makeNSView(context: Context) -> InputCaptureNSView {
        InputCaptureNSView()
    }

    func updateNSView(_ nsView: InputCaptureNSView, context: Context) {
        nsView.session = session
        nsView.onMouseInput = onMouseInput
        nsView.onScrollInput = onScrollInput
        nsView.onKeyInput = onKeyInput
        nsView.onTextInput = onTextInput
        nsView.onPasteShortcut = onPasteShortcut
    }
}

private final class InputCaptureNSView: NSView {
    var session: WindowMirrorSession?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    var onScrollInput: ((String, Int, Int, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onTextInput: ((String, String) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], HostPasteboardContent) -> Void)?
    private let keyboardMapper = MacKeyboardInputMapper()
    private let textInputRouter = MacTextInputRouter()

    /// In-progress IME composition. The guest never sees this; only committed text is sent.
    private var markedText = ""

    /// Set when the current key press produced committed text.
    ///
    /// Without this, a key that was delivered as `input.text` would also send a matching `input.key`
    /// key-up, posting a `WM_KEYUP` with no preceding `WM_KEYDOWN`. Harmless in a plain edit control,
    /// but apps that act on key-up would fire twice for one keystroke.
    private var didCommitTextForCurrentKeyPress = false

    /// A press in the Windows caption that has not yet turned into a window drag or a click.
    private var captionPress: (region: WindowsCaptionRegion, mouseDown: NSEvent)?

    /// How far a caption press travels before it becomes a window drag, matching a Windows drag threshold.
    private static let captionDragThreshold: CGFloat = 4

    override var acceptsFirstResponder: Bool { true }

    /// A click on a mirrored window or popup that is not key still reaches Windows, as it would there. Without
    /// this the first click on a popup or a background app window only activated it and was lost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The macOS titlebar is hidden over this view, and AppKit would otherwise drag the window for any press
    /// in that band before the Windows caption buttons under it ever saw the click.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// Draws the in-progress IME composition.
    ///
    /// The mirrored surface is a bitmap of a Windows window, so there is no text cursor to draw an
    /// inline composition at. Without this overlay a user typing Korean would see nothing at all until
    /// the syllable committed. Shown at the bottom-left, out of the way of most content.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !markedText.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        let composition = NSAttributedString(string: markedText, attributes: attributes)
        let textSize = composition.size()
        let padding: CGFloat = 6
        let background = NSRect(
            x: padding,
            y: padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
        let backgroundPath = NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4)
        backgroundPath.fill()
        NSColor.separatorColor.setStroke()
        backgroundPath.stroke()

        composition.draw(at: NSPoint(x: background.minX + padding, y: background.minY + padding / 2))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let region = captionRegion(for: event)
        guard region != .content else {
            send("leftDown", event)
            return
        }

        if region == .caption, event.clickCount == 2 {
            performCaptionDoubleClick()
            return
        }

        // Held back until the press either moves (a window drag) or is released (a click), since a press on
        // the caption cannot be both forwarded to Windows and turned into a Mac window drag.
        captionPress = (region, event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let press = captionPress else {
            send("leftUp", event)
            return
        }

        captionPress = nil
        VeilLog.window.notice("Caption click \(String(describing: press.region), privacy: .public)")
        switch press.region {
        case .closeButton:
            window?.performClose(nil)
        case .minimizeButton:
            window?.performMiniaturize(nil)
        case .maximizeButton:
            window?.performZoom(nil)
        case .caption, .content:
            // Some apps put tabs or a search box in the caption, so a plain click still reaches Windows.
            send("leftDown", press.mouseDown)
            send("leftUp", event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        send("rightDown", event)
    }

    override func rightMouseUp(with event: NSEvent) {
        send("rightUp", event)
    }

    /// Windows wheel units per point of precise (trackpad or Magic Mouse) scrolling. A notch of 120 scrolls
    /// three lines, about 60 points, so 2 keeps content tracking the fingers.
    static let wheelUnitsPerPoint = 2.0
    /// Sub-unit scroll amounts carried to the next event so slow trackpad movement still scrolls.
    private var scrollRemainder = (x: 0.0, y: 0.0)

    /// Trackpad and wheel scrolling, sent with its amount so Windows scrolls as far and as smoothly as the
    /// Mac gesture. macOS has already applied the user's natural-scrolling setting to these deltas.
    override func scrollWheel(with event: NSEvent) {
        guard let session,
              session.connectionMode == .agent,
              let point = guestPoint(for: event, session: session) else {
            return
        }

        let unitsPerDelta = event.hasPreciseScrollingDeltas ? Self.wheelUnitsPerPoint : 120
        let amount = WindowsScrollAmount.accumulate(
            remainder: scrollRemainder,
            scrollingDeltaX: Double(event.scrollingDeltaX),
            scrollingDeltaY: Double(event.scrollingDeltaY),
            unitsPerDelta: unitsPerDelta
        )
        scrollRemainder = amount.remainder
        guard amount.deltaX != 0 || amount.deltaY != 0 else {
            return
        }
        onScrollInput?(session.id, point.x, point.y, amount.deltaX, amount.deltaY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press = captionPress else {
            send("move", event)
            return
        }

        let start = press.mouseDown.locationInWindow
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) >= Self.captionDragThreshold else {
            return
        }

        // The window server runs the drag from here until the button is released, with the usual macOS
        // snapping and Space behavior, and the matching mouse-up never reaches this view.
        captionPress = nil
        VeilLog.window.notice("Caption drag from \(String(describing: press.region), privacy: .public)")
        window?.performDrag(with: event)
    }

    private func captionRegion(for event: NSEvent) -> WindowsCaptionRegion {
        guard let session,
              !session.window.isPopup,
              session.connectionMode == .agent,
              let guestPoint = guestPoint(for: event, session: session) else {
            return .content
        }

        let windowWidth = session.latestFrame?.width ?? session.window.bounds.width
        let region = WindowsCaptionRegion.classify(guestX: guestPoint.x, guestY: guestPoint.y, windowWidth: windowWidth)
        if region != .content {
            let point = convert(event.locationInWindow, from: nil)
            VeilLog.window.notice(
                """
                Caption press \(String(describing: region), privacy: .public) clicks=\(event.clickCount) \
                view=\(Int(point.x)),\(Int(point.y)) in \(Int(self.bounds.width))x\(Int(self.bounds.height)) \
                guest=\(guestPoint.x),\(guestPoint.y) source=\(session.latestFrame?.width ?? -1)x\(session.latestFrame?.height ?? -1) \
                bounds=\(session.window.bounds.width)x\(session.window.bounds.height) \
                window=\(Int(self.window?.frame.width ?? 0))x\(Int(self.window?.frame.height ?? 0))
                """
            )
        }
        return region
    }

    /// Follows the macOS "Double-click a window's title bar to" setting, which a Mac titlebar would.
    private func performCaptionDoubleClick() {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window?.performMiniaturize(nil)
        case "None":
            break
        default:
            window?.performZoom(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        didCommitTextForCurrentKeyPress = false

        // Text-producing keys go to the macOS input context first so an IME can compose them. The
        // context calls back into setMarkedText/insertText below. Keys whose guest meaning is the key
        // itself (Enter, Tab, arrows, shortcuts) skip it and keep the proven virtual-key path.
        if textInputRouter.shouldOfferToInputMethod(
            keyCode: event.keyCode,
            modifiers: macKeyboardModifiers(from: event),
            isComposing: hasMarkedText()
        ), inputContext?.handleEvent(event) == true {
            return
        }

        if !sendKey("keyDown", event) {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        // A key that produced committed text, or one still feeding an open composition, has already
        // been accounted for. Sending a key-up here would post an unmatched WM_KEYUP to the guest.
        if didCommitTextForCurrentKeyPress || hasMarkedText() {
            didCommitTextForCurrentKeyPress = false
            return
        }

        if !sendKey("keyUp", event) {
            super.keyUp(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // With sharing off the shortcut falls through to a plain Ctrl+V, so Windows pastes its own clipboard
        // and nothing on the Mac pasteboard is read.
        if isPasteShortcut(event),
           ClipboardSharingPreferences.isSharingEnabled(),
           let session,
           session.connectionMode == .agent,
           let input = keyboardMapper.input(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: macKeyboardModifiers(from: event)
           ),
           let content = HostPasteboardContent.read(
                from: .general,
                includeFiles: ClipboardSharingPreferences.isFilePasteEnabled()
           ) {
            onPasteShortcut?(session.id, input.key, input.windowsVirtualKey, input.modifiers, content)
            return true
        }

        guard sendKey("keyDown", event) else {
            return super.performKeyEquivalent(with: event)
        }

        _ = sendKey("keyUp", event)
        return true
    }

    private func send(_ inputEvent: String, _ event: NSEvent) {
        guard let session,
              session.connectionMode == .agent,
              let guestPoint = guestPoint(for: event, session: session) else {
            return
        }

        onMouseInput?(session.id, inputEvent, guestPoint.x, guestPoint.y)
    }

    private func guestPoint(for event: NSEvent, session: WindowMirrorSession) -> WindowFramePoint? {
        guard bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        let point = convert(event.locationInWindow, from: nil)
        let sourceWidth = session.latestFrame?.width ?? session.window.bounds.width
        let sourceHeight = session.latestFrame?.height ?? session.window.bounds.height
        let viewport = WindowFrameViewport(
            viewWidth: Double(bounds.width),
            viewHeight: Double(bounds.height),
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            fitsSourceIntoView: session.latestFrame != nil,
            // Matches WindowsAppFrameSurface, which draws the frame unscaled from the top-left.
            anchoredPointsPerPixel: session.latestFrame.map {
                WindowFrameViewport.pointsPerPixel(forWindowsScale: $0.scale)
            }
        )
        return viewport.guestPoint(
            forViewX: Double(point.x),
            viewYFromBottom: Double(point.y)
        )
    }

    private func sendKey(_ inputEvent: String, _ event: NSEvent) -> Bool {
        guard let session,
              session.connectionMode == .agent else {
            return false
        }

        switch textInputRouter.route(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: macKeyboardModifiers(from: event)
        ) {
        case .virtualKey(let input):
            onKeyInput?(session.id, inputEvent, input.key, input.windowsVirtualKey, input.modifiers)
            return true
        case .committedText(let text):
            // Punctuation and space have no virtual key in the mapper, so they used to be dropped here.
            // Sent once on key-down only; a character has no up event.
            guard inputEvent == "keyDown" else {
                return true
            }
            didCommitTextForCurrentKeyPress = true
            onTextInput?(session.id, text)
            return true
        case .unsupported:
            return false
        }
    }

    private func sendCommittedText(_ text: String) {
        guard let session,
              session.connectionMode == .agent else {
            return
        }

        switch textInputRouter.route(committedText: text) {
        case .virtualKey(let input):
            onKeyInput?(session.id, "keyDown", input.key, input.windowsVirtualKey, input.modifiers)
            onKeyInput?(session.id, "keyUp", input.key, input.windowsVirtualKey, input.modifiers)
        case .committedText(let committed):
            onTextInput?(session.id, committed)
        case .unsupported:
            break
        }
    }

    private func macKeyboardModifiers(from event: NSEvent) -> MacKeyboardModifier {
        let flags = event.modifierFlags
        var modifiers: MacKeyboardModifier = []

        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }

        return modifiers
    }

    private func isPasteShortcut(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    /// Handles editing commands the input method synthesizes after a composition closes.
    ///
    /// Routed through `sendCommittedText` so Enter and Tab still arrive at the guest as keys with their
    /// real semantics instead of as control characters, and so AppKit does not beep on keys it cannot
    /// act on itself.
    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            sendCommittedText("\r")
            return
        }

        if selector == #selector(NSResponder.insertTab(_:)) {
            sendCommittedText("\t")
        }
    }

}

/// macOS owns IME composition for mirrored Windows windows.
///
/// The alternative -- forwarding raw keystrokes and letting the Windows IME compose -- would need a
/// per-keystroke round trip plus a guest candidate window rendered over a mirrored bitmap. Composing on
/// the host keeps the round trip to one message per committed string and lets the user keep the macOS
/// input source they already use.
extension InputCaptureNSView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        markedText = ""
        didCommitTextForCurrentKeyPress = true
        needsDisplay = true

        let text: String
        switch string {
        case let attributed as NSAttributedString:
            text = attributed.string
        case let plain as String:
            text = plain
        default:
            return
        }

        sendCommittedText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = attributed.string
        case let plain as String:
            markedText = plain
        default:
            markedText = ""
        }

        needsDisplay = true
    }

    func unmarkText() {
        markedText = ""
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        NSRange(location: markedText.utf16.count, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        // The authoritative text lives in the Windows app, not here, so only the in-progress
        // composition can be served back to the input method.
        guard !markedText.isEmpty,
              range.location == 0,
              range.length <= markedText.utf16.count else {
            return nil
        }

        return NSAttributedString(string: markedText)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// Anchors the IME candidate window near the composition overlay drawn in `draw(_:)`.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let anchor = NSRect(x: 6, y: 6, width: 1, height: 20)
        guard let window else {
            return anchor
        }

        return window.convertToScreen(convert(anchor, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }

}
