import CoreGraphics
import Testing
@testable import VeilHostCore

struct CoherenceBorderlessCropTests {
    @Test("drops the one-pixel Windows border on every side at 100%")
    func dropsBorderAtOneToOne() throws {
        let crop = CGRect(x: 626, y: 347, width: 988, height: 708)
        let borderless = try #require(
            CoherenceBorderlessCrop(crop: crop, borderPixels: CoherenceBorderlessCrop.borderPixels(pointsPerPixel: 1))
        )
        #expect(borderless.inner == CGRect(x: 627, y: 348, width: 986, height: 706))
        #expect(borderless.innerOffset == CGPoint(x: 1, y: 1))
    }

    @Test("drops one Mac point, two guest pixels, at 200%")
    func dropsOnePointOnRetina() {
        #expect(CoherenceBorderlessCrop.borderPixels(pointsPerPixel: 0.5) == 2)
        #expect(CoherenceBorderlessCrop.borderPixels(pointsPerPixel: 1) == 1)
        #expect(CoherenceBorderlessCrop.borderPixels(pointsPerPixel: 0) == 1)
    }

    @Test("a window too small to lose its border is drawn whole")
    func tinyWindowKeepsCrop() {
        #expect(CoherenceBorderlessCrop(crop: CGRect(x: 0, y: 0, width: 2, height: 40), borderPixels: 1) == nil)
    }
}
