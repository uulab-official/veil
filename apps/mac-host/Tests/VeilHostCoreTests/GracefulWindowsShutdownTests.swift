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
}
