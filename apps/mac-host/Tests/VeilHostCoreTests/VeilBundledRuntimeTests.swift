import Foundation
import Testing

@testable import VeilHostCore

@Suite("Bundled Windows engine")
struct VeilBundledRuntimeTests {
    private let runtime = URL(fileURLWithPath: "/Applications/Veil.app/Contents/Resources/Runtime", isDirectory: true)

    @Test("the QEMU inside Veil.app wins over Homebrew")
    func bundledQEMUComesFirst() {
        let bundledQEMU = runtime.appendingPathComponent("bin/qemu-system-aarch64").path
        let probe = VMRuntimeProviderProbe(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            bundledRuntimeDirectory: runtime,
            fileExists: { $0 == bundledQEMU || $0 == "/opt/homebrew/bin/qemu-system-aarch64" },
            executableVersion: { _ in "QEMU emulator version 11.1.3" }
        )

        let qemu = probe.localProviders(architecture: "arm64", minimumOSSupported: true)
            .first { $0.kind == .qemuHypervisor }
        #expect(qemu?.executablePath == bundledQEMU)
        #expect(qemu?.status == .active)
    }

    @Test("an explicit QEMU override still beats the bundled engine")
    func overrideBeatsBundledQEMU() {
        let override = "/Users/test/qemu/bin/qemu-system-aarch64"
        let probe = VMRuntimeProviderProbe(
            environment: [VMRuntimeProviderProbe.qemuEnvironmentKey: override],
            bundledRuntimeDirectory: runtime,
            fileExists: { _ in true },
            executableVersion: { _ in "QEMU emulator version 11.1.3" }
        )

        let qemu = probe.localProviders(architecture: "arm64", minimumOSSupported: true)
            .first { $0.kind == .qemuHypervisor }
        #expect(qemu?.executablePath == override)
    }

    @Test("the bundled Secure Boot firmware and TPM emulator are checked first")
    func bundledFirmwareAndTPMComeFirst() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(LocalQEMUWindowsBootPlanFactory.defaultSecureFirmwarePaths(homeDirectory: home, bundledRuntimeDirectory: runtime).first
            == runtime.appendingPathComponent("share/qemu/edk2-aarch64-secure-code.fd").path)
        #expect(LocalQEMUWindowsBootPlanFactory.defaultSecureFirmwareVarsTemplatePaths(homeDirectory: home, bundledRuntimeDirectory: runtime).first
            == runtime.appendingPathComponent("share/qemu/edk2-arm-secure-vars.fd").path)
        #expect(LocalQEMUWindowsBootPlanFactory.tpmEmulatorPaths(environment: [:], homeDirectory: home, bundledRuntimeDirectory: runtime).first
            == runtime.appendingPathComponent("bin/swtpm").path)
    }

    @Test("a build without the runtime keeps the existing search order")
    func noBundleKeepsSearchOrder() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(VMRuntimeProviderProbe.qemuExecutablePaths(environment: [:], homeDirectory: home, bundledRuntimeDirectory: nil).first
            == "/Users/test/Library/Application Support/Veil/Runtime/bin/qemu-system-aarch64")
        #expect(VeilBundledRuntime.directory(bundle: .main, fileExists: { _ in false }) == nil)
    }
}
