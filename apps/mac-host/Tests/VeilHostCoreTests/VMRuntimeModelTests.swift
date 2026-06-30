import Testing

@testable import VeilHostCore

@Suite("VM runtime model")
struct VMRuntimeModelTests {
    @Test("loads supported host with no configured VM profile")
    @MainActor
    func loadsSupportedHostWithoutProfile() async throws {
        let model = VMRuntimeModel(
            service: FakeVMRuntimeService(
                snapshot: VMRuntimeSnapshot(
                    state: .notConfigured,
                    virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: nil,
                installerMediaPath: nil,
                virtualDiskPath: nil,
                bootReady: false,
                detail: "No Windows VM profile has been created."
            )
            )
        )

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.state == .notConfigured)
        #expect(model.statusText == "VM profile not configured")
        #expect(model.canStart == false)
        #expect(model.capabilitySummary == "Virtualization.framework available on arm64")
    }

    @Test("loads unsupported host capability message")
    @MainActor
    func loadsUnsupportedHostCapabilityMessage() async throws {
        let model = VMRuntimeModel(
            service: FakeVMRuntimeService(
                snapshot: VMRuntimeSnapshot(
                    state: .unsupported,
                    virtualizationAvailable: false,
                    architecture: "x86_64",
                    minimumOSSupported: false,
                    profileName: nil,
                    installerMediaPath: nil,
                    virtualDiskPath: nil,
                    bootReady: false,
                    detail: "Veil requires macOS 15+ on Apple Silicon."
                )
            )
        )

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.statusText == "VM runtime unsupported")
        #expect(model.canStart == false)
        #expect(model.capabilitySummary == "Virtualization.framework unavailable on x86_64")
    }

    @Test("stores service errors")
    @MainActor
    func storesServiceErrors() async throws {
        let model = VMRuntimeModel(service: FakeVMRuntimeService(error: VMRuntimeError.capabilityProbeFailed))

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Unable to inspect VM runtime capabilities.")
    }

    @Test("creates default profile and refreshes runtime state")
    @MainActor
    func createsDefaultProfileAndRefreshesRuntimeState() async throws {
        let service = FakeVMRuntimeService(
            snapshot: VMRuntimeSnapshot(
                state: .notConfigured,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: nil,
                installerMediaPath: nil,
                virtualDiskPath: nil,
                bootReady: false,
                detail: "No Windows VM profile has been created."
            ),
            createdSnapshot: VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: nil,
                virtualDiskPath: nil,
                bootReady: false,
                detail: "Installer media and virtual disk paths are required before boot."
            )
        )
        let model = VMRuntimeModel(service: service)

        await model.createDefaultProfile()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.state == .stopped)
        #expect(model.snapshot?.profileName == "Windows 11 Arm")
        #expect(model.canStart == false)
        #expect(service.createCount == 1)
    }

    @Test("updates profile paths and refreshes boot readiness")
    @MainActor
    func updatesProfilePathsAndRefreshesBootReadiness() async throws {
        let service = FakeVMRuntimeService(
            snapshot: VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: nil,
                virtualDiskPath: nil,
                bootReady: false,
                detail: "Installer media and virtual disk paths are required before boot."
            ),
            updatedSnapshot: VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: "/Users/test/Downloads/Windows.iso",
                virtualDiskPath: "/Users/test/Virtual Machines/Windows.vhdx",
                bootReady: true,
                detail: "Ready to boot when VM boot support lands."
            )
        )
        let model = VMRuntimeModel(service: service)

        await model.updateProfilePaths(
            installerMediaPath: "/Users/test/Downloads/Windows.iso",
            virtualDiskPath: "/Users/test/Virtual Machines/Windows.vhdx"
        )

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.bootReady == true)
        #expect(model.canStart)
        #expect(service.updatedInstallerMediaPath == "/Users/test/Downloads/Windows.iso")
        #expect(service.updatedVirtualDiskPath == "/Users/test/Virtual Machines/Windows.vhdx")
    }
}

@MainActor
private final class FakeVMRuntimeService: VMRuntimeService {
    var snapshot: VMRuntimeSnapshot?
    var createdSnapshot: VMRuntimeSnapshot?
    var updatedSnapshot: VMRuntimeSnapshot?
    var error: (any Error)?
    private(set) var updatedInstallerMediaPath: String?
    private(set) var updatedVirtualDiskPath: String?
    private(set) var createCount = 0

    init(
        snapshot: VMRuntimeSnapshot? = nil,
        createdSnapshot: VMRuntimeSnapshot? = nil,
        updatedSnapshot: VMRuntimeSnapshot? = nil,
        error: (any Error)? = nil
    ) {
        self.snapshot = snapshot
        self.createdSnapshot = createdSnapshot
        self.updatedSnapshot = updatedSnapshot
        self.error = error
    }

    func loadSnapshot() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        return try #require(snapshot)
    }

    func createDefaultProfile() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        createCount += 1
        let createdSnapshot = try #require(createdSnapshot)
        snapshot = createdSnapshot
        return createdSnapshot
    }

    func updateProfilePaths(installerMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        updatedInstallerMediaPath = installerMediaPath
        updatedVirtualDiskPath = virtualDiskPath
        let updatedSnapshot = try #require(updatedSnapshot)
        snapshot = updatedSnapshot
        return updatedSnapshot
    }
}
