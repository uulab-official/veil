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

extension VeilHostShellApp {
    /// Keeps the Windows IME where the keys need it: off in the apps view, where macOS composes, and on or
    /// off with the Mac's input source in the desktop view, where Windows composes.
    @MainActor
    func syncGuestImeMode() async {
        let source = MacInputSource.current()
        await model.syncGuestImeMode(
            GuestImeMode.desired(
                isDesktopView: shellNavigation.viewMode == .desktop,
                macInputSourceLanguages: source.languages,
                macInputSourceIsInputMode: source.isInputMode
            )
        )
    }

    @MainActor
    func startGuestImeModeSync() {
        MacInputSource.observeChanges {
            Task { @MainActor in await syncGuestImeMode() }
        }
    }
}
