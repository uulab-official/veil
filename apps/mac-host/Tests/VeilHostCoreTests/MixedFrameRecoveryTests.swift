import Foundation
import Testing

@testable import VeilHostCore

@Suite("Mixed frame recovery")
@MainActor
struct MixedFrameRecoveryTests {
    @Test("only a validated JSON full frame restores a rejected binary stream", arguments: ["valid", "undecodable", "mismatched"])
    func restoresFromJSON(payloadKind: String) async throws {
        let model = HostDashboardModel(
            service: DemoHostDashboardService(),
            restoreIntentStore: MixedFrameRestoreStore(),
            pendingLaunchIntentStore: MixedFramePendingStore()
        )
        let result = try #require(await model.launchNotepad())
        let windowId = result.window.windowId
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let tile = WindowFrameTile(
            windowId: windowId, sequence: 1, surfaceWidth: 1, surfaceHeight: 1, scale: 1,
            isKeyFrame: true, rect: WindowFrameTileRect(x: 0, y: 0, width: 1, height: 1),
            payload: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        )
        #expect(model.receiveWindowFrameTile(tile, receivedAt: startedAt))
        let originalTiming = model.mirrorSessions.first?.frameTiming
        var broken = tile
        broken.isKeyFrame = false
        broken.payload = Data("broken PNG".utf8)
        #expect(!model.receiveWindowFrameTile(broken, receivedAt: startedAt.addingTimeInterval(1)))

        var jsonFrame = tile.surfaceMetadataFrameEvent()
        jsonFrame.format = "png"
        jsonFrame.encodedData = payloadKind == "undecodable"
            ? broken.payload.base64EncodedString() : tile.payload.base64EncodedString()
        if payloadKind == "mismatched" { jsonFrame.width = 2 }
        model.receiveWindowFrame(jsonFrame, receivedAt: startedAt.addingTimeInterval(2))

        let recovered = payloadKind == "valid"
        #expect((model.mirrorSessions.first?.awaitingKeyFrameReason == nil) == recovered)
        #expect((model.compositedFrameImage(for: windowId) != nil) == recovered)
        let heartbeat = WindowFrameUnchangedEvent(
            windowId: windowId, sequence: 3, capturedAt: "2026-09-08T00:00:00Z"
        )
        #expect(model.receiveWindowFrameUnchanged(heartbeat, receivedAt: startedAt.addingTimeInterval(60)) == recovered)
        let session = try #require(model.mirrorSessions.first)
        #expect(WindowFrameStreamAssessment.assess(
            session: session, generatedAt: startedAt.addingTimeInterval(60)
        ).status == (recovered ? .fresh : .stale))
        if recovered {
            #expect(session.latestFrame == jsonFrame)
            #expect(session.frameTiming?.receivedFrameCount == 2)
        } else {
            #expect(session.frameTiming == originalTiming)
        }

        var nextDelta = tile
        // The validated JSON frame re-establishes sequence 1 as the new key-frame base. The
        // next delta must therefore be the adjacent sequence, not a number from the discarded
        // stream epoch.
        nextDelta.sequence = 2
        nextDelta.isKeyFrame = false
        #expect(model.receiveWindowFrameTile(nextDelta, receivedAt: startedAt.addingTimeInterval(61)) == recovered)
    }
}

private actor MixedFrameRestoreStore: WindowRestoreIntentStore {
    var value: WindowRestoreIntent?
    func load() -> WindowRestoreIntent? { value }
    func save(_ intent: WindowRestoreIntent) { value = intent }
}

private actor MixedFramePendingStore: PendingLaunchIntentStore {
    var value: PendingLaunchIntent?
    func load() -> PendingLaunchIntent? { value }
    func save(_ intent: PendingLaunchIntent) { value = intent }
    func clear() { value = nil }
}
