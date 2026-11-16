import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

struct WindowsRuntimeWaitPresentationTests {
    @Test("starting runtime reports elapsed boot time")
    func reportsElapsedBootTime() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let presentation = WindowsRuntimeWaitPresentation.resolve(
            state: .starting,
            attemptStartedAt: startedAt,
            now: Date(timeIntervalSince1970: 1_042)
        )

        #expect(presentation?.elapsedSeconds == 42)
        #expect(presentation?.elapsedText == "42s")
        #expect(presentation?.isLongWait == false)
        #expect(presentation?.title == "Starting Windows")
    }

    @Test("long startup gives an honest recovery hint")
    func reportsLongStartup() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let presentation = WindowsRuntimeWaitPresentation.resolve(
            state: .starting,
            attemptStartedAt: startedAt,
            now: Date(timeIntervalSince1970: 1_125)
        )

        #expect(presentation?.elapsedText == "2m 5s")
        #expect(presentation?.isLongWait == true)
        #expect(presentation?.title == "Windows is taking longer than usual")
        #expect(presentation?.detail.contains("Refresh status") == true)
    }

    @Test("starting without a launch record still has useful copy")
    func handlesMissingLaunchRecord() {
        let presentation = WindowsRuntimeWaitPresentation.resolve(
            state: .starting,
            attemptStartedAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(presentation?.elapsedSeconds == nil)
        #expect(presentation?.elapsedText == nil)
        #expect(presentation?.detail.contains("display") == true)
    }

    @Test("a persisted launch timestamp is not reused for a new attempt")
    func ignoresPersistedLaunchTimestamp() {
        let context = WindowsRuntimeWaitContext(
            attemptStartedAt: nil,
            persistedLaunchStartedAt: Date(timeIntervalSince1970: 1_000)
        )
        let presentation = WindowsRuntimeWaitPresentation.resolve(
            state: .starting,
            context: context,
            now: Date(timeIntervalSince1970: 10_000)
        )

        #expect(presentation?.elapsedSeconds == nil)
        #expect(presentation?.isLongWait == false)
    }

    @Test("non-starting runtime has no wait presentation")
    func ignoresNonStartingRuntime() {
        #expect(WindowsRuntimeWaitPresentation.resolve(
            state: .running,
            attemptStartedAt: Date(timeIntervalSince1970: 1_000),
            now: Date(timeIntervalSince1970: 1_100)
        ) == nil)
    }
}
