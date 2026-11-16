import AppKit
import SwiftUI
import VeilHostCore

/// The window that shows the guest display while Windows' secure desktop has it: a User Account Control
/// prompt, the lock screen, or the Ctrl+Alt+Del screen. See `SecureDesktopPresentation`.
///
/// It shows the display over QEMU's loopback display connection, whose pointer and key events arrive in
/// Windows as hardware input. That is the only input the secure desktop takes: what the agent sends with
/// `SendInput` goes to the user's desktop. The display keeps its size, so no app window moves.
@MainActor
final class SecureDesktopWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var isClosingItself = false
    /// The user closed the window while the secure desktop was still up.
    private(set) var wasDismissed = false
    /// Attention was asked for in the Dock during this prompt.
    private(set) var attentionRequested = false

    /// Run when Veil becomes the app in use, which is when a prompt that only asked for attention shows.
    var onAppBecameActive: (@MainActor () -> Void)?
    private var activationObserver: NSObjectProtocol?

    override init() {
        super.init()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                // Coming back to Veil is a fresh look: a prompt closed earlier shows again while it lasts.
                self.resetForNewAttempt()
                self.onAppBecameActive?()
            }
        }
    }

    var isShown: Bool {
        window != nil
    }

    func show(surface: VMConsoleDisplaySurface, display: GuestPixelRect, commandKeyMapping: VMCommandKeyMapping) {
        guard window == nil else {
            return
        }
        let rootView = WindowsEmbeddedDisplayPreview(
            image: nil,
            surface: surface,
            path: "",
            revisionID: surface.endpoint ?? "windows-secure-desktop",
            // Pointer and keys go over the display connection; these are for a surface without one.
            pointerTapAction: { _, _ in },
            keyAction: { _ in },
            commandKeyMapping: commandKeyMapping,
            resizesGuestDisplay: false
        )
        .background(Color.black)

        let visible = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = SecureDesktopPresentation.contentSize(
            display: display,
            visibleWidth: visible.width,
            visibleHeight: visible.height
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("windows-secure-desktop")
        window.title = String(localized: "Windows Needs Your Attention")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.contentAspectRatio = NSSize(width: size.width, height: size.height)
        window.contentMinSize = NSSize(width: 480, height: 480 * size.height / max(size.width, 1))
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))
        self.window = window
        window.makeKeyAndOrderFront(nil)
        VeilLog.window.notice("Showing the Windows secure desktop in its own window")
    }

    /// Asks for attention in the Dock once per prompt, without bringing Veil forward.
    func requestAttention() {
        attentionRequested = true
        NSApp.requestUserAttention(.informationalRequest)
    }

    /// Closes the window because the secure desktop is gone, and forgets what happened during it.
    func close() {
        wasDismissed = false
        attentionRequested = false
        guard let window else {
            return
        }
        isClosingItself = true
        window.close()
        isClosingItself = false
        self.window = nil
    }

    /// Forgets that the prompt was closed or announced, so the next check may show it again.
    func resetForNewAttempt() {
        wasDismissed = false
        attentionRequested = false
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        if !isClosingItself {
            wasDismissed = true
        }
        window = nil
    }
}
