import Foundation
import Testing

@testable import VeilHostCore

/// Records qemu-img calls and stands in for the tool: `create` and `convert` write a qcow2 header to
/// their output file, everything else answers from `replies`.
private final class FakeQEMUImage: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var replies: [String: QEMUProcessOutcome] = [:]

    var calls: [[String]] {
        lock.withLock { recorded }
    }

    func run(_ path: String, _ arguments: [String]) -> QEMUProcessOutcome {
        lock.withLock { recorded.append(arguments) }
        switch arguments.first {
        case "create":
            FileManager.default.createFile(atPath: arguments[4], contents: Data(QEMUDiskImageFormat.qcow2Magic + [0, 0, 0, 3]))
        case "convert":
            FileManager.default.createFile(atPath: arguments[6], contents: Data(QEMUDiskImageFormat.qcow2Magic + [0, 0, 0, 3]))
        default:
            if let reply = replies[arguments.first ?? ""] {
                return reply
            }
        }
        return QEMUProcessOutcome(terminationStatus: 0, standardOutput: "")
    }

    var tool: QEMUDiskImageTool {
        QEMUDiskImageTool(toolPath: "/Applications/Veil.app/Contents/Resources/Runtime/bin/qemu-img") { self.run($0, $1) }
    }
}

private actor JobQMP: QEMUQMPControlling {
    private(set) var commands: [QEMUQMPCommand] = []
    private let jobError: String?
    private var polls = 0

    init(jobError: String? = nil) {
        self.jobError = jobError
    }

    func execute(_ commands: [QEMUQMPCommand], socketPath: String, idleTimeoutSeconds: Int) async throws -> [QEMUQMPReply] {
        self.commands.append(contentsOf: commands)
        return commands.map { command in
            guard command == .queryJobs else {
                return QEMUQMPReply(id: nil, isSuccess: true)
            }
            polls += 1
            // The job is still running on the first poll.
            let status = polls == 1 ? "running" : "concluded"
            return QEMUQMPReply(id: nil, isSuccess: true, jobsReturn: [QEMUQMPJob(id: "job-1", status: status, error: status == "concluded" ? jobError : nil)])
        }
    }
}

@Suite("qcow2 disks and snapshots")
struct QEMUDiskImageTests {
    private let gigabyte: Int64 = 1_024 * 1_024 * 1_024

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("the format comes from the file header, or from the extension before the file exists")
    func detectsFormat() throws {
        let directory = try temporaryDirectory()
        let qcow2 = directory.appendingPathComponent("named.img")
        try Data(QEMUDiskImageFormat.qcow2Magic + [0, 0, 0, 3]).write(to: qcow2)
        let raw = directory.appendingPathComponent("named.qcow2")
        try Data(count: 512).write(to: raw)

        #expect(QEMUDiskImageFormat.detect(atPath: qcow2.path) == .qcow2)
        #expect(QEMUDiskImageFormat.detect(atPath: raw.path) == .raw)
        #expect(QEMUDiskImageFormat.detect(atPath: directory.appendingPathComponent("new.qcow2").path) == .qcow2)
        #expect(QEMUDiskImageFormat.detect(atPath: directory.appendingPathComponent("new.img").path) == .raw)
    }

    @Test("qemu-img info JSON gives the format and both sizes")
    func parsesInfo() {
        let info = QEMUDiskImageInfo.parse(#"{"virtual-size": 137438953472, "filename": "w.qcow2", "format": "qcow2", "actual-size": 200704, "dirty-flag": false}"#)
        #expect(info == QEMUDiskImageInfo(format: .qcow2, virtualSizeBytes: 137_438_953_472, actualSizeBytes: 200_704))
        #expect(QEMUDiskImageInfo.parse(#"{"format": "vmdk", "virtual-size": 1}"#) == nil)
    }

    @Test("qemu-img is taken from Veil.app first, then beside the QEMU Veil would launch")
    func locatesBundledToolFirst() {
        let runtime = URL(fileURLWithPath: "/Applications/Veil.app/Contents/Resources/Runtime", isDirectory: true)
        let candidates = QEMUDiskImageTool.candidatePaths(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            bundledRuntimeDirectory: runtime
        )
        #expect(candidates.first == "/Applications/Veil.app/Contents/Resources/Runtime/bin/qemu-img")
        #expect(candidates.contains("/opt/homebrew/bin/qemu-img"))
        #expect(Set(candidates).count == candidates.count)

        let tool = QEMUDiskImageTool.located(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            bundledRuntimeDirectory: nil,
            isExecutable: { $0 == "/opt/homebrew/bin/qemu-img" }
        )
        #expect(tool?.toolPath == "/opt/homebrew/bin/qemu-img")
    }

    @Test("qemu-img commands, and errors keep what qemu-img printed")
    func buildsCommands() throws {
        let fake = FakeQEMUImage()
        fake.replies["resize"] = QEMUProcessOutcome(terminationStatus: 1, standardOutput: "qemu-img: Image is locked\n")
        let tool = fake.tool

        try tool.createQCOW2(path: "/vm/w.qcow2", sizeBytes: 128 * gigabyte)
        try tool.convertToQCOW2(source: "/vm/w.img", destination: "/vm/w.qcow2.partial")
        try tool.createSnapshot(path: "/vm/w.qcow2", tag: "before-update")
        #expect(throws: VMSnapshotError.invalidTag("bad name")) {
            try tool.applySnapshot(path: "/vm/w.qcow2", tag: "bad name")
        }
        #expect(throws: QEMUDiskImageError.shrinkNotSupported(currentBytes: 128 * gigabyte, requestedBytes: 64 * gigabyte)) {
            try tool.grow(path: "/vm/w.qcow2", format: .qcow2, currentBytes: 128 * gigabyte, newSizeBytes: 64 * gigabyte)
        }
        #expect(throws: QEMUDiskImageError.commandFailed(command: "qemu-img resize", message: "qemu-img: Image is locked")) {
            try tool.grow(path: "/vm/w.qcow2", format: .qcow2, currentBytes: 128 * gigabyte, newSizeBytes: 256 * gigabyte)
        }

        #expect(fake.calls == [
            ["create", "-q", "-f", "qcow2", "/vm/w.qcow2", "137438953472"],
            ["convert", "-f", "raw", "-O", "qcow2", "/vm/w.img", "/vm/w.qcow2.partial"],
            ["snapshot", "-c", "before-update", "/vm/w.qcow2"],
            ["resize", "-q", "-f", "qcow2", "/vm/w.qcow2", "274877906944"]
        ])
    }

    @Test("a qcow2 system disk boots as qcow2 with a node name, and a raw one is unchanged")
    func bootPlanFollowsDiskFormat() throws {
        var profile = VMProfile.defaultWindows11Arm(homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true))
        profile.installerMediaPath = "/Users/test/Downloads/Win11_Arm64.iso"
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"

        let qcow2Plan = try QEMUWindowsBootPlanner(executablePath: "/opt/homebrew/bin/qemu-system-aarch64", isExecutableAvailable: true)
            .makePlan(for: profile)
        #expect(qcow2Plan.arguments.contains("if=none,id=system,format=qcow2,node-name=veil-system,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"))
        #expect(VMSnapshotCapabilityFactory.systemDiskFormat(in: qcow2Plan.arguments) == "qcow2")

        let launch = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: qcow2Plan,
            serialLogPath: "/tmp/serial.log",
            monitorSocketPath: "/tmp/m.sock",
            qmpSocketPath: "/tmp/q.sock"
        )
        #expect(launch.contains("driver=qcow2,node-name=veil-system,file.driver=file,file.locking=off,file.filename=/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2,if=none,id=system"))
        #expect(VMSnapshotCapabilityFactory.systemDiskFormat(in: launch) == "qcow2")

        // An older disk keeps booting as raw even when its file is named .qcow2, because the header says so.
        let rawPlan = try QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            systemDiskFormat: { _ in .raw }
        ).makePlan(for: profile)
        #expect(rawPlan.arguments.contains("if=none,id=system,format=raw,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"))
    }

    @Test("snapshot jobs name only the system disk node and wait for QEMU to finish")
    func snapshotJobs() async throws {
        let qmp = JobQMP()
        let controller = QEMUSnapshotController(qmp: qmp, sleeper: { _ in }, makeJobID: { "job-1" })

        _ = try await controller.create(tag: "before-update", qmpSocketPath: "/tmp/q.sock")

        let commands = await qmp.commands
        #expect(commands == [
            .snapshotSave(jobID: "job-1", tag: "before-update", node: "veil-system"),
            .queryJobs,
            .queryJobs,
            .jobDismiss(jobID: "job-1")
        ])
        let line = try QEMUQMPCommand.snapshotSave(jobID: "job-1", tag: "before-update", node: "veil-system").jsonLine(id: "x")
        #expect(line == #"{"arguments":{"devices":["veil-system"],"job-id":"job-1","tag":"before-update","vmstate":"veil-system"},"execute":"snapshot-save","id":"x"}"#)

        let missing = QEMUSnapshotController(qmp: JobQMP(jobError: "Snapshot 'nope' does not exist in one or more devices"), sleeper: { _ in }, makeJobID: { "job-1" })
        await #expect(throws: VMSnapshotError.snapshotNotFound("nope")) {
            try await missing.restore(tag: "nope", qmpSocketPath: "/tmp/q.sock")
        }
    }

    @Test("query-jobs replies are read as jobs")
    func parsesJobs() {
        let replies = QEMUQMPClient.parseReplies(from: #"{"return": [{"current-progress": 1, "status": "concluded", "total-progress": 1, "type": "snapshot-load", "id": "l2", "error": "Snapshot 'nope' does not exist in one or more devices"}], "id": "veil-qmp-0"}"#)
        #expect(replies.first?.jobsReturn == [QEMUQMPJob(id: "l2", status: "concluded", error: "Snapshot 'nope' does not exist in one or more devices")])
    }

    // MARK: - Runtime service

    private struct Fixture {
        let store: JSONVMProfileStore
        let home: URL
        let fake: FakeQEMUImage
        let discarded: DiscardedFiles
        func service(tool: Bool = true) -> LocalVMRuntimeService {
            LocalVMRuntimeService(
                profileStore: store,
                defaultHomeDirectory: home,
                automaticInstallMediaBuilder: StubMediaBuilder(),
                firmwareVarsTemplatePaths: [],
                installationDiscarder: { [discarded] in try discarded.record($0) },
                diskImageTool: tool ? fake.tool : nil
            )
        }
    }

    private func makeFixture(diskPath: String? = nil) async throws -> Fixture {
        let directory = try temporaryDirectory()
        let home = directory.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400), homeDirectory: home)
        profile.virtualDiskPath = diskPath
        try await store.save(profile)
        return Fixture(store: store, home: home, fake: FakeQEMUImage(), discarded: DiscardedFiles())
    }

    @Test("a new Windows disk is qcow2, and raw only without qemu-img")
    func newDisksAreQCOW2() async throws {
        let fixture = try await makeFixture()
        let snapshot = try await fixture.service().prepareDefaultVM()
        let path = try #require(snapshot.virtualDiskPath)
        #expect(path.hasSuffix("Virtual Machines/Veil/Windows 11 Arm.qcow2"))
        #expect(QEMUDiskImageFormat.detect(atPath: path) == .qcow2)
        #expect(fixture.fake.calls.first?.prefix(4) == ["create", "-q", "-f", "qcow2"])

        let withoutTool = try await makeFixture()
        let rawPath = try #require(try await withoutTool.service(tool: false).prepareDefaultVM().virtualDiskPath)
        #expect(rawPath.hasSuffix("Windows 11 Arm.img"))
        #expect(QEMUDiskImageFormat.detect(atPath: rawPath) == .raw)
    }

    @Test("converting moves the VM to a qcow2 copy and the raw disk to the Trash")
    func convertsRawDisk() async throws {
        let directory = try temporaryDirectory()
        let rawURL = directory.appendingPathComponent("Windows 11 Arm.img")
        try Data(count: 4_096).write(to: rawURL)
        let fixture = try await makeFixture(diskPath: rawURL.path)
        let service = fixture.service()

        await #expect(throws: QEMUDiskImageError.self) {
            _ = try await service.convertDiskToQCOW2(availableBytes: { _ in 1 })
        }
        #expect(fixture.discarded.names.isEmpty)

        let status = try #require(try await service.convertDiskToQCOW2(availableBytes: { _ in 1 << 40 }))
        #expect(status.format == .qcow2)
        #expect(status.path == directory.appendingPathComponent("Windows 11 Arm.qcow2").path)
        #expect(try await fixture.store.load()?.virtualDiskPath == status.path)
        #expect(fixture.discarded.names == ["Windows 11 Arm.img"])
        #expect(!FileManager.default.fileExists(atPath: status.path + ".partial"))

        await #expect(throws: QEMUDiskImageError.alreadyQCOW2) {
            _ = try await service.convertDiskToQCOW2()
        }
    }

    @Test("growing a stopped disk resizes it and records the new size")
    func growsDisk() async throws {
        let directory = try temporaryDirectory()
        let diskURL = directory.appendingPathComponent("Windows 11 Arm.qcow2")
        try Data(QEMUDiskImageFormat.qcow2Magic + [0, 0, 0, 3]).write(to: diskURL)
        let fixture = try await makeFixture(diskPath: diskURL.path)
        fixture.fake.replies["info"] = QEMUProcessOutcome(
            terminationStatus: 0,
            standardOutput: #"{"virtual-size": 137438953472, "format": "qcow2", "actual-size": 200704}"#
        )

        _ = try await fixture.service().growDisk(toGB: 256)

        #expect(fixture.fake.calls.contains(["resize", "-q", "-f", "qcow2", diskURL.path, "274877906944"]))
        #expect(try await fixture.store.load()?.diskGB == 256)
    }

    @Test("a stopped Windows snapshots its disk with qemu-img; a raw disk is refused")
    func offlineSnapshots() async throws {
        let directory = try temporaryDirectory()
        let diskURL = directory.appendingPathComponent("Windows 11 Arm.qcow2")
        try Data(QEMUDiskImageFormat.qcow2Magic + [0, 0, 0, 3]).write(to: diskURL)
        let fixture = try await makeFixture(diskPath: diskURL.path)
        fixture.fake.replies["snapshot"] = QEMUProcessOutcome(
            terminationStatus: 0,
            standardOutput: """
            Snapshot list:
            ID        TAG               VM_SIZE                DATE        VM_CLOCK     ICOUNT
            1         clean               0 B 2026-11-05 14:00:53  0000:00:00.000         --
            """
        )
        let service = fixture.service()

        let status = try #require(try await service.createSnapshot(named: "clean"))
        _ = try await service.restoreSnapshot(named: "clean")
        _ = try await service.deleteSnapshot(named: "clean")

        #expect(status.snapshots.map(\.tag) == ["clean"])
        #expect(!LocalVMRuntimeService.snapshotHasMemoryState(status.snapshots[0]))
        let changes = fixture.fake.calls.filter { $0.first == "snapshot" && $0[1] != "-U" }
        #expect(changes == [
            ["snapshot", "-c", "clean", diskURL.path],
            ["snapshot", "-a", "clean", diskURL.path],
            ["snapshot", "-d", "clean", diskURL.path]
        ])

        let rawURL = directory.appendingPathComponent("Old.img")
        try Data(count: 512).write(to: rawURL)
        let rawFixture = try await makeFixture(diskPath: rawURL.path)
        await #expect(throws: VMDiskError.snapshotsNeedQCOW2) {
            _ = try await rawFixture.service().createSnapshot(named: "clean")
        }
    }

    @Test("a disk named like the converted copy gets a distinct qcow2 name")
    func convertedNames() {
        #expect(LocalVMRuntimeService.convertedDiskURL(for: URL(fileURLWithPath: "/vm/Windows 11 Arm.img")).path == "/vm/Windows 11 Arm.qcow2")
        #expect(LocalVMRuntimeService.convertedDiskURL(for: URL(fileURLWithPath: "/vm/disk.qcow2")).path == "/vm/disk-converted.qcow2")
    }
}

private struct StubMediaBuilder: AutomaticInstallMediaBuilding {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("media".utf8).write(to: mediaURL)
    }
}

private final class DiscardedFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var names: [String] {
        lock.withLock { recorded }
    }

    func record(_ url: URL) throws {
        lock.withLock { recorded.append(url.lastPathComponent) }
        try FileManager.default.removeItem(at: url)
    }
}
