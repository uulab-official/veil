import CoreGraphics
import Foundation
import Testing

@testable import VeilHostCore

/// The host reads everything about a mirrored window from the guest, and the guest runs Windows — which the
/// user may have infected. These tests cover the cases where a guest-supplied number reached an allocation, a
/// conversion that traps, or an encoder that refuses.
///
/// None of them need malformed data. Every input below is a well-formed message that passes every other check.
@Suite("Guest value hardening")
struct GuestInputHardeningTests {
    // MARK: Surface area

    @Test("refuses a surface that is small on each axis and enormous in total")
    func refusesEnormousSurfaceArea() {
        // 32768 on each axis passes the per-axis ceiling and asks for a 4 GiB bitmap. A 1-bit PNG of those
        // dimensions deflates to roughly 130 KB, so this fits in a single WebSocket message — bounding each
        // side independently did not bound the allocation at all.
        let tile = WindowFrameTile(
            windowId: "hwnd:0003029A",
            sequence: 1,
            surfaceWidth: 32_768,
            surfaceHeight: 32_768,
            scale: 1,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: 32_768, height: 32_768),
            payload: Data([0x01])
        )

        #expect(throws: VeilFrameChannelCodec.CodecError.implausibleSurface(width: 32_768, height: 32_768)) {
            _ = try VeilFrameChannelCodec.encode(tile)
        }
    }

    @Test("accepts a surface larger than 8K but inside the area ceiling")
    func acceptsLargeButPlausibleSurface() throws {
        // 8K is 7680x4320, about 33 million pixels. The ceiling allows half again as much, so no window on any
        // display Apple ships is refused.
        let tile = WindowFrameTile(
            windowId: "hwnd:0003029A",
            sequence: 1,
            surfaceWidth: 7_680,
            surfaceHeight: 4_320,
            scale: 2,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: 7_680, height: 4_320),
            payload: Data([0x01, 0x02])
        )

        let encoded = try VeilFrameChannelCodec.encode(tile)
        let decoded = try VeilFrameChannelCodec.decode(encoded)

        #expect(decoded.surfaceWidth == 7_680)
        #expect(decoded.surfaceHeight == 4_320)
    }

    @Test("bounds the area below the square of the per-axis ceiling")
    func areaCeilingIsBelowAxisCeilingSquared() {
        // If the area ceiling were not strictly smaller, it would be decorative.
        let axisSquared = VeilFrameChannelCodec.maximumSurfaceDimension
            * VeilFrameChannelCodec.maximumSurfaceDimension

        #expect(VeilFrameChannelCodec.maximumSurfacePixelCount < axisSquared)
        // Still above 8K, so the bound is a safety limit rather than a functional one.
        #expect(VeilFrameChannelCodec.maximumSurfacePixelCount > 7_680 * 4_320)
    }

    // MARK: Compositor surface count

    @Test("bounds how many window surfaces are held at once")
    func boundsSurfaceCount() {
        // `veil-vmctl frame-pipeline-measure` composites straight off the guest channel with no window-id
        // gate, so a guest inventing a fresh id per message would otherwise allocate a surface for each one.
        let compositor = WindowFrameCompositor(decodeImage: { _ in Self.solidImage(width: 4, height: 4) })

        for index in 0..<(WindowFrameCompositor.maximumSurfaceCount * 3) {
            _ = compositor.apply(Self.keyFrameTile(windowId: "hwnd:invented\(index)"))
        }

        var liveSurfaces = 0
        for index in 0..<(WindowFrameCompositor.maximumSurfaceCount * 3) {
            if compositor.hasSurface(for: "hwnd:invented\(index)") {
                liveSurfaces += 1
            }
        }

        #expect(liveSurfaces <= WindowFrameCompositor.maximumSurfaceCount)
    }

    @Test("evicts the least recently composited window, keeping the newest")
    func evictsLeastRecentlyUsedSurface() {
        let compositor = WindowFrameCompositor(decodeImage: { _ in Self.solidImage(width: 4, height: 4) })

        for index in 0..<(WindowFrameCompositor.maximumSurfaceCount + 1) {
            _ = compositor.apply(Self.keyFrameTile(windowId: "hwnd:window\(index)"))
        }

        // Eviction rather than refusal, so an over-budget compositor degrades into "needs a key frame" —
        // which is exactly how a window that never had a surface already behaves.
        #expect(compositor.hasSurface(for: "hwnd:window0") == false)
        #expect(compositor.hasSurface(for: "hwnd:window\(WindowFrameCompositor.maximumSurfaceCount)"))
    }

    @Test("a tile for an evicted window asks for a key frame instead of drawing")
    func evictedWindowNeedsKeyFrame() {
        let compositor = WindowFrameCompositor(decodeImage: { _ in Self.solidImage(width: 4, height: 4) })
        _ = compositor.apply(Self.keyFrameTile(windowId: "hwnd:first"))

        for index in 0..<WindowFrameCompositor.maximumSurfaceCount {
            _ = compositor.apply(Self.keyFrameTile(windowId: "hwnd:later\(index)"))
        }

        let outcome = compositor.apply(
            Self.keyFrameTile(windowId: "hwnd:first", isKeyFrame: false)
        )

        #expect(outcome == .needsKeyFrame(reason: .noSurface))
    }

    @Test("forgetting a window makes room again")
    func forgettingReleasesBudget() {
        let compositor = WindowFrameCompositor(decodeImage: { _ in Self.solidImage(width: 4, height: 4) })
        for index in 0..<WindowFrameCompositor.maximumSurfaceCount {
            _ = compositor.apply(Self.keyFrameTile(windowId: "hwnd:window\(index)"))
        }

        compositor.forget(windowId: "hwnd:window0")
        _ = compositor.apply(Self.keyFrameTile(windowId: "hwnd:fresh"))

        // If `forget` had not also cleaned the ordering, the freed slot would have been unusable and eviction
        // would have started dropping live windows instead.
        #expect(compositor.hasSurface(for: "hwnd:fresh"))
        #expect(compositor.hasSurface(for: "hwnd:window1"))
    }

    // MARK: Input coordinate conversion

    @Test("refuses to map input through an implausible source size instead of trapping")
    func refusesImplausibleSourceSize() {
        // `guestPoint` multiplies a normalized position by `Double(sourceWidth)` and converts with `Int(_:)`,
        // which traps rather than saturating above `Int.max`. `sourceWidth` comes from a guest-supplied
        // `window.frame`, so a width of `Int.max` plus a click at the right edge was a hard crash.
        let viewport = WindowFrameViewport(
            viewWidth: 800,
            viewHeight: 600,
            sourceWidth: Int.max,
            sourceHeight: Int.max
        )

        #expect(viewport.hasPlausibleSourceSize == false)
        #expect(viewport.guestPoint(forViewX: 800, viewYFromBottom: 600) == nil)
    }

    @Test("still maps input for an ordinary window")
    func mapsOrdinarySourceSize() throws {
        let viewport = WindowFrameViewport(
            viewWidth: 800,
            viewHeight: 600,
            sourceWidth: 800,
            sourceHeight: 600
        )

        #expect(viewport.hasPlausibleSourceSize)
        let point = try #require(viewport.guestPoint(forViewX: 400, viewYFromBottom: 300))
        #expect(point.x == 400)
        #expect(point.y == 300)
    }

    @Test("shares the frame channel's ceilings so the two paths cannot disagree")
    func sourceSizeSharesCodecCeilings() {
        let atCeiling = WindowFrameViewport(
            viewWidth: 800,
            viewHeight: 600,
            sourceWidth: VeilFrameChannelCodec.maximumSurfaceDimension,
            sourceHeight: 1
        )
        let overCeiling = WindowFrameViewport(
            viewWidth: 800,
            viewHeight: 600,
            sourceWidth: VeilFrameChannelCodec.maximumSurfaceDimension + 1,
            sourceHeight: 1
        )

        #expect(atCeiling.hasPlausibleSourceSize)
        #expect(overCeiling.hasPlausibleSourceSize == false)
    }

    // MARK: Frame size plausibility

    @Test("rejects a frame size the binary channel would have refused")
    func rejectsImplausibleFrameSize() {
        // A `window.frame` declaring 30000x30000 is a ~110 KB message and a multi-gigabyte NSImage decode on
        // the main thread. The JSON path had no bound anywhere.
        #expect(HostDashboardModel.isPlausibleFrameSize(width: 30_000, height: 30_000) == false)
        #expect(HostDashboardModel.isPlausibleFrameSize(width: 32_769, height: 1) == false)
        #expect(HostDashboardModel.isPlausibleFrameSize(width: 0, height: 100) == false)
        #expect(HostDashboardModel.isPlausibleFrameSize(width: -1, height: 100) == false)
    }

    @Test("accepts the sizes real windows report")
    func acceptsRealFrameSizes() {
        #expect(HostDashboardModel.isPlausibleFrameSize(width: 1, height: 1))
        #expect(HostDashboardModel.isPlausibleFrameSize(width: 1_440, height: 900))
        #expect(HostDashboardModel.isPlausibleFrameSize(width: 7_680, height: 4_320))
    }

    // MARK: Display scale plausibility

    @Test("rejects a denormal scale that would make the ratio infinite")
    func rejectsDenormalScale() {
        // 1e-320 is valid JSON, decodes fine, and passes a bare `> 0` check. Dividing by it yields infinity,
        // which `JSONEncoder` refuses to encode — so one malformed frame took the whole status report down.
        #expect(HostDashboardModel.isPlausibleDisplayScale(1e-320) == false)
        #expect(HostDashboardModel.isPlausibleDisplayScale(0) == false)
        #expect(HostDashboardModel.isPlausibleDisplayScale(-2) == false)
        #expect(HostDashboardModel.isPlausibleDisplayScale(.infinity) == false)
        #expect(HostDashboardModel.isPlausibleDisplayScale(.nan) == false)
        #expect(HostDashboardModel.isPlausibleDisplayScale(1e308) == false)
    }

    @Test("accepts every scale Windows can actually be set to")
    func acceptsRealDisplayScales() {
        // Windows offers 100% through 500%.
        for scale in [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0] {
            #expect(HostDashboardModel.isPlausibleDisplayScale(scale))
        }
    }

    // MARK: Helpers

    private static func keyFrameTile(windowId: String, isKeyFrame: Bool = true) -> WindowFrameTile {
        WindowFrameTile(
            windowId: windowId,
            sequence: 1,
            surfaceWidth: 4,
            surfaceHeight: 4,
            scale: 1,
            isKeyFrame: isKeyFrame,
            rect: WindowFrameTileRect(x: 0, y: 0, width: 4, height: 4),
            payload: Data([0x01])
        )
    }

    private static func solidImage(width: Int, height: Int) -> CGImage? {
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
        return context.makeImage()
    }
}
