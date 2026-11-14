import Foundation

/// Maps Mac trackpad gestures onto the Windows input that apps there already understand.
///
/// Windows has no way to inject a precision-touchpad gesture (`CreateSyntheticPointerDevice` accepts only
/// touch and pen), so each gesture becomes the input Windows apps treat the same way:
///
/// - Pinch becomes Ctrl+wheel, the zoom input of Paint, Edge, Office, File Explorer and most other apps.
/// - A page swipe becomes the browser Back or Forward key, which `DefWindowProc` turns into `WM_APPCOMMAND`.
/// - Rotation has no shared meaning in Windows apps and is not sent.
///
/// See "Input Mouse" and "Input Key" in `docs/protocol.md`.
public enum WindowsTrackpadGesture {
    /// One wheel notch, the amount a single Ctrl+wheel zoom step is.
    public static let wheelNotch = 120

    /// Wheel units per unit of Mac magnification. Doubling the pinch (a magnification of 1) zooms five
    /// notches, about what Edge takes to go from 100% to 200%.
    public static let wheelUnitsPerMagnification = 600.0

    /// The Ctrl+wheel amount for one pinch event, in whole notches.
    ///
    /// Many Windows apps zoom one step per wheel message whatever its amount, so sending each small pinch
    /// event would zoom far too fast; only whole notches go out and the rest waits for the next event.
    /// A pinch outward (positive magnification) zooms in, as an upward wheel does.
    public static func pinchWheel(
        remainder: Double,
        magnification: Double
    ) -> (deltaY: Int, remainder: Double) {
        let total = remainder + magnification * wheelUnitsPerMagnification
        let notches = Int((total / Double(wheelNotch)).rounded(.towardZero))
        let deltaY = notches * wheelNotch
        return (deltaY, total - Double(deltaY))
    }

    /// The modifiers sent with a pinch's wheel input so Windows reads it as zoom.
    public static let pinchModifiers = ["ctrl"]

    public struct NavigationKey: Equatable, Sendable {
        public var key: String
        public var windowsVirtualKey: Int

        /// `VK_BROWSER_BACK`.
        public static let back = NavigationKey(key: "browserBack", windowsVirtualKey: 0xA6)
        /// `VK_BROWSER_FORWARD`.
        public static let forward = NavigationKey(key: "browserForward", windowsVirtualKey: 0xA7)
    }

    /// The navigation key for a page swipe, from the swipe event's `deltaX`.
    ///
    /// AppKit reports a positive `deltaX` for the swipe that Safari and Chrome treat as Back and a negative
    /// one for Forward. A vertical swipe has a zero `deltaX` and sends nothing.
    public static func navigationKey(forSwipeDeltaX deltaX: Double) -> NavigationKey? {
        if deltaX > 0 {
            return .back
        }
        if deltaX < 0 {
            return .forward
        }
        return nil
    }
}
