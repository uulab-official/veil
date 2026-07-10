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
        let isCompactUtilityWindow = sourceWidth <= 640
            && sourceHeight >= 640
            && sourceHeight >= sourceWidth * 1.1
        // Preserve a readable native-like scale for normal Windows apps instead of enlarging a
        // small guest HWND until its text looks like a full-screen VM console.
        let preferredMinimumWidth = isCompactUtilityWindow ? 520.0 : 720.0
        let preferredMinimumHeight = isCompactUtilityWindow ? 360.0 : 480.0
        let minimumWidth = min(preferredMinimumWidth, maximumWidth)
        let minimumHeight = min(preferredMinimumHeight, maximumHeight)

        var targetWidth = sourceWidth
        var targetHeight = sourceHeight

        if targetWidth < minimumWidth || targetHeight < minimumHeight {
            let scale = max(minimumWidth / targetWidth, minimumHeight / targetHeight)
            targetWidth *= scale
            targetHeight *= scale
        }

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

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), max(lower, upper))
    }
}
