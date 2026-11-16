import Testing

@testable import VeilHostCore

@Suite("Windows caption region")
struct WindowsCaptionRegionTests {
    @Test("treats everything below the caption band as app content")
    func treatsEverythingBelowTheCaptionAsContent() {
        #expect(WindowsCaptionRegion.classify(guestX: 600, guestY: 32, windowWidth: 1182) == .content)
        #expect(WindowsCaptionRegion.classify(guestX: 1170, guestY: 400, windowWidth: 1182) == .content)
    }

    @Test("maps the right end of the caption to close, maximize, and minimize")
    func mapsCaptionButtons() {
        #expect(WindowsCaptionRegion.classify(guestX: 1181, guestY: 10, windowWidth: 1182) == .closeButton)
        #expect(WindowsCaptionRegion.classify(guestX: 1136, guestY: 10, windowWidth: 1182) == .closeButton)
        #expect(WindowsCaptionRegion.classify(guestX: 1135, guestY: 10, windowWidth: 1182) == .maximizeButton)
        #expect(WindowsCaptionRegion.classify(guestX: 1090, guestY: 10, windowWidth: 1182) == .maximizeButton)
        #expect(WindowsCaptionRegion.classify(guestX: 1089, guestY: 10, windowWidth: 1182) == .minimizeButton)
        #expect(WindowsCaptionRegion.classify(guestX: 1044, guestY: 10, windowWidth: 1182) == .minimizeButton)
        #expect(WindowsCaptionRegion.classify(guestX: 1043, guestY: 10, windowWidth: 1182) == .caption)
        #expect(WindowsCaptionRegion.classify(guestX: 0, guestY: 0, windowWidth: 1182) == .caption)
    }

    @Test("keeps a very narrow window's whole caption draggable")
    func keepsNarrowCaptionDraggable() {
        #expect(WindowsCaptionRegion.classify(guestX: 150, guestY: 10, windowWidth: 160) == .caption)
    }

    @Test("ignores points outside the window")
    func ignoresPointsOutsideTheWindow() {
        #expect(WindowsCaptionRegion.classify(guestX: -1, guestY: 10, windowWidth: 1182) == .content)
        #expect(WindowsCaptionRegion.classify(guestX: 1182, guestY: 10, windowWidth: 1182) == .content)
        #expect(WindowsCaptionRegion.classify(guestX: 10, guestY: 10, windowWidth: 0) == .content)
    }
}
