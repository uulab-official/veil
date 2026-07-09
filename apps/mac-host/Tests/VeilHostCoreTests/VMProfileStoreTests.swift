import Foundation
import Testing

@testable import VeilHostCore

private struct FakeAutomaticInstallMediaBuilder: AutomaticInstallMediaBuilding {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        guard FileManager.default.fileExists(atPath: answerFileURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("Autounattend.xml is missing.")
        }

        try FileManager.default.createDirectory(
            at: mediaURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fake auto install media".utf8).write(to: mediaURL)
    }
}

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
        profile.driverMediaPath = "/Users/test/Downloads/virtio-win.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Windows.vhdx"

        try await store.save(profile)
        let loaded = try await store.load()

        #expect(loaded?.installerMediaPath == "/Users/test/Downloads/Windows.iso")
        #expect(loaded?.driverMediaPath == "/Users/test/Downloads/virtio-win.iso")
        #expect(loaded?.virtualDiskPath == "/Users/test/Virtual Machines/Windows.vhdx")
    }

    @Test("profile path updates persist security scoped bookmarks")
    func profilePathUpdatesPersistSecurityScopedBookmarks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(profileStore: store)

        _ = try await service.updateProfilePaths(
            installerMediaPath: installerURL.path,
            driverMediaPath: driverURL.path,
            virtualDiskPath: diskURL.path
        )
        let profile = try #require(await store.load())

        let installerBookmark = try #require(profile.installerMediaBookmarkData)
        let driverBookmark = try #require(profile.driverMediaBookmarkData)
        let diskBookmark = try #require(profile.virtualDiskBookmarkData)
        #expect(try resolvedBookmarkPath(installerBookmark) == canonicalPath(installerURL))
        #expect(try resolvedBookmarkPath(driverBookmark) == canonicalPath(driverURL))
        #expect(try resolvedBookmarkPath(diskBookmark) == canonicalPath(diskURL))

        let replacementInstallerURL = directory.appendingPathComponent("Windows-2.iso")
        try Data("replacement installer".utf8).write(to: replacementInstallerURL)
        _ = try await service.updateProfilePaths(
            installerMediaPath: replacementInstallerURL.path,
            driverMediaPath: driverURL.path,
            virtualDiskPath: diskURL.path
        )
        let updatedProfile = try #require(await store.load())

        #expect(updatedProfile.installerMediaBookmarkData != installerBookmark)
        #expect(updatedProfile.driverMediaBookmarkData == driverBookmark)
        #expect(updatedProfile.virtualDiskBookmarkData == diskBookmark)
        #expect(try resolvedBookmarkPath(try #require(updatedProfile.installerMediaBookmarkData)) == canonicalPath(replacementInstallerURL))
    }

    @Test("export diagnostics redacts the current user's home directory from serialized paths")
    func exportDiagnosticsRedactsHomeDirectoryFromSerializedPaths() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var profile = VMProfile.defaultWindows11Arm(
            createdAt: Date(timeIntervalSince1970: 1_782_752_400),
            homeDirectory: homeDirectory
        )
        profile.installerMediaPath = homeDirectory.appendingPathComponent("Downloads/Windows.iso").path
        try await store.save(profile)
        let service = LocalVMRuntimeService(profileStore: store)

        let outputURL = try await service.exportDiagnostics(
            to: directory.appendingPathComponent("Diagnostics", isDirectory: true)
        )
        let json = try String(contentsOf: outputURL, encoding: .utf8)
        let escapedHomeDirectoryPath = homeDirectory.path.replacingOccurrences(of: "/", with: "\\/")

        #expect(!json.contains(homeDirectory.path))
        #expect(!json.contains(escapedHomeDirectoryPath))
        #expect(json.contains("~"))
        #expect(json.contains("Downloads"))
        #expect(json.contains("Windows.iso"))
        #expect(json.contains("Veil Shared"))
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

        let providerProbe = VMRuntimeProviderProbe(
            environment: ["VEIL_QEMU_SYSTEM_AARCH64": "/opt/veil/bin/qemu-system-aarch64"],
            fileExists: { path in path == "/opt/veil/bin/qemu-system-aarch64" },
            executableVersion: { _ in "QEMU emulator version 11.0.2" }
        )
        let service = LocalVMRuntimeService(profileStore: store, providerProbe: providerProbe)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.bootReady == false)
        #expect(snapshot.detail == "Installer media and virtual disk paths are required before boot.")
        #expect(snapshot.installationSteps.map(\.id) == [
            "windows-installer",
            "virtual-disk",
            "shared-folder",
            "auto-install-answer-file",
            "guest-agent"
        ])
        #expect(snapshot.installationSteps.map(\.state) == [
            .blocked,
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
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let processLogURL = qemuLaunchDirectory.appendingPathComponent("qemu-launch.log")
        try Data("qemu log".utf8).write(to: processLogURL)
        let consoleScreenshotURL = qemuLaunchDirectory.appendingPathComponent("qemu-console-2026-07-02T11-10-00Z.png")
        try Data("png".utf8).write(to: consoleScreenshotURL)
        let launchRecord = QEMULaunchRecord(
            pid: 1234,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-display", "cocoa"],
            processLogPath: processLogURL.path,
            monitorSocketPath: "/tmp/vq-test.sock",
            qmpSocketPath: "/tmp/vq-test.qmp.sock",
            vncHost: "127.0.0.1",
            vncPort: 5_907,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        let launchEncoder = JSONEncoder()
        launchEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        launchEncoder.dateEncodingStrategy = .iso8601
        try launchEncoder.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory)
        )
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .stopped)
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.installerMediaPath == installerURL.path)
        #expect(snapshot.virtualDiskPath == diskURL.path)
        #expect(snapshot.virtualDiskAllocatedBytes != nil)
        #expect(snapshot.bootReady)
        #expect(snapshot.latestConsoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.provider == "QEMU/HVF")
        #expect(snapshot.latestConsoleLaunch?.pid == 1234)
        #expect(snapshot.latestConsoleLaunch?.processLogPath == processLogURL.path)
        #expect(snapshot.latestConsoleLaunch?.monitorSocketPath == "/tmp/vq-test.sock")
        #expect(snapshot.latestConsoleLaunch?.qmpSocketPath == "/tmp/vq-test.qmp.sock")
        #expect(snapshot.latestConsoleLaunch?.vncHost == "127.0.0.1")
        #expect(snapshot.latestConsoleLaunch?.vncPort == 5_907)
        #expect(snapshot.latestConsoleLaunch?.displaySurface.kind == .vncLoopback)
        #expect(snapshot.latestConsoleLaunch?.displaySurface.endpoint == "127.0.0.1:5907")
        #expect(snapshot.latestConsoleLaunch?.displaySurface.isLiveCapable == true)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.previewStatus == .stale)
        #expect(snapshot.latestConsoleLaunch?.startedAt == Date(timeIntervalSince1970: 1_782_838_800))
        #expect(snapshot.detail == "Windows is not installed yet.")
        #expect(snapshot.installEvidence.kind == .sparseDisk)
        #expect(snapshot.installEvidence.isInstalled == false)
        #expect(snapshot.installationSteps.map(\.state) == [
            .complete,
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

    @Test("builds Windows install status report from launch evidence")
    func buildsWindowsInstallStatusReportFromLaunchEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let processLogURL = qemuLaunchDirectory.appendingPathComponent("qemu-launch.log")
        let consoleScreenshotURL = qemuLaunchDirectory.appendingPathComponent("qemu-console-2026-07-03T08-40-00Z.png")
        try Data("qemu log".utf8).write(to: processLogURL)
        try Data("png".utf8).write(to: consoleScreenshotURL)
        let launchRecord = QEMULaunchRecord(
            pid: 2345,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-drive", "file=\(diskURL.path),if=none", "-display", "vnc=127.0.0.1:7"],
            displayMode: .vncLoopback,
            processLogPath: processLogURL.path,
            monitorSocketPath: "/tmp/vq-install-status.sock",
            qmpSocketPath: "/tmp/vq-install-status.qmp.sock",
            vncHost: "127.0.0.1",
            vncPort: 5_907,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date(timeIntervalSince1970: 1_782_914_400)
        )
        try JSONEncoder.veilDiagnostics.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.driverMediaPath = driverURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory),
            qemuLaunchProcessIsRunning: { $0 == 2345 }
        )
        let snapshot = try await service.loadSnapshot()
        let report = snapshot.windowsInstallStatusReport(
            generatedAt: Date(timeIntervalSince1970: 1_782_914_800)
        )

        #expect(report.kind == "qemuWindowsInstallStatus")
        #expect(report.generatedAt == Date(timeIntervalSince1970: 1_782_914_800))
        #expect(report.state == .running)
        #expect(report.profileName == "Windows 11 Arm")
        #expect(report.bootReady)
        #expect(report.windowsInstalled == false)
        #expect(report.installEvidence.kind == .sparseDisk)
        #expect(report.installerMediaPath == installerURL.path)
        #expect(report.driverMediaPath == driverURL.path)
        #expect(report.virtualDiskPath == diskURL.path)
        #expect(report.automaticInstallMediaPath == sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso").path)
        #expect(report.automaticInstallMediaStatus.state == .current)
        #expect(report.automaticInstallMediaStatus.isCurrent)
        #expect(report.automaticInstallMediaStatus.recommendedAction == "none")
        #expect(report.latestConsoleScreenshotPath == consoleScreenshotURL.path)
        #expect(report.displaySurface.kind == .vncLoopback)
        #expect(report.displaySurface.endpoint == "127.0.0.1:5907")
        #expect(report.displaySurface.plannedWidthInPixels == 1440)
        #expect(report.displaySurface.plannedHeightInPixels == 900)
        #expect(report.displaySurface.scalingMode == "aspect-fit host window")
        #expect(report.displaySurface.dynamicResolution == "fixed guest framebuffer until guest agent display bridge")
        #expect(report.displaySurface.retinaScaling == "host-rendered Retina interpolation")
        #expect(report.displaySurface.validationCommand == "veil-vmctl qemu-display-smoke --json")
        #expect(report.latestConsoleLaunch?.displaySurface.kind == .vncLoopback)
        #expect(report.latestConsoleLaunch?.displaySurface.endpoint == "127.0.0.1:5907")
        #expect(report.nextActions.contains("Validate the embedded console with `veil-vmctl qemu-display-smoke --json`."))
        #expect(report.nextActions.contains("Refresh install evidence with `veil-vmctl qemu-capture --json` before changing recovery steps."))
        #expect(report.nextActions.contains("Continue Windows Setup in the console; use `veil-vmctl qemu-oobe-bypass --json` only when OOBE network setup blocks local account creation."))
    }

    @Test("reports running QEMU recovery before blocked install actions")
    func reportsRunningQEMURecoveryBeforeBlockedInstallActions() {
        let snapshot = VMRuntimeSnapshot(
            state: .running,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            installerMediaPath: "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso",
            virtualDiskPath: "/Users/test/Virtual Machines/Windows.img",
            runningQEMUProcess: QEMURunningProcess(
                pid: 2468,
                commandLine: "qemu-system-aarch64 -drive file=/Users/test/Virtual Machines/Windows.img,if=none -monitor unix:/tmp/vq-recovery.sock,server,nowait -qmp unix:/tmp/vq-recovery.qmp.sock,server,nowait",
                monitorSocketPath: "/tmp/vq-recovery.sock",
                qmpSocketPath: "/tmp/vq-recovery.qmp.sock"
            ),
            preflightChecks: [
                VMPreflightCheck(
                    id: "installer-media",
                    title: "Installer media",
                    detail: "Installer media is in Downloads. Re-select it with the file picker so Veil can store macOS file access before starting Windows.",
                    state: .failed
                )
            ],
            installEvidence: VMInstallEvidenceSummary(
                kind: .setupBlocked,
                isInstalled: false,
                title: "Setup blocked",
                detail: "Installer media is in Downloads."
            ),
            bootReady: false,
            windowsInstalled: false,
            detail: "Installer media requires file picker access."
        )

        let report = snapshot.windowsInstallStatusReport(
            generatedAt: Date(timeIntervalSince1970: 1_782_918_000)
        )

        #expect(report.state == .running)
        #expect(report.latestConsoleLaunch == nil)
        #expect(report.runningQEMUProcess?.pid == 2468)
        #expect(report.runningQEMUProcess?.monitorSocketPath == "/tmp/vq-recovery.sock")
        #expect(report.runningQEMUProcess?.qmpSocketPath == "/tmp/vq-recovery.qmp.sock")
        #expect(report.nextActions.first == "Close existing QEMU/Windows PID 2468 before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record.")
        #expect(report.nextActions.dropFirst().first == "Installer media: Installer media is in Downloads. Re-select it with the file picker so Veil can store macOS file access before starting Windows.")
        #expect(report.nextActions.contains("Re-register the selected installer with `veil-vmctl prepare --installer /Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso`."))
    }

    @Test("install status reports stale automatic install media before guest agent repair")
    func installStatusReportsStaleAutomaticInstallMedia() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        let agentBundleURL = sharedFolderURL.appendingPathComponent("Veil Guest Agent", isDirectory: true)
        try FileManager.default.createDirectory(at: agentBundleURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let mediaURL = sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso")
        let answerURL = sharedFolderURL.appendingPathComponent("Autounattend.xml")
        let scriptURL = agentBundleURL.appendingPathComponent("V.cmd")
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("old media".utf8).write(to: mediaURL)
        try Data("<unattend />".utf8).write(to: answerURL)
        try Data("new script".utf8).write(to: scriptURL)

        let oldDate = Date(timeIntervalSince1970: 1_782_900_000)
        let newDate = Date(timeIntervalSince1970: 1_782_910_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: mediaURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: answerURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: scriptURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: agentBundleURL.path)

        let snapshot = VMRuntimeSnapshot(
            state: .running,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            installerMediaPath: installerURL.path,
            driverMediaPath: driverURL.path,
            automaticInstallAnswerFilePath: answerURL.path,
            automaticInstallMediaPath: mediaURL.path,
            installEvidence: VMInstallEvidenceSummary(
                kind: .profileFlag,
                isInstalled: true,
                title: "Windows installed",
                detail: "The local profile is marked installed."
            ),
            bootReady: true,
            windowsInstalled: true,
            detail: "Windows is installed."
        )

        let report = snapshot.windowsInstallStatusReport()

        #expect(report.automaticInstallMediaStatus.state == .stale)
        #expect(report.automaticInstallMediaStatus.isCurrent == false)
        #expect(report.automaticInstallMediaStatus.mediaPath == mediaURL.path)
        #expect(report.automaticInstallMediaStatus.sourcePath == sharedFolderURL.path)
        #expect(report.automaticInstallMediaStatus.mediaModifiedAt == oldDate)
        #expect(report.automaticInstallMediaStatus.sourceModifiedAt == newDate)
        #expect(report.automaticInstallMediaStatus.recommendedAction == "rebuild-media-and-relaunch")
        #expect(report.automaticInstallMediaStatus.requiresRelaunch)
        #expect(report.automaticInstallMediaStatus.rebuildCommand == "veil-vmctl prepare --installer \(installerURL.path) --drivers \(driverURL.path)")
        #expect(report.nextActions.contains { action in
            action.contains("qemu-powerdown")
                && action.contains("rebuild guest tools media")
                && action.contains("VeilAutoInstall.iso")
        })
    }

    @Test("local runtime avoids protected Downloads console screenshot during snapshot load")
    func localRuntimeAvoidsProtectedDownloadsConsoleScreenshotDuringSnapshotLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.vhdx")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        let downloadsDirectory = directory.appendingPathComponent("Home/Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let consoleScreenshotURL = downloadsDirectory.appendingPathComponent("qemu-console.png")
        try Data("png".utf8).write(to: consoleScreenshotURL)

        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let launchRecord = QEMULaunchRecord(
            pid: 1234,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-display", "cocoa"],
            processLogPath: qemuLaunchDirectory.appendingPathComponent("qemu-launch.log").path,
            monitorSocketPath: "/tmp/vq-test.sock",
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        try JSONEncoder.veilDiagnostics.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory)
        )

        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.bootReady)
        #expect(snapshot.latestConsoleScreenshotPath == nil)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotPath == nil)
        #expect(snapshot.latestConsoleLaunch?.previewStatus == .unavailable)
    }

    @Test("Downloads installer without security bookmark requires file picker")
    func downloadsInstallerWithoutSecurityBookmarkRequiresFilePicker() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadsDirectory = directory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let installerURL = downloadsDirectory.appendingPathComponent("Win11_25H2_Korean_Arm64_v2.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running)
        let service = LocalVMRuntimeService(profileStore: store, bootRunner: bootRunner)

        let snapshot = try await service.loadSnapshot()

        #expect(!snapshot.bootReady)
        #expect(snapshot.detail == "Installer media is in Downloads. Re-select it with the file picker so Veil can store macOS file access before starting Windows.")
        #expect(snapshot.installationSteps.first { $0.id == "windows-installer" }?.state == .blocked)
        #expect(snapshot.preflightChecks.first { $0.id == "installer-media" }?.state == .failed)
        await #expect(throws: VMRuntimeError.bootPrerequisitesMissing) {
            try await service.start()
        }
        #expect(bootRunner.startCount == 0)
    }

    @Test("Downloads installer with security bookmark is boot ready")
    func downloadsInstallerWithSecurityBookmarkIsBootReady() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadsDirectory = directory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let installerURL = downloadsDirectory.appendingPathComponent("Win11_25H2_Korean_Arm64_v2.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.installerMediaBookmarkData = try installerURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let service = LocalVMRuntimeService(profileStore: store)

        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.bootReady)
        #expect(snapshot.preflightChecks.first { $0.id == "installer-media" }?.state == .passed)
    }

    @Test("local runtime refreshes live QEMU console screenshot")
    func localRuntimeRefreshesLiveQEMUConsoleScreenshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let processLogURL = qemuLaunchDirectory.appendingPathComponent("qemu-launch.log")
        let consoleScreenshotURL = qemuLaunchDirectory.appendingPathComponent("qemu-console.png")
        let monitorSocketURL = directory.appendingPathComponent("vq-test.sock")
        try Data("qemu log".utf8).write(to: processLogURL)
        try Data("stale".utf8).write(to: consoleScreenshotURL)
        try Data("socket".utf8).write(to: monitorSocketURL)

        let launchRecord = QEMULaunchRecord(
            pid: 1234,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-display", "cocoa"],
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        let launchEncoder = JSONEncoder()
        launchEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        launchEncoder.dateEncodingStrategy = .iso8601
        try launchEncoder.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.driverMediaPath = driverURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory),
            diagnosticDate: { Date(timeIntervalSince1970: 1_782_838_860) },
            consoleScreenshotRefresher: { _, imageURL in
                try? Data("fresh".utf8).write(to: imageURL)
            }
        )

        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.latestConsoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotRefreshedAt == Date(timeIntervalSince1970: 1_782_838_860))
        #expect(snapshot.latestConsoleLaunch?.previewStatus == .fresh)
        #expect(try String(contentsOf: consoleScreenshotURL, encoding: .utf8) == "fresh")
    }

    @Test("local runtime keeps stale QEMU console screenshot when refresh does not update the file")
    func localRuntimeKeepsStaleQEMUConsoleScreenshotWhenRefreshDoesNotUpdateFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let processLogURL = qemuLaunchDirectory.appendingPathComponent("qemu-launch.log")
        let consoleScreenshotURL = qemuLaunchDirectory.appendingPathComponent("qemu-console.png")
        let monitorSocketURL = directory.appendingPathComponent("vq-test.sock")
        try Data("qemu log".utf8).write(to: processLogURL)
        try Data("stale".utf8).write(to: consoleScreenshotURL)
        try Data("socket".utf8).write(to: monitorSocketURL)

        let launchRecord = QEMULaunchRecord(
            pid: 1234,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-display", "none"],
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        let launchEncoder = JSONEncoder()
        launchEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        launchEncoder.dateEncodingStrategy = .iso8601
        try launchEncoder.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.driverMediaPath = driverURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory),
            diagnosticDate: { Date(timeIntervalSince1970: 1_782_838_860) },
            consoleScreenshotRefresher: { _, _ in }
        )

        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.latestConsoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotRefreshedAt == nil)
        #expect(snapshot.latestConsoleLaunch?.previewStatus == .stale)
        #expect(try String(contentsOf: consoleScreenshotURL, encoding: .utf8) == "stale")
    }

    @Test("local runtime preserves qemu capture refresh evidence from launch record")
    func localRuntimePreservesQEMUCaptureRefreshEvidenceFromLaunchRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let processLogURL = qemuLaunchDirectory.appendingPathComponent("qemu-launch.log")
        let consoleScreenshotURL = qemuLaunchDirectory.appendingPathComponent("qemu-console.png")
        let monitorSocketURL = directory.appendingPathComponent("vq-test.sock")
        try Data("qemu log".utf8).write(to: processLogURL)
        try Data("fresh from qemu-capture".utf8).write(to: consoleScreenshotURL)
        try Data("socket".utf8).write(to: monitorSocketURL)
        let capturedAt = Date(timeIntervalSince1970: 1_782_839_120)

        let launchRecord = QEMULaunchRecord(
            pid: 1234,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-display", "none"],
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            consoleScreenshotRefreshedAt: capturedAt,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        let launchEncoder = JSONEncoder()
        launchEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        launchEncoder.dateEncodingStrategy = .iso8601
        try launchEncoder.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.driverMediaPath = driverURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory),
            consoleScreenshotRefresher: { _, _ in }
        )

        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.latestConsoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotPath == consoleScreenshotURL.path)
        #expect(snapshot.latestConsoleLaunch?.consoleScreenshotRefreshedAt == capturedAt)
        #expect(snapshot.latestConsoleLaunch?.previewStatus == .fresh)
    }

    @Test("local runtime reports running when latest QEMU launch pid is alive")
    func localRuntimeReportsRunningWhenLatestQEMULaunchPIDIsAlive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let processLogURL = qemuLaunchDirectory.appendingPathComponent("qemu-launch.log")
        let consoleScreenshotURL = qemuLaunchDirectory.appendingPathComponent("qemu-console.png")
        try Data("qemu log".utf8).write(to: processLogURL)
        try Data("png".utf8).write(to: consoleScreenshotURL)
        let launchRecord = QEMULaunchRecord(
            pid: 4321,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: [
                "-display",
                "cocoa",
                "driver=raw,file.driver=file,file.locking=off,file.filename=\(diskURL.path),if=none,id=system"
            ],
            processLogPath: processLogURL.path,
            monitorSocketPath: "/tmp/vq-live.sock",
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        try JSONEncoder.veilDiagnostics.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.driverMediaPath = driverURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let service = LocalVMRuntimeService(
            profileStore: store,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory),
            qemuLaunchProcessIsRunning: { $0 == 4321 }
        )

        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.state == .running)
        #expect(snapshot.latestConsoleLaunch?.pid == 4321)
        #expect(snapshot.latestConsoleScreenshotPath == consoleScreenshotURL.path)
    }

    @Test("local runtime reports installed Windows state from profile")
    func localRuntimeReportsInstalledWindowsState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.windowsInstalled = true
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        #expect(snapshot.windowsInstalled)
        #expect(snapshot.installEvidence.kind == .profileFlag)
        #expect(snapshot.installEvidence.isInstalled)
    }

    @Test("local runtime persists guest agent evidence as installed Windows")
    func localRuntimePersistsGuestAgentEvidenceAsInstalledWindows() async throws {
        let connectedAt = Date(timeIntervalSince1970: 1_783_000_000)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONVMProfileStore(directory: directory)
        let profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        try await store.save(profile)

        let service = LocalVMRuntimeService(
            profileStore: store,
            diagnosticDate: { connectedAt }
        )
        let snapshot = try await service.markGuestAgentConnected(agentVersion: "0.1.0")
        let savedProfile = try #require(await store.load())

        #expect(savedProfile.windowsInstalled == true)
        #expect(savedProfile.guestAgentVersion == "0.1.0")
        #expect(savedProfile.guestAgentConnectedAt == connectedAt)
        #expect(snapshot.windowsInstalled)
        #expect(snapshot.installEvidence.kind == .guestAgent)
        #expect(snapshot.installEvidence.isInstalled)
        #expect(snapshot.installEvidence.title == "Guest agent connected")
        #expect(snapshot.installEvidence.detail.contains("0.1.0"))
    }

    @Test("local runtime marks Windows installed without guest agent evidence")
    func localRuntimeMarksWindowsInstalledWithoutGuestAgentEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let diskURL = directory.appendingPathComponent("Windows.img")
        try Data("installed disk".utf8).write(to: diskURL)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.virtualDiskPath = diskURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.markWindowsInstalled()
        let savedProfile = try #require(await store.load())

        #expect(savedProfile.windowsInstalled == true)
        #expect(savedProfile.guestAgentVersion == nil)
        #expect(savedProfile.guestAgentConnectedAt == nil)
        #expect(snapshot.windowsInstalled)
        #expect(snapshot.installEvidence.kind == .profileFlag)
        #expect(snapshot.installEvidence.isInstalled)
    }

    @Test("local runtime reports sparse disk allocation evidence")
    func localRuntimeReportsSparseDiskAllocationEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))

        #expect(FileManager.default.createFile(atPath: diskURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: diskURL)
        try handle.truncate(atOffset: 128 * 1_024 * 1_024 * 1_024)
        try handle.close()

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()

        let allocatedBytes = try #require(snapshot.virtualDiskAllocatedBytes)
        #expect(snapshot.bootReady)
        #expect(allocatedBytes < 1_024 * 1_024 * 1_024)
        #expect(snapshot.detail == "Windows is not installed yet.")
        #expect(snapshot.installEvidence.kind == .sparseDisk)
        #expect(snapshot.installEvidence.isInstalled == false)
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

        #expect(provider.kind == .qemuHypervisor)
        #expect(provider.displayName == "QEMU/HVF")
        #expect(provider.acceleration == "HVF")
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
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.driverMediaPath = driverURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()
        let devices = try #require(snapshot.deviceSummary)
        let configuration = try #require(snapshot.configurationSummary)

        #expect(devices.platform == "Generic")
        #expect(devices.bootLoader == "EFI")
        #expect(devices.networkMode == "NAT")
        #expect(devices.graphics.widthInPixels == 1440)
        #expect(devices.graphics.heightInPixels == 900)
        #expect(devices.inputDevices == ["USB keyboard", "USB screen-coordinate pointer"])
        #expect(devices.entropyDevice == "Virtio entropy")
        #expect(devices.storageDevices.map(\.role) == ["installer", "auto-install", "drivers", "system-disk"])
        #expect(devices.storageDevices.map(\.attachment) == ["USB mass storage", "USB mass storage", "USB mass storage", "Virtio block"])
        #expect(devices.storageDevices.map(\.readOnly) == [true, true, true, false])
        #expect(devices.storageDevices.map(\.path) == [
            installerURL.path,
            sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso").path,
            driverURL.path,
            diskURL.path
        ])
        #expect(configuration.system.name == "Windows 11 Arm")
        #expect(configuration.system.cpuCount == profile.cpuCount)
        #expect(configuration.system.memoryMB == profile.memoryMB)
        #expect(configuration.system.diskGB == profile.diskGB)
        #expect(configuration.display.surface == "Embedded VNC loopback")
        #expect(configuration.display.widthInPixels == 1440)
        #expect(configuration.display.heightInPixels == 900)
        #expect(configuration.display.scalingMode == "aspect-fit host window")
        #expect(configuration.display.dynamicResolution == "fixed guest framebuffer until guest agent display bridge")
        #expect(configuration.display.retinaScaling == "host-rendered Retina interpolation")
        #expect(configuration.sharing.sharedFolderPath == sharedFolderURL.path)
        #expect(configuration.storage.devices.map(\.role) == ["installer", "auto-install", "drivers", "system-disk"])
        #expect(configuration.network.mode == "NAT")
        #expect(configuration.input.devices == ["USB keyboard", "USB screen-coordinate pointer"])
        #expect(configuration.guestAgent.isInstalled == false)
        #expect(configuration.guestAgent.version == nil)
    }

    @Test("installed Windows runtime does not require installer media")
    func installedWindowsRuntimeDoesNotRequireInstallerMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installed disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)

        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.windowsInstalled = true
        profile.guestAgentVersion = "0.1.0"
        profile.installerMediaPath = nil
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)

        let service = LocalVMRuntimeService(profileStore: store)
        let snapshot = try await service.loadSnapshot()
        let devices = try #require(snapshot.deviceSummary)

        #expect(snapshot.bootReady)
        #expect(snapshot.installerMediaPath == nil)
        #expect(snapshot.installEvidence.isInstalled)
        #expect(snapshot.detail == "Windows is installed and can be started.")
        #expect(snapshot.installationSteps.first { $0.id == "windows-installer" }?.detail.contains("no longer required") == true)
        #expect(snapshot.preflightChecks.first { $0.id == "installer-media" }?.state == .passed)
        #expect(devices.storageDevices.map(\.role) == ["system-disk"])
        #expect(devices.storageDevices.map(\.path) == [diskURL.path])
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
            resourcePlan: resourcePlan,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
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
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
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
        profile.installerMediaBookmarkData = try installerURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        profile.virtualDiskPath = diskURL.path
        profile.virtualDiskBookmarkData = try diskURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let installerBookmarkBase64 = try #require(profile.installerMediaBookmarkData?.base64EncodedString())
        let diskBookmarkBase64 = try #require(profile.virtualDiskBookmarkData?.base64EncodedString())
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
        #expect(bundle.profile?.installerMediaBookmarkData == nil)
        #expect(bundle.profile?.virtualDiskPath == diskURL.path)
        #expect(bundle.profile?.virtualDiskBookmarkData == nil)
        #expect(bundle.host.architecture == "arm64")
        #expect(bundle.host.processorCount >= 1)
        #expect(bundle.host.physicalMemoryBytes > 0)
        #expect(!json.contains("secret installer bytes"))
        #expect(!json.contains("secret disk bytes"))
        #expect(!json.contains(installerBookmarkBase64))
        #expect(!json.contains(diskBookmarkBase64))
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
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
        )

        let snapshot = try await service.prepareDefaultVM()
        let profile = try #require(await store.load())
        let diskPath = try #require(profile.virtualDiskPath)
        var sharedFolderIsDirectory: ObjCBool = false
        var diskIsDirectory: ObjCBool = false
        var tpmStateIsDirectory: ObjCBool = false
        var uefiVarsIsDirectory: ObjCBool = false
        let answerFileURL = URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("Autounattend.xml")
        let tpmStateURL = URL(fileURLWithPath: diskPath)
            .deletingLastPathComponent()
            .appendingPathComponent("tpm", isDirectory: true)
        let uefiVarsURL = URL(fileURLWithPath: diskPath)
            .deletingLastPathComponent()
            .appendingPathComponent("uefi-vars.fd")
        let agentBundleURL = URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("Veil Guest Agent", isDirectory: true)
        let installCommandURL = agentBundleURL.appendingPathComponent("Install Veil Agent.cmd")
        let startCommandURL = agentBundleURL.appendingPathComponent("Start Veil Agent.cmd")
        let diagnosticsCommandURL = agentBundleURL.appendingPathComponent("Collect Veil Agent Diagnostics.cmd")
        let repairCommandURL = agentBundleURL.appendingPathComponent("Repair Veil Agent Connectivity.cmd")
        let prepareSparsePackageCommandURL = agentBundleURL.appendingPathComponent("Prepare Sparse Package.cmd")
        let sparsePackageBootstrapCommandURL = agentBundleURL.appendingPathComponent("P.cmd")
        let bootstrapCommandURL = agentBundleURL.appendingPathComponent("V.cmd")
        let agentReadmeURL = agentBundleURL.appendingPathComponent("README.txt")
        let installScriptURL = agentBundleURL.appendingPathComponent("scripts/Install-VeilAgent.ps1")
        let publishScriptURL = agentBundleURL.appendingPathComponent("scripts/Publish-VeilAgentBundle.ps1")
        let sparsePackageScriptURL = agentBundleURL.appendingPathComponent("scripts/Build-VeilAgentSparsePackage.ps1")
        let startScriptURL = agentBundleURL.appendingPathComponent("scripts/Start-VeilAgent.ps1")
        let diagnosticsScriptURL = agentBundleURL.appendingPathComponent("scripts/Collect-VeilAgentDiagnostics.ps1")
        let repairScriptURL = agentBundleURL.appendingPathComponent("scripts/Repair-VeilAgentConnectivity.ps1")
        let packageManifestURL = agentBundleURL.appendingPathComponent("package/AppxManifest.xml")
        let projectURL = agentBundleURL.appendingPathComponent("src/VeilAgent/VeilAgent.csproj")
        let answerFile = try String(contentsOf: answerFileURL, encoding: .utf8)
        let installCommand = try String(contentsOf: installCommandURL, encoding: .utf8)
        let startCommand = try String(contentsOf: startCommandURL, encoding: .utf8)
        let diagnosticsCommand = try String(contentsOf: diagnosticsCommandURL, encoding: .utf8)
        let repairCommand = try String(contentsOf: repairCommandURL, encoding: .utf8)
        let prepareSparsePackageCommand = try String(contentsOf: prepareSparsePackageCommandURL, encoding: .utf8)
        let sparsePackageBootstrapCommand = try String(contentsOf: sparsePackageBootstrapCommandURL, encoding: .utf8)
        let bootstrapCommand = try String(contentsOf: bootstrapCommandURL, encoding: .utf8)
        let installScript = try String(contentsOf: installScriptURL, encoding: .utf8)
        let agentReadme = try String(contentsOf: agentReadmeURL, encoding: .utf8)

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
        #expect(FileManager.default.fileExists(atPath: tpmStateURL.path, isDirectory: &tpmStateIsDirectory))
        #expect(tpmStateIsDirectory.boolValue)
        if LocalQEMUWindowsBootPlanFactory.defaultFirmwareVarsTemplatePaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            #expect(FileManager.default.fileExists(atPath: uefiVarsURL.path, isDirectory: &uefiVarsIsDirectory))
            #expect(uefiVarsIsDirectory.boolValue == false)
        }
        #expect(snapshot.profileName == "Windows 11 Arm")
        #expect(snapshot.virtualDiskPath == diskPath)
        #expect(snapshot.automaticInstallAnswerFilePath == answerFileURL.path)
        #expect(snapshot.automaticInstallMediaPath == homeDirectory.appendingPathComponent("Veil Shared/VeilAutoInstall.iso").path)
        #expect(answerFile.contains("<unattend"))
        #expect(answerFile.contains("<AcceptEula>true</AcceptEula>"))
        #expect(answerFile.contains("<DiskConfiguration>"))
        #expect(answerFile.contains("<DiskID>0</DiskID>"))
        #expect(answerFile.contains("<WillWipeDisk>true</WillWipeDisk>"))
        #expect(answerFile.contains("<Type>EFI</Type>"))
        #expect(answerFile.contains("<Type>MSR</Type>"))
        #expect(answerFile.contains("<Type>Primary</Type>"))
        #expect(answerFile.contains("<Label>System</Label>"))
        #expect(answerFile.contains("<Format>FAT32</Format>"))
        #expect(answerFile.contains("<Label>Windows</Label>"))
        #expect(answerFile.contains("<Format>NTFS</Format>"))
        #expect(answerFile.contains("<ImageInstall>"))
        #expect(answerFile.contains("<InstallTo>"))
        #expect(answerFile.contains("<PartitionID>3</PartitionID>"))
        #expect(answerFile.contains("<Key>/IMAGE/NAME</Key>"))
        #expect(answerFile.contains("<Value>Windows 11 Pro</Value>"))
        #expect(answerFile.range(
            of: #"<DiskConfiguration>[\s\S]*?<WillShowUI>Never</WillShowUI>[\s\S]*?</DiskConfiguration>"#,
            options: .regularExpression
        ) != nil)
        #expect(answerFile.range(
            of: #"<ImageInstall>[\s\S]*?<WillShowUI>Never</WillShowUI>[\s\S]*?</ImageInstall>"#,
            options: .regularExpression
        ) != nil)
        #expect(!answerFile.contains("<WillShowUI>OnError</WillShowUI>"))
        #expect(answerFile.contains("<ProductKey>"))
        #expect(answerFile.contains("<WillShowUI>Never</WillShowUI>"))
        #expect(answerFile.contains("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>"))
        #expect(answerFile.contains("<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>"))
        #expect(answerFile.contains("HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE /v BypassNRO"))
        #expect(answerFile.contains("<FirstLogonCommands>"))
        #expect(answerFile.contains("Get-Volume -FileSystemLabel 'VEIL_AUTO'"))
        #expect(answerFile.contains("Veil Guest Agent\\scripts\\Bootstrap-VeilAgentFromMedia.ps1"))
        #expect(answerFile.range(
            of: #"<ProductKey>[\s\S]*?<Key>"#,
            options: .regularExpression
        ) == nil)
        #expect(FileManager.default.fileExists(atPath: installScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: publishScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: sparsePackageScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: startScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: diagnosticsScriptURL.path))
        #expect(FileManager.default.fileExists(atPath: packageManifestURL.path))
        #expect(FileManager.default.fileExists(atPath: projectURL.path))
        #expect(installCommand.contains("Install-VeilAgent.ps1"))
        #expect(installCommand.contains("-ExecutionPolicy Bypass"))
        #expect(installScript.contains("[string]$SparsePackagePath"))
        #expect(installScript.contains("[switch]$RequirePackageIdentity"))
        #expect(installScript.contains("-RequirePackageIdentity:$RequirePackageIdentity"))
        #expect(installScript.contains("Register-VeilSparsePackage"))
        #expect(installScript.contains("-RunLevel Limited"))
        #expect(!installScript.contains("-RunLevel LeastPrivilege"))
        #expect(installScript.contains(#""VEIL_AGENT_HOST", "0.0.0.0""#))
        #expect(installScript.contains("Continuing with current-session agent start"))
        #expect(installScript.contains("without a logon task"))
        let startScript = try String(contentsOf: startScriptURL, encoding: .utf8)
        #expect(startScript.contains(#"$ListenHost = "0.0.0.0""#))
        #expect(startScript.contains(#"$ProbeHost = "127.0.0.1""#))
        #expect(startCommand.contains("Start-VeilAgent.ps1"))
        #expect(diagnosticsCommand.contains("Collect-VeilAgentDiagnostics.ps1"))
        #expect(diagnosticsCommand.contains("-ExecutionPolicy Bypass"))
        #expect(repairCommand.contains("Repair-VeilAgentConnectivity.ps1"))
        #expect(repairCommand.contains("-ExecutionPolicy Bypass"))
        #expect(prepareSparsePackageCommand.contains("Build-VeilAgentSparsePackage.ps1"))
        #expect(prepareSparsePackageCommand.contains("%LOCALAPPDATA%\\Veil\\Agent\\package"))
        #expect(prepareSparsePackageCommand.contains("-StatusPath"))
        #expect(prepareSparsePackageCommand.contains("sparse-package-status.json"))
        #expect(prepareSparsePackageCommand.contains("-SparsePackagePath"))
        #expect(prepareSparsePackageCommand.contains("-RequirePackageIdentity"))
        #expect(sparsePackageBootstrapCommand.contains("Prepare Sparse Package.cmd"))
        #expect(sparsePackageBootstrapCommand.contains("VEIL_AGENT_AUTOMATION_HOLD"))
        #expect(sparsePackageBootstrapCommand.contains("Veil sparse package status will remain visible"))
        #expect(bootstrapCommand.contains("Repair Veil Agent Connectivity.cmd"))
        #expect(bootstrapCommand.contains("Install Veil Agent.cmd"))
        #expect(bootstrapCommand.contains("VEIL_AGENT_AUTOMATION_HOLD"))
        #expect(bootstrapCommand.contains("Veil automation status will remain visible"))
        #expect(FileManager.default.fileExists(atPath: repairScriptURL.path))
        #expect(agentReadme.contains("Install Veil Agent.cmd"))
        #expect(agentReadme.contains("Prepare Sparse Package.cmd"))
        #expect(agentReadme.contains("sparse-package-status.json"))
        #expect(agentReadme.contains("P.cmd"))
        #expect(agentReadme.contains("V.cmd"))
        #expect(agentReadme.contains("Repair Veil Agent Connectivity.cmd"))
        #expect(agentReadme.contains("Collect Veil Agent Diagnostics.cmd"))
        #expect(agentReadme.contains("diagnostics ZIP"))
        #expect(agentReadme.contains("0.0.0.0:18444"))
        #expect(agentReadme.contains("ws://127.0.0.1:18444/"))
        #expect(agentReadme.contains("%LOCALAPPDATA%\\Veil\\Agent\\logs"))
        #expect(snapshot.installationSteps.first { $0.id == "shared-folder" }?.state == .complete)
        #expect(snapshot.installationSteps.first { $0.id == "auto-install-answer-file" }?.state == .complete)
        #expect(snapshot.installationSteps.first { $0.id == "virtual-disk" }?.state == .complete)
    }

    @Test("prepare default VM does not scan Downloads for installer media")
    func prepareDefaultVMDoesNotScanDownloadsForInstallerMedia() async throws {
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
        )

        let snapshot = try await service.prepareDefaultVM()
        let profile = try #require(await store.load())

        #expect(profile.installerMediaPath == nil)
        #expect(FileManager.default.fileExists(atPath: installerURL.path))
        #expect(snapshot.installerMediaPath == nil)
        #expect(snapshot.discoveredInstallerMediaPath == nil)
        #expect(snapshot.installationSteps.first { $0.id == "windows-installer" }?.state == .blocked)
        #expect(!snapshot.bootReady)
    }

    @Test("automatic install media is rebuilt when the answer file is newer")
    func automaticInstallMediaIsRebuiltWhenAnswerFileIsNewer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let answerFileURL = directory.appendingPathComponent("Autounattend.xml")
        let mediaURL = directory.appendingPathComponent("VeilAutoInstall.iso")
        try Data("answer v2".utf8).write(to: answerFileURL)
        try Data("stale media".utf8).write(to: mediaURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: mediaURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 20)],
            ofItemAtPath: answerFileURL.path
        )
        final class Capture: @unchecked Sendable {
            var processCalls = 0
        }
        let capture = Capture()
        let builder = HdiutilAutomaticInstallMediaBuilder { _, arguments in
            capture.processCalls += 1
            let outputIndex = try #require(arguments.firstIndex(of: "-o"))
            #expect(arguments.indices.contains(outputIndex + 1))
            let outputPath = arguments[outputIndex + 1]
            try Data("fresh media".utf8).write(to: URL(fileURLWithPath: "\(outputPath).iso"))
            return 0
        }

        try builder.prepareMedia(answerFileURL: answerFileURL, mediaURL: mediaURL)

        #expect(capture.processCalls == 1)
        #expect(try String(contentsOf: mediaURL, encoding: .utf8) == "fresh media")
    }

    @Test("automatic install media includes the guest agent bundle")
    func automaticInstallMediaIncludesGuestAgentBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let answerFileURL = directory.appendingPathComponent("Autounattend.xml")
        let mediaURL = directory.appendingPathComponent("VeilAutoInstall.iso")
        let agentBundleURL = directory.appendingPathComponent("Veil Guest Agent", isDirectory: true)
        let scriptsURL = agentBundleURL.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
        try Data("answer".utf8).write(to: answerFileURL)
        try Data("installer".utf8).write(to: agentBundleURL.appendingPathComponent("Install Veil Agent.cmd"))
        try Data("diagnostics".utf8).write(to: agentBundleURL.appendingPathComponent("Collect Veil Agent Diagnostics.cmd"))
        try Data("repair".utf8).write(to: agentBundleURL.appendingPathComponent("Repair Veil Agent Connectivity.cmd"))
        try Data("sparse".utf8).write(to: agentBundleURL.appendingPathComponent("Prepare Sparse Package.cmd"))
        try Data("sparse bootstrap".utf8).write(to: agentBundleURL.appendingPathComponent("P.cmd"))
        try Data("bootstrap".utf8).write(to: agentBundleURL.appendingPathComponent("V.cmd"))
        try Data("script".utf8).write(to: scriptsURL.appendingPathComponent("Install-VeilAgent.ps1"))
        try Data("diagnostics script".utf8).write(to: scriptsURL.appendingPathComponent("Collect-VeilAgentDiagnostics.ps1"))
        try Data("repair script".utf8).write(to: scriptsURL.appendingPathComponent("Repair-VeilAgentConnectivity.ps1"))
        try Data("sparse script".utf8).write(to: scriptsURL.appendingPathComponent("Build-VeilAgentSparsePackage.ps1"))
        let packageURL = agentBundleURL.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try Data("manifest".utf8).write(to: packageURL.appendingPathComponent("AppxManifest.xml"))
        final class Capture: @unchecked Sendable {
            var stagedInstallCommandExists = false
            var stagedScriptExists = false
            var stagedDiagnosticsCommandExists = false
            var stagedDiagnosticsScriptExists = false
            var stagedRepairCommandExists = false
            var stagedRepairScriptExists = false
            var stagedPrepareSparsePackageCommandExists = false
            var stagedSparsePackageBootstrapCommandExists = false
            var stagedSparsePackageScriptExists = false
            var stagedPackageManifestExists = false
            var stagedBootstrapCommandExists = false
        }
        let capture = Capture()
        let builder = HdiutilAutomaticInstallMediaBuilder { _, arguments in
            let outputIndex = try #require(arguments.firstIndex(of: "-o"))
            let stagingPath = try #require(arguments.last)
            let stagingURL = URL(fileURLWithPath: stagingPath)
            capture.stagedInstallCommandExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/Install Veil Agent.cmd").path
            )
            capture.stagedScriptExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/scripts/Install-VeilAgent.ps1").path
            )
            capture.stagedDiagnosticsCommandExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/Collect Veil Agent Diagnostics.cmd").path
            )
            capture.stagedDiagnosticsScriptExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/scripts/Collect-VeilAgentDiagnostics.ps1").path
            )
            capture.stagedRepairCommandExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/Repair Veil Agent Connectivity.cmd").path
            )
            capture.stagedRepairScriptExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/scripts/Repair-VeilAgentConnectivity.ps1").path
            )
            capture.stagedPrepareSparsePackageCommandExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/Prepare Sparse Package.cmd").path
            )
            capture.stagedSparsePackageBootstrapCommandExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/P.cmd").path
            )
            capture.stagedSparsePackageScriptExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/scripts/Build-VeilAgentSparsePackage.ps1").path
            )
            capture.stagedPackageManifestExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/package/AppxManifest.xml").path
            )
            capture.stagedBootstrapCommandExists = FileManager.default.fileExists(
                atPath: stagingURL.appendingPathComponent("Veil Guest Agent/V.cmd").path
            )
            let outputPath = arguments[outputIndex + 1]
            try Data("fresh media".utf8).write(to: URL(fileURLWithPath: "\(outputPath).iso"))
            return 0
        }

        try builder.prepareMedia(answerFileURL: answerFileURL, mediaURL: mediaURL)

        #expect(capture.stagedInstallCommandExists)
        #expect(capture.stagedScriptExists)
        #expect(capture.stagedDiagnosticsCommandExists)
        #expect(capture.stagedDiagnosticsScriptExists)
        #expect(capture.stagedRepairCommandExists)
        #expect(capture.stagedRepairScriptExists)
        #expect(capture.stagedPrepareSparsePackageCommandExists)
        #expect(capture.stagedSparsePackageBootstrapCommandExists)
        #expect(capture.stagedSparsePackageScriptExists)
        #expect(capture.stagedPackageManifestExists)
        #expect(capture.stagedBootstrapCommandExists)
    }

    @Test("load snapshot avoids Downloads installer discovery before profile exists")
    func loadSnapshotAvoidsDownloadsInstallerDiscoveryBeforeProfileExists() async throws {
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
        )

        let snapshot = try await service.loadSnapshot()
        let storedProfile = try await store.load()

        #expect(FileManager.default.fileExists(atPath: installerURL.path))
        #expect(snapshot.discoveredInstallerMediaPath == nil)
        #expect(snapshot.installerMediaPath == nil)
        #expect(storedProfile == nil)
    }

    @Test("load snapshot avoids Downloads installer discovery without mutating profile")
    func loadSnapshotAvoidsDownloadsInstallerDiscoveryWithoutMutatingProfile() async throws {
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
        )

        let snapshot = try await service.loadSnapshot()
        let storedProfile = try #require(await store.load())

        #expect(FileManager.default.fileExists(atPath: installerURL.path))
        #expect(snapshot.discoveredInstallerMediaPath == nil)
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
        )

        let snapshot = try await service.prepareDefaultVM()
        let storedProfile = try #require(await store.load())

        #expect(storedProfile.installerMediaPath == configuredInstallerURL.path)
        #expect(snapshot.installerMediaPath == configuredInstallerURL.path)
        #expect(snapshot.discoveredInstallerMediaPath == nil)
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
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
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder()
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
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
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

    @Test("local runtime starts installed Windows without installer media")
    func localRuntimeStartsInstalledWindowsWithoutInstallerMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installed disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.windowsInstalled = true
        profile.guestAgentVersion = "0.1.0"
        profile.installerMediaPath = nil
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running)
        let service = LocalVMRuntimeService(profileStore: store, bootRunner: bootRunner)

        let snapshot = try await service.start()

        #expect(snapshot.state == .running)
        #expect(bootRunner.startCount == 1)
        #expect(bootRunner.startedProfile?.installerMediaPath == nil)
        #expect(bootRunner.startedProfile?.virtualDiskPath == diskURL.path)
    }

    @Test("local runtime starts with paths resolved from security scoped bookmarks")
    func localRuntimeStartsWithPathsResolvedFromSecurityScopedBookmarks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = directory.appendingPathComponent("Moved-Windows.iso").path
        profile.installerMediaBookmarkData = try installerURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        profile.virtualDiskPath = directory.appendingPathComponent("Moved-Windows.img").path
        profile.virtualDiskBookmarkData = try diskURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        let bootRunner = FakeVMRuntimeBooter(startState: .running)
        let service = LocalVMRuntimeService(profileStore: store, bootRunner: bootRunner)

        let snapshot = try await service.start()

        #expect(snapshot.state == .running)
        #expect(bootRunner.startCount == 1)
        #expect(bootRunner.startedProfile?.installerMediaPath == canonicalPath(installerURL))
        #expect(bootRunner.startedProfile?.virtualDiskPath == canonicalPath(diskURL))
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
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
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
        #expect(report.deviceSummary.storageDevices.map(\.role) == ["installer", "auto-install", "system-disk"])
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
        try Data("<unattend />".utf8).write(to: sharedFolderURL.appendingPathComponent("Autounattend.xml"))
        try Data("auto install media".utf8).write(to: sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso"))
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
        #expect(report.profile.installerMediaBookmarkData == nil)
        #expect(report.profile.virtualDiskBookmarkData == nil)
        #expect(bundle.lastBootReport?.result == .failed)
        #expect(bundle.lastBootReport?.errorMessage == "Simulated boot failure.")
        #expect(bundle.lastBootReport?.profile.installerMediaBookmarkData == nil)
        #expect(bundle.lastBootReport?.profile.virtualDiskBookmarkData == nil)
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

    @Test("local runtime stops a running QEMU launch record")
    func localRuntimeStopsRunningQEMULaunchRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let installerURL = directory.appendingPathComponent("Windows.iso")
        let diskURL = directory.appendingPathComponent("Windows.img")
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        try Data("installer".utf8).write(to: installerURL)
        try Data("disk".utf8).write(to: diskURL)
        try FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
        let qemuLaunchDirectory = directory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: qemuLaunchDirectory, withIntermediateDirectories: true)
        let launchRecord = QEMULaunchRecord(
            pid: 4321,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-drive", "file=\(diskURL.path)"],
            processLogPath: qemuLaunchDirectory.appendingPathComponent("qemu-launch.log").path,
            monitorSocketPath: "/tmp/vq-test.sock",
            qmpSocketPath: "/tmp/vq-test.qmp.sock",
            consoleScreenshotPath: nil,
            startedAt: Date(timeIntervalSince1970: 1_782_838_800)
        )
        try JSONEncoder.veilDiagnostics.encode(launchRecord)
            .write(to: qemuLaunchDirectory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.installerMediaPath = installerURL.path
        profile.virtualDiskPath = diskURL.path
        profile.sharedFolderPath = sharedFolderURL.path
        try await store.save(profile)
        final class TerminationCapture: @unchecked Sendable {
            var pids: [Int32] = []
        }
        let terminationCapture = TerminationCapture()
        let bootRunner = FakeVMRuntimeBooter(startState: .running, currentState: nil)
        let service = LocalVMRuntimeService(
            profileStore: store,
            bootRunner: bootRunner,
            qemuLaunchRecordStore: JSONQEMULaunchRecordStore(directory: qemuLaunchDirectory),
            qemuLaunchProcessIsRunning: { pid in pid == 4321 },
            qemuLaunchProcessTerminator: { pid in
                terminationCapture.pids.append(pid)
                return true
            }
        )

        let snapshot = try await service.stop()

        #expect(bootRunner.stopCount == 1)
        #expect(terminationCapture.pids == [4321])
        #expect(snapshot.state == .stopped)
    }

    @Test("prepare default VM copies secure boot UEFI vars when available")
    func prepareDefaultVMCopiesSecureBootUEFIVarsWhenAvailable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let firmwareDirectory = directory.appendingPathComponent("Firmware", isDirectory: true)
        try FileManager.default.createDirectory(at: firmwareDirectory, withIntermediateDirectories: true)
        let secureVarsTemplateURL = firmwareDirectory.appendingPathComponent("edk2-arm-secure-vars.fd")
        try Data("secure-vars-template".utf8).write(to: secureVarsTemplateURL)
        let store = JSONVMProfileStore(directory: directory)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder(),
            firmwareVarsTemplatePaths: [secureVarsTemplateURL.path]
        )

        _ = try await service.prepareDefaultVM()
        let profile = try #require(await store.load())
        let diskPath = try #require(profile.virtualDiskPath)
        let uefiVarsURL = URL(fileURLWithPath: diskPath)
            .deletingLastPathComponent()
            .appendingPathComponent("uefi-vars.fd")
        let copiedVars = try String(contentsOf: uefiVarsURL, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: uefiVarsURL.path)
        let fileSize = try #require(attributes[.size] as? UInt64)

        #expect(copiedVars.hasPrefix("secure-vars-template"))
        #expect(fileSize == 64 * 1_024 * 1_024)
    }

    @Test("prepare default VM upgrades existing UEFI vars to secure vars before Windows install")
    func prepareDefaultVMUpgradesExistingUEFIVarsToSecureVarsBeforeWindowsInstall() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = directory.appendingPathComponent("Home", isDirectory: true)
        let firmwareDirectory = directory.appendingPathComponent("Firmware", isDirectory: true)
        let vmDirectory = homeDirectory
            .appendingPathComponent("Virtual Machines", isDirectory: true)
            .appendingPathComponent("Veil", isDirectory: true)
        try FileManager.default.createDirectory(at: firmwareDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vmDirectory, withIntermediateDirectories: true)
        let secureVarsTemplateURL = firmwareDirectory.appendingPathComponent("edk2-arm-secure-vars.fd")
        let diskURL = vmDirectory.appendingPathComponent("Windows 11 Arm.img")
        let existingVarsURL = vmDirectory.appendingPathComponent("uefi-vars.fd")
        try Data("secure-vars-template".utf8).write(to: secureVarsTemplateURL)
        try Data("disk".utf8).write(to: diskURL)
        try Data("old-insecure-vars".utf8).write(to: existingVarsURL)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(
            createdAt: Date(timeIntervalSince1970: 1_782_752_400),
            homeDirectory: homeDirectory
        )
        profile.virtualDiskPath = diskURL.path
        profile.windowsInstalled = false
        try await store.save(profile)
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: homeDirectory,
            automaticInstallMediaBuilder: FakeAutomaticInstallMediaBuilder(),
            firmwareVarsTemplatePaths: [secureVarsTemplateURL.path]
        )

        _ = try await service.prepareDefaultVM()
        let copiedVars = try String(contentsOf: existingVarsURL, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: existingVarsURL.path)
        let fileSize = try #require(attributes[.size] as? UInt64)

        #expect(copiedVars.hasPrefix("secure-vars-template"))
        #expect(fileSize == 64 * 1_024 * 1_024)
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

private func resolvedBookmarkPath(_ data: Data) throws -> String {
    var isStale = false
    let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )
    let didStart = url.startAccessingSecurityScopedResource()
    defer {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
    #expect(!isStale)
    return canonicalPath(url)
}

private func canonicalPath(_ url: URL) -> String {
    let path = url.resolvingSymlinksInPath().path
    if path.hasPrefix("/var/") {
        return "/private\(path)"
    }
    return path
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
