import Foundation
import Testing
@testable import VeilHostCore

struct QEMULaunchProcessTests {
    @Test func recognizesQEMUByItsCommandLine() {
        #expect(LocalVMRuntimeService.isQEMUSystemEmulatorCommand(
            "/Applications/Veil.app/Contents/Resources/Runtime/bin/qemu-system-aarch64 -name Windows 11 Arm -machine virt"
        ))
        #expect(LocalVMRuntimeService.isQEMUSystemEmulatorCommand(
            "/Users/me/Library/Application Support/Veil/qemu-aarch64-softmmu -m 8192"
        ))
        #expect(!LocalVMRuntimeService.isQEMUSystemEmulatorCommand("/usr/sbin/cupsd -l"))
        #expect(!LocalVMRuntimeService.isQEMUSystemEmulatorCommand(""))
    }

    /// A launch record outlives its QEMU, and the process id goes to another program. This test process
    /// stands in for that program: alive, but not QEMU.
    @Test func aLivingProcessThatIsNotQEMUDoesNotCountAsTheVirtualMachine() {
        #expect(!LocalVMRuntimeService.processIsRunning(pid: ProcessInfo.processInfo.processIdentifier))
    }

    @Test func aProcessIdNothingHasIsNotRunning() {
        // Above the largest process id macOS gives out (99998).
        #expect(!LocalVMRuntimeService.processIsRunning(pid: 4_000_000))
    }
}
