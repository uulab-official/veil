import Foundation
import Testing

@testable import VeilHostCore

@Suite("Windows scroll amount")
struct WindowsScrollAmountTests {
    @Test("reveals content above for a positive Mac delta and to the right for a negative one")
    func mapsDirectionsToWindowsWheelSigns() {
        let amount = WindowsScrollAmount.accumulate(
            remainder: (0, 0), scrollingDeltaX: -10, scrollingDeltaY: 10, unitsPerDelta: 2
        )

        #expect(amount.deltaY == 20)
        #expect(amount.deltaX == 20)
    }

    @Test("carries sub-unit trackpad movement until it adds up to a whole unit")
    func carriesFractions() {
        var remainder = (x: 0.0, y: 0.0)
        var sent = 0
        for _ in 0..<4 {
            let amount = WindowsScrollAmount.accumulate(
                remainder: remainder, scrollingDeltaX: 0, scrollingDeltaY: 0.3, unitsPerDelta: 2
            )
            remainder = amount.remainder
            sent += amount.deltaY
        }

        // 4 x 0.3 points x 2 units = 2.4 units: two sent, the rest kept for the next event.
        #expect(sent == 2)
        #expect(abs(remainder.y - 0.4) < 0.0001)
    }

    @Test("a wheel notch is one Windows notch")
    func wheelNotchIsOneNotch() {
        let amount = WindowsScrollAmount.accumulate(
            remainder: (0, 0), scrollingDeltaX: 0, scrollingDeltaY: -1, unitsPerDelta: 120
        )

        #expect(amount.deltaY == -120)
    }

    @Test("only scroll events carry wheel amounts on the wire")
    func onlyScrollCarriesDeltas() throws {
        let click = String(decoding: try JSONEncoder().encode(
            InputMouseEvent(windowId: "hwnd:1", event: "leftDown", x: 1, y: 2)
        ), as: UTF8.self)
        let scroll = String(decoding: try JSONEncoder().encode(
            InputMouseEvent(windowId: "hwnd:1", event: "scroll", x: 1, y: 2, deltaX: 0, deltaY: -36)
        ), as: UTF8.self)

        #expect(!click.contains("delta"))
        #expect(scroll.contains(#""deltaY":-36"#))
    }
}
