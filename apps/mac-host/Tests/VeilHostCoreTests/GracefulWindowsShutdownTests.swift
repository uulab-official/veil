import CoreGraphics
import Foundation
import Testing

@testable import VeilHostCore

@MainActor
@Suite("Graceful Windows shutdown")
struct GracefulWindowsShutdownTests {
    @Test("the tools shut Windows down without pressing the power button")
    func toolsShutdown() async {
        var buttonPresses = 0
        var checks = 0
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { true },
            pressPowerButton: { buttonPresses += 1; return true },
            isStillRunning: { checks += 1; return checks < 3 },
            pollInterval: .zero
        )

        #expect(outcome == .poweredOffViaTools)
        #expect(buttonPresses == 0)
        #expect(checks == 3)
    }

    @Test("without the tools Veil presses the power button")
    func powerButtonFallback() async {
        var buttonPresses = 0
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { false },
            pressPowerButton: { buttonPresses += 1; return true },
            isStillRunning: { false },
            pollInterval: .zero
        )

        #expect(outcome == .poweredOffViaPowerButton)
        #expect(buttonPresses == 1)
    }

    @Test("a Windows that never powers off times out so the caller can turn it off")
    func timesOut() async {
        var clock = Date(timeIntervalSince1970: 0)
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { false },
            pressPowerButton: { true },
            isStillRunning: { clock.addTimeInterval(30); return true },
            pollInterval: .zero,
            now: { clock }
        )

        #expect(outcome == .timedOut)
        #expect(!outcome.poweredOff)
        #expect(clock.timeIntervalSince1970 >= GracefulWindowsShutdown.powerButtonSeconds)
    }

    @Test("waiting again for a shutdown already asked for asks nothing and still sees it finish")
    func waitsAgainWithoutAsking() async {
        var clock = Date(timeIntervalSince1970: 0)
        var polls = 0
        let poweredOff = await GracefulWindowsShutdown.waitForPowerOff(
            viaTools: true,
            isStillRunning: { polls += 1; clock.addTimeInterval(10); return polls < 3 },
            timeout: 60,
            pollInterval: .zero,
            now: { clock }
        )
        #expect(poweredOff == .poweredOffViaTools)

        let stillOn = await GracefulWindowsShutdown.waitForPowerOff(
            viaTools: false,
            isStillRunning: { clock.addTimeInterval(10); return true },
            hasFinishedShuttingDown: { true },
            timeout: 60,
            pollInterval: .zero,
            now: { clock }
        )
        // A power button press never counts a quiet guest as finished.
        #expect(stillOn == .timedOut)
    }

    @Test("nothing to ask means nothing to wait for")
    func notRequested() async {
        var checks = 0
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { false },
            pressPowerButton: { false },
            isStillRunning: { checks += 1; return true },
            pollInterval: .zero
        )

        #expect(outcome == .notRequested)
        #expect(checks == 0)
    }

    @Test("a Windows that finished shutting down but stays on is done once it has been quiet for a while")
    func finishedWithoutPowerOff() async {
        var clock = Date(timeIntervalSince1970: 0)
        var quiet = false
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { true },
            pressPowerButton: { true },
            isStillRunning: {
                clock.addTimeInterval(2)
                // Busy with updates for the first minute, then idle.
                quiet = clock.timeIntervalSince1970 > 60
                return true
            },
            hasFinishedShuttingDown: { quiet },
            pollInterval: .zero,
            now: { clock }
        )

        #expect(outcome == .finishedWithoutPowerOff)
        #expect(outcome.poweredOff)
        #expect(clock.timeIntervalSince1970 >= 60 + GracefulWindowsShutdown.settledSeconds)
        #expect(clock.timeIntervalSince1970 < 120)
    }

    @Test("a power button press never counts quiet as finished, since Windows may be asleep")
    func powerButtonIgnoresQuiet() async {
        var clock = Date(timeIntervalSince1970: 0)
        let outcome = await GracefulWindowsShutdown.run(
            requestToolsShutdown: { false },
            pressPowerButton: { true },
            isStillRunning: { clock.addTimeInterval(2); return true },
            hasFinishedShuttingDown: { true },
            pollInterval: .zero,
            now: { clock }
        )

        #expect(outcome == .timedOut)
    }
}

@Suite("QEMU process activity")
struct QEMUProcessActivityTests {
    // Lower bound only: tests running in parallel add their own CPU time to this process, and a busy CI runner
    // gave the loop a third of a core. The bound is there to catch units: Mach ticks read as nanoseconds would
    // come out about 40 times too small on Apple silicon, near 0.02.
    @Test("reads this process's CPU time in nanoseconds and a busy loop as a tenth of a core or more")
    func measuresOwnProcess() throws {
        let activity = QEMUProcessActivity(pid: getpid())
        let start = Date()
        #expect(activity.coreFractionSinceLastSample(now: start) == nil)

        var spin = 0.0
        while Date().timeIntervalSince(start) < 0.3 {
            spin += sin(spin)
        }
        let fraction = try #require(activity.coreFractionSinceLastSample(now: Date()))
        #expect(fraction > 0.1, "fraction \(fraction), spin \(spin)")
    }
}

@Suite("Guest shutdown completion probe")
struct GuestShutdownCompletionProbeTests {
    private func image(gray: CGFloat, dot: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        if dot {
            // A shutdown dialog: a light panel in the middle of a dark screen.
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(CGRect(x: 200, y: 160, width: 240, height: 160))
        }
        return try #require(context.makeImage())
    }

    @Test("a black display counts as finished; anything drawn on it does not")
    func blackness() throws {
        #expect(GuestShutdownCompletionProbe.isBlack(try image(gray: 0)))
        #expect(GuestShutdownCompletionProbe.isBlack(try image(gray: 0.05)))
        #expect(!GuestShutdownCompletionProbe.isBlack(try image(gray: 0, dot: true)))
        #expect(!GuestShutdownCompletionProbe.isBlack(try image(gray: 0.3)))
    }
}
