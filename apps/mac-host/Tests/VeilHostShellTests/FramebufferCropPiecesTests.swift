import CoreGraphics
import Testing
@testable import VeilHostShell

struct FramebufferCropPiecesTests {
    @Test func keepsVisiblePartsInsideTheBorderlessWindow() {
        // An 800 by 600 window without its one-pixel border.
        let inner = CGRect(x: 1, y: 1, width: 798, height: 598)

        let pieces = FramebufferCropPieces.pieces(
            visible: [CGRect(x: 0, y: 0, width: 800, height: 300), CGRect(x: 0, y: 300, width: 400, height: 300)],
            within: inner
        )

        #expect(pieces == [CGRect(x: 1, y: 1, width: 798, height: 299), CGRect(x: 1, y: 300, width: 399, height: 299)])
    }

    @Test func dropsAPartThatIsOnlyBorder() {
        let inner = CGRect(x: 1, y: 1, width: 798, height: 598)

        #expect(FramebufferCropPieces.pieces(visible: [CGRect(x: 0, y: 0, width: 800, height: 1)], within: inner).isEmpty)
    }
}
