import AppKit
import SwiftUI
import VeilHostCore

@MainActor
final class WindowsAppWindowPresenter: NSObject, NSWindowDelegate {
    private var windowsById: [String: NSWindow] = [:]

    func showWindow(
        for event: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        supportsCapture: Bool
    ) {
        if let window = windowsById[event.windowId] {
            window.title = event.title
            window.contentView = hostingView(
                for: event,
                connectionMode: connectionMode,
                supportsCapture: supportsCapture
            )
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: frame(for: event.bounds),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(event.windowId)
        window.title = event.title
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 360)
        window.contentView = hostingView(
            for: event,
            connectionMode: connectionMode,
            supportsCapture: supportsCapture
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        windowsById[event.windowId] = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
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
    }

    private func hostingView(
        for event: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        supportsCapture: Bool
    ) -> NSHostingView<WindowsAppMirrorPlaceholderView> {
        NSHostingView(
            rootView: WindowsAppMirrorPlaceholderView(
                event: event,
                connectionMode: connectionMode,
                supportsCapture: supportsCapture
            )
        )
    }

    private func frame(for bounds: WindowBounds) -> NSRect {
        let width = min(max(CGFloat(bounds.width), 720), 1280)
        let height = min(max(CGFloat(bounds.height), 460), 860)
        return NSRect(x: 0, y: 0, width: width, height: height)
    }
}

private struct WindowsAppMirrorPlaceholderView: View {
    var event: WindowCreatedEvent
    var connectionMode: HostConnectionMode
    var supportsCapture: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.headline)
                    Text(event.windowId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(connectionMode == .demo ? "Demo Window" : "Agent Window", systemImage: connectionMode == .demo ? "play.rectangle" : "bolt.horizontal.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(connectionMode == .demo ? .orange : .green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((connectionMode == .demo ? Color.orange : Color.green).opacity(0.12), in: Capsule())
            }
            .padding(14)
            .background(.regularMaterial)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Untitled")
                        .font(.system(size: 28, weight: .semibold))
                    Spacer()
                    Text(event.state.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("This macOS window is mapped to a Windows HWND. Live frame capture will replace this placeholder when the guest agent starts streaming the app surface.")
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
                        detail: supportsCapture ? "Available" : "Pending",
                        symbolName: "viewfinder",
                        tint: supportsCapture ? .green : .orange
                    )
                    MirrorStateTile(
                        title: "Input",
                        detail: "Planned",
                        symbolName: "keyboard",
                        tint: .secondary
                    )
                }

                Spacer()

                Text("Process \(event.processId)  |  \(event.bounds.width)x\(event.bounds.height) @ \(event.bounds.x),\(event.bounds.y)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
        }
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
