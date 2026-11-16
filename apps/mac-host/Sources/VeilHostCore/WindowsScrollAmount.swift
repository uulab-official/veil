import Foundation

/// Converts Mac scroll deltas into Windows wheel units.
///
/// Windows counts a positive vertical wheel amount as scrolling up and a positive horizontal one as scrolling
/// right. A Mac `scrollingDeltaY` that is positive also reveals content above, but a positive
/// `scrollingDeltaX` reveals content to the left, so the horizontal sign flips. Whole units are sent and the
/// fraction is kept for the next event, so slow trackpad movement adds up instead of being dropped.
public enum WindowsScrollAmount {
    public static func accumulate(
        remainder: (x: Double, y: Double),
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        unitsPerDelta: Double
    ) -> (deltaX: Int, deltaY: Int, remainder: (x: Double, y: Double)) {
        let totalX = remainder.x - scrollingDeltaX * unitsPerDelta
        let totalY = remainder.y + scrollingDeltaY * unitsPerDelta
        let deltaX = Int(totalX.rounded(.towardZero))
        let deltaY = Int(totalY.rounded(.towardZero))
        return (deltaX, deltaY, (totalX - Double(deltaX), totalY - Double(deltaY)))
    }
}
