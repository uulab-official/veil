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
    /// Used until the user picks a resolution. See docs/checklists/2026-11-11-retina-guest-scale.md for the
    /// frame rate measured both ways.
    static let retinaResolutionDefault = false

    static func isRetinaResolutionEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: retinaResolutionKey) as? Bool ?? retinaResolutionDefault
    }

    static func guestPixelsPerPoint(
        screenScale: CGFloat?,
        retinaResolution: Bool = isRetinaResolutionEnabled()
    ) -> Double {
        guard retinaResolution, let screenScale, screenScale > 0 else {
            return 1
        }
        return Double(screenScale)
    }
}
