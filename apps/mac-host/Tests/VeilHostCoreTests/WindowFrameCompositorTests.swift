import CoreGraphics
import Foundation
import Testing

@testable import VeilHostCore

@Suite("Window frame compositor")
struct WindowFrameCompositorTests {
    /// Stand-in for a decoded tile image. Only its dimensions matter to the compositor's contract, so a
    /// synthetic image keeps these tests free of PNG fixtures.
    private static func image(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Encodes the tile's declared rectangle into its payload so the fake decoder can produce a matching
    /// image without a real PNG.
    private static func payload(width: Int, height: Int) -> Data {
        Data("\(width)x\(height)".utf8)
    }

    private static func makeCompositor(undecodable: Bool = false) -> WindowFrameCompositor {
        WindowFrameCompositor { data in
            guard !undecodable else {
                return nil
            }

            let parts = String(decoding: data, as: UTF8.self).split(separator: "x")
            guard parts.count == 2,
                  let width = Int(parts[0]),
                  let height = Int(parts[1]) else {
                return nil
            }

            return image(width: width, height: height)
        }
    }

    private static func tile(
        windowId: String = "hwnd:0003029A",
        sequence: Int = 1,
        surfaceWidth: Int = 200,
        surfaceHeight: Int = 100,
        isKeyFrame: Bool = false,
        rect: WindowFrameTileRect = WindowFrameTileRect(x: 10, y: 20, width: 30, height: 40),
        payloadSize: (width: Int, height: Int)? = nil
    ) -> WindowFrameTile {
        let size = payloadSize ?? (rect.width, rect.height)
        return WindowFrameTile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            scale: 1,
            isKeyFrame: isKeyFrame,
            rect: rect,
            payload: payload(width: size.width, height: size.height)
        )
    }

    private static func keyFrame(
        windowId: String = "hwnd:0003029A",
        sequence: Int = 1,
        surfaceWidth: Int = 200,
        surfaceHeight: Int = 100
    ) -> WindowFrameTile {
        tile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: surfaceWidth, height: surfaceHeight)
        )
    }

    @Test("establishes a surface from a key frame and composites subsequent tiles onto it")
    func compositesTilesOntoKeyFrameSurface() {
        let compositor = Self.makeCompositor()

        #expect(compositor.apply(Self.keyFrame()) == .composited(generation: 1))
        #expect(compositor.apply(Self.tile(sequence: 2)) == .composited(generation: 2))
        #expect(compositor.apply(Self.tile(sequence: 3)) == .composited(generation: 3))

        let image = compositor.image(for: "hwnd:0003029A")
        #expect(image?.width == 200)
        #expect(image?.height == 100)
        #expect(compositor.generation(for: "hwnd:0003029A") == 3)
    }

    @Test("refuses a tile that arrives before any key frame")
    func refusesTileBeforeKeyFrame() {
        let compositor = Self.makeCompositor()

        // Drawing onto no surface would either crash or invent content. Waiting visibly is the honest
        // behavior.
        #expect(compositor.apply(Self.tile()) == .needsKeyFrame(reason: .noSurface))
        #expect(compositor.image(for: "hwnd:0003029A") == nil)
        #expect(!compositor.hasSurface(for: "hwnd:0003029A"))
    }

    @Test("drops the surface when the declared size changes without a key frame")
    func dropsSurfaceOnUnkeyedResize() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame()) == .composited(generation: 1))

        // A resize invalidates every retained pixel, so compositing onto the old buffer would produce a
        // plausible-looking but wrong window.
        let resized = Self.tile(sequence: 2, surfaceWidth: 400, surfaceHeight: 200)
        #expect(compositor.apply(resized) == .needsKeyFrame(reason: .surfaceSizeChanged))
        #expect(!compositor.hasSurface(for: "hwnd:0003029A"))

        #expect(compositor.apply(Self.keyFrame(sequence: 3, surfaceWidth: 400, surfaceHeight: 200)).isComposited)
        #expect(compositor.image(for: "hwnd:0003029A")?.width == 400)
    }

    @Test("accepts a key frame that resizes the surface")
    func acceptsKeyFrameResize() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame()).isComposited)
        #expect(compositor.apply(Self.keyFrame(sequence: 2, surfaceWidth: 640, surfaceHeight: 480)).isComposited)

        let image = compositor.image(for: "hwnd:0003029A")
        #expect(image?.width == 640)
        #expect(image?.height == 480)
    }

    @Test("refuses a payload whose real size disagrees with the declared rectangle")
    func refusesPayloadRectMismatch() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame()).isComposited)

        // Scaling to fit would silently distort the window, so the disagreement has to surface.
        let mismatched = Self.tile(
            sequence: 2,
            rect: WindowFrameTileRect(x: 0, y: 0, width: 30, height: 40),
            payloadSize: (width: 31, height: 40)
        )
        #expect(compositor.apply(mismatched) == .needsKeyFrame(reason: .payloadRectMismatch))
    }

    @Test("refuses an undecodable payload")
    func refusesUndecodablePayload() {
        let compositor = Self.makeCompositor(undecodable: true)

        #expect(compositor.apply(Self.keyFrame()) == .needsKeyFrame(reason: .undecodablePayload))
    }

    @Test("keeps surfaces separate per window")
    func keepsSurfacesSeparatePerWindow() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame(windowId: "hwnd:A")).isComposited)
        #expect(compositor.apply(Self.keyFrame(windowId: "hwnd:B", surfaceWidth: 320, surfaceHeight: 240)).isComposited)

        #expect(compositor.image(for: "hwnd:A")?.width == 200)
        #expect(compositor.image(for: "hwnd:B")?.width == 320)
        #expect(compositor.apply(Self.tile(windowId: "hwnd:C")) == .needsKeyFrame(reason: .noSurface))
    }

    @Test("releases a surface when a window is forgotten")
    func releasesSurfaceOnForget() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame()).isComposited)

        // Each surface is a full-resolution bitmap; a closed window that kept one would hold megabytes for
        // the process's lifetime.
        compositor.forget(windowId: "hwnd:0003029A")

        #expect(compositor.image(for: "hwnd:0003029A") == nil)
        #expect(compositor.generation(for: "hwnd:0003029A") == 0)
        #expect(compositor.apply(Self.tile()) == .needsKeyFrame(reason: .noSurface))
    }

    @Test("forgetting every window releases all surfaces")
    func forgettingEveryWindowReleasesAllSurfaces() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame(windowId: "hwnd:A")).isComposited)
        #expect(compositor.apply(Self.keyFrame(windowId: "hwnd:B")).isComposited)

        compositor.forgetAll()

        #expect(!compositor.hasSurface(for: "hwnd:A"))
        #expect(!compositor.hasSurface(for: "hwnd:B"))
    }

    @Test("composites a tile at every corner of the surface")
    func compositesTilesAtEveryCorner() {
        let compositor = Self.makeCompositor()
        #expect(compositor.apply(Self.keyFrame()).isComposited)

        // The guest uses a top-left origin and CoreGraphics uses bottom-left. A flip error would only show
        // up at the edges, so every corner is exercised.
        for rect in [
            WindowFrameTileRect(x: 0, y: 0, width: 10, height: 10),
            WindowFrameTileRect(x: 190, y: 0, width: 10, height: 10),
            WindowFrameTileRect(x: 0, y: 90, width: 10, height: 10),
            WindowFrameTileRect(x: 190, y: 90, width: 10, height: 10)
        ] {
            #expect(compositor.apply(Self.tile(rect: rect)).isComposited, "\(rect)")
        }
    }

    @Test("a JSON frame can be treated as a key-frame tile")
    func jsonFrameBecomesKeyFrameTile() throws {
        let frame = WindowFrameEvent(
            type: .windowFrame,
            windowId: "hwnd:0003029A",
            frameId: "frame_000001",
            sequence: 1,
            format: "png",
            width: 64,
            height: 32,
            scale: 1,
            encodedData: Data("64x32".utf8).base64EncodedString()
        )

        let tile = try #require(frame.asKeyFrameTile())
        #expect(tile.isKeyFrame)
        #expect(tile.rect.covers(surfaceWidth: 64, surfaceHeight: 32))
        #expect(Self.makeCompositor().apply(tile).isComposited)
    }

    @Test("a composited metadata frame does not pretend to carry pixels")
    func compositedMetadataFrameCarriesNoPixels() {
        let event = Self.keyFrame().surfaceMetadataFrameEvent()

        // Renderers must read the compositor for these. Copying a full-surface PNG into every session
        // update is the cost this whole slice exists to remove.
        #expect(event.isCompositedSurface)
        #expect(event.encodedData.isEmpty)
        #expect(event.width == 200)
        #expect(event.height == 100)
        #expect(event.frameId == "frame_000001")
        #expect(event.asKeyFrameTile() == nil)
    }
}

private extension WindowFrameCompositor.ApplyResult {
    var isComposited: Bool {
        if case .composited = self {
            return true
        }
        return false
    }
}
