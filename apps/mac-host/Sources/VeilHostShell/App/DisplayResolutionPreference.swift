import CoreGraphics
import Foundation
import VeilHostCore

/// How many Windows pixels Veil asks for per Mac point when Windows follows a Veil window or the Mac screen.
///
/// "Retina resolution", like Parallels' "Best for Retina", gives Windows the screen's full pixels and sets
/// Windows' display scale to match (200% on a Retina Mac), so text keeps its size and is drawn at the
/// display's own pixels. "Scaled" gives Windows one pixel per point and the user's own scale, which macOS
/// then doubles on a Retina display, so text is soft.
///
/// Retina is the default only while the Windows agent can set the display scale (`displayScale`): full
/// pixels at 100% made text and controls half size. A resolution the user picked always wins. The frame
/// rate cost, measured in docs/checklists/2026-11-11-retina-guest-scale.md, was about 5%.
enum DisplayResolutionPreference {
    static let retinaResolutionKey = "VeilDisplayRetinaResolution"

    /// Whether the connected agent can set Windows' display scale. Updated from agent health.
    nonisolated(unsafe) static var guestCanSetScale = false

    static func isRetinaResolutionEnabled(
        _ defaults: UserDefaults = .standard,
        guestCanSetScale: Bool = guestCanSetScale
    ) -> Bool {
        defaults.object(forKey: retinaResolutionKey) as? Bool ?? guestCanSetScale
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

    /// The Windows display scale that goes with a guest pixels-per-point, or nil for the user's own.
    static func windowsScalePercent(guestPixelsPerPoint: Double) -> Int? {
        let whole = CoherenceDisplayScale.retinaPixelsPerPoint(backingScale: guestPixelsPerPoint)
        return whole > 1 ? whole * 100 : nil
    }
}
