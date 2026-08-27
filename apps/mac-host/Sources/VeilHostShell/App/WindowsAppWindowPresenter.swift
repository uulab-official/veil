import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

@MainActor
final class WindowsAppWindowPresenter: NSObject, NSWindowDelegate {
    private var windowsById: [String: NSWindow] = [:]
    private var windowOrder: [String] = []
    private var suppressedCloseWindowIds: Set<String> = []
    private(set) var foregroundWindowId: String?

    var onUserWindowClose: ((String) -> Void)?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onTextInput: ((String, String) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], String) -> Void)?
    /// `(appId, windowId, fileName, contentBase64)`. Carries the window id so a failure that only Windows
    /// can report can still be shown on the window the file was dropped onto.
    var onFileDrop: ((String, String, String, String) -> Void)?
    /// Called when a dragged file was not sent. Separate from `onFileDrop` because a refusal has to reach
    /// the user: macOS has already played its accept animation by the time most refusals are known.
    var onDropRefused: ((WindowsAppFileDropRefusal) -> Void)?
    /// Reads the composited surface for a window. Supplied by the app, which owns the model that owns the
    /// compositor.
    var compositedImageProvider: ((String) -> CGImage?)?
    var onRestartFrameStream: ((String) -> Void)?
    /// `(windowId, isVisible)`. Fires when a mirrored window is minimized or restored, so frame streaming can
    /// stop for a window that cannot show anything.
    var onWindowVisibilityChange: ((String, Bool) -> Void)?

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
        if let window = windowsById[session.id] {
            updateExistingWindow(window, for: session, bringToFront: bringToFront)
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
        present(window, windowId: session.id)
    }

    func closeAll() {
        suppressedCloseWindowIds.formUnion(windowsById.keys)
        for window in windowsById.values {
            window.close()
        }
        windowsById.removeAll()
        windowOrder.removeAll()
        foregroundWindowId = nil
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
        guard !windowsById.isEmpty else {
            return
        }

        for windowId in visibleWindowIds {
            if let window = windowsById[windowId] {
                MacWindowRestorePolicy.restoreToFront(window)
            }
        }
        foregroundWindowId = visibleWindowIds.last
        NSApp.activate(ignoringOtherApps: true)
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

    private func present(_ window: NSWindow, windowId: String) {
        rememberWindowId(windowId)
        foregroundWindowId = windowId
        MacWindowRestorePolicy.restoreToFront(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateExistingWindow(
        _ window: NSWindow,
        for session: WindowMirrorSession,
        bringToFront: Bool
    ) {
        let preservedFrame = window.frame
        configure(window, for: session)
        window.contentView = hostingView(
            for: session
        )
        if !NSEqualRects(window.frame, preservedFrame) {
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
        NSHostingView(
            rootView: WindowsAppMirrorView(
                session: session,
                onMouseInput: { [weak self] windowId, event, x, y in
                    self?.onMouseInput?(windowId, event, x, y)
                },
                onKeyInput: { [weak self] windowId, event, key, windowsVirtualKey, modifiers in
                    self?.onKeyInput?(windowId, event, key, windowsVirtualKey, modifiers)
                },
                onTextInput: { [weak self] windowId, text in
                    self?.onTextInput?(windowId, text)
                },
                onPasteShortcut: { [weak self] windowId, key, windowsVirtualKey, modifiers, text in
                    self?.onPasteShortcut?(windowId, key, windowsVirtualKey, modifiers, text)
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
                }
            )
        )
    }

    private func configure(_ window: NSWindow, for session: WindowMirrorSession) {
        window.title = session.window.title
        applyResizeConstraints(to: window, for: session)
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.backgroundColor = .black
        window.isOpaque = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.toolbar = nil
    }

    /// Locks a mirrored window to the guest window's shape while the user resizes it.
    ///
    /// Veil cannot resize the Windows window — the protocol has no host-to-guest resize message — so dragging
    /// a corner only changes how the guest's bitmap is presented. `WindowsAppFrameSurface` renders with
    /// `scaledToFit` over black, so before this, any shape other than the guest's produced black letterbox
    /// bars: the window grew and the app did not follow.
    ///
    /// Re-applied whenever guest bounds change, because the guest window really can be resized from inside
    /// Windows, and the lock has to track it rather than pin the shape it had at launch.
    private func applyResizeConstraints(to window: NSWindow, for session: WindowMirrorSession) {
        let minimumSize = WindowsAppWindowPlacement.minimumContentSize(for: session.window.bounds)
        window.contentMinSize = NSSize(width: minimumSize.width, height: minimumSize.height)

        guard let ratio = WindowsAppWindowPlacement.contentAspectRatio(for: session.window.bounds) else {
            // A degenerate guest size would produce a ratio derived from nothing. Leaving the window freely
            // resizable is better than locking it to a guess.
            //
            // `contentResizeIncrements`, not `resizeIncrements`: AppKit pairs content-space aspect ratio with
            // content-space increments, and frame-space with frame-space. Clearing the wrong pair would leave
            // a stale ratio from an earlier refresh in place.
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
            return
        }

        window.contentAspectRatio = NSSize(width: ratio.width, height: ratio.height)
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
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onTextInput: (String, String) -> Void
    var onPasteShortcut: (String, String, Int, [String], String) -> Void
    /// Called synchronously on the main actor with the accepted providers. Loading them is the presenter's job.
    var onDropProviders: ([NSItemProvider]) -> Void
    var onDropRefused: (WindowsAppFileDropRefusal) -> Void
    var onRestartFrameStream: (String) -> Void
    var compositedImageProvider: (String) -> CGImage?
    @State private var isTargetedForDrop = false

    var body: some View {
        ZStack {
            WindowsAppFrameSurface(
                session: session,
                restartFrameStreamAction: onRestartFrameStream,
                compositedImageProvider: compositedImageProvider
            )

            InputCaptureView(
                session: session,
                onMouseInput: onMouseInput,
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
        .background(Color.black)
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
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onTextInput: (String, String) -> Void
    var onPasteShortcut: (String, String, Int, [String], String) -> Void

    func makeNSView(context: Context) -> InputCaptureNSView {
        InputCaptureNSView()
    }

    func updateNSView(_ nsView: InputCaptureNSView, context: Context) {
        nsView.session = session
        nsView.onMouseInput = onMouseInput
        nsView.onKeyInput = onKeyInput
        nsView.onTextInput = onTextInput
        nsView.onPasteShortcut = onPasteShortcut
    }
}

private final class InputCaptureNSView: NSView {
    var session: WindowMirrorSession?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onTextInput: ((String, String) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], String) -> Void)?
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

    override var acceptsFirstResponder: Bool { true }

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
        send("leftDown", event)
    }

    override func mouseUp(with event: NSEvent) {
        send("leftUp", event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        send("rightDown", event)
    }

    override func rightMouseUp(with event: NSEvent) {
        send("rightUp", event)
    }

    override func mouseDragged(with event: NSEvent) {
        send("move", event)
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

        if isPasteShortcut(event),
           let session,
           session.connectionMode == .agent,
           let input = keyboardMapper.input(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: macKeyboardModifiers(from: event)
           ),
           let pasteboardText = NSPasteboard.general.string(forType: .string) {
            onPasteShortcut?(session.id, input.key, input.windowsVirtualKey, input.modifiers, pasteboardText)
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
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let sourceWidth = session.latestFrame?.width ?? session.window.bounds.width
        let sourceHeight = session.latestFrame?.height ?? session.window.bounds.height
        let viewport = WindowFrameViewport(
            viewWidth: Double(bounds.width),
            viewHeight: Double(bounds.height),
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            fitsSourceIntoView: session.latestFrame != nil
        )
        guard let guestPoint = viewport.guestPoint(
            forViewX: Double(point.x),
            viewYFromBottom: Double(point.y)
        ) else {
            return
        }

        onMouseInput?(session.id, inputEvent, guestPoint.x, guestPoint.y)
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
