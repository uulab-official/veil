import AppKit
import Virtualization
import VeilHostCore

@MainActor
final class VMConsoleWindowPresenter: NSObject, NSWindowDelegate {
    private let bootRunner: VirtualizationVMRuntimeBooter
    private var window: NSWindow?

    init(bootRunner: VirtualizationVMRuntimeBooter) {
        self.bootRunner = bootRunner
        super.init()
    }

    func showConsoleIfAvailable() {
        guard let virtualMachine = bootRunner.activeVirtualMachine else {
            return
        }

        let consoleView = VZVirtualMachineView()
        consoleView.virtualMachine = virtualMachine
        consoleView.capturesSystemKeys = true
        consoleView.automaticallyReconfiguresDisplay = true

        if let window {
            window.contentView = consoleView
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Windows 11 Arm"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 1024, height: 640)
        window.contentView = consoleView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func closeConsole() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window {
            window = nil
        }
    }
}
