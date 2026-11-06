import Testing
import VeilHostCore
@testable import VeilHostShell

struct DiskSettingsPolicyTests {
    @Test("a stopped Windows can resize, convert, and take disk-only snapshots")
    func stoppedWindows() {
        let policy = DiskSettingsPolicy.resolve(runtimeState: .stopped, isWorking: false)

        #expect(policy == DiskSettingsPolicy(canChangeDisk: true, canUseSnapshots: true, snapshotsIncludeMemory: false))
    }

    @Test("a running Windows keeps its disk but snapshots with memory")
    func runningWindows() {
        let policy = DiskSettingsPolicy.resolve(runtimeState: .running, isWorking: false)

        #expect(policy == DiskSettingsPolicy(canChangeDisk: false, canUseSnapshots: true, snapshotsIncludeMemory: true))
    }

    @Test("nothing changes while Windows starts, is suspended, or another disk operation runs", arguments: [
        (VMRuntimeState.starting, false),
        (.suspended, false),
        (.stopped, true),
        (.running, true)
    ])
    func locked(state: VMRuntimeState, isWorking: Bool) {
        let policy = DiskSettingsPolicy.resolve(runtimeState: state, isWorking: isWorking)

        #expect(!policy.canChangeDisk)
        #expect(!policy.canUseSnapshots)
    }

    @Test("the Disk tab sits between Hardware and Installation")
    func diskTabOrder() {
        let tabs = MachineConfigurationTab.allCases.map(\.rawValue)
        // Other tabs (such as USB Devices) may be added; only the Disk tab's place is pinned here.
        #expect(Array(tabs.prefix(4)) == ["general", "hardware", "disk", "installation"])
        #expect(tabs.last == "diagnostics")
    }
}
