import AppKit
import VeilHostCore

/// Sends pointer and key events to Windows over QEMU's display connection, where they arrive as hardware
/// input. Used for windows the agent cannot reach; see `HardwareInputTranslator`.
///
/// The connection is open only while such a window is shown. It also receives the display, which costs
/// QEMU work to send, and elevated windows are mostly installers that come and go.
@MainActor
final class GuestHardwareInput: GuestHardwareInputSending {
    static let shared = GuestHardwareInput()

    private let display = RFBEmbeddedDisplayModel()

    private init() {
        // Connecting must not move the guest pointer.
        display.wakesDisplayOnConnect = false
    }

    var isReady: Bool {
        display.isReceiving
    }

    /// Connects while `isNeeded` and the surface is QEMU's loopback display; disconnects otherwise.
    func update(surface: VMConsoleDisplaySurface?, isNeeded: Bool) {
        guard isNeeded, let surface, surface.kind == .vncLoopback else {
            if display.activeEndpoint != nil {
                display.stop()
                VeilLog.window.notice("Hardware input connection closed")
            }
            return
        }
        if display.activeEndpoint == nil {
            VeilLog.window.notice("Hardware input connection opening for a window run as administrator")
        }
        display.connectIfNeeded(to: surface)
    }

    func send(_ events: [HardwareInputEvent]) {
        for event in events {
            switch event {
            case .pointer(let x, let y, let buttons):
                display.sendPointer(x: x, y: y, buttonMask: buttons)
            case .key(let keysym, let isDown):
                display.sendKeyEvent(keysym: keysym, isDown: isDown)
            }
        }
    }
}
