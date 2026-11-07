import CoreGraphics
import Foundation

/// How many Windows pixels Veil asks for per Mac point when Windows follows a Veil window.
///
/// The default matches Parallels' "Scaled" resolution: one pixel per point, so Windows keeps its 100%
/// text size. Asking for the screen's full pixels on a Retina Mac gave Windows a 2x desktop at 100%
/// scaling, where text and controls came out half size. "Retina resolution" restores full pixels for
/// users who then set Windows' display scale to 200% themselves.
enum DisplayResolutionPreference {
    static let retinaResolutionKey = "VeilDisplayRetinaResolution"

    static func guestPixelsPerPoint(
        screenScale: CGFloat?,
        retinaResolution: Bool = UserDefaults.standard.bool(forKey: retinaResolutionKey)
    ) -> Double {
        guard retinaResolution, let screenScale, screenScale > 0 else {
            return 1
        }
        return Double(screenScale)
    }
}
