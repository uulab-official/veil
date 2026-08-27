import Foundation
import Testing

@testable import VeilHostCore

/// Bounding the size of one guest message does nothing about a megabyte every ten milliseconds. These events
/// cross into things the user owns — the macOS pasteboard, Notification Center — and the guest controls both
/// their content and their timing.
///
/// The limiter is told the time rather than reading a clock, precisely so these tests are deterministic. A
/// limiter that is slightly wrong either lets a flood through or silently discards a user's real work, and
/// neither is discoverable from a test that depends on wall time.
@Suite("Guest event rate limiter")
struct GuestEventRateLimiterTests {
    private static let origin = Date(timeIntervalSince1970: 1_000)

    /// Results are collected before asserting, not asserted inline.
    ///
    /// `allows(at:)` is `mutating`, and swift-testing's `#expect` decomposes a member call into a closure that
    /// receives the value as an immutable parameter — so `#expect(limiter.allows(at: x))` does not compile.
    /// Collecting first is also clearer for a sequence: the assertion shows the whole shape at once.
    private func outcomes(_ limiter: inout GuestEventRateLimiter, at times: [TimeInterval]) -> [Bool] {
        times.map { limiter.allows(at: Self.origin.addingTimeInterval($0)) }
    }

    @Test("allows a burst up to the limit")
    func allowsBurstUpToLimit() {
        var limiter = GuestEventRateLimiter(maximumEvents: 3, window: 10)

        let results = outcomes(&limiter, at: [0, 0, 0, 0])

        #expect(results == [true, true, true, false])
    }

    @Test("allows again once the window has passed")
    func allowsAfterWindow() {
        var limiter = GuestEventRateLimiter(maximumEvents: 2, window: 10)

        let results = outcomes(&limiter, at: [0, 0, 0, 10])

        #expect(results == [true, true, false, true])
    }

    @Test("slides rather than resetting on a fixed boundary")
    func windowSlides() {
        var limiter = GuestEventRateLimiter(maximumEvents: 2, window: 10)

        let results = outcomes(&limiter, at: [0, 9, 10, 10, 18, 19])

        // A fixed-bucket limiter would reset at t=10 and allow two more immediately, letting through double the
        // intended rate across a boundary. Here the event at t=9 is still inside the window at t=18, so the
        // budget is not free until t=19.
        #expect(results == [true, true, true, false, false, true])
    }

    @Test("sustains the intended rate indefinitely")
    func sustainsIntendedRate() {
        var limiter = GuestEventRateLimiter(maximumEvents: 5, window: 10)
        var accepted = 0

        // One event every two seconds is exactly the limit, so every one should be accepted over a long run.
        for step in 0..<100 {
            if limiter.allows(at: Self.origin.addingTimeInterval(Double(step) * 2)) {
                accepted += 1
            }
        }

        #expect(accepted == 100)
    }

    @Test("drops a flood down to the intended rate")
    func dropsFlood() {
        var limiter = GuestEventRateLimiter(maximumEvents: 5, window: 10)
        var accepted = 0

        // 1000 events in one second: the shape of the attack.
        for step in 0..<1_000 {
            if limiter.allows(at: Self.origin.addingTimeInterval(Double(step) * 0.001)) {
                accepted += 1
            }
        }

        #expect(accepted == 5)
    }

    @Test("never retains more timestamps than the limit")
    func retainsBoundedState() {
        var limiter = GuestEventRateLimiter(maximumEvents: 4, window: 10)

        for step in 0..<10_000 {
            _ = limiter.allows(at: Self.origin.addingTimeInterval(Double(step) * 0.001))
        }

        // The limiter must not become its own memory leak while defending against one.
        #expect(limiter.recordedEventCount <= 4)
    }

    @Test("refuses a nonsensical configuration instead of dividing by it")
    func normalizesConfiguration() {
        let zeroEvents = GuestEventRateLimiter(maximumEvents: 0, window: 10)
        let negativeWindow = GuestEventRateLimiter(maximumEvents: 5, window: -10)

        // A limit of zero would block every event forever, which is a worse failure than no limiter at all.
        #expect(zeroEvents.maximumEvents == 1)
        #expect(negativeWindow.window == 0)
    }

    @Test("a zero window still admits one event at a time")
    func zeroWindowAdmitsSequentially() {
        var limiter = GuestEventRateLimiter(maximumEvents: 1, window: 0)

        let results = outcomes(&limiter, at: [0, 0])

        // With a zero-length window the previous event is never inside it, so the next call is free. The point
        // is that a degenerate configuration does not deadlock the bridge.
        #expect(results == [true, true])
    }

    @Test("clipboard and notification rates match how each is actually used")
    func presetRatesAreDefensible() {
        // A person copies a few times a second at most; six per second is well above deliberate human use.
        #expect(GuestEventRateLimiter.guestClipboard.maximumEvents == 30)
        #expect(GuestEventRateLimiter.guestClipboard.window == 5)
        // Notifications are intrusive and carry guest text under Veil's identity, so this one is deliberately
        // much tighter: twenty a minute covers a busy mail or chat client.
        #expect(GuestEventRateLimiter.guestNotifications.maximumEvents == 20)
        #expect(GuestEventRateLimiter.guestNotifications.window == 60)
    }
}
