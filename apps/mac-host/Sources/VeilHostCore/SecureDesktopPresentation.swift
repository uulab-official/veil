import Foundation

/// What to do about Windows' secure desktop while apps show as their own Mac windows.
///
/// A User Account Control prompt, the lock screen, and the Ctrl+Alt+Del screen take the whole guest display
/// and belong to no app window, so no Mac window shows them, and input sent through the agent does not
/// reach them. Veil then shows the guest display in a window of its own, where clicks and keys go through
/// the virtual hardware. The agent reports the state in `window.layout`'s `secureDesktop`.
public enum SecureDesktopPresentation {
    public enum Action: Equatable, Sendable {
        case none
        /// Open the window showing the guest display and make it the key window.
        case show
        /// Veil is not the app in use: ask for attention in the Dock and wait until it is.
        case requestAttention
        case close
    }

    /// - Parameters:
    ///   - isSecure: the latest layout says the secure desktop is up.
    ///   - canShowDisplay: Windows is running and its display can be shown and driven.
    ///   - showsApps: apps are shown as Mac windows. In the desktop view the display is already on screen.
    ///   - isWindowShown: the window for the secure desktop is open.
    ///   - wasDismissed: the user closed that window during this prompt.
    ///   - appIsActive: Veil is the app in use.
    ///   - attentionRequested: attention was already asked for during this prompt.
    public static func action(
        isSecure: Bool,
        canShowDisplay: Bool,
        showsApps: Bool,
        isWindowShown: Bool,
        wasDismissed: Bool,
        appIsActive: Bool,
        attentionRequested: Bool
    ) -> Action {
        guard isSecure, canShowDisplay, showsApps else {
            return isWindowShown ? .close : .none
        }
        if isWindowShown || wasDismissed {
            return .none
        }
        if appIsActive {
            return .show
        }
        // A window opening over another app would take the user out of what they are doing for a prompt
        // that may not be theirs, such as Windows locking itself after sitting idle.
        return attentionRequested ? .none : .requestAttention
    }

    /// The size of the window's content: the guest display's shape, as large as fits in the given share of
    /// the screen's usable area.
    public static func contentSize(
        display: GuestPixelRect,
        visibleWidth: Double,
        visibleHeight: Double,
        share: Double = 0.62
    ) -> (width: Double, height: Double) {
        let aspect = display.width > 0 && display.height > 0
            ? Double(display.width) / Double(display.height)
            : 16.0 / 10.0
        var width = max(visibleWidth * share, 640)
        var height = width / aspect
        let maximumHeight = max(visibleHeight * share, 400)
        if height > maximumHeight {
            height = maximumHeight
            width = height * aspect
        }
        return (width.rounded(), height.rounded())
    }
}
