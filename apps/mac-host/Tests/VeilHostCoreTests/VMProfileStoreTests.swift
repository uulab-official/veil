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
        #expect(snapshot.detail == "Ready to boot when VM boot support lands.")
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

    @Test("local runtime start reports that VM boot is not implemented")
    func localRuntimeStartReportsBootNotImplemented() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)

        await #expect(throws: VMRuntimeError.bootNotImplemented) {
            try await service.start()
        }
    }
}
