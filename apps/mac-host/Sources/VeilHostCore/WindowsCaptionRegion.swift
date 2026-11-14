import Foundation

/// Where a point in a mirrored window's bitmap falls relative to the Windows title bar.
///
/// A mirrored window shows the Windows app's own title bar, the way Parallels Coherence does, instead of
/// stacking a macOS titlebar above it. The host still has to own moving, minimizing, zooming, and closing the
/// Mac window, so presses in the Windows caption are classified here before any of them reach the guest.
///
/// The geometry is the Windows 11 standard caption at 100% scaling: a 32 px tall caption with 46 px wide
/// minimize, maximize, and close buttons at its right edge. The agent does not report the window's DPI or
/// caption metrics yet, so a guest at a larger text scale gets a caption band that is slightly too short and
/// buttons that are slightly too narrow. Both errors stay inside the real caption, so a press is never taken
/// away from the app's own content.
/// See https://learn.microsoft.com/windows/apps/design/basics/titlebar-design.
public enum WindowsCaptionRegion: Equatable, Sendable {
    case content
    case caption
    case minimizeButton
    case maximizeButton
    case closeButton

    public static let captionHeight = 32
    public static let captionButtonWidth = 46

    /// Classifies a point in guest window pixels, measured from the window's top-left corner.
    public static func classify(guestX: Int, guestY: Int, windowWidth: Int) -> WindowsCaptionRegion {
        guard windowWidth > 0,
              guestX >= 0,
              guestX < windowWidth,
              guestY >= 0,
              guestY < captionHeight else {
            return .content
        }

        let distanceFromRightEdge = windowWidth - guestX
        // A window too narrow for three buttons and some caption keeps its whole caption draggable instead
        // of turning every press into a button.
        guard windowWidth > captionButtonWidth * 4 else {
            return .caption
        }

        switch distanceFromRightEdge {
        case ...captionButtonWidth:
            return .closeButton
        case ...(captionButtonWidth * 2):
            return .maximizeButton
        case ...(captionButtonWidth * 3):
            return .minimizeButton
        default:
            return .caption
        }
    }
}
