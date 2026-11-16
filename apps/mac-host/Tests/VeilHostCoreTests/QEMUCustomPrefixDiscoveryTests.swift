import Foundation
import Testing

@testable import VeilHostCore

@Suite("QEMU discovery under custom Homebrew prefixes")
struct QEMUCustomPrefixDiscoveryTests {
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    @Test("finds QEMU installed under a home-directory Homebrew prefix")
    func findsQEMUUnderHomeHomebrewPrefix() {
        let probe = VMRuntimeProviderProbe(
            environment: [:],
            homeDirectory: home,
            fileExists: { $0 == "/Users/test/homebrew/bin/qemu-system-aarch64" },
            executableVersion: { _ in "QEMU emulator version 11.0.2" }
        )

        let qemu = probe.localProviders(architecture: "arm64", minimumOSSupported: true)
            .first { $0.kind == .qemuHypervisor }

        #expect(qemu?.status == .active)
        #expect(qemu?.executablePath == "/Users/test/homebrew/bin/qemu-system-aarch64")
    }

    @Test("standard prefixes still win over custom prefixes")
    func standardPrefixWins() {
        let probe = VMRuntimeProviderProbe(
            environment: ["HOMEBREW_PREFIX": "/Volumes/Tools/brew"],
            homeDirectory: home,
            fileExists: {
                $0 == "/opt/homebrew/bin/qemu-system-aarch64"
                    || $0 == "/Volumes/Tools/brew/bin/qemu-system-aarch64"
            },
            executableVersion: { _ in "QEMU emulator version 11.0.2" }
        )

        let qemu = probe.localProviders(architecture: "arm64", minimumOSSupported: true)
            .first { $0.kind == .qemuHypervisor }

        #expect(qemu?.executablePath == "/opt/homebrew/bin/qemu-system-aarch64")
    }

    @Test("custom prefixes are deduplicated and skip standard ones")
    func prefixesAreDeduplicated() {
        let prefixes = VMRuntimeProviderProbe.userPackagePrefixes(
            environment: ["HOMEBREW_PREFIX": "/Users/test/homebrew"],
            homeDirectory: home
        )
        #expect(prefixes == ["/Users/test/homebrew", "/Users/test/.homebrew"])

        let standard = VMRuntimeProviderProbe.userPackagePrefixes(
            environment: ["HOMEBREW_PREFIX": "/opt/homebrew"],
            homeDirectory: home
        )
        #expect(!standard.contains("/opt/homebrew"))
    }

    @Test("boot plan uses firmware and swtpm shipped beside a custom-prefix QEMU")
    func bootPlanUsesFirmwareBesideCustomPrefixQEMU() throws {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_25H2_Arm64.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"

        let existing: Set<String> = [
            "/Users/test/homebrew/bin/qemu-system-aarch64",
            "/Users/test/homebrew/share/qemu/edk2-aarch64-code.fd",
            "/Users/test/homebrew/share/qemu/edk2-arm-vars.fd",
            "/Users/test/homebrew/bin/swtpm",
            "/Users/test/Virtual Machines/Veil/uefi-vars.fd"
        ]

        let plan = try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: "arm64",
            minimumOSSupported: true,
            providerProbe: VMRuntimeProviderProbe(
                environment: [:],
                homeDirectory: home,
                fileExists: { existing.contains($0) },
                executableVersion: { _ in "QEMU emulator version 11.0.2" }
            ),
            homeDirectory: home,
            fileExists: { existing.contains($0) },
            secureFirmwarePaths: [],
            secureVarsTemplatePaths: [],
            isHostPortFree: { _ in true },
            environment: [:]
        )

        #expect(plan.executablePath == "/Users/test/homebrew/bin/qemu-system-aarch64")
        #expect(plan.firmwarePath == "/Users/test/homebrew/share/qemu/edk2-aarch64-code.fd")
        #expect(plan.firmwareVarsTemplatePath == "/Users/test/homebrew/share/qemu/edk2-arm-vars.fd")
        #expect(plan.tpmEmulatorPath == "/Users/test/homebrew/bin/swtpm")
    }

    @Test("UEFI variable templates include custom prefixes after the standard ones")
    func varsTemplatesIncludeCustomPrefixes() {
        let paths = LocalQEMUWindowsBootPlanFactory.firmwareVarsTemplatePaths(environment: [:], homeDirectory: home)
        #expect(Array(paths.prefix(3)) == LocalQEMUWindowsBootPlanFactory.defaultFirmwareVarsTemplatePaths)
        #expect(paths.contains("/Users/test/homebrew/share/qemu/edk2-arm-vars.fd"))
    }
}
