import Foundation
import Testing

@testable import VeilHostCore

private struct StubInstallMediaBuilder: AutomaticInstallMediaBuilding {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("media".utf8).write(to: mediaURL)
    }
}

private final class DiscardLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func record(_ url: URL) throws {
        lock.withLock { names.append(url.lastPathComponent) }
        try FileManager.default.removeItem(at: url)
    }

    var discarded: [String] {
        lock.withLock { names }
    }
}

@Suite("Restart Windows installation")
struct RestartWindowsInstallationTests {
    private struct Fixture {
        let store: JSONVMProfileStore
        let service: LocalVMRuntimeService
        let log: DiscardLog
        let diskURL: URL
        let vmDirectory: URL
    }

    private func makeFixture(windowsInstalled: Bool) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = directory.appendingPathComponent("Home", isDirectory: true)
        let firmware = directory.appendingPathComponent("Firmware", isDirectory: true)
        let vmDirectory = home.appendingPathComponent("Virtual Machines/Veil", isDirectory: true)
        try FileManager.default.createDirectory(at: firmware, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vmDirectory.appendingPathComponent("tpm"), withIntermediateDirectories: true)
        let template = firmware.appendingPathComponent("edk2-arm-secure-vars.fd")
        try Data("secure-vars-template".utf8).write(to: template)

        let diskURL = vmDirectory.appendingPathComponent("Windows 11 Arm.img")
        try Data("half-installed windows".utf8).write(to: diskURL)
        try Data("stale boot entries".utf8).write(to: vmDirectory.appendingPathComponent("uefi-vars.fd"))
        try Data("old tpm".utf8).write(to: vmDirectory.appendingPathComponent("tpm/tpm2-00.permall"))

        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400), homeDirectory: home)
        profile.virtualDiskPath = diskURL.path
        profile.windowsInstalled = windowsInstalled
        let store = JSONVMProfileStore(directory: directory)
        try await store.save(profile)

        let log = DiscardLog()
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: home,
            automaticInstallMediaBuilder: StubInstallMediaBuilder(),
            firmwareVarsTemplatePaths: [template.path],
            installationDiscarder: { try log.record($0) }
        )
        return Fixture(store: store, service: service, log: log, diskURL: diskURL, vmDirectory: vmDirectory)
    }

    @Test("an unfinished install gets a blank disk, fresh UEFI variables, and an empty TPM")
    func resetsUnfinishedInstall() async throws {
        let fixture = try await makeFixture(windowsInstalled: false)

        _ = try await fixture.service.restartWindowsInstallation()

        #expect(Set(fixture.log.discarded) == ["Windows 11 Arm.img", "uefi-vars.fd", "tpm"])
        let profile = try #require(await fixture.store.load())
        #expect(profile.virtualDiskPath == fixture.diskURL.path)
        #expect(profile.windowsInstalled == false)

        let diskSize = try #require(try FileManager.default.attributesOfItem(atPath: fixture.diskURL.path)[.size] as? UInt64)
        #expect(diskSize == UInt64(profile.diskGB) * 1_024 * 1_024 * 1_024)
        let vars = try String(contentsOf: fixture.vmDirectory.appendingPathComponent("uefi-vars.fd"), encoding: .utf8)
        #expect(vars.hasPrefix("secure-vars-template"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.vmDirectory.appendingPathComponent("tpm").path).isEmpty)
    }

    @Test("an installed Windows is never erased")
    func refusesInstalledWindows() async throws {
        let fixture = try await makeFixture(windowsInstalled: true)

        await #expect(throws: VMRuntimeError.restartInstallationRequiresUninstalledWindows) {
            _ = try await fixture.service.restartWindowsInstallation()
        }
        #expect(fixture.log.discarded.isEmpty)
        #expect(try String(contentsOf: fixture.diskURL, encoding: .utf8) == "half-installed windows")
    }
}
