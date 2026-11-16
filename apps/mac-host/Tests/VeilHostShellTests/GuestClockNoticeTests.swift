import Foundation
import Testing

@testable import VeilHostShell

@Suite("Guest clock notice")
struct GuestClockNoticeTests {
    @Test("Only a clock that needs the repair and is minutes off notifies, once")
    func notifiesOnce() {
        let hours = 9 * 3_600_000
        #expect(GuestClockNotice.shouldNotify(needsRepair: true, skewMilliseconds: hours, alreadyNotified: false))
        #expect(GuestClockNotice.shouldNotify(needsRepair: true, skewMilliseconds: -hours, alreadyNotified: false))
        #expect(!GuestClockNotice.shouldNotify(needsRepair: true, skewMilliseconds: hours, alreadyNotified: true))
        #expect(!GuestClockNotice.shouldNotify(needsRepair: false, skewMilliseconds: hours, alreadyNotified: false))
        #expect(!GuestClockNotice.shouldNotify(needsRepair: true, skewMilliseconds: 4 * 60_000, alreadyNotified: false))
        #expect(!GuestClockNotice.shouldNotify(needsRepair: true, skewMilliseconds: nil, alreadyNotified: false))
    }

    @Test("The skew reads as hours and minutes")
    func skewText() {
        let text = GuestClockNotice.skewText(milliseconds: 34_404_429)
        #expect(text.contains("9"))
        #expect(text.contains("33"))
        #expect(!GuestClockNotice.skewText(milliseconds: -2 * 86_400_000).isEmpty)
    }
}
