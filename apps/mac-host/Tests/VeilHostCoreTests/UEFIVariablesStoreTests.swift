import Foundation
import Testing

@testable import VeilHostCore

private struct StubInstallMediaBuilder: AutomaticInstallMediaBuilding {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("media".utf8).write(to: mediaURL)
    }
}

@Suite("UEFI variable store")
struct UEFIVariablesStoreTests {
    private struct Fixture {
        let service: LocalVMRuntimeService
        let diskURL: URL
        let varsURL: URL
    }

    private func makeFixture(diskContents: Data) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = directory.appendingPathComponent("Home", isDirectory: true)
        let firmware = directory.appendingPathComponent("Firmware", isDirectory: true)
        let vmDirectory = home.appendingPathComponent("Virtual Machines/Veil", isDirectory: true)
        try FileManager.default.createDirectory(at: firmware, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vmDirectory, withIntermediateDirectories: true)
        let template = firmware.appendingPathComponent("edk2-arm-secure-vars.fd")
        try Data("secure-vars-template".utf8).write(to: template)

        let diskURL = vmDirectory.appendingPathComponent("Windows 11 Arm.img")
        try diskContents.write(to: diskURL)
        let varsURL = vmDirectory.appendingPathComponent("uefi-vars.fd")
        try Data("Windows Boot Manager".utf8).write(to: varsURL)

        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400), homeDirectory: home)
        profile.virtualDiskPath = diskURL.path
        profile.windowsInstalled = false
        let store = JSONVMProfileStore(directory: directory)
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: home,
            automaticInstallMediaBuilder: StubInstallMediaBuilder(),
            firmwareVarsTemplatePaths: [template.path]
        )
        return Fixture(service: service, diskURL: diskURL, varsURL: varsURL)
    }

    @Test("a blank disk's variables are upgraded to the Secure Boot template")
    func blankDiskGetsSecureTemplate() async throws {
        let fixture = try await makeFixture(diskContents: Data("blank".utf8))

        _ = try await fixture.service.prepareDefaultVM()

        let vars = try String(contentsOf: fixture.varsURL, encoding: .utf8)
        #expect(vars.hasPrefix("secure-vars-template"))
    }

    @Test("variables stay once Windows Setup has written to the disk")
    func setupInProgressKeepsBootEntries() async throws {
        let setupWork = Data(repeating: 0xA5, count: Int(LocalVMRuntimeService.windowsSetupStartedAllocatedBytes))
        let fixture = try await makeFixture(diskContents: setupWork)

        _ = try await fixture.service.prepareDefaultVM()

        let vars = try String(contentsOf: fixture.varsURL, encoding: .utf8)
        #expect(vars == "Windows Boot Manager")
    }
}
