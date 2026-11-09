import Testing

@testable import VeilHostCore

@Suite("Mirrored window display fit")
struct MirroredWindowDisplayFitTests {
    @Test("grows a small guest display to the Mac screen for a zoomed window")
    func growsSmallDisplayToMacScreen() {
        let size = MirroredWindowDisplayFit.displaySize(
            windowWidth: 1963,
            windowHeight: 1177,
            currentDisplay: GuestDisplaySize(width: 1280, height: 768),
            macScreenWidth: 2048,
            macScreenHeight: 1280
        )

        #expect(size == GuestDisplaySize(width: 2048, height: 1280))
    }

    @Test("leaves a display alone when the window already fits above the taskbar")
    func leavesFittingDisplayAlone() {
        let size = MirroredWindowDisplayFit.displaySize(
            windowWidth: 1182,
            windowHeight: 708,
            currentDisplay: GuestDisplaySize(width: 2048, height: 1280),
            macScreenWidth: 2048,
            macScreenHeight: 1280
        )

        #expect(size == nil)
    }

    @Test("settles an unknown display size on the first resize")
    func settlesUnknownDisplaySize() {
        let size = MirroredWindowDisplayFit.displaySize(
            windowWidth: 1182,
            windowHeight: 708,
            currentDisplay: nil,
            macScreenWidth: 1512,
            macScreenHeight: 982
        )

        #expect(size == GuestDisplaySize(width: 1512, height: 982))
    }

    @Test("never shrinks the display and stays within what the agent accepts")
    func neverShrinksAndClampsToAgentLimits() {
        #expect(MirroredWindowDisplayFit.displaySize(
            windowWidth: 3000,
            windowHeight: 700,
            currentDisplay: GuestDisplaySize(width: 2560, height: 1600),
            macScreenWidth: 1512,
            macScreenHeight: 982
        ) == GuestDisplaySize(width: 3000, height: 1600))

        #expect(MirroredWindowDisplayFit.displaySize(
            windowWidth: 6000,
            windowHeight: 3000,
            currentDisplay: nil,
            macScreenWidth: 6016,
            macScreenHeight: 3384
        ) == nil)
    }
}
