import Testing
import VeilHostCore
@testable import VeilHostShell

struct AppConnectionRepairGateTests {
    @Test("an unreachable agent on a Mac without Windows is a setup state, not a repair")
    func firstRunIsNotARepair() {
        for state in [nil, VMRuntimeState.stopped, .starting, .running, .failed] {
            #expect(
                !WindowsShellCopy.appConnectionNeedsRepair(
                    hasLiveAppConnection: false,
                    agentUnavailable: true,
                    windowsInstalled: false,
                    runtimeState: state
                )
            )
        }
    }

    @Test("an installed but stopped or booting Windows waits instead of asking for repair")
    func stoppedOrBootingIsNotARepair() {
        for state in [nil, VMRuntimeState.stopped, .starting, .suspended] {
            #expect(
                !WindowsShellCopy.appConnectionNeedsRepair(
                    hasLiveAppConnection: false,
                    agentUnavailable: true,
                    windowsInstalled: true,
                    runtimeState: state
                )
            )
        }
    }

    @Test("a running installed Windows with an unreachable agent asks for repair")
    func runningWithoutAgentNeedsRepair() {
        #expect(
            WindowsShellCopy.appConnectionNeedsRepair(
                hasLiveAppConnection: false,
                agentUnavailable: true,
                windowsInstalled: true,
                runtimeState: .running
            )
        )
        #expect(
            !WindowsShellCopy.appConnectionNeedsRepair(
                hasLiveAppConnection: true,
                agentUnavailable: true,
                windowsInstalled: true,
                runtimeState: .running
            )
        )
    }
}
