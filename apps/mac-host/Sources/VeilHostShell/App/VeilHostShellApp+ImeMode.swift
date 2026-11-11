import Carbon
import Foundation
import VeilHostCore

/// The macOS input source, read for the Windows IME to follow (docs/protocol.md § Input IME Mode).
enum MacInputSource {
    static func current() -> (languages: [String], isInputMode: Bool) {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ([], false)
        }
        var languages: [String] = []
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            languages = (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
        }
        var isInputMode = false
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) {
            let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
            isInputMode = CFEqual(type, kTISTypeKeyboardInputMode) || CFEqual(type, kTISTypeKeyboardInputMethodModeEnabled)
        }
        return (languages, isInputMode)
    }

    @MainActor private static var observer: NSObjectProtocol?

    /// Calls `onChange` when the user switches input source, for example with Caps Lock or Control-Space.
    @MainActor
    static func observeChanges(_ onChange: @escaping @MainActor () -> Void) {
        guard observer == nil else {
            return
        }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in onChange() }
        }
    }
}

/// While Veil types commands into Windows itself, the Windows IME stays off whatever the Mac input source is.
@MainActor
enum GuestAutomatedTyping {
    /// Long enough for the Run dialog to take the command and start it.
    static let holdSeconds: TimeInterval = 20
    private(set) static var until: Date?

    static var isActive: Bool {
        guard let until else { return false }
        return Date() < until
    }

    static func begin() {
        until = Date().addingTimeInterval(holdSeconds)
    }
}

extension VeilHostShellApp {
    /// Keeps the Windows IME on or off with the Mac's input source: Windows composes from the keys in both views.
    @MainActor
    func syncGuestImeMode() async {
        let source = MacInputSource.current()
        let mode = GuestAutomatedTyping.isActive
            ? GuestImeMode.alphanumeric
            : GuestImeMode.desired(macInputSourceLanguages: source.languages, macInputSourceIsInputMode: source.isInputMode)
        await model.syncGuestImeMode(mode)
    }

    @MainActor
    func startGuestImeModeSync() {
        vmRuntimeBooter.prepareGuestForTyping = {
            GuestAutomatedTyping.begin()
            await syncGuestImeMode()
            // Back to the Mac's input source once the command has run.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(GuestAutomatedTyping.holdSeconds + 1))
                await syncGuestImeMode()
            }
        }
        MacInputSource.observeChanges {
            Task { @MainActor in await syncGuestImeMode() }
        }
    }
}
