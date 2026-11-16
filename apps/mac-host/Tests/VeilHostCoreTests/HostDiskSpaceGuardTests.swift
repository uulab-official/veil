import Foundation
import Testing
@testable import VeilHostCore

@Suite("Host disk space guard")
struct HostDiskSpaceGuardTests {
    private static let gib = HostDiskSpaceGuard.gibibyte

    @Test("Free space alone decides what to look at")
    func needFollowsFreeSpace() {
        #expect(HostDiskSpaceGuard.need(availableBytes: nil, pausedByGuard: false) == .none)
        #expect(HostDiskSpaceGuard.need(availableBytes: nil, pausedByGuard: true) == .none)
        #expect(HostDiskSpaceGuard.need(availableBytes: 10 * Self.gib, pausedByGuard: false) == .none)
        #expect(HostDiskSpaceGuard.need(availableBytes: 2 * Self.gib, pausedByGuard: false) == .none)
        #expect(HostDiskSpaceGuard.need(availableBytes: 2 * Self.gib - 1, pausedByGuard: false) == .pause)
        // Between the two thresholds a paused Windows stays paused, so it cannot flap.
        #expect(HostDiskSpaceGuard.need(availableBytes: 3 * Self.gib, pausedByGuard: true) == .confirmStillPaused)
        #expect(HostDiskSpaceGuard.need(availableBytes: 4 * Self.gib, pausedByGuard: true) == .resume)
    }

    @Test("The system disk path is read from the rewritten and the original drive argument")
    func systemDiskPath() {
        let rewritten = [
            "-drive", "driver=qcow2,node-name=veil-system,file.driver=file,file.locking=off,file.filename=/Users/a/Win,,11/disk.qcow2,if=none,id=system",
        ]
        #expect(HostDiskSpaceGuard.systemDiskPath(arguments: rewritten) == "/Users/a/Win,11/disk.qcow2")

        let original = ["-drive", "if=none,id=system,format=raw,file=/tmp/disk.img"]
        #expect(HostDiskSpaceGuard.systemDiskPath(arguments: original) == "/tmp/disk.img")

        #expect(HostDiskSpaceGuard.systemDiskPath(arguments: ["-drive", "if=none,id=installer,file=/x.iso"]) == nil)
    }

    @Test("Free space of a real volume is readable")
    func readsFreeSpace() {
        let bytes = HostDiskSpaceGuard.availableBytes(atPath: NSTemporaryDirectory())
        #expect((bytes ?? 0) > 0)
        #expect(HostDiskSpaceGuard.availableBytes(atPath: "/no/such/path/\(UUID().uuidString)") == nil)
    }

    @Test("Plenty of space never asks QEMU")
    func plentyOfSpaceSkipsQMP() async {
        let qmp = StatusQMP(status: "running")
        let outcome = await check(qmp: qmp, available: 50 * Self.gib, pausedByGuard: false)
        #expect(outcome == .unchanged)
        #expect(await qmp.commands.isEmpty)
    }

    @Test("A running Windows is paused when space runs low")
    func pausesRunningWindows() async {
        let qmp = StatusQMP(status: "running")
        let outcome = await check(qmp: qmp, available: Self.gib, pausedByGuard: false)
        #expect(outcome == .paused(availableBytes: Self.gib))
        #expect(await qmp.commands == [.queryStatus, .stop])
    }

    @Test("A Windows paused by something else is left alone")
    func leavesOtherPausesAlone() async {
        let qmp = StatusQMP(status: "paused")
        #expect(await check(qmp: qmp, available: Self.gib, pausedByGuard: false) == .unchanged)
        #expect(await qmp.commands == [.queryStatus])
    }

    @Test("The guard's own pause is continued once there is room")
    func continuesOwnPause() async {
        let qmp = StatusQMP(status: "paused")
        #expect(await check(qmp: qmp, available: 5 * Self.gib, pausedByGuard: true) == .resumed(availableBytes: 5 * Self.gib))
        #expect(await qmp.commands == [.queryStatus, .cont])
    }

    @Test("A pause the guard no longer owns is released, not continued")
    func releasesPauseItNoLongerOwns() async {
        // Continued by something else, or a suspend has finished saving.
        for status in ["running", "postmigrate", "finish-migrate", "shutdown"] {
            let qmp = StatusQMP(status: status)
            #expect(await check(qmp: qmp, available: 5 * Self.gib, pausedByGuard: true) == .released)
            #expect(await qmp.commands == [.queryStatus])
        }
        let stillPausedQMP = StatusQMP(status: "paused")
        #expect(await check(qmp: stillPausedQMP, available: 3 * Self.gib, pausedByGuard: true) == .stillPaused(availableBytes: 3 * Self.gib))
        let lowQMP = StatusQMP(status: "running")
        #expect(await check(qmp: lowQMP, available: 3 * Self.gib, pausedByGuard: true) == .released)
    }

    @Test("QEMU having exited releases the pause")
    func exitedQEMUReleases() async {
        let qmp = StatusQMP(status: "paused")
        let outcome = await HostDiskSpaceGuard.check(
            launchRecord: Self.record,
            pausedByGuard: true,
            qmp: qmp,
            processIsRunning: { _ in false },
            availableBytes: { _ in Self.gib }
        )
        #expect(outcome == .released)
        #expect(await qmp.commands.isEmpty)
    }

    @Test("A refused pause changes nothing")
    func refusedPause() async {
        let qmp = StatusQMP(status: "running", refuses: .stop)
        #expect(await check(qmp: qmp, available: Self.gib, pausedByGuard: false) == .unchanged)
    }

    private static let record = QEMULaunchRecord(
        pid: 4242,
        executablePath: "/usr/bin/true",
        arguments: ["-drive", "if=none,id=system,format=raw,file=/tmp/disk.img"],
        processLogPath: "/tmp/qemu.log",
        monitorSocketPath: "/tmp/monitor.sock",
        qmpSocketPath: NSTemporaryDirectory(),
        startedAt: Date(timeIntervalSince1970: 0)
    )

    private func check(qmp: StatusQMP, available: Int64, pausedByGuard: Bool) async -> HostDiskSpaceGuard.Outcome {
        await HostDiskSpaceGuard.check(
            launchRecord: Self.record,
            pausedByGuard: pausedByGuard,
            qmp: qmp,
            processIsRunning: { _ in true },
            availableBytes: { path in
                #expect(path == "/tmp/disk.img")
                return available
            }
        )
    }
}

private actor StatusQMP: QEMUQMPControlling {
    private let status: String
    private let refuses: QEMUQMPCommand?
    private(set) var commands: [QEMUQMPCommand] = []

    init(status: String, refuses: QEMUQMPCommand? = nil) {
        self.status = status
        self.refuses = refuses
    }

    func execute(
        _ commands: [QEMUQMPCommand],
        socketPath: String,
        idleTimeoutSeconds: Int
    ) async throws -> [QEMUQMPReply] {
        self.commands.append(contentsOf: commands)
        return commands.map { command in
            if command == refuses {
                return QEMUQMPReply(id: nil, isSuccess: false, errorClass: "GenericError", errorMessage: "refused")
            }
            return QEMUQMPReply(id: nil, isSuccess: true, statusReturn: command == .queryStatus ? status : nil)
        }
    }
}
