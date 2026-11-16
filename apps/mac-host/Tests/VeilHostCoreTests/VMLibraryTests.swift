import Foundation
import Testing
@testable import VeilHostCore

/// Every test builds its own Application Support and home folders, so nothing touches the real
/// `~/Virtual Machines/Veil` or `~/Library/Application Support/Veil`.
private struct LibrarySandbox {
    let root: URL
    let support: URL
    let home: URL
    var nextID = 0

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VMLibraryTests-\(UUID().uuidString)", isDirectory: true)
        support = root.appendingPathComponent("Support", isDirectory: true)
        home = root.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func library(diskInUse: Bool = false) -> VMLibrary {
        let counter = IDCounter()
        return VMLibrary(
            applicationSupportDirectory: support,
            homeDirectory: home,
            isDiskInUse: { _ in diskInUse },
            now: { Date(timeIntervalSince1970: 1_793_000_000) },
            makeID: { counter.next() }
        )
    }

    /// The single-machine layout Veil wrote before the library existed.
    @discardableResult
    func writeLegacyMachine() throws -> VMProfile {
        let vmDirectory = home.appendingPathComponent("Virtual Machines/Veil", isDirectory: true)
        try FileManager.default.createDirectory(at: vmDirectory.appendingPathComponent("tpm"), withIntermediateDirectories: true)
        try Data("legacy-disk".utf8).write(to: vmDirectory.appendingPathComponent("Windows 11 Arm.img"))
        try Data("legacy-vars".utf8).write(to: vmDirectory.appendingPathComponent("uefi-vars.fd"))
        try Data("legacy-tpm".utf8).write(to: vmDirectory.appendingPathComponent("tpm/tpm2-00.permall"))
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_780_000_000), homeDirectory: home)
        profile.virtualDiskPath = vmDirectory.appendingPathComponent("Windows 11 Arm.img").path
        profile.installerMediaPath = home.appendingPathComponent("Downloads/Win11_Arm64.iso").path
        profile.windowsInstalled = true
        let profiles = support.appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        try JSONEncoder.veilDiagnostics.encode(profile)
            .write(to: profiles.appendingPathComponent("default-vm-profile.json"))
        return profile
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class IDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return "vm_test\(value)"
    }
}

private final class DiscardLog: @unchecked Sendable {
    var urls: [URL] = []
}

struct VMLibraryTests {
    @Test("the pre-library machine stays where it was and becomes the first machine")
    func legacyMachineIsReferencedInPlace() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeLegacyMachine()
        let legacyProfileURL = sandbox.support.appendingPathComponent("Profiles/default-vm-profile.json")
        let legacyBytes = try Data(contentsOf: legacyProfileURL)
        let library = sandbox.library()

        #expect(library.activeMachineID() == VMLibrary.legacyMachineID)
        #expect(library.machines().map(\.id) == [VMLibrary.legacyMachineID])

        let second = try library.createMachine(name: "Work PC", resourcePlan: VMResourcePlan(cpuCount: 4, memoryMB: 8_192, diskGB: 64))

        #expect(library.machines().map(\.id) == [VMLibrary.legacyMachineID, second.id])
        #expect(library.activeMachineID() == second.id)
        #expect(try Data(contentsOf: legacyProfileURL) == legacyBytes)
        #expect(FileManager.default.fileExists(atPath: sandbox.home.appendingPathComponent("Virtual Machines/Veil/Windows 11 Arm.img").path))
        let legacy = try library.machine(id: VMLibrary.legacyMachineID)
        #expect(legacy.isLegacyMachine)
        #expect(legacy.diagnosticsDirectory == sandbox.support.appendingPathComponent("Diagnostics", isDirectory: true))
        #expect(legacy.machineDirectory.path == sandbox.home.appendingPathComponent("Virtual Machines/Veil").path)
    }

    @Test("each machine has its own profile, diagnostics, and disk folder")
    func machinesHaveSeparateState() async throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        let library = sandbox.library()
        let first = try library.createMachine(name: "One")
        let second = try library.createMachine(name: "Two")

        #expect(library.profileURL(for: first.id) != library.profileURL(for: second.id))
        #expect(library.diagnosticsDirectory(for: first.id) != library.diagnosticsDirectory(for: second.id))
        #expect(library.diagnosticsDirectory(for: second.id).path.hasSuffix("Machines/\(second.id)/Diagnostics"))
        #expect(library.defaultMachineDirectory(for: second.id).path.hasSuffix("Virtual Machines/Veil Machines/\(second.id)"))
        #expect(library.diagnosticsDirectory(for: VMLibrary.legacyMachineID).lastPathComponent == "Diagnostics")

        try library.select(id: first.id)
        #expect(library.activeMachineID() == first.id)
        let store = JSONVMProfileStore(directory: library.profileURL(for: first.id).deletingLastPathComponent(), fileName: "\(first.id).json")
        #expect(try await store.load()?.name == "One")
    }

    @Test("a new library machine's disk lands in its own folder, not the legacy one")
    func newMachineDiskPath() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        let service = LocalVMRuntimeService(defaultHomeDirectory: sandbox.home)
        var profile = VMProfile.defaultWindows11Arm(homeDirectory: sandbox.home)
        #expect(service.defaultVirtualDiskURL(for: profile).path
            == sandbox.home.appendingPathComponent("Virtual Machines/Veil/Windows 11 Arm.img").path)
        profile.id = "vm_test1"
        #expect(service.defaultVirtualDiskURL(for: profile).path
            == sandbox.home.appendingPathComponent("Virtual Machines/Veil Machines/vm_test1/Windows.img").path)
    }

    @Test("names are trimmed, required, and kept unique")
    func renameKeepsNamesUnique() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        let library = sandbox.library()
        let first = try library.createMachine(name: "  Windows 11 Arm ")
        let second = try library.createMachine(name: "Windows 11 Arm")
        #expect(first.name == "Windows 11 Arm")
        #expect(second.name == "Windows 11 Arm 2")

        try library.renameMachine(id: second.id, to: "Office")
        #expect(try library.machine(id: second.id).profile.name == "Office")
        #expect(throws: VMLibraryError.invalidName) {
            try library.renameMachine(id: second.id, to: "   ")
        }
        try library.renameMachine(id: second.id, to: "windows 11 arm")
        #expect(try library.machine(id: second.id).profile.name == "windows 11 arm 2")
    }

    @Test("a clone copies disk, UEFI variables, and TPM into its own folder")
    func cloneCopiesMachineFiles() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeLegacyMachine()
        let library = sandbox.library()

        let clone = try library.cloneMachine(id: VMLibrary.legacyMachineID)
        let folder = library.defaultMachineDirectory(for: clone.id)

        #expect(clone.name == "Windows 11 Arm Copy")
        #expect(clone.virtualDiskPath == folder.appendingPathComponent("Windows 11 Arm.img").path)
        #expect(try String(contentsOfFile: clone.virtualDiskPath!, encoding: .utf8) == "legacy-disk")
        #expect(try String(contentsOf: folder.appendingPathComponent("uefi-vars.fd"), encoding: .utf8) == "legacy-vars")
        #expect(try String(contentsOf: folder.appendingPathComponent("tpm/tpm2-00.permall"), encoding: .utf8) == "legacy-tpm")
        #expect(clone.windowsInstalled == true)
        #expect(library.activeMachineID() == clone.id)

        // Writing the clone leaves the original untouched.
        try Data("changed".utf8).write(to: URL(fileURLWithPath: clone.virtualDiskPath!))
        #expect(try String(contentsOfFile: sandbox.home.appendingPathComponent("Virtual Machines/Veil/Windows 11 Arm.img").path, encoding: .utf8) == "legacy-disk")
    }

    @Test("running or suspended machines are not cloned or exported")
    func liveMachinesAreRefused() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeLegacyMachine()

        #expect(throws: VMLibraryError.machineIsRunning("Windows 11 Arm")) {
            try sandbox.library(diskInUse: true).cloneMachine(id: VMLibrary.legacyMachineID)
        }

        let library = sandbox.library()
        let record = VMSuspensionRecord(
            stateFilePath: sandbox.home.appendingPathComponent("Virtual Machines/Veil/suspend.vmstate").path,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            machineFingerprint: "fp",
            migrationStatus: "completed",
            suspendedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let recordURL = sandbox.support.appendingPathComponent("Diagnostics/QEMU Suspend/qemu-suspend-latest.json")
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.veilDiagnostics.encode(record).write(to: recordURL)

        #expect(throws: VMLibraryError.machineIsSuspended("Windows 11 Arm")) {
            try library.cloneMachine(id: VMLibrary.legacyMachineID)
        }
        #expect(throws: VMLibraryError.machineIsSuspended("Windows 11 Arm")) {
            try library.exportMachine(id: VMLibrary.legacyMachineID, to: sandbox.root.appendingPathComponent("x.veilvm"))
        }
    }

    @Test("deleting a library machine trashes its folders and selects another machine")
    func deleteLibraryMachine() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeLegacyMachine()
        let library = sandbox.library()
        let clone = try library.cloneMachine(id: VMLibrary.legacyMachineID)
        try FileManager.default.createDirectory(at: library.diagnosticsDirectory(for: clone.id), withIntermediateDirectories: true)
        let log = DiscardLog()

        try library.deleteMachine(id: clone.id) { url in
            log.urls.append(url)
            try FileManager.default.removeItem(at: url)
        }

        #expect(log.urls.contains(library.defaultMachineDirectory(for: clone.id)))
        #expect(log.urls.contains(library.profileURL(for: clone.id)))
        #expect(log.urls.contains(library.machineStateDirectory(for: clone.id)))
        #expect(library.machines().map(\.id) == [VMLibrary.legacyMachineID])
        #expect(library.activeMachineID() == VMLibrary.legacyMachineID)
        #expect(throws: VMLibraryError.machineIsRunning("Windows 11 Arm")) {
            try sandbox.library(diskInUse: true).deleteMachine(id: VMLibrary.legacyMachineID) { _ in }
        }
    }

    @Test("deleting the legacy machine takes only its own files from the shared folder")
    func deleteLegacyMachineKeepsOtherFiles() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeLegacyMachine()
        let vmDirectory = sandbox.home.appendingPathComponent("Virtual Machines/Veil")
        let unrelated = vmDirectory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let library = sandbox.library()
        let log = DiscardLog()

        try library.deleteMachine(id: VMLibrary.legacyMachineID) { log.urls.append($0) }

        #expect(Set(log.urls.map(\.lastPathComponent)) == ["Windows 11 Arm.img", "uefi-vars.fd", "tpm", "default-vm-profile.json"])
        #expect(!log.urls.contains(vmDirectory))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("an exported bundle imports as a new machine that can build a boot plan")
    func exportImportRoundTrip() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        try sandbox.writeLegacyMachine()
        let library = sandbox.library()
        let bundle = sandbox.root.appendingPathComponent("Windows 11 Arm.veilvm", isDirectory: true)

        try library.exportMachine(id: VMLibrary.legacyMachineID, to: bundle)

        let manifestData = try Data(contentsOf: bundle.appendingPathComponent("veilvm.json"))
        let manifest = try JSONDecoder.veilDiagnostics.decode(VMBundleManifest.self, from: manifestData)
        #expect(manifest.formatVersion == 1)
        #expect(manifest.disk == "Disk.img")
        #expect(manifest.firmwareVariables == "uefi-vars.fd")
        #expect(manifest.tpmState == "tpm")
        #expect(manifest.profile.virtualDiskPath == nil)
        #expect(manifest.profile.installerMediaPath == nil)
        #expect(!String(decoding: manifestData, as: UTF8.self).contains(sandbox.home.path))

        let imported = try library.importBundle(
            from: bundle,
            limits: VMResourceLimits(processorCount: 8, physicalMemoryBytes: 16 * 1_073_741_824)
        )
        let folder = library.defaultMachineDirectory(for: imported.id)
        #expect(imported.id != VMLibrary.legacyMachineID)
        #expect(imported.name == "Windows 11 Arm 2")
        #expect(imported.windowsInstalled == true)
        #expect(imported.sharedFolderPath == sandbox.home.appendingPathComponent("Veil Shared").path)
        #expect(imported.virtualDiskPath == folder.appendingPathComponent("Windows.img").path)
        #expect(try String(contentsOf: folder.appendingPathComponent("uefi-vars.fd"), encoding: .utf8) == "legacy-vars")
        #expect(library.activeMachineID() == imported.id)

        let varsPath = folder.appendingPathComponent("uefi-vars.fd").path
        let plan = try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: imported,
            architecture: "arm64",
            minimumOSSupported: true,
            providerProbe: VMRuntimeProviderProbe(
                environment: [:],
                fileExists: { $0 == "/opt/homebrew/bin/qemu-system-aarch64" },
                executableVersion: { _ in "QEMU emulator version 11.0.2" }
            ),
            fileExists: { path in
                path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                    || path == "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
                    || path == varsPath
            }
        )
        #expect(plan.arguments.contains { $0.contains("file=\(imported.virtualDiskPath!)") })
        #expect(plan.arguments.contains("if=pflash,format=raw,file=\(varsPath)"))
    }

    @Test("bundles that point outside themselves are refused")
    func unsafeBundleEntriesAreRefused() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        let library = sandbox.library()
        let secret = sandbox.root.appendingPathComponent("secret.img")
        try Data("host file".utf8).write(to: secret)

        func writeBundle(disk: String, link: Bool = false) throws -> URL {
            let bundle = sandbox.root.appendingPathComponent("\(UUID().uuidString).veilvm", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            if link {
                try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent(disk), withDestinationURL: secret)
            }
            let manifest = VMBundleManifest(
                exportedAt: Date(timeIntervalSince1970: 0),
                profile: VMProfile.defaultWindows11Arm(homeDirectory: sandbox.home),
                disk: disk,
                firmwareVariables: nil,
                tpmState: nil
            )
            try JSONEncoder.veilDiagnostics.encode(manifest).write(to: bundle.appendingPathComponent("veilvm.json"))
            return bundle
        }

        #expect(throws: VMLibraryError.bundleUnsafePath("../secret.img")) {
            try library.importBundle(from: writeBundle(disk: "../secret.img"))
        }
        #expect(throws: VMLibraryError.bundleUnsafePath("Disk.img")) {
            try library.importBundle(from: writeBundle(disk: "Disk.img", link: true))
        }
        #expect(library.machines().isEmpty)
    }

    @Test("foreign disks are converted to raw with qemu-img")
    func importForeignDisk() throws {
        let sandbox = try LibrarySandbox()
        defer { sandbox.cleanUp() }
        let library = sandbox.library()
        let source = sandbox.root.appendingPathComponent("Hyper-V Windows.vhdx")
        try Data("vhdx".utf8).write(to: source)
        let calls = DiscardLog()
        let converter = VMDiskConverter(candidatePaths: ["/bin/sh"]) { executable, arguments in
            calls.urls.append(URL(fileURLWithPath: executable))
            #expect(arguments.prefix(5) == ["convert", "-f", "vhdx", "-O", "raw"])
            try Data(count: 3 * 1_073_741_824 / 1_024).write(to: URL(fileURLWithPath: arguments[6]))
            return (0, "")
        }

        let profile = try library.importDisk(from: source, converter: converter)

        #expect(calls.urls.count == 1)
        #expect(profile.name == "Hyper-V Windows")
        #expect(profile.windowsInstalled == true)
        #expect(profile.virtualDiskPath == library.defaultMachineDirectory(for: profile.id).appendingPathComponent("Windows.img").path)
        #expect(profile.diskGB == 1)
        #expect(try String(contentsOf: source, encoding: .utf8) == "vhdx")

        #expect(throws: VMLibraryError.diskConverterMissing) {
            try library.importDisk(from: source, converter: VMDiskConverter(candidatePaths: ["/nonexistent/qemu-img"]))
        }
        #expect(throws: VMLibraryError.unsupportedDiskFormat("iso")) {
            try library.importDisk(from: sandbox.root.appendingPathComponent("x.iso"))
        }
        #expect(VMImportedDiskFormat(fileExtension: "VHD") == .vpc)
        #expect(VMImportedDiskFormat(fileExtension: "vmdk") == .vmdk)
        #expect(VMImportedDiskFormat(fileExtension: "qcow2") == .qcow2)
    }
}
