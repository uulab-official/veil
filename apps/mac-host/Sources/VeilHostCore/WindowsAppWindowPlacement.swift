import Foundation

public struct HostVisibleFrameGeometry: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum WindowsAppWindowPlacement {
    public static func initialFrame(
        for bounds: WindowBounds,
        visibleFrame: HostVisibleFrameGeometry,
        existingWindowCount: Int = 0
    ) -> HostVisibleFrameGeometry {
        let sourceWidth = max(Double(bounds.width), 1)
        let sourceHeight = max(Double(bounds.height), 1)
        let maximumWidth = max(320, visibleFrame.width * 0.92)
        let maximumHeight = max(240, visibleFrame.height * 0.88)

        // The Mac window starts at the Windows window's own size. The window's picture is drawn unscaled,
        // so a Mac window made larger than a small Windows window, as an earlier version did up to
        // 720 x 480, showed the app in one corner of an empty frame. Character Map is 477 x 430.
        var targetWidth = sourceWidth
        var targetHeight = sourceHeight

        if targetWidth > maximumWidth || targetHeight > maximumHeight {
            let scale = min(maximumWidth / targetWidth, maximumHeight / targetHeight)
            targetWidth *= scale
            targetHeight *= scale
        }

        let cascadeOffset = Double(existingWindowCount % 6) * 28
        let centeredX = visibleFrame.x + (visibleFrame.width - targetWidth) / 2 + cascadeOffset
        let centeredY = visibleFrame.y + (visibleFrame.height - targetHeight) / 2 - cascadeOffset
        let x = clamp(centeredX, lower: visibleFrame.x, upper: visibleFrame.x + visibleFrame.width - targetWidth)
        let y = clamp(centeredY, lower: visibleFrame.y, upper: visibleFrame.y + visibleFrame.height - targetHeight)

        return HostVisibleFrameGeometry(
            x: x,
            y: y,
            width: targetWidth,
            height: targetHeight
        )
    }

    /// The aspect ratio a mirrored window should be locked to while the user resizes it.
    ///
    /// The host keeps the mirror aspect-correct while a user resize is in progress, then sends the final
    /// content size through `window.resize.request`. The guest resizes the real HWND and emits updated
    /// bounds, which causes the next capture surface to match the host window instead of leaving black bars.
    /// See `docs/checklists/2026-08-14-mirrored-window-resize.md`.
    ///
    /// - Returns: `nil` when the guest reported a degenerate size, in which case the window should stay
    ///   freely resizable rather than being locked to a ratio derived from nothing.
    public static func contentAspectRatio(for bounds: WindowBounds) -> HostVisibleFrameGeometry? {
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        return HostVisibleFrameGeometry(
            x: 0,
            y: 0,
            width: Double(bounds.width),
            height: Double(bounds.height)
        )
    }

    /// The smallest content size a mirrored window should allow, with the guest's aspect ratio preserved.
    ///
    /// A fixed minimum size fights an aspect-ratio lock: AppKit would have to violate one of them for a
    /// window whose guest ratio does not match the minimum's. Deriving the minimum from the same ratio
    /// removes the conflict.
    ///
    /// - Parameter shortestSide: The floor for the smaller dimension. The larger dimension follows from the
    ///   ratio, so a tall guest window gets a tall minimum rather than a wide one.
    public static func minimumContentSize(
        for bounds: WindowBounds,
        shortestSide: Double = 320
    ) -> HostVisibleFrameGeometry {
        let sourceWidth = max(Double(bounds.width), 1)
        let sourceHeight = max(Double(bounds.height), 1)

        // Never larger than the guest window itself: a small utility window must not be given a minimum it
        // cannot satisfy.
        let scale = min(1, max(shortestSide / sourceWidth, shortestSide / sourceHeight))

        return HostVisibleFrameGeometry(
            x: 0,
            y: 0,
            width: sourceWidth * scale,
            height: sourceHeight * scale
        )
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), max(lower, upper))
    }
}
