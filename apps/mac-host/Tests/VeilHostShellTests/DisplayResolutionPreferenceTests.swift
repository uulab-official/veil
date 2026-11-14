import Foundation
import Testing

@testable import VeilHostShell

@Suite("Display resolution preference")
struct DisplayResolutionPreferenceTests {
    @Test("scaled resolution gives Windows one pixel per Mac point, even on Retina")
    func scaledIsOnePixelPerPoint() {
        #expect(DisplayResolutionPreference.guestPixelsPerPoint(screenScale: 2, retinaResolution: false) == 1)
        #expect(DisplayResolutionPreference.guestPixelsPerPoint(screenScale: 1, retinaResolution: false) == 1)
    }

    @Test("Retina resolution uses the screen's pixels and survives a missing screen")
    func retinaUsesScreenScale() {
        #expect(DisplayResolutionPreference.guestPixelsPerPoint(screenScale: 2, retinaResolution: true) == 2)
        #expect(DisplayResolutionPreference.guestPixelsPerPoint(screenScale: nil, retinaResolution: true) == 1)
    }
}

@Suite("Display resolution default")
struct DisplayResolutionDefaultTests {
    private func defaults() -> UserDefaults {
        let name = "veil-display-resolution-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("defaults to Retina only when the agent can set Windows' scale")
    func defaultFollowsAgent() {
        let store = defaults()
        #expect(DisplayResolutionPreference.isRetinaResolutionEnabled(store, guestCanSetScale: true))
        #expect(!DisplayResolutionPreference.isRetinaResolutionEnabled(store, guestCanSetScale: false))
    }

    @Test("a resolution the user picked wins over the default")
    func userChoiceWins() {
        let store = defaults()
        store.set(false, forKey: DisplayResolutionPreference.retinaResolutionKey)
        #expect(!DisplayResolutionPreference.isRetinaResolutionEnabled(store, guestCanSetScale: true))
        store.set(true, forKey: DisplayResolutionPreference.retinaResolutionKey)
        #expect(DisplayResolutionPreference.isRetinaResolutionEnabled(store, guestCanSetScale: false))
    }

    @Test("pairs full pixels with 200% and one pixel per point with the user's scale")
    func scaleForPixels() {
        #expect(DisplayResolutionPreference.windowsScalePercent(guestPixelsPerPoint: 2) == 200)
        #expect(DisplayResolutionPreference.windowsScalePercent(guestPixelsPerPoint: 1) == nil)
    }
}
