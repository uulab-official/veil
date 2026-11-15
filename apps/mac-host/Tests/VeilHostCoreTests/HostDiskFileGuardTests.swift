import Foundation
import Testing
@testable import VeilHostCore

@Suite("Host disk file guard")
struct HostDiskFileGuardTests {
    private static let gib = HostDiskSpaceGuard.gibibyte

    @Test("Only a path that is definitely gone counts as missing")
    func missingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("disk.img")
        #expect(HostDiskFileGuard.fileIsMissing(atPath: file.path))
        FileManager.default.createFile(atPath: file.path, contents: Data())
        #expect(!HostDiskFileGuard.fileIsMissing(atPath: file.path))
    }

    @Test("A missing disk is reported only for a QEMU that still runs")
    func missingDiskNeedsLiveQEMU() {
        #expect(HostDiskFileGuard.missingDiskPath(
            launchRecord: Self.record,
            processIsRunning: { _ in true },
            fileIsMissing: { _ in true }
        ) == "/tmp/veil-missing/disk.img")
        #expect(HostDiskFileGuard.missingDiskPath(
            launchRecord: Self.record,
            processIsRunning: { _ in false },
            fileIsMissing: { _ in true }
        ) == nil)
        #expect(HostDiskFileGuard.missingDiskPath(
            launchRecord: Self.record,
            processIsRunning: { _ in true },
            fileIsMissing: { _ in false }
        ) == nil)
        #expect(HostDiskFileGuard.missingDiskPath(launchRecord: nil, processIsRunning: { _ in true }) == nil)
    }

    @Test("The disk is mirrored to its path in its own format, then the drive switches over")
    func restoresByMirroring() async throws {
        let path = try Self.missingPath()
        let qmp = MirrorQMP(path: path, jobStatuses: ["running", "ready", "pending"])
        let outcome = await HostDiskFileGuard.restore(
            path: path,
            socketPath: "/tmp/qmp.sock",
            qmp: qmp,
            availableBytes: { _ in 100 * Self.gib },
            pause: {}
        )
        #expect(outcome == .restored(path: path))
        let commands = await qmp.commands
        #expect(commands.contains(.driveMirror(
            jobID: HostDiskFileGuard.rescueJobID,
            device: "system",
            targetPath: path,
            format: "qcow2",
            bytesPerSecond: HostDiskFileGuard.copyBytesPerSecond
        )))
        #expect(commands.filter { $0 == .jobComplete(jobID: HostDiskFileGuard.rescueJobID) }.count == 1)
    }

    @Test("Too little free space refuses before any copy starts")
    func refusesWithoutSpace() async throws {
        let path = try Self.missingPath()
        let qmp = MirrorQMP(path: path, jobStatuses: [])
        let outcome = await HostDiskFileGuard.restore(
            path: path,
            socketPath: "/tmp/qmp.sock",
            qmp: qmp,
            availableBytes: { _ in 10 * Self.gib },
            pause: {}
        )
        #expect(outcome == .notEnoughSpace(
            neededBytes: 36 * Self.gib + HostDiskFileGuard.spareBytes,
            availableBytes: 10 * Self.gib
        ))
        #expect(await qmp.commands == [.queryJobs, .queryBlock])
    }

    @Test("A copy an earlier Veil started is finished, not started again")
    func resumesRunningCopy() async throws {
        let path = try Self.missingPath()
        let qmp = MirrorQMP(path: path, jobStatuses: ["ready", "ready", "concluded"], copyAlreadyRunning: true)
        let outcome = await HostDiskFileGuard.restore(
            path: path,
            socketPath: "/tmp/qmp.sock",
            qmp: qmp,
            availableBytes: { _ in 100 * Self.gib },
            pause: {}
        )
        #expect(outcome == .restored(path: path))
        #expect(await !qmp.commands.contains { if case .driveMirror = $0 { true } else { false } })
    }

    @Test("A failed copy is reported and dismissed")
    func reportsFailedCopy() async throws {
        let path = try Self.missingPath()
        let qmp = MirrorQMP(path: path, jobStatuses: ["running"], failure: "No space left on device")
        let outcome = await HostDiskFileGuard.restore(
            path: path,
            socketPath: "/tmp/qmp.sock",
            qmp: qmp,
            availableBytes: { _ in 100 * Self.gib },
            pause: {}
        )
        #expect(outcome == .failed(reason: "No space left on device"))
        #expect(await qmp.commands.last == .jobDismiss(jobID: HostDiskFileGuard.rescueJobID))
    }

    @Test("The QMP commands carry the mirror and completion arguments")
    func commandEncoding() throws {
        let mirror = try QEMUQMPCommand.driveMirror(
            jobID: "j", device: "system", targetPath: "/a b/disk.img", format: "raw", bytesPerSecond: 7
        ).jsonLine(id: "1")
        #expect(mirror.contains("\"execute\":\"drive-mirror\""))
        #expect(mirror.contains("\"mode\":\"absolute-paths\""))
        #expect(mirror.contains("\"sync\":\"full\""))
        #expect(mirror.contains("\"target\":\"\\/a b\\/disk.img\"") || mirror.contains("\"target\":\"/a b/disk.img\""))
        #expect(mirror.contains("\"speed\":7"))
        let complete = try QEMUQMPCommand.jobComplete(jobID: "j").jsonLine(id: "2")
        #expect(complete.contains("\"execute\":\"job-complete\""))
        #expect(complete.contains("\"id\":\"j\""))
    }

    @Test("query-block replies decode drive files and sizes")
    func decodesQueryBlock() {
        let output = """
        {"return": [{"device": "system", "inserted": {"file": "/v/disk.img", "drv": "raw", "image": {"format": "raw", "actual-size": 39031521280, "virtual-size": 137438953472}}}, {"device": "veil-cd"}]}
        """
        let reply = QEMUQMPClient.parseReplies(from: output).first
        #expect(reply?.blockDevicesReturn == [
            QEMUQMPBlockDevice(
                device: "system",
                filename: "/v/disk.img",
                format: "raw",
                actualSize: 39_031_521_280,
                virtualSize: 137_438_953_472
            )
        ])
        #expect(reply?.jobsReturn == [])
    }

    private static let record = QEMULaunchRecord(
        pid: 4242,
        executablePath: "/usr/bin/true",
        arguments: ["-drive", "if=none,id=system,format=raw,file=/tmp/veil-missing/disk.img"],
        processLogPath: "/tmp/qemu.log",
        monitorSocketPath: "/tmp/monitor.sock",
        qmpSocketPath: NSTemporaryDirectory(),
        startedAt: Date(timeIntervalSince1970: 0)
    )

    /// A path in a fresh, empty directory; the fake QEMU creates it on completion.
    private static func missingPath() throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Windows 11 Arm.img").path
    }
}

/// Plays QEMU through one mirror: each `query-jobs` reports the next status, and completing the job
/// writes the target file, as QEMU's switch to the copy would leave it.
private actor MirrorQMP: QEMUQMPControlling {
    private let path: String
    private var jobStatuses: [String]
    private let failure: String?
    private var copyRunning: Bool
    private(set) var commands: [QEMUQMPCommand] = []

    init(path: String, jobStatuses: [String], copyAlreadyRunning: Bool = false, failure: String? = nil) {
        self.path = path
        self.jobStatuses = jobStatuses
        self.failure = failure
        self.copyRunning = copyAlreadyRunning
    }

    func execute(_ commands: [QEMUQMPCommand], socketPath: String, idleTimeoutSeconds: Int) async throws -> [QEMUQMPReply] {
        self.commands.append(contentsOf: commands)
        return commands.map(reply)
    }

    private func reply(_ command: QEMUQMPCommand) -> QEMUQMPReply {
        switch command {
        case .queryJobs:
            guard copyRunning else {
                return QEMUQMPReply(id: nil, isSuccess: true, jobsReturn: [])
            }
            if let failure {
                return QEMUQMPReply(id: nil, isSuccess: true, jobsReturn: [
                    QEMUQMPJob(id: HostDiskFileGuard.rescueJobID, status: "concluded", error: failure)
                ])
            }
            guard !jobStatuses.isEmpty else {
                copyRunning = false
                return QEMUQMPReply(id: nil, isSuccess: true, jobsReturn: [])
            }
            let status = jobStatuses.removeFirst()
            return QEMUQMPReply(id: nil, isSuccess: true, jobsReturn: [
                QEMUQMPJob(id: HostDiskFileGuard.rescueJobID, status: status)
            ])
        case .queryBlock:
            return QEMUQMPReply(id: nil, isSuccess: true, blockDevicesReturn: [
                QEMUQMPBlockDevice(
                    device: "system",
                    filename: path,
                    format: "qcow2",
                    actualSize: 36 * HostDiskSpaceGuard.gibibyte,
                    virtualSize: 128 * HostDiskSpaceGuard.gibibyte
                )
            ])
        case .driveMirror:
            copyRunning = true
            return QEMUQMPReply(id: nil, isSuccess: true)
        case .jobComplete:
            FileManager.default.createFile(atPath: path, contents: Data())
            return QEMUQMPReply(id: nil, isSuccess: true)
        default:
            return QEMUQMPReply(id: nil, isSuccess: true)
        }
    }
}
