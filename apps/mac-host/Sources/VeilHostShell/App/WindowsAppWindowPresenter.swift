import AppKit
import SwiftUI
import VeilHostCore

@MainActor
final class WindowsAppWindowPresenter: NSObject, NSWindowDelegate {
    private var windowsById: [String: NSWindow] = [:]
    private var suppressedCloseWindowIds: Set<String> = []

    var onUserWindowClose: ((String) -> Void)?
    var onMouseInput: ((String, String, Int, Int) -> Void)?
    var onKeyInput: ((String, String, String, Int, [String]) -> Void)?
    var onPasteShortcut: ((String, String, Int, [String], String) -> Void)?

    func showWindow(for session: WindowMirrorSession) {
        if let window = windowsById[session.id] {
            window.title = session.window.title
            window.contentView = hostingView(
                for: session
            )
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: frame(for: session.window.bounds),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(session.id)
        window.title = session.window.title
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 360)
        window.contentView = hostingView(
            for: session
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        windowsById[session.id] = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
        suppressedCloseWindowIds.formUnion(windowsById.keys)
        for window in windowsById.values {
            window.close()
        }
        windowsById.removeAll()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let windowId = window.identifier?.rawValue else {
            return
        }

        windowsById[windowId] = nil

        if suppressedCloseWindowIds.remove(windowId) == nil {
            onUserWindowClose?(windowId)
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
                }
            )
        )
    }

    private func frame(for bounds: WindowBounds) -> NSRect {
        let width = min(max(CGFloat(bounds.width), 760), 1040)
        let height = min(max(CGFloat(bounds.height) * 0.70, 440), 620)
        return NSRect(x: 0, y: 0, width: width, height: height)
    }
}

private struct WindowsAppMirrorView: View {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void
    var onKeyInput: (String, String, String, Int, [String]) -> Void
    var onPasteShortcut: (String, String, Int, [String], String) -> Void

    var body: some View {
        ZStack {
            mirrorSurface

            InputCaptureView(
                session: session,
                onMouseInput: onMouseInput,
                onKeyInput: onKeyInput,
                onPasteShortcut: onPasteShortcut
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var mirrorSurface: some View {
        if let latestFrameImage {
            Color.black
                .overlay {
                    Image(nsImage: latestFrameImage)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        } else {
            pendingSurface
        }
    }

    private var latestFrameImage: NSImage? {
        guard let frame = session.latestFrame,
              frame.format == "png",
              let data = frame.encodedPayloadData else {
            return nil
        }

        return NSImage(data: data)
    }

    private var pendingSurface: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            VStack(spacing: 14) {
                Image(systemName: "note.text")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
           let key = inputKey(from: event),
           let windowsVirtualKey = windowsVirtualKey(from: event, key: key),
           let pasteboardText = NSPasteboard.general.string(forType: .string) {
            onPasteShortcut?(session.id, key, windowsVirtualKey, windowsModifiers(from: event), pasteboardText)
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
              let key = inputKey(from: event),
              let windowsVirtualKey = windowsVirtualKey(from: event, key: key) else {
            return false
        }

        onKeyInput?(session.id, inputEvent, key, windowsVirtualKey, windowsModifiers(from: event))
        return true
    }

    private func inputKey(from event: NSEvent) -> String? {
        if let characters = event.charactersIgnoringModifiers,
           let scalar = characters.unicodeScalars.first,
           scalar.value >= 32,
           scalar.value <= 126 {
            return String(Character(scalar)).lowercased()
        }

        switch event.keyCode {
        case 36:
            return "enter"
        case 48:
            return "tab"
        case 49:
            return "space"
        case 51:
            return "backspace"
        case 53:
            return "escape"
        case 123:
            return "arrowLeft"
        case 124:
            return "arrowRight"
        case 125:
            return "arrowDown"
        case 126:
            return "arrowUp"
        default:
            return nil
        }
    }

    private func windowsVirtualKey(from event: NSEvent, key: String) -> Int? {
        if let scalar = key.uppercased().unicodeScalars.first,
           scalar.value >= 65,
           scalar.value <= 90 {
            return Int(scalar.value)
        }

        if let scalar = key.unicodeScalars.first,
           scalar.value >= 48,
           scalar.value <= 57 {
            return Int(scalar.value)
        }

        switch event.keyCode {
        case 36:
            return 13
        case 48:
            return 9
        case 49:
            return 32
        case 51:
            return 8
        case 53:
            return 27
        case 123:
            return 37
        case 124:
            return 39
        case 125:
            return 40
        case 126:
            return 38
        default:
            return nil
        }
    }

    private func windowsModifiers(from event: NSEvent) -> [String] {
        let flags = event.modifierFlags
        var modifiers: [String] = []

        if flags.contains(.command) || flags.contains(.control) {
            modifiers.append("ctrl")
        }
        if flags.contains(.shift) {
            modifiers.append("shift")
        }
        if flags.contains(.option) {
            modifiers.append("alt")
        }

        return modifiers
    }

    private func isPasteShortcut(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

}
