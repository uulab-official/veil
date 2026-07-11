import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

@MainActor
final class WindowsAppWindowPresenter: NSObject, NSWindowDelegate {
    private var windowsById: [String: NSWindow] = [:]
    private var appIdByWindowId: [String: String] = [:]
    private var windowOrder: [String] = []
    private var suppressedCloseWindowIds: Set<String> = []
    private(set) var foregroundWindowId: String?

    var onUserWindowClose: ((String) -> Void)?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], String) -> Void)?
    var onFileDrop: ((String, String, String) -> Void)?
    var onRestartFrameStream: ((String) -> Void)?

    var visibleWindowIds: [String] {
        windowOrder.filter { windowsById[$0] != nil }
    }

    func showWindow(for session: WindowMirrorSession) {
        if let window = windowsById[session.id] {
            updateExistingWindow(window, for: session)
            return
        }

        // This is a second, UI-level guard behind HostDashboardModel's app-first policy. An
        // unexpected guest HWND for the same app must replace the old presenter entry, never
        // accumulate a cascade of native macOS windows.
        if let existingWindowId = appIdByWindowId.first(where: { $0.value == session.window.appId })?.key {
            closeWindow(windowId: existingWindowId)
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
        window.contentMinSize = NSSize(width: 520, height: 360)
        configure(window, for: session)
        window.contentView = hostingView(
            for: session
        )
        windowsById[session.id] = window
        appIdByWindowId[session.id] = session.window.appId
        present(window, windowId: session.id)
    }

    func closeAll() {
        suppressedCloseWindowIds.formUnion(windowsById.keys)
        for window in windowsById.values {
            window.close()
        }
        windowsById.removeAll()
        appIdByWindowId.removeAll()
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
        appIdByWindowId[windowId] = nil
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
        appIdByWindowId[windowId] = nil
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

    private func present(_ window: NSWindow, windowId: String) {
        rememberWindowId(windowId)
        foregroundWindowId = windowId
        MacWindowRestorePolicy.restoreToFront(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateExistingWindow(_ window: NSWindow, for session: WindowMirrorSession) {
        let preservedFrame = window.frame
        configure(window, for: session)
        window.contentView = hostingView(
            for: session
        )
        if !NSEqualRects(window.frame, preservedFrame) {
            window.setFrame(preservedFrame, display: true, animate: false)
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
                onPasteShortcut: { [weak self] windowId, key, windowsVirtualKey, modifiers, text in
                    self?.onPasteShortcut?(windowId, key, windowsVirtualKey, modifiers, text)
                },
                onFileDrop: { [weak self] appId, fileName, contentBase64 in
                    self?.onFileDrop?(appId, fileName, contentBase64)
                },
                onRestartFrameStream: { [weak self] windowId in
                    self?.onRestartFrameStream?(windowId)
                }
            )
        )
    }

    private func configure(_ window: NSWindow, for session: WindowMirrorSession) {
        window.title = session.window.title
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

// Matches the guest's own MaxDroppedFileBytes cap (AgentSession.cs) -- checked here too so an
// oversized file fails fast locally instead of paying the cost of reading, base64-encoding, and
// sending it over the wire only for the guest to reject it afterward. A plain top-level constant
// (not a View's static member) so it can be read from the non-isolated NSItemProvider completion
// closure without a Sendable/MainActor-isolation warning.
private let maxDroppedFileBytes = 50 * 1024 * 1024

private struct WindowsAppMirrorView: View {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onPasteShortcut: (String, String, Int, [String], String) -> Void
    var onFileDrop: (String, String, String) -> Void
    var onRestartFrameStream: (String) -> Void
    @State private var isTargetedForDrop = false

    var body: some View {
        ZStack {
            WindowsAppFrameSurface(
                session: session,
                restartFrameStreamAction: onRestartFrameStream
            )

            InputCaptureView(
                session: session,
                onMouseInput: onMouseInput,
                onKeyInput: onKeyInput,
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
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil,
                  let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            guard let fileSize, fileSize > 0, fileSize <= maxDroppedFileBytes else {
                return
            }

            guard let fileContent = try? Data(contentsOf: url), !fileContent.isEmpty else {
                return
            }

            let fileName = url.lastPathComponent
            let contentBase64 = fileContent.base64EncodedString()
            DispatchQueue.main.async {
                onFileDrop(session.window.appId, fileName, contentBase64)
            }
        }

        return true
    }
}

private struct InputCaptureView: NSViewRepresentable {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onPasteShortcut: (String, String, Int, [String], String) -> Void

    func makeNSView(context: Context) -> InputCaptureNSView {
        InputCaptureNSView()
    }

    func updateNSView(_ nsView: InputCaptureNSView, context: Context) {
        nsView.session = session
        nsView.onMouseInput = onMouseInput
        nsView.onKeyInput = onKeyInput
        nsView.onPasteShortcut = onPasteShortcut
    }
}

private final class InputCaptureNSView: NSView {
    var session: WindowMirrorSession?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], String) -> Void)?
    private let keyboardMapper = MacKeyboardInputMapper()

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
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
        if !sendKey("keyDown", event) {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
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
              session.connectionMode == .agent,
              let input = keyboardMapper.input(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: macKeyboardModifiers(from: event)
              ) else {
            return false
        }

        onKeyInput?(session.id, inputEvent, input.key, input.windowsVirtualKey, input.modifiers)
        return true
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

}
