import Foundation
import Testing

@testable import VeilHostCore

@Suite("Machine settings")
struct MachineSettingsTests {
    private let gigabyte: UInt64 = 1_024 * 1_024 * 1_024

    @Test("limits leave the Mac a core and a quarter of its memory")
    func limitsReserveHostResources() {
        let limits = VMResourceLimits(processorCount: 10, physicalMemoryBytes: 32 * gigabyte)
        #expect(limits.maximumCPUCount == 9)
        #expect(limits.maximumMemoryMB == 24 * 1_024)

        let small = VMResourceLimits(processorCount: 2, physicalMemoryBytes: 8 * gigabyte)
        #expect(small.maximumCPUCount == 2)
        #expect(small.maximumMemoryMB == 4_096)
    }

    @Test("requested sizes are clamped to Windows' minimum and the Mac's maximum")
    func clampsRequestedSizes() {
        let limits = VMResourceLimits(processorCount: 10, physicalMemoryBytes: 32 * gigabyte)
        #expect(limits.clampedCPUCount(1) == 2)
        #expect(limits.clampedCPUCount(64) == 9)
        #expect(limits.clampedMemoryMB(1_000) == 4_096)
        #expect(limits.clampedMemoryMB(9_000) == 9_216)
        #expect(limits.clampedMemoryMB(1_000_000) == 24 * 1_024)
    }

    @Test("hardware and startup behavior are saved to the profile")
    func savesSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = directory.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        try await store.save(VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400), homeDirectory: home))
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: home,
            resourceLimits: VMResourceLimits(processorCount: 10, physicalMemoryBytes: 32 * gigabyte)
        )

        let hardware = try await service.updateHardware(cpuCount: 6, memoryMB: 12 * 1_024)
        #expect(hardware.cpuCount == 6)
        #expect(hardware.memoryMB == 12 * 1_024)

        let startup = try await service.updateStartupBehavior(autoStart: false, suspendOnQuit: true)
        #expect(startup.autoStart == false)
        #expect(startup.suspendOnQuit == true)
        let profile = try #require(await store.load())
        #expect(profile.cpuCount == 6)
        #expect(profile.autoStart == false)
    }
}
