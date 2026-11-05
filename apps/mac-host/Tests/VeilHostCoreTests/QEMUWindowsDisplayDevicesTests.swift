import Foundation
import Testing

@testable import VeilHostCore

@Suite("QEMU Windows display devices")
struct QEMUWindowsDisplayDevicesTests {
    @Test("setup and Windows without viogpudo keep ramfb ahead of virtio-gpu")
    func ramfbUntilTheDriverIsReported() throws {
        var profile = Self.profile(installed: false)
        profile.virtioGPUDriverInstalled = true
        profile.bootsOnVirtioGPU = true
        #expect(try Self.displayDevices(profile) == ["ramfb", "virtio-gpu-pci"])

        profile = Self.profile(installed: true)
        #expect(try Self.displayDevices(profile) == ["ramfb", "virtio-gpu-pci"])
        #expect(!QEMUWindowsDisplayDevices.bootsOnVirtioGPU(profile))
    }

    @Test("an installed Windows with viogpudo boots on virtio-gpu alone after a cold start chose it")
    func virtioGPUAloneOnceChosen() throws {
        var profile = Self.profile(installed: true)
        profile.virtioGPUDriverInstalled = true
        #expect(QEMUWindowsDisplayDevices.bootsOnVirtioGPU(profile))
        // The live report alone does not change the plan; only a cold start stores the choice.
        #expect(try Self.displayDevices(profile) == ["ramfb", "virtio-gpu-pci"])

        profile.bootsOnVirtioGPU = true
        #expect(try Self.displayDevices(profile) == ["virtio-gpu-pci"])
    }

    private static func profile(installed: Bool) -> VMProfile {
        var profile = VMProfile.defaultWindows11Arm(
            createdAt: Date(timeIntervalSince1970: 1_782_752_400),
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )
        profile.installerMediaPath = "/Users/test/Downloads/Win11_Arm64.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.windowsInstalled = installed
        return profile
    }

    /// The display `-device` values in plan order, with input and storage devices filtered out.
    private static func displayDevices(_ profile: VMProfile) throws -> [String] {
        let plan = try QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true
        ).makePlan(for: profile)
        let arguments = plan.arguments
        return arguments.indices.compactMap { index in
            guard arguments[index] == "-device", arguments.indices.contains(index + 1) else {
                return nil
            }
            let device = arguments[index + 1]
            return device == "ramfb" || device == "virtio-gpu-pci" ? device : nil
        }
    }
}
