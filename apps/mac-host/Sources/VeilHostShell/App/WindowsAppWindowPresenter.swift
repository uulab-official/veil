import AppKit
import SwiftUI
import VeilHostCore

@MainActor
final class WindowsAppWindowPresenter: NSObject, NSWindowDelegate {
    private var windowsById: [String: NSWindow] = [:]
    private var suppressedCloseWindowIds: Set<String> = []

    var onUserWindowClose: ((String) -> Void)?
    var onMouseInput: ((String, String, Int, Int) -> Void)?

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
    ) -> NSHostingView<WindowsAppMirrorPlaceholderView> {
        NSHostingView(
            rootView: WindowsAppMirrorPlaceholderView(
                session: session,
                onMouseInput: { [weak self] windowId, event, x, y in
                    self?.onMouseInput?(windowId, event, x, y)
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

private struct WindowsAppMirrorPlaceholderView: View {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.window.title)
                        .font(.headline)
                    Text(session.window.windowId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(session.connectionMode == .demo ? "Demo Window" : "Agent Window", systemImage: session.connectionMode == .demo ? "play.rectangle" : "bolt.horizontal.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.connectionMode == .demo ? .orange : .green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((session.connectionMode == .demo ? Color.orange : Color.green).opacity(0.12), in: Capsule())
            }
            .padding(14)
            .background(.regularMaterial)

            Divider()

            ZStack {
                if let latestFrameImage {
                    ZStack(alignment: .bottomLeading) {
                        Color(nsColor: .windowBackgroundColor)
                        Image(nsImage: latestFrameImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Text(frameCaption)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Untitled")
                                .font(.system(size: 28, weight: .semibold))
                            Spacer()
                            Text(session.window.state.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(captureDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            MirrorStateTile(
                                title: "Window Tracking",
                                detail: "Mapped",
                                symbolName: "rectangle.3.group",
                                tint: .green
                            )
                            MirrorStateTile(
                                title: "Capture",
                                detail: captureDetail,
                                symbolName: "viewfinder",
                                tint: captureTint
                            )
                            MirrorStateTile(
                                title: "Input",
                                detail: session.connectionMode == .agent ? "Forwarded" : "Planned",
                                symbolName: "keyboard",
                                tint: session.connectionMode == .agent ? .green : .secondary
                            )
                        }

                        Spacer()

                        Text("Process \(session.window.processId)  |  \(session.window.bounds.width)x\(session.window.bounds.height) @ \(session.window.bounds.x),\(session.window.bounds.y)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))
                }

                MouseInputCaptureView(session: session, onMouseInput: onMouseInput)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var frameCaption: String {
        guard let frame = session.latestFrame else {
            return ""
        }

        return "\(frame.format.uppercased()) \(frame.width)x\(frame.height) #\(frame.sequence)"
    }

    private var captureDescription: String {
        switch session.captureState {
        case .streaming:
            "Live pixels are streaming from the Windows guest for this HWND."
        case .pending:
            "Mapped to a Windows HWND. Capture is available and waiting for the guest agent to start streaming this window."
        case .unavailable:
            "Mapped to a Windows HWND. Live app pixels will appear here when the guest agent starts streaming this window."
        }
    }

    private var captureDetail: String {
        switch session.captureState {
        case .streaming:
            "Streaming"
        case .pending:
            "Pending"
        case .unavailable:
            "Unavailable"
        }
    }

    private var captureTint: Color {
        switch session.captureState {
        case .streaming:
            .green
        case .pending:
            .orange
        case .unavailable:
            .secondary
        }
    }
}

private struct MouseInputCaptureView: NSViewRepresentable {
    var session: WindowMirrorSession
    var onMouseInput: (String, String, Int, Int) -> Void

    func makeNSView(context: Context) -> MouseInputNSView {
        MouseInputNSView()
    }

    func updateNSView(_ nsView: MouseInputNSView, context: Context) {
        nsView.session = session
        nsView.onMouseInput = onMouseInput
    }
}

private final class MouseInputNSView: NSView {
    var session: WindowMirrorSession?
    var onMouseInput: ((String, String, Int, Int) -> Void)?

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

    private func send(_ inputEvent: String, _ event: NSEvent) {
        guard let session,
              session.connectionMode == .agent,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let windowX = clamp(
            Int((point.x / bounds.width) * CGFloat(session.window.bounds.width)),
            lower: 0,
            upper: max(session.window.bounds.width - 1, 0)
        )
        let topOriginY = bounds.height - point.y
        let windowY = clamp(
            Int((topOriginY / bounds.height) * CGFloat(session.window.bounds.height)),
            lower: 0,
            upper: max(session.window.bounds.height - 1, 0)
        )

        onMouseInput?(session.id, inputEvent, windowX, windowY)
    }

    private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}

private struct MirrorStateTile: View {
    var title: String
    var detail: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.callout.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
