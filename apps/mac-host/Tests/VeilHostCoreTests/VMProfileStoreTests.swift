import Foundation
import Testing

@testable import VeilHostCore

@Suite("VM profile store")
struct VMProfileStoreTests {
    @Test("automatic resource policy scales with host resources")
    func automaticResourcePolicyScalesWithHostResources() {
        let plan = VMResourcePolicy.automatic(
            processorCount: 12,
            physicalMemoryBytes: 64 * 1_024 * 1_024 * 1_024
        )

        #expect(plan.cpuCount == 6)
        #expect(plan.memoryMB == 16_384)
        #expect(plan.diskGB == 128)
    }

    @Test("automatic resource policy keeps small hosts usable")
    func automaticResourcePolicyKeepsSmallHostsUsable() {
        let plan = VMResourcePolicy.automatic(
            processorCount: 4,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
        )

        #expect(plan.cpuCount == 2)
        #expect(plan.memoryMB == 4_096)
        #expect(plan.diskGB == 128)
    }

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
            .passed,
            .passed
        ])
    }

    @Test("local runtime reports local runtime provider")
    func localRuntimeReportsLocalRuntimeProvider() async throws {
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
        let provider = try #require(snapshot.runtimeProvider)

        #expect(provider.kind == .appleVirtualization)
        #expect(provider.displayName == "Apple Virtualization")
        #expect(provider.acceleration == "Apple Hypervisor")
        #expect(provider.isServerBacked == false)
        #expect(provider.status == .active)
    }

    @Test("runtime provider probe reports QEMU provider when executable exists")
    func runtimeProviderProbeReportsQEMUProvider() {
        let probe = VMRuntimeProviderProbe(
            environment: ["VEIL_QEMU_SYSTEM_AARCH64": "/opt/veil/bin/qemu-system-aarch64"],
            fileExists: { path in path == "/opt/veil/bin/qemu-system-aarch64" },
            executableVersion: { path in
                path == "/opt/veil/bin/qemu-system-aarch64"
                    ? "qemu-system-aarch64 version 8.2.0"
                    : nil
            }
        )

        let providers = probe.localProviders(
            architecture: "arm64",
            minimumOSSupported: true
        )
        let qemu = providers.first { $0.kind == .qemuHypervisor }

        #expect(providers.map(\.kind) == [.appleVirtualization, .qemuHypervisor])
        #expect(qemu?.displayName == "QEMU/HVF")
        #expect(qemu?.acceleration == "HVF")
        #expect(qemu?.isServerBacked == false)
        #expect(qemu?.status == .active)
        #expect(qemu?.executablePath == "/opt/veil/bin/qemu-system-aarch64")
        #expect(qemu?.executableVersion == "qemu-system-aarch64 version 8.2.0")
    }

    @Test("runtime provider probe reports QEMU version")
    func runtimeProviderProbeReportsQEMUVersion() {
        let probe = VMRuntimeProviderProbe(
            environment: ["VEIL_QEMU_SYSTEM_AARCH64": "/opt/homebrew/bin/qemu-system-aarch64"],
            fileExists: { path in path == "/opt/homebrew/bin/qemu-system-aarch64" },
            executableVersion: { path in
                path == "/opt/homebrew/bin/qemu-system-aarch64"
                    ? "qemu-system-aarch64 version 9.2.4\nCopyright (c) 2003-2025 Fabrice Bellard and the QEMU Project developers"
                    : nil
            }
        )

        let providers = probe.localProviders(
            architecture: "arm64",
            minimumOSSupported: true
        )
        let qemu = providers.first { $0.kind == .qemuHypervisor }

        #expect(qemu?.executableVersion == "qemu-system-aarch64 version 9.2.4")
    }

    @Test("runtime provider probe marks QEMU planned when executable is missing")
    func runtimeProviderProbeMarksQEMUPlannedWhenMissing() {
        let probe = VMRuntimeProviderProbe(
            environment: [:],
            fileExists: { _ in false }
        )

        let providers = probe.localProviders(
            architecture: "arm64",
            minimumOSSupported: true
        )
        let qemu = providers.first { $0.kind == .qemuHypervisor }

        #expect(qemu?.status == .planned)
        #expect(qemu?.executablePath == nil)
        #expect(qemu?.detail.contains("qemu-system-aarch64 not found") == true)
    }

    @Test("local runtime reports provider candidates")
    func localRuntimeReportsProviderCandidates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(
            createdAt: Date(timeIntervalSince1970: 1_782_752_400),
            homeDirectory: directory.appendingPathComponent("Home", isDirectory: true)
        )
        let providerProbe = VMRuntimeProviderProbe(
            environment: ["VEIL_QEMU_SYSTEM_AARCH64": "/opt/veil/bin/qemu-system-aarch64"],
            fileExists: { path in path == "/opt/veil/bin/qemu-system-aarch64" }
        )
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            providerProbe: providerProbe
        )
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.runtimeProviders.map(\.kind) == [.appleVirtualization, .qemuHypervisor])
        #expect(snapshot.runtimeProviders.first { $0.kind == .qemuHypervisor }?.status == .active)
    }

    @Test("local runtime reports virtualization device summary")
    func localRuntimeReportsVirtualizationDeviceSummary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
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
        let devices = try #require(snapshot.deviceSummary)

        #expect(devices.platform == "Generic")
        #expect(devices.bootLoader == "EFI")
        #expect(devices.networkMode == "NAT")
        #expect(devices.graphics.widthInPixels == 1440)
        #expect(devices.graphics.heightInPixels == 900)
        #expect(devices.inputDevices == ["USB keyboard", "USB screen-coordinate pointer"])
        #expect(devices.entropyDevice == "Virtio entropy")
        #expect(devices.storageDevices.map(\.role) == ["installer", "system-disk"])
        #expect(devices.storageDevices.map(\.attachment) == ["USB mass storage", "Virtio block"])
        #expect(devices.storageDevices.map(\.readOnly) == [true, false])
        #expect(devices.storageDevices.map(\.path) == [installerURL.path, diskURL.path])
    }

    @Test("prepare default VM applies injected adaptive resource plan")
    func prepareDefaultVMAppliesInjectedAdaptiveResourcePlan() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let resourcePlan = VMResourcePlan(cpuCount: 6, memoryMB: 12_288, diskGB: 160)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory,
            resourcePlan: resourcePlan
        )

        _ = try await service.prepareDefaultVM()
        let profile = try #require(await store.load())

        #expect(profile.cpuCount == 6)
        #expect(profile.memoryMB == 12_288)
        #expect(profile.diskGB == 160)
        #expect(profile.virtualDiskPath?.hasSuffix("Windows 11 Arm.img") == true)
    }

    @Test("local runtime rejects unsupported installer media extensions")
    func localRuntimeRejectsUnsupportedInstallerMediaExtensions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.vhdx")
        let diskURL = directory.appendingPathComponent("Windows.img")
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
        let installerCheck = try #require(snapshot.preflightChecks.first { $0.id == "installer-media" })

        #expect(snapshot.bootReady == false)
        #expect(snapshot.detail == "VM profile needs attention before boot.")
        #expect(installerCheck.state == .failed)
        #expect(installerCheck.detail == "Select a bootable ISO installer for Windows setup. VHDX files should be used as disk images, not installer media.")
    }

    @Test("exports diagnostic bundle without media contents")
    func exportsDiagnosticBundleWithoutMediaContents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let diagnosticsDirectory = directory.appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("secret installer bytes".utf8).write(to: installerURL)
        try Data("secret disk bytes".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let service = LocalVMRuntimeService(
            profileStore: store,
            diagnosticDate: { Date(timeIntervalSince1970: 1_782_838_800) }
        )

        let outputURL = try await service.exportDiagnostics(to: diagnosticsDirectory)
        let data = try Data(contentsOf: outputURL)
        let bundle = try JSONDecoder.veilDiagnostics.decode(VMRuntimeDiagnosticBundle.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        #expect(outputURL.deletingLastPathComponent() == diagnosticsDirectory)
        #expect(outputURL.lastPathComponent == "veil-vm-diagnostics-2026-06-30T17-00-00Z.json")
        #expect(bundle.generatedAt == Date(timeIntervalSince1970: 1_782_838_800))
        #expect(bundle.snapshot.profileName == "Windows 11 Arm")
        #expect(bundle.profile?.installerMediaPath == installerURL.path)
        #expect(bundle.profile?.virtualDiskPath == diskURL.path)
        #expect(bundle.host.architecture == "arm64")
        #expect(bundle.host.processorCount >= 1)
        #expect(bundle.host.physicalMemoryBytes > 0)
        #expect(!json.contains("secret installer bytes"))
        #expect(!json.contains("secret disk bytes"))
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
            "installer-media",
            "guest-os",
            "cpu",
            "memory",
            "disk-size"
        ])
        #expect(snapshot.preflightChecks.map(\.state) == [
            .passed,
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

    @Test("prepares default profile shared folder and virtual disk together")
    func preparesDefaultProfileSharedFolderAndVirtualDiskTogether() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.prepareDefaultVM()
        let profile = try #require(await store.load())
        let diskPath = try #require(profile.virtualDiskPath)
        var sharedFolderIsDirectory: ObjCBool = false
        var diskIsDirectory: ObjCBool = false

        #expect(profile.name == "Windows 11 Arm")
        #expect(profile.sharedFolderPath == homeDirectory.appendingPathComponent("Veil Shared").path)
        #expect(diskPath == homeDirectory
            .appendingPathComponent("Virtual Machines", isDirectory: true)
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Windows 11 Arm.img").path)
        #expect(FileManager.default.fileExists(atPath: profile.sharedFolderPath, isDirectory: &sharedFolderIsDirectory))
        #expect(sharedFolderIsDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: diskPath, isDirectory: &diskIsDirectory))
        #expect(diskIsDirectory.boolValue == false)
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.virtualDiskPath == diskPath)
        #expect(snapshot.installationSteps.first { $0.id == "shared-folder" }?.state == .complete)
        #expect(snapshot.installationSteps.first { $0.id == "virtual-disk" }?.state == .complete)
    }

    @Test("prepare default VM auto detects Windows Arm ISO from Downloads")
    func prepareDefaultVMAutoDetectsWindowsArmISOFromDownloads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let downloadsDirectory = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let installerURL = downloadsDirectory.appendingPathComponent("Win11_25H2_Korean_Arm64_v2.iso")
        try Data("installer".utf8).write(to: installerURL)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.prepareDefaultVM()
        let profile = try #require(await store.load())
        let installerMediaPath = try #require(profile.installerMediaPath)

        #expect(URL(fileURLWithPath: installerMediaPath).lastPathComponent == installerURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: installerMediaPath))
        #expect(snapshot.installerMediaPath == profile.installerMediaPath)
        #expect(snapshot.installationSteps.first { $0.id == "windows-installer" }?.state == .complete)
        #expect(snapshot.bootReady)
    }

    @Test("load snapshot reports discovered installer before profile exists")
    func loadSnapshotReportsDiscoveredInstallerBeforeProfileExists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let downloadsDirectory = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let installerURL = downloadsDirectory.appendingPathComponent("Win11_25H2_Korean_Arm64_v2.iso")
        try Data("installer".utf8).write(to: installerURL)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.loadSnapshot()
        let storedProfile = try await store.load()

        let discoveredPath = try #require(snapshot.discoveredInstallerMediaPath)
        #expect(URL(fileURLWithPath: discoveredPath).lastPathComponent == installerURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: discoveredPath))
        #expect(snapshot.installerMediaPath == nil)
        #expect(storedProfile == nil)
    }

    @Test("load snapshot reports discovered installer without mutating profile")
    func loadSnapshotReportsDiscoveredInstallerWithoutMutatingProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let downloadsDirectory = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let installerURL = downloadsDirectory.appendingPathComponent("Win11_25H2_Korean_Arm64_v2.iso")
        try Data("installer".utf8).write(to: installerURL)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(homeDirectory: homeDirectory)
        try await store.save(profile)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.loadSnapshot()
        let storedProfile = try #require(await store.load())

        let discoveredPath = try #require(snapshot.discoveredInstallerMediaPath)
        #expect(URL(fileURLWithPath: discoveredPath).lastPathComponent == installerURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: discoveredPath))
        #expect(snapshot.installerMediaPath == nil)
        #expect(storedProfile.installerMediaPath == nil)
    }

    @Test("prepare default VM preserves an existing configured installer")
    func prepareDefaultVMPreservesExistingConfiguredInstaller() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let downloadsDirectory = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let detectedInstallerURL = downloadsDirectory.appendingPathComponent("Win11_25H2_Korean_Arm64_v2.iso")
        let configuredInstallerURL = directory.appendingPathComponent("Configured.iso")
        try Data("detected".utf8).write(to: detectedInstallerURL)
        try Data("configured".utf8).write(to: configuredInstallerURL)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(homeDirectory: homeDirectory)
        profile.installerMediaPath = configuredInstallerURL.path
        try await store.save(profile)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory
        )

        let snapshot = try await service.prepareDefaultVM()
        let storedProfile = try #require(await store.load())

        #expect(storedProfile.installerMediaPath == configuredInstallerURL.path)
        #expect(snapshot.installerMediaPath == configuredInstallerURL.path)
    }

    @Test("prepare default VM preserves an existing configured disk")
    func prepareDefaultVMPreservesExistingConfiguredDisk() async throws {
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

        let snapshot = try await service.prepareDefaultVM()
        let storedProfile = try #require(await store.load())
        let attributes = try FileManager.default.attributesOfItem(atPath: existingDiskURL.path)
        let fileSize = try #require(attributes[.size] as? UInt64)

        #expect(storedProfile.virtualDiskPath == existingDiskURL.path)
        #expect(snapshot.virtualDiskPath == existingDiskURL.path)
        #expect(fileSize == UInt64(Data("existing".utf8).count))
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
        let reportStore = JSONVMRuntimeBootReportStore(
            directory: directory.appendingPathComponent("Reports", isDirectory: true)
        )

        let service = LocalVMRuntimeService(
            profileStore: store,
            bootRunner: bootRunner,
            bootReportStore: reportStore
        )

        let snapshot = try await service.start()

        #expect(snapshot.state == .running)
        #expect(snapshot.detail == "Windows VM is running.")
        #expect(bootRunner.startCount == 1)
        #expect(bootRunner.startedProfile?.installerMediaPath == installerURL.path)
        #expect(bootRunner.startedProfile?.virtualDiskPath == diskURL.path)
    }

    @Test("local runtime records successful boot report")
    func localRuntimeRecordsSuccessfulBootReport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reportDirectory = directory.appendingPathComponent("Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        let reportStore = JSONVMRuntimeBootReportStore(directory: reportDirectory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running)
        let service = LocalVMRuntimeService(
            profileStore: store,
            bootRunner: bootRunner,
            bootReportStore: reportStore,
            diagnosticDate: { Date(timeIntervalSince1970: 1_782_838_800) }
        )

        _ = try await service.start()
        let report = try #require(await reportStore.load())

        #expect(report.startedAt == Date(timeIntervalSince1970: 1_782_838_800))
        #expect(report.completedAt == Date(timeIntervalSince1970: 1_782_838_800))
        #expect(report.result == .succeeded)
        #expect(report.resultingState == .running)
        #expect(report.errorMessage == nil)
        #expect(report.profile.installerMediaPath == installerURL.path)
        #expect(report.profile.virtualDiskPath == diskURL.path)
        #expect(report.deviceSummary.storageDevices.map(\.role) == ["installer", "system-disk"])
    }

    @Test("local runtime records failed boot report in diagnostics")
    func localRuntimeRecordsFailedBootReportInDiagnostics() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reportDirectory = directory.appendingPathComponent("Reports", isDirectory: true)
        let diagnosticsDirectory = directory.appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        let reportStore = JSONVMRuntimeBootReportStore(directory: reportDirectory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(
            startState: .failed,
            startError: FakeBootError.simulated
        )
        let service = LocalVMRuntimeService(
            profileStore: store,
            bootRunner: bootRunner,
            bootReportStore: reportStore,
            diagnosticDate: { Date(timeIntervalSince1970: 1_782_838_800) }
        )

        await #expect(throws: FakeBootError.simulated) {
            try await service.start()
        }
        let report = try #require(await reportStore.load())
        let diagnosticsURL = try await service.exportDiagnostics(to: diagnosticsDirectory)
        let bundle = try JSONDecoder.veilDiagnostics.decode(
            VMRuntimeDiagnosticBundle.self,
            from: Data(contentsOf: diagnosticsURL)
        )

        #expect(report.result == .failed)
        #expect(report.resultingState == .failed)
        #expect(report.errorMessage == "Simulated boot failure.")
        #expect(bundle.lastBootReport?.result == .failed)
        #expect(bundle.lastBootReport?.errorMessage == "Simulated boot failure.")
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

private enum FakeBootError: Error, LocalizedError {
    case simulated

    var errorDescription: String? {
        "Simulated boot failure."
    }
}

private final class FakeVMRuntimeBooter: VMRuntimeBooting, @unchecked Sendable {
    var startState: VMRuntimeState
    var currentState: VMRuntimeState?
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var startedProfile: VMProfile?

    init(
        startState: VMRuntimeState,
        currentState: VMRuntimeState? = nil,
        startError: (any Error)? = nil
    ) {
        self.startState = startState
        self.currentState = currentState
        self.startError = startError
    }

    func runtimeState() async -> VMRuntimeState? {
        currentState
    }

    func start(profile: VMProfile) async throws -> VMRuntimeState {
        startCount += 1
        startedProfile = profile
        if let startError {
            currentState = .failed
            throw startError
        }

        currentState = startState
        return startState
    }

    func stop() async throws -> VMRuntimeState {
        stopCount += 1
        currentState = .stopped
        return .stopped
    }
}
