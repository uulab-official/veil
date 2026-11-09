import AppKit
import CoreGraphics
import Testing

@testable import VeilHostShell

@Suite("Frame layer view")
@MainActor
struct FrameLayerViewTests {
    @Test("puts the frame in the layer unscaled from the top-left with the backdrop behind it")
    func showsFrameInLayer() throws {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let view = FrameLayerHostView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        let backdrop = CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)

        view.show(image, pointsPerPixel: 0.5, backdrop: backdrop)

        #expect(view.displayedImage === image)
        #expect(view.layer?.sublayers?.first?.frame == CGRect(x: 0, y: 0, width: 20, height: 10))
        #expect(view.layer?.backgroundColor == backdrop)
        // Input goes to the capture view layered above.
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }
}
