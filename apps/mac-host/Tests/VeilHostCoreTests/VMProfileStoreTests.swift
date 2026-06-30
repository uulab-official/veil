import Foundation
import Testing

@testable import VeilHostCore

@Suite("VM profile store")
struct VMProfileStoreTests {
    @Test("saves and loads a profile as JSON")
    func savesAndLoadsProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))

        try await store.save(profile)
        let loaded = try await store.load()

        #expect(loaded == profile)
        #expect(loaded?.name == "Windows 11 Arm")
        #expect(loaded?.memoryMB == 8192)
        #expect(loaded?.sharedFolderPath.hasSuffix("Veil Shared") == true)
        #expect(loaded?.installerMediaPath == nil)
        #expect(loaded?.virtualDiskPath == nil)
    }

    @Test("preserves installer media and virtual disk paths")
    func preservesBootPaths() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = "/Users/test/Downloads/Windows.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Windows.vhdx"

        try await store.save(profile)
        let loaded = try await store.load()

        #expect(loaded?.installerMediaPath == "/Users/test/Downloads/Windows.iso")
        #expect(loaded?.virtualDiskPath == "/Users/test/Virtual Machines/Windows.vhdx")
    }

    @Test("local runtime service reports stopped when profile exists")
    func localRuntimeReportsStoppedProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(
            createdAt: Date(timeIntervalSince1970: 1_782_752_400),
            homeDirectory: directory.appendingPathComponent("Home", isDirectory: true)
        )
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.bootReady == false)
        #expect(snapshot.detail == "Installer media and virtual disk paths are required before boot.")
        #expect(snapshot.installationSteps.map(\.id) == [
            "windows-installer",
            "virtual-disk",
            "shared-folder",
            "guest-agent"
        ])
        #expect(snapshot.installationSteps.map(\.state) == [
            .blocked,
            .blocked,
            .blocked,
            .pending
        ])
    }

    @Test("local runtime reports boot ready when profile paths exist")
    func localRuntimeReportsBootReadyProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.installerMediaPath == installerURL.path)
        #expect(snapshot.virtualDiskPath == diskURL.path)
        #expect(snapshot.bootReady)
        #expect(snapshot.detail == "Ready to start Windows.")
        #expect(snapshot.installationSteps.map(\.state) == [
            .complete,
            .complete,
            .complete,
            .pending
        ])
        #expect(snapshot.preflightChecks.map(\.state) == [
            .passed,
            .passed,
            .passed,
            .passed
        ])
    }

    @Test("local runtime is not boot ready when VM profile resources are invalid")
    func localRuntimeRejectsInvalidProfileResources() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.os = "windows-x86_64"
        profile.cpuCount = 1
        profile.memoryMB = 2048
        profile.diskGB = 32
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.bootReady == false)
        #expect(snapshot.detail == "VM profile needs attention before boot.")
        #expect(snapshot.preflightChecks.map(\.id) == [
            "guest-os",
            "cpu",
            "memory",
            "disk-size"
        ])
        #expect(snapshot.preflightChecks.map(\.state) == [
            .failed,
            .failed,
            .failed,
            .failed
        ])
    }

    @Test("creates shared folder when creating default profile")
    func createsSharedFolderForDefaultProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.createDefaultProfile()
        let profile = try #require(await store.load())
        var isDirectory: ObjCBool = false

        #expect(FileManager.default.fileExists(atPath: profile.sharedFolderPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(profile.sharedFolderPath == homeDirectory.appendingPathComponent("Veil Shared").path)
        #expect(snapshot.installationSteps.first { $0.id == "shared-folder" }?.state == .complete)
    }

    @Test("creates default virtual disk file and updates profile")
    func createsDefaultVirtualDiskFileAndUpdatesProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.createDefaultVirtualDisk()
        let profile = try #require(await store.load())
        let diskPath = try #require(profile.virtualDiskPath)
        var isDirectory: ObjCBool = false

        #expect(diskPath == homeDirectory
            .appendingPathComponent("Virtual Machines", isDirectory: true)
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Windows 11 Arm.img").path)
        #expect(FileManager.default.fileExists(atPath: diskPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue == false)
        #expect(snapshot.virtualDiskPath == diskPath)
        #expect(snapshot.installationSteps.first { $0.id == "virtual-disk" }?.state == .complete)
    }

    @Test("default virtual disk creation preserves an existing configured disk")
    func defaultVirtualDiskCreationPreservesExistingConfiguredDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existingDiskURL = directory.appendingPathComponent("Existing.vhdx")
        try Data("existing".utf8).write(to: existingDiskURL)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(homeDirectory: homeDirectory)
        profile.virtualDiskPath = existingDiskURL.path
        try await store.save(profile)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.createDefaultVirtualDisk()
        let storedProfile = try #require(await store.load())
        let attributes = try FileManager.default.attributesOfItem(atPath: existingDiskURL.path)
        let fileSize = try #require(attributes[.size] as? UInt64)

        #expect(storedProfile.virtualDiskPath == existingDiskURL.path)
        #expect(snapshot.virtualDiskPath == existingDiskURL.path)
        #expect(fileSize == UInt64(Data("existing".utf8).count))
    }

    @Test("local runtime is not boot ready when stored paths are missing")
    func localRuntimeRejectsMissingBootPaths() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = directory.appendingPathComponent("Missing.iso").path
        profile.virtualDiskPath = directory.appendingPathComponent("Missing.vhdx").path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.bootReady == false)
        #expect(snapshot.detail == "Installer media path does not exist.")
    }

    @Test("local runtime is not boot ready when stored paths are directories")
    func localRuntimeRejectsDirectoryBootPaths() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installerDirectory = directory.appendingPathComponent("Windows.iso", isDirectory: true)
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        try FileManager.default.createDirectory(at: installerDirectory, withIntermediateDirectories: true)
        try Data("disk".utf8).write(to: diskURL)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerDirectory.path
        profile.virtualDiskPath = diskURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.bootReady == false)
        #expect(snapshot.detail == "Installer media path must reference a file.")
    }

    @Test("local runtime starts a boot-ready profile")
    func localRuntimeStartsBootReadyProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running)

        let service = LocalVMRuntimeService(profileStore: store, bootRunner: bootRunner)

        let snapshot = try await service.start()

        #expect(snapshot.state == .running)
        #expect(snapshot.detail == "Windows VM is running.")
        #expect(bootRunner.startCount == 1)
        #expect(bootRunner.startedProfile?.installerMediaPath == installerURL.path)
        #expect(bootRunner.startedProfile?.virtualDiskPath == diskURL.path)
    }

    @Test("local runtime stops a running profile")
    func localRuntimeStopsRunningProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running, currentState: .running)

        let service = LocalVMRuntimeService(profileStore: store, bootRunner: bootRunner)

        let snapshot = try await service.stop()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.detail == "Windows VM is stopped.")
        #expect(bootRunner.stopCount == 1)
    }

    @Test("local runtime start rejects profiles that are not boot ready")
    func localRuntimeStartRejectsProfilesThatAreNotBootReady() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running)

        let service = LocalVMRuntimeService(profileStore: store, bootRunner: bootRunner)

        await #expect(throws: VMRuntimeError.bootPrerequisitesMissing) {
            try await service.start()
        }
        #expect(bootRunner.startCount == 0)
    }
}

private final class FakeVMRuntimeBooter: VMRuntimeBooting, @unchecked Sendable {
    var startState: VMRuntimeState
    var currentState: VMRuntimeState?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var startedProfile: VMProfile?

    init(startState: VMRuntimeState, currentState: VMRuntimeState? = nil) {
        self.startState = startState
        self.currentState = currentState
    }

    func runtimeState() async -> VMRuntimeState? {
        currentState
    }

    func start(profile: VMProfile) async throws -> VMRuntimeState {
        startCount += 1
        startedProfile = profile
        currentState = startState
        return startState
    }

    func stop() async throws -> VMRuntimeState {
        stopCount += 1
        currentState = .stopped
        return .stopped
    }
}
