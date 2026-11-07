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
