import Testing

@testable import VeilHostCore

@Suite("Window frame viewport")
struct WindowFrameViewportTests {
    @Test("maps clicks through an unscaled frame pinned to the top-left")
    func mapsClicksThroughTopLeftAnchoredFrame() {
        // A 1000x600 guest bitmap in a window the user has just dragged to 1200x700 points.
        let viewport = WindowFrameViewport(
            viewWidth: 1200,
            viewHeight: 700,
            sourceWidth: 1000,
            sourceHeight: 600,
            anchoredPointsPerPixel: 1
        )

        #expect(viewport.visibleFrame == WindowFrameRect(x: 0, y: 100, width: 1000, height: 600))
        // Top-left of the view is the guest's top-left pixel, and nothing is stretched.
        #expect(viewport.guestPoint(forViewX: 0, viewYFromBottom: 700) == WindowFramePoint(x: 0, y: 0))
        #expect(viewport.guestPoint(forViewX: 500, viewYFromBottom: 400) == WindowFramePoint(x: 500, y: 300))
        // The area the guest has not drawn yet takes no input.
        #expect(viewport.guestPoint(forViewX: 1100, viewYFromBottom: 400) == nil)
        #expect(viewport.guestPoint(forViewX: 500, viewYFromBottom: 50) == nil)
    }

    @Test("converts a Windows DPI scale to points per pixel")
    func convertsWindowsScaleToPointsPerPixel() {
        #expect(WindowFrameViewport.pointsPerPixel(forWindowsScale: 1) == 1)
        #expect(WindowFrameViewport.pointsPerPixel(forWindowsScale: 2) == 0.5)
        #expect(WindowFrameViewport.pointsPerPixel(forWindowsScale: 0) == 1)
    }

    @Test("maps clicks through the aspect-fit frame rect")
    func mapsClicksThroughAspectFitFrameRect() throws {
        let viewport = WindowFrameViewport(
            viewWidth: 1000,
            viewHeight: 800,
            sourceWidth: 1000,
            sourceHeight: 500
        )

        #expect(viewport.visibleFrame == WindowFrameRect(x: 0, y: 150, width: 1000, height: 500))
        #expect(viewport.guestPoint(forViewX: 500, viewYFromBottom: 400) == WindowFramePoint(x: 500, y: 250))
        #expect(viewport.guestPoint(forViewX: 500, viewYFromBottom: 799) == nil)
        #expect(viewport.guestPoint(forViewX: 500, viewYFromBottom: 1) == nil)
    }

    @Test("maps placeholder clicks through the full window bounds")
    func mapsPlaceholderClicksThroughFullWindowBounds() throws {
        let viewport = WindowFrameViewport(
            viewWidth: 1000,
            viewHeight: 800,
            sourceWidth: 1280,
            sourceHeight: 800,
            fitsSourceIntoView: false
        )

        #expect(viewport.visibleFrame == WindowFrameRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(viewport.guestPoint(forViewX: 250, viewYFromBottom: 600) == WindowFramePoint(x: 320, y: 200))
    }
}
