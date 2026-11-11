import Foundation

public struct GuestDisplaySize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The newest size the Mac asked a mirrored window to take, waiting behind a resize already in flight.
struct PendingMirrorResize: Equatable, Sendable {
    var width: Int
    var height: Int
    var macScreenWidth: Int
    var macScreenHeight: Int
    var pixelsPerPoint: Int = 1
}

/// Picks a Windows display size large enough for a mirrored window to take the size the Mac asked for.
///
/// Windows never lets a window grow much past its display: a request for a bigger window is clamped to the
/// display plus its resize borders. Zooming a mirrored window on a Mac screen larger than the guest display
/// therefore stretched a small guest bitmap across a large Mac window instead of giving the app more room.
/// The display grows to the Mac screen first, the way Parallels Coherence sizes its guest display to the Mac
/// screen, and the window resize follows.
public enum MirroredWindowDisplayFit {
    /// Room for the Windows taskbar, which still occupies the bottom of the guest display.
    public static let taskbarAllowance = 48

    /// The display size to request before resizing the window, or nil when the current display already fits.
    ///
    /// An unknown current size counts as too small, so the first zoom always settles the display. The display
    /// never shrinks here; shrinking it would move every other mirrored window that still fits.
    public static func displaySize(
        windowWidth: Int,
        windowHeight: Int,
        currentDisplay: GuestDisplaySize?,
        macScreenWidth: Int,
        macScreenHeight: Int,
        pixelsPerPoint: Int = 1
    ) -> GuestDisplaySize? {
        // Window sizes are logical and the Mac screen is in points; the display is in pixels.
        let scale = max(pixelsPerPoint, 1)
        let neededWidth = windowWidth * scale
        let neededHeight = (windowHeight + taskbarAllowance) * scale
        let macScreenWidth = macScreenWidth * scale
        let macScreenHeight = macScreenHeight * scale
        if let currentDisplay,
           currentDisplay.width >= neededWidth,
           currentDisplay.height >= neededHeight {
            return nil
        }

        var width = max(macScreenWidth, neededWidth, currentDisplay?.width ?? 0)
        var height = max(macScreenHeight, neededHeight, currentDisplay?.height ?? 0)
        width = min(max(width, DisplayResizeRequest.minimumDimension), DisplayResizeRequest.maximumDimension)
        height = min(max(height, DisplayResizeRequest.minimumDimension), DisplayResizeRequest.maximumDimension)
        guard DisplayResizeRequest.isPlausible(width: width, height: height) else {
            return nil
        }

        let target = GuestDisplaySize(width: width, height: height)
        return target == currentDisplay ? nil : target
    }
}
