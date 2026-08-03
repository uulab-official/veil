import Testing
import VeilHostCore
@testable import VeilHostShell

struct RuntimeDisplaySelectionTests {
    @Test("uses the native Apple VM view while Apple Virtualization is running")
    func selectsAppleVirtualMachine() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .appleVirtualization,
                state: .running,
                hasAppleVirtualMachine: true,
                hasCapturedSurface: true
            ) == .appleVirtualMachine
        )
    }

    @Test("keeps QEMU on the captured display surface")
    func selectsQEMUCapturedSurface() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .qemuHypervisor,
                state: .running,
                hasAppleVirtualMachine: true,
                hasCapturedSurface: true
            ) == .capturedSurface
        )
    }

    @Test("does not retain the native VM view after the runtime stops")
    func hidesStoppedAppleVirtualMachine() {
        #expect(
            RuntimeDisplaySelection.resolve(
                provider: .appleVirtualization,
                state: .stopped,
                hasAppleVirtualMachine: true,
                hasCapturedSurface: false
            ) == .placeholder
        )
    }
}
