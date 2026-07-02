import Testing

@testable import VeilHostCore

@Suite("Window frame viewport")
struct WindowFrameViewportTests {
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
