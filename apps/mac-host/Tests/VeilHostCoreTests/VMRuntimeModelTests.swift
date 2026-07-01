import Foundation
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

    @Test("prepares default VM and refreshes runtime state")
    @MainActor
    func preparesDefaultVMAndRefreshesRuntimeState() async throws {
        let service = FakeVMRuntimeService(
            preparedSnapshot: VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: nil,
                virtualDiskPath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img",
                bootReady: false,
                detail: "Select a Windows 11 Arm installer before setup can continue."
            )
        )
        let model = VMRuntimeModel(service: service)

        await model.prepareDefaultVM()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.profileName == "Windows 11 Arm")
        #expect(model.snapshot?.virtualDiskPath == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img")
        #expect(service.prepareCount == 1)
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
                detail: "Ready to start Windows."
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

    @Test("creates default virtual disk through the service boundary")
    @MainActor
    func createsDefaultVirtualDiskThroughServiceBoundary() async throws {
        let service = FakeVMRuntimeService(
            diskSnapshot: VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: nil,
                virtualDiskPath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img",
                bootReady: false,
                detail: "Select a Windows 11 Arm installer before setup can continue."
            )
        )
        let model = VMRuntimeModel(service: service)

        await model.createDefaultVirtualDisk()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.virtualDiskPath == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img")
        #expect(service.createDiskCount == 1)
    }

    @Test("starts runtime through the service boundary")
    @MainActor
    func startsRuntimeThroughServiceBoundary() async throws {
        let service = FakeVMRuntimeService(
            startedSnapshot: VMRuntimeSnapshot(
                state: .starting,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: "/Users/test/Downloads/Windows.iso",
                virtualDiskPath: "/Users/test/Virtual Machines/Windows.vhdx",
                bootReady: true,
                detail: "VM boot requested."
            )
        )
        let model = VMRuntimeModel(service: service)

        await model.start()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.state == .starting)
        #expect(model.statusText == "VM starting")
        #expect(service.startCount == 1)
    }

    @Test("stops runtime through the service boundary")
    @MainActor
    func stopsRuntimeThroughServiceBoundary() async throws {
        let service = FakeVMRuntimeService(
            stoppedSnapshot: VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: "arm64",
                minimumOSSupported: true,
                profileName: "Windows 11 Arm",
                installerMediaPath: "/Users/test/Downloads/Windows.iso",
                virtualDiskPath: "/Users/test/Virtual Machines/Windows.vhdx",
                bootReady: true,
                detail: "Windows VM is stopped."
            )
        )
        let model = VMRuntimeModel(service: service)

        await model.stop()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.state == .stopped)
        #expect(model.statusText == "VM stopped")
        #expect(service.stopCount == 1)
    }

    @Test("reports stop availability for running VMs")
    @MainActor
    func reportsStopAvailabilityForRunningVMs() async throws {
        let model = VMRuntimeModel(
            service: FakeVMRuntimeService(
                snapshot: VMRuntimeSnapshot(
                    state: .running,
                    virtualizationAvailable: true,
                    architecture: "arm64",
                    minimumOSSupported: true,
                    profileName: "Windows 11 Arm",
                    installerMediaPath: "/Users/test/Downloads/Windows.iso",
                    virtualDiskPath: "/Users/test/Virtual Machines/Windows.vhdx",
                    bootReady: true,
                    detail: "Windows VM is running."
                )
            )
        )

        await model.load()

        #expect(model.canStop)
        #expect(model.canStart == false)
    }

    @Test("stores start errors")
    @MainActor
    func storesStartErrors() async throws {
        let model = VMRuntimeModel(service: FakeVMRuntimeService(error: VMRuntimeError.bootNotImplemented))

        await model.start()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "VM boot is not implemented yet.")
    }

    @Test("exports diagnostics through the service boundary")
    @MainActor
    func exportsDiagnosticsThroughServiceBoundary() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/veil-vm-diagnostics.json")
        let directory = URL(fileURLWithPath: "/tmp/VeilDiagnostics", isDirectory: true)
        let service = FakeVMRuntimeService(diagnosticsURL: outputURL)
        let model = VMRuntimeModel(service: service)

        await model.exportDiagnostics(to: directory)

        #expect(model.phase == .loaded)
        #expect(model.diagnosticsURL == outputURL)
        #expect(model.errorMessage == nil)
        #expect(service.diagnosticsDirectory == directory)
    }
}

@MainActor
private final class FakeVMRuntimeService: VMRuntimeService {
    var snapshot: VMRuntimeSnapshot?
    var createdSnapshot: VMRuntimeSnapshot?
    var diskSnapshot: VMRuntimeSnapshot?
    var preparedSnapshot: VMRuntimeSnapshot?
    var updatedSnapshot: VMRuntimeSnapshot?
    var startedSnapshot: VMRuntimeSnapshot?
    var stoppedSnapshot: VMRuntimeSnapshot?
    var diagnosticsURL: URL?
    var error: (any Error)?
    private(set) var updatedInstallerMediaPath: String?
    private(set) var updatedVirtualDiskPath: String?
    private(set) var createCount = 0
    private(set) var createDiskCount = 0
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var diagnosticsDirectory: URL?

    init(
        snapshot: VMRuntimeSnapshot? = nil,
        createdSnapshot: VMRuntimeSnapshot? = nil,
        diskSnapshot: VMRuntimeSnapshot? = nil,
        preparedSnapshot: VMRuntimeSnapshot? = nil,
        updatedSnapshot: VMRuntimeSnapshot? = nil,
        startedSnapshot: VMRuntimeSnapshot? = nil,
        stoppedSnapshot: VMRuntimeSnapshot? = nil,
        diagnosticsURL: URL? = nil,
        error: (any Error)? = nil
    ) {
        self.snapshot = snapshot
        self.createdSnapshot = createdSnapshot
        self.diskSnapshot = diskSnapshot
        self.preparedSnapshot = preparedSnapshot
        self.updatedSnapshot = updatedSnapshot
        self.startedSnapshot = startedSnapshot
        self.stoppedSnapshot = stoppedSnapshot
        self.diagnosticsURL = diagnosticsURL
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

    func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        createDiskCount += 1
        let diskSnapshot = try #require(diskSnapshot)
        snapshot = diskSnapshot
        return diskSnapshot
    }

    func prepareDefaultVM() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        prepareCount += 1
        let preparedSnapshot = try #require(preparedSnapshot)
        snapshot = preparedSnapshot
        return preparedSnapshot
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

    func start() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        startCount += 1
        let startedSnapshot = try #require(startedSnapshot)
        snapshot = startedSnapshot
        return startedSnapshot
    }

    func stop() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        stopCount += 1
        let stoppedSnapshot = try #require(stoppedSnapshot)
        snapshot = stoppedSnapshot
        return stoppedSnapshot
    }

    func exportDiagnostics(to directory: URL) async throws -> URL {
        if let error {
            throw error
        }

        diagnosticsDirectory = directory
        return try #require(diagnosticsURL)
    }
}
