import Testing
import VeilHostCore
@testable import VeilHostShell

struct AppGuestAgentConnectionTests {
    @Test("uses the proved QEMU loopback guest-agent endpoint")
    func qemuLoopback() {
        let plan = AppGuestAgentConnectionPlan.resolve(provider: .qemu, environment: [:])

        #expect(plan.transport == .qemuLoopback)
        #expect(plan.endpoint == "ws://127.0.0.1:18444")
        #expect(plan.isAvailable)
    }

    @Test("does not pretend Apple Virtualization has a guest-agent route")
    func appleTransportUnavailable() {
        let plan = AppGuestAgentConnectionPlan.resolve(provider: .appleVirtualization, environment: [:])

        #expect(plan.transport == .unavailable)
        #expect(!plan.isAvailable)
        #expect(plan.detail.contains("not configured a routable guest-agent endpoint"))
        #expect(plan.nextActions.contains { $0.contains("QEMU/HVF") })
    }

    @Test("allows a deliberate WebSocket endpoint override for either provider")
    func explicitEndpoint() {
        let plan = AppGuestAgentConnectionPlan.resolve(
            provider: .appleVirtualization,
            environment: [AppGuestAgentConnectionPlan.environmentKey: "ws://192.168.64.10:18444"]
        )

        #expect(plan.transport == .explicitWebSocket)
        #expect(plan.endpointURL?.host == "192.168.64.10")
        #expect(plan.isAvailable)
    }

    @Test("rejects invalid endpoint overrides before opening a transport")
    func invalidExplicitEndpoint() {
        let plan = AppGuestAgentConnectionPlan.resolve(
            provider: .qemu,
            environment: [AppGuestAgentConnectionPlan.environmentKey: "http://127.0.0.1:18444"]
        )

        #expect(plan.transport == .unavailable)
        #expect(!plan.isAvailable)
        #expect(plan.detail.contains("ws:// or wss://"))
    }

    @Test("unavailable provider service returns typed diagnostics without polling")
    @MainActor
    func unavailableServiceDiagnostic() async {
        let plan = AppGuestAgentConnectionPlan.resolve(provider: .appleVirtualization, environment: [:])
        let model = HostDashboardModel(service: UnavailableGuestAgentService(plan: plan))

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.agentDiagnostic?.endpoint == plan.endpoint)
        #expect(model.agentDiagnostic?.nextActions == plan.nextActions)

        let wait = await model.waitForLiveAgentConnection(endpoint: plan.endpoint, timeoutSeconds: 30)
        #expect(wait.status == .unavailable)
        #expect(wait.waitedSeconds == 0)
        #expect(wait.attempts == 0)
    }
}
