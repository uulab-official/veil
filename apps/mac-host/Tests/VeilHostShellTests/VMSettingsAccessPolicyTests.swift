import Testing
import VeilHostCore
@testable import VeilHostShell

struct VMSettingsAccessPolicyTests {
    @Test("allows resource changes while Windows is stopped")
    func allowsStoppedResourceChanges() {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: .stopped, isLoading: false)

        #expect(policy.canChangeResources)
        #expect(policy.guidance == nil)
    }

    @Test("locks resource changes while Windows is running or starting", arguments: [VMRuntimeState.running, .starting])
    func locksActiveRuntime(state: VMRuntimeState) {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: state, isLoading: false)

        #expect(!policy.canChangeResources)
        #expect(policy.guidance?.contains("Stop Windows") == true)
    }

    @Test("protects suspended session resources")
    func locksSuspendedRuntime() {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: .suspended, isLoading: false)

        #expect(!policy.canChangeResources)
        #expect(policy.guidance?.contains("suspended session") == true)
    }

    @Test("locks settings during an in-flight operation")
    func locksLoadingState() {
        let policy = VMSettingsAccessPolicy.resolve(runtimeState: .stopped, isLoading: true)

        #expect(!policy.canChangeResources)
        #expect(policy.guidance?.contains("current Windows operation") == true)
    }
}
