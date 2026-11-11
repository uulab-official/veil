import Foundation
import Testing

@testable import VeilHostCore

@Suite("Windows trackpad gestures")
struct WindowsTrackpadGestureTests {
    @Test("a pinch outward zooms in with an upward Ctrl+wheel notch")
    func pinchOutZoomsIn() {
        let wheel = WindowsTrackpadGesture.pinchWheel(remainder: 0, magnification: 0.25)

        #expect(wheel.deltaY == 120)
        #expect(abs(wheel.remainder - 30) < 0.0001)
        #expect(WindowsTrackpadGesture.pinchModifiers == ["ctrl"])
    }

    @Test("a pinch inward zooms out")
    func pinchInZoomsOut() {
        let wheel = WindowsTrackpadGesture.pinchWheel(remainder: 0, magnification: -0.45)

        #expect(wheel.deltaY == -240)
        #expect(abs(wheel.remainder - -30) < 0.0001)
    }

    @Test("small pinch events add up to whole notches instead of zooming per event")
    func carriesPartialNotches() {
        var remainder = 0.0
        var sent: [Int] = []
        for _ in 0..<10 {
            let wheel = WindowsTrackpadGesture.pinchWheel(remainder: remainder, magnification: 0.05)
            remainder = wheel.remainder
            if wheel.deltaY != 0 {
                sent.append(wheel.deltaY)
            }
        }

        // 10 × 0.05 × 600 = 300 units: two notches, 60 left over.
        #expect(sent == [120, 120])
        #expect(abs(remainder - 60) < 0.0001)
    }

    @Test("a page swipe maps to the browser Back and Forward keys")
    func swipeMapsToNavigationKeys() {
        #expect(WindowsTrackpadGesture.navigationKey(forSwipeDeltaX: 1) == .back)
        #expect(WindowsTrackpadGesture.navigationKey(forSwipeDeltaX: -1) == .forward)
        #expect(WindowsTrackpadGesture.navigationKey(forSwipeDeltaX: 0) == nil)
        #expect(WindowsTrackpadGesture.NavigationKey.back.windowsVirtualKey == 0xA6)
        #expect(WindowsTrackpadGesture.NavigationKey.forward.windowsVirtualKey == 0xA7)
    }
}
