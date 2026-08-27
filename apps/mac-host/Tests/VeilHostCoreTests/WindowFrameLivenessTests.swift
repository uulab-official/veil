import Foundation
import Testing

@testable import VeilHostCore

@Suite("Window frame liveness")
struct WindowFrameLivenessTests {
    private static let firstFrameAt = Date(timeIntervalSince1970: 1_000)

    private static func streamingSession(
        timing: WindowFrameTiming,
        restartCount: Int = 0
    ) -> WindowMirrorSession {
        WindowMirrorSession(
            window: WindowCreatedEvent(
                windowId: "hwnd:0003029A",
                processId: 4_912,
                appId: "winapp_notepad",
                title: "Untitled - Notepad",
                bounds: WindowBounds(x: 0, y: 0, width: 640, height: 480),
                state: "normal",
                focused: true
            ),
            connectionMode: .agent,
            captureState: .streaming,
            frameTiming: timing,
            frameStreamRequestedAt: firstFrameAt,
            frameStreamRestartCount: restartCount
        )
    }

    @Test("an idle window stays fresh while heartbeats keep arriving")
    func idleWindowStaysFreshWhileHeartbeatsArrive() {
        // This is the whole point of the split. Before it, freshness came from the frame time alone, so a
        // guest that stopped re-encoding identical pixels was escalated into recovery and had to keep
        // paying for a full-window PNG several times a second just to look alive.
        let timing = WindowFrameTiming(
            firstFrameReceivedAt: Self.firstFrameAt,
            latestFrameReceivedAt: Self.firstFrameAt,
            latestActivityAt: Self.firstFrameAt.addingTimeInterval(30),
            receivedFrameCount: 1,
            unchangedHeartbeatCount: 120
        )

        let assessment = WindowFrameStreamAssessment.assess(
            session: Self.streamingSession(timing: timing),
            generatedAt: Self.firstFrameAt.addingTimeInterval(30.25)
        )

        #expect(assessment.status == .fresh)
        #expect(assessment.recommendedAction == "none")
        #expect(!assessment.recoveryEscalated)
        #expect(!assessment.reopenEscalated)
        // The picture really is 30 seconds old, and the contract still says so.
        #expect(assessment.latestFrameAgeMilliseconds == 30_250)
        #expect(assessment.latestActivityAgeMilliseconds == 250)
        #expect(assessment.unchangedHeartbeatCount == 120)
    }

    @Test("a window whose guest went silent still goes stale")
    func silentGuestStillGoesStale() {
        // Heartbeats are the liveness signal, so their absence must still escalate. Otherwise the split
        // would have traded a false alarm for a missed one.
        let timing = WindowFrameTiming(
            firstFrameReceivedAt: Self.firstFrameAt,
            latestFrameReceivedAt: Self.firstFrameAt,
            latestActivityAt: Self.firstFrameAt,
            receivedFrameCount: 4
        )

        let assessment = WindowFrameStreamAssessment.assess(
            session: Self.streamingSession(timing: timing),
            generatedAt: Self.firstFrameAt.addingTimeInterval(6)
        )

        #expect(assessment.status == .stale)
        #expect(assessment.recommendedAction == "restart-frame-subscription")
        #expect(assessment.latestActivityAgeMilliseconds == 6_000)
    }

    @Test("a delayed stream is judged on liveness, not on picture age")
    func delayedStreamIsJudgedOnLiveness() {
        let timing = WindowFrameTiming(
            firstFrameReceivedAt: Self.firstFrameAt,
            latestFrameReceivedAt: Self.firstFrameAt,
            latestActivityAt: Self.firstFrameAt.addingTimeInterval(10),
            receivedFrameCount: 2,
            unchangedHeartbeatCount: 3
        )

        let assessment = WindowFrameStreamAssessment.assess(
            session: Self.streamingSession(timing: timing),
            generatedAt: Self.firstFrameAt.addingTimeInterval(13)
        )

        #expect(assessment.status == .delayed)
        #expect(assessment.recommendedAction == "refresh-runtime-status")
        #expect(assessment.latestFrameAgeMilliseconds == 13_000)
        #expect(assessment.latestActivityAgeMilliseconds == 3_000)
    }

    @Test("existing escalation still applies when liveness stops after repeated restarts")
    func escalationStillAppliesWhenLivenessStops() {
        let timing = WindowFrameTiming(
            firstFrameReceivedAt: Self.firstFrameAt,
            latestFrameReceivedAt: Self.firstFrameAt,
            latestActivityAt: Self.firstFrameAt,
            receivedFrameCount: 1
        )

        let recovery = WindowFrameStreamAssessment.assess(
            session: Self.streamingSession(timing: timing, restartCount: 2),
            generatedAt: Self.firstFrameAt.addingTimeInterval(6)
        )
        let reopen = WindowFrameStreamAssessment.assess(
            session: Self.streamingSession(timing: timing, restartCount: 3),
            generatedAt: Self.firstFrameAt.addingTimeInterval(6)
        )

        #expect(recovery.recommendedAction == "recover-window-capture")
        #expect(recovery.recoveryEscalated)
        #expect(reopen.recommendedAction == "reopen-windows-app")
        #expect(reopen.reopenEscalated)
    }

    @Test("a guest that never sends heartbeats behaves exactly as before")
    func guestWithoutHeartbeatsBehavesAsBefore() {
        // `latestActivityAt` defaults to the frame time, so an older agent is unaffected by the split.
        let timing = WindowFrameTiming(
            firstFrameReceivedAt: Self.firstFrameAt,
            latestFrameReceivedAt: Self.firstFrameAt.addingTimeInterval(2)
        )

        #expect(timing.latestActivityAt == timing.latestFrameReceivedAt)
        #expect(timing.unchangedHeartbeatCount == 0)

        let assessment = WindowFrameStreamAssessment.assess(
            session: Self.streamingSession(timing: timing),
            generatedAt: Self.firstFrameAt.addingTimeInterval(8)
        )

        #expect(assessment.status == .stale)
        #expect(assessment.latestFrameAgeMilliseconds == 6_000)
        #expect(assessment.latestActivityAgeMilliseconds == 6_000)
    }

    @Test("waiting for a first frame is unaffected by the liveness split")
    func waitingForFirstFrameIsUnaffected() {
        let session = WindowMirrorSession(
            window: WindowCreatedEvent(
                windowId: "hwnd:0003029A",
                processId: 4_912,
                appId: "winapp_notepad",
                title: "Untitled - Notepad",
                bounds: WindowBounds(x: 0, y: 0, width: 640, height: 480),
                state: "normal",
                focused: true
            ),
            connectionMode: .agent,
            captureState: .pending,
            frameStreamRequestedAt: Self.firstFrameAt
        )

        let assessment = WindowFrameStreamAssessment.assess(
            session: session,
            generatedAt: Self.firstFrameAt.addingTimeInterval(3)
        )

        #expect(assessment.status == .waitingForFirstFrame)
        #expect(assessment.unchangedHeartbeatCount == 0)
        #expect(assessment.latestActivityAgeMilliseconds == nil)
    }
}
