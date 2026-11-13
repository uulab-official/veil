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
        #expect(view.imageFrame == CGRect(x: 0, y: 0, width: 20, height: 10))
        #expect(view.borderFill == nil)
        #expect(view.layer?.backgroundColor == backdrop)
        // Input goes to the capture view layered above.
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }

    /// A window frame copied from the guest screen: the app's own colour inside a one-pixel ring of whatever
    /// was behind the window, here red.
    private func windowFrame(width: Int, height: Int, border: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1))
        context.fill(CGRect(x: border, y: border, width: width - 2 * border, height: height - 2 * border))
        return try #require(context.makeImage())
    }

    /// Draws the view's layers into a bitmap of the view's size, as the window server would.
    private func rendered(_ view: FrameLayerHostView, width: Int, height: Int) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        try #require(view.layer).render(in: context)
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return Array(UnsafeBufferPointer(start: bytes, count: width * height * 4))
    }

    @Test("keeps what was behind a Windows window out of its Mac window's edge")
    func dropsTheWindowsBorder() throws {
        let image = try windowFrame(width: 40, height: 20, border: 1)
        let view = FrameLayerHostView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))

        view.show(image, pointsPerPixel: 1, backdrop: CGColor(gray: 0, alpha: 1), dropsWindowBorder: true)

        // The inside is still drawn pixel for pixel, where it was.
        #expect(view.imageFrame == CGRect(x: 1, y: 1, width: 38, height: 18))
        #expect(view.imageContentsRect == CGRect(x: 1.0 / 40, y: 1.0 / 20, width: 38.0 / 40, height: 18.0 / 20))
        #expect(view.borderFill?.frame == CGRect(x: 0, y: 0, width: 40, height: 20))

        let pixels = try rendered(view, width: 40, height: 20)
        let reddest = stride(from: 0, to: pixels.count, by: 4)
            .map { Int(pixels[$0]) - Int(pixels[$0 + 1]) }
            .max() ?? 0
        // Every pixel, the edge included, is the app's grey; none of the red behind it is left.
        #expect(reddest < 8)
    }

    @Test("draws the whole frame when the border is kept, as for a popup")
    func keepsTheBorderWhenAsked() throws {
        let image = try windowFrame(width: 40, height: 20, border: 1)
        let view = FrameLayerHostView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))

        view.show(image, pointsPerPixel: 1, backdrop: CGColor(gray: 0, alpha: 1), dropsWindowBorder: true)
        view.show(image, pointsPerPixel: 1, backdrop: CGColor(gray: 0, alpha: 1))

        #expect(view.imageFrame == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(view.imageContentsRect == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(view.borderFill == nil)
        let pixels = try rendered(view, width: 40, height: 20)
        #expect(pixels[0] > 200 && pixels[1] < 50)
    }

    @Test("drops two guest pixels a side at two pixels per point")
    func dropsTheBorderAtRetinaScale() throws {
        let image = try windowFrame(width: 40, height: 20, border: 2)
        let view = FrameLayerHostView(frame: NSRect(x: 0, y: 0, width: 20, height: 10))

        view.show(image, pointsPerPixel: 0.5, backdrop: CGColor(gray: 0, alpha: 1), dropsWindowBorder: true)

        #expect(view.imageFrame == CGRect(x: 1, y: 1, width: 18, height: 8))
        #expect(view.borderFill?.frame == CGRect(x: 0, y: 0, width: 20, height: 10))
    }
}
