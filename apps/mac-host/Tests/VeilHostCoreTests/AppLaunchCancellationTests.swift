import Foundation
import Testing
@testable import VeilHostCore

@Suite("App launch cancellation propagation")
struct AppLaunchCancellationTests {
    @Test("cancelling the model launch while health waits prevents further guest commands")
    @MainActor
    func cancelsInnerLaunchBeforeGuestSideEffects() async {
        let transport = SuspendedLaunchHealthTransport()
        let model = HostDashboardModel(service: VeilHostClient(transport: transport))
        let launch = Task { await model.launchApp(appId: "winapp_notepad") }
        await transport.waitForHealth()
        launch.cancel()
        await transport.releaseHealth()
        #expect(await launch.value == nil)
        #expect(await transport.sentTypes == ["agent.health.request"])
        #expect(model.mirrorSessions.isEmpty)
    }
}

/// Deliberately non-cooperative: models a reply that races with cancellation.
private actor SuspendedLaunchHealthTransport: HostTransport {
    private(set) var sentTypes: [String] = []
    private var healthWaiter: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func waitForHealth() async {
        if healthWaiter != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func releaseHealth() {
        healthWaiter?.resume()
        healthWaiter = nil
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
        let type = object?["type"] as? String ?? "unknown"
        sentTypes.append(type)
        guard type == "agent.health.request" else {
            throw VeilHostError.missingReply("Unexpected command after cancellation")
        }
        await withCheckedContinuation {
            healthWaiter = $0
            observer?.resume()
            observer = nil
        }
        return [Data(#"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"test"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true,"packageIdentity":false,"operationAcks":true}}"#.utf8)]
    }
}
