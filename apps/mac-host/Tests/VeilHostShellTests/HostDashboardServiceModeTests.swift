import Testing
@testable import VeilHostShell

struct HostDashboardServiceModeTests {
    @Test("defaults to the live Windows agent")
    func defaultsToLiveAgent() {
        #expect(
            HostDashboardServiceMode.resolve(
                arguments: ["veil-host-shell"],
                environment: [:]
            ) == .live
        )
    }

    @Test("enables demo mode only through an explicit launch argument")
    func resolvesDemoArgument() {
        #expect(
            HostDashboardServiceMode.resolve(
                arguments: ["veil-host-shell", "--demo"],
                environment: [:]
            ) == .demo
        )
    }

    @Test("enables demo mode through the documented environment opt-in")
    func resolvesDemoEnvironment() {
        #expect(
            HostDashboardServiceMode.resolve(
                arguments: ["veil-host-shell"],
                environment: ["VEIL_DEMO_MODE": "1"]
            ) == .demo
        )
    }

    @Test("does not treat arbitrary environment values as demo mode")
    func rejectsImplicitDemoEnvironment() {
        #expect(
            HostDashboardServiceMode.resolve(
                arguments: ["veil-host-shell"],
                environment: ["VEIL_DEMO_MODE": "true"]
            ) == .live
        )
    }
}
