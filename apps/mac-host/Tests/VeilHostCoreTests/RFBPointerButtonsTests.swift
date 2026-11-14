import CoreGraphics
import Testing
@testable import VeilHostCore

struct RFBPointerButtonsTests {
    @Test func mapsAppKitButtonsToRFBBits() {
        #expect(RFBPointerButtons.bit(forButtonNumber: 0) == 1)
        #expect(RFBPointerButtons.bit(forButtonNumber: 1) == 4)
        #expect(RFBPointerButtons.bit(forButtonNumber: 2) == 2)
        #expect(RFBPointerButtons.bit(forButtonNumber: 3) == nil)
    }

    @Test func sendsOneWheelButtonPerNotch() {
        #expect(RFBPointerButtons.wheelNotches(deltaX: 0, deltaY: 2) == [8, 8])
        #expect(RFBPointerButtons.wheelNotches(deltaX: -1, deltaY: -1) == [16, 32])
        #expect(RFBPointerButtons.wheelNotches(deltaX: 0, deltaY: 0).isEmpty)
    }

    @Test func clampsADragOutsideThePictureToTheNearestEdge() {
        let viewport = CGRect(x: 10, y: 0, width: 100, height: 50)

        let inside = RFBPointerButtons.framebufferPixel(
            pointInContainer: CGPoint(x: 10, y: 50), viewport: viewport, framebufferWidth: 201, framebufferHeight: 101
        )
        #expect(inside?.x == 0)
        #expect(inside?.y == 0)

        let outside = RFBPointerButtons.framebufferPixel(
            pointInContainer: CGPoint(x: 500, y: -20), viewport: viewport, framebufferWidth: 201, framebufferHeight: 101
        )
        #expect(outside?.x == 200)
        #expect(outside?.y == 100)
    }
}
