import Testing
import VeilHostCore
@testable import VeilHostShell

struct AppRuntimeBooterTests {
    @Test("prefers QEMU when the local compatibility provider is active")
    func prefersActiveQEMU() {
        #expect(
            AppRuntimeProviderSelection.resolve(
                providers: [provider(kind: .appleVirtualization, status: .active), provider(kind: .qemuHypervisor, status: .active)],
                environment: [:]
            ) == .qemu
        )
    }

    @Test("falls back to Apple Virtualization when QEMU is not installed")
    func fallsBackToAppleVirtualization() {
        #expect(
            AppRuntimeProviderSelection.resolve(
                providers: [provider(kind: .appleVirtualization, status: .active), provider(kind: .qemuHypervisor, status: .planned)],
                environment: [:]
            ) == .appleVirtualization
        )
    }

    @Test("honors explicit provider overrides")
    func honorsProviderOverrides() {
        let providers = [
            provider(kind: .appleVirtualization, status: .active),
            provider(kind: .qemuHypervisor, status: .planned)
        ]

        #expect(
            AppRuntimeProviderSelection.resolve(
                providers: providers,
                environment: [AppRuntimeProviderSelection.environmentKey: "qemu"]
            ) == .qemu
        )
        #expect(
            AppRuntimeProviderSelection.resolve(
                providers: providers,
                environment: [AppRuntimeProviderSelection.environmentKey: "apple"]
            ) == .appleVirtualization
        )
    }

    private func provider(
        kind: VMRuntimeProviderKind,
        status: VMRuntimeProviderStatus
    ) -> VMRuntimeProviderSummary {
        VMRuntimeProviderSummary(
            kind: kind,
            displayName: kind == .qemuHypervisor ? "QEMU/HVF" : "Apple Virtualization",
            mode: "Local",
            acceleration: "Apple Hypervisor",
            isServerBacked: false,
            status: status,
            detail: "Test provider"
        )
    }
}
