import CoreGraphics
import Foundation
import Testing

@testable import VeilHostCore

@Suite("Coherence display scale")
struct CoherenceDisplayScaleTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("runs Windows at 200% on twice the screen's points on a Retina Mac")
    func doublesOnRetina() throws {
        let target = try #require(CoherenceDisplayScale.target(
            screenFrame: laptop, backingScale: 2, retinaEnabled: true, agentCanScale: true, scaleRefused: false))

        #expect(target.pixelsPerPoint == 2)
        #expect(target.display == GuestDisplaySize(width: 3024, height: 1964))
        #expect(target.scalePercent == 200)
    }

    @Test("stays at one pixel per point and the user's scale otherwise", arguments: [
        (1.0, true, true, false),
        (2.0, false, true, false),
        (2.0, true, false, false),
        (2.0, true, true, true)
    ])
    func staysAtOnePixelPerPoint(backing: Double, retina: Bool, agentCanScale: Bool, refused: Bool) throws {
        let target = try #require(CoherenceDisplayScale.target(
            screenFrame: laptop, backingScale: backing, retinaEnabled: retina, agentCanScale: agentCanScale, scaleRefused: refused))

        #expect(target.pixelsPerPoint == 1)
        #expect(target.display == GuestDisplaySize(width: 1512, height: 982))
        #expect(target.scalePercent == nil)
    }

    @Test("falls back to one pixel per point when twice the screen is too big for a guest display")
    func fallsBackOnFiveK() throws {
        let fiveK = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let target = try #require(CoherenceDisplayScale.target(
            screenFrame: fiveK, backingScale: 2, retinaEnabled: true, agentCanScale: true, scaleRefused: false))

        #expect(target.pixelsPerPoint == 1)
        #expect(target.display == GuestDisplaySize(width: 2560, height: 1440))
    }

    @Test("treats an unknown or fractional backing scale as whole pixels")
    func wholePixels() {
        #expect(CoherenceDisplayScale.retinaPixelsPerPoint(backingScale: nil) == 1)
        #expect(CoherenceDisplayScale.retinaPixelsPerPoint(backingScale: .nan) == 1)
        #expect(CoherenceDisplayScale.retinaPixelsPerPoint(backingScale: 2) == 2)
        #expect(CoherenceDisplayScale.retinaPixelsPerPoint(backingScale: 3) == 2)
    }

    @Test("grows the display before raising the scale and lowers the scale before shrinking it")
    func ordersResizeAndScale() {
        #expect(CoherenceDisplayScale.resizesDisplayFirst(fromScalePercent: nil, toScalePercent: 200))
        #expect(CoherenceDisplayScale.resizesDisplayFirst(fromScalePercent: 100, toScalePercent: 200))
        #expect(!CoherenceDisplayScale.resizesDisplayFirst(fromScalePercent: 200, toScalePercent: nil))
        #expect(!CoherenceDisplayScale.resizesDisplayFirst(fromScalePercent: 200, toScalePercent: 125))
    }

    @Test("places windows in display pixels, so a 2x display doubles the guest origin")
    func placementDoubles() throws {
        let display = GuestPixelRect(x: 0, y: 0, width: 3024, height: 1964)
        let content = CGRect(x: 120, y: 982 - 100 - 600, width: 800, height: 600)

        let origin = try #require(CoherencePlacement.guestOrigin(contentFrame: content, screenFrame: laptop, display: display))

        #expect(origin.x == 240 && origin.y == 200)
    }

    @Test("compares a logical window with the display in pixels at 2x")
    func displayFitAtTwoX() {
        // A 1400x900 logical window needs 2800x1896 pixels with the taskbar allowance.
        #expect(MirroredWindowDisplayFit.displaySize(
            windowWidth: 1400,
            windowHeight: 900,
            currentDisplay: GuestDisplaySize(width: 3024, height: 1964),
            macScreenWidth: 1512,
            macScreenHeight: 982,
            pixelsPerPoint: 2
        ) == nil)
        // Without the scale the same display would be compared with logical units and asked to shrink.
        #expect(MirroredWindowDisplayFit.displaySize(
            windowWidth: 1400,
            windowHeight: 900,
            currentDisplay: nil,
            macScreenWidth: 1512,
            macScreenHeight: 982,
            pixelsPerPoint: 2
        ) == GuestDisplaySize(width: 3024, height: 1964))
    }

    @Test("decodes the display scale fixtures")
    func decodesFixtures() throws {
        let request = try decode(DisplayScaleRequest.self, "display.scale.request")
        let restore = try decode(DisplayScaleRequest.self, "display.scale.request.restore")
        let response = try decode(DisplayScaleResponse.self, "display.scale.response")

        #expect(request.type == .displayScaleRequest && request.scalePercent == 200 && request.restoresUserScale == nil)
        #expect(restore.scalePercent == nil && restore.restoresUserScale == true)
        #expect(response.type == .displayScaleResponse && response.accepted && response.scalePercent == 200)
        #expect(DisplayScaleRequest(requestId: "a", scalePercent: nil) == DisplayScaleRequest(
            requestId: "a", scalePercent: nil))
        #expect(DisplayScaleRequest(requestId: "a", scalePercent: nil).restoresUserScale == true)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder.veilProtocol.decode(T.self, from: Data(contentsOf: url))
    }
}
