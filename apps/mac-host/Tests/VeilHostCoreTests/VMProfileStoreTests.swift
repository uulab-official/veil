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
    }

    @Test("local runtime service reports stopped when profile exists")
    func localRuntimeReportsStoppedProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.detail == "Ready to boot when VM boot support lands.")
    }
}
