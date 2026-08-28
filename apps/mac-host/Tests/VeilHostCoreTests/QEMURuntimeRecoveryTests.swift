import Foundation
import Testing

@testable import VeilHostCore

@Suite("QEMU runtime recovery")
struct QEMURuntimeRecoveryTests {
    @Test("recovers only a machine that was running and verifies the final state")
    func recoversRunningMachine() async {
        let qmp = ScriptedQMP(
            steps: [
                .reply(Self.runningReply),
                .reply(Self.runningReply),
                .reply(Self.runningReply),
                .reply(Self.runningReply)
            ]
        )
        let controller = QEMURuntimeRecoveryController(
            qmp: qmp,
            launchRecordStore: StaticLaunchRecordStore(record: Self.launchRecord)
        )

        let result = await controller.recoverStalledRuntime()

        #expect(result == .recovered)
        #expect(await qmp.commands == [.queryStatus, .stop, .cont, .queryStatus])
    }

    @Test("does not resume an intentionally paused machine")
    func leavesPausedMachineAlone() async {
        let qmp = ScriptedQMP(steps: [.reply(Self.pausedReply)])
        let controller = QEMURuntimeRecoveryController(
            qmp: qmp,
            launchRecordStore: StaticLaunchRecordStore(record: Self.launchRecord)
        )

        let result = await controller.recoverStalledRuntime()

        #expect(result == .notNeeded)
        #expect(await qmp.commands == [.queryStatus])
    }

    @Test("refuses recovery when there is no launch record")
    func refusesMissingLaunchRecord() async {
        let qmp = ScriptedQMP(steps: [])
        let controller = QEMURuntimeRecoveryController(
            qmp: qmp,
            launchRecordStore: StaticLaunchRecordStore(record: nil)
        )

        let result = await controller.recoverStalledRuntime()

        #expect(result == .unavailable("QEMU control is unavailable because no QMP socket is recorded."))
        #expect(await qmp.commands.isEmpty)
    }

    @Test("accepts a pause timeout only after QMP confirms the guest is paused")
    func confirmsPauseAfterTimeout() async {
        let qmp = ScriptedQMP(
            steps: [
                .reply(Self.runningReply),
                .failure(.transportUnavailable("/tmp/veil.qmp.sock")),
                .reply(Self.pausedReply),
                .reply(Self.runningReply),
                .reply(Self.runningReply)
            ]
        )
        let controller = QEMURuntimeRecoveryController(
            qmp: qmp,
            launchRecordStore: StaticLaunchRecordStore(record: Self.launchRecord)
        )

        let result = await controller.recoverStalledRuntime()

        #expect(result == .recovered)
        #expect(await qmp.commands == [.queryStatus, .stop, .queryStatus, .cont, .queryStatus])
    }

    @Test("does not force a resume when the pause transition cannot be confirmed")
    func refusesUnconfirmedPause() async {
        let qmp = ScriptedQMP(
            steps: [
                .reply(Self.runningReply),
                .failure(.transportUnavailable("/tmp/veil.qmp.sock")),
                .reply(Self.runningReply)
            ]
        )
        let controller = QEMURuntimeRecoveryController(
            qmp: qmp,
            launchRecordStore: StaticLaunchRecordStore(record: Self.launchRecord)
        )

        let result = await controller.recoverStalledRuntime()

        #expect(result == .failed("QEMU pause was not confirmed; the machine still reports running."))
        #expect(await qmp.commands == [.queryStatus, .stop, .queryStatus])
    }

    private static let runningReply = QEMUQMPReply(
        id: nil,
        isSuccess: true,
        statusReturn: "running",
        isRunning: true
    )

    private static let pausedReply = QEMUQMPReply(
        id: nil,
        isSuccess: true,
        statusReturn: "paused",
        isRunning: false
    )

    private static let launchRecord = QEMULaunchRecord(
        pid: 123,
        executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
        arguments: [],
        processLogPath: "/tmp/qemu.log",
        monitorSocketPath: "/tmp/veil-monitor.sock",
        qmpSocketPath: "/tmp/veil.qmp.sock",
        startedAt: Date(timeIntervalSince1970: 1)
    )
}

private struct StaticLaunchRecordStore: QEMULaunchRecordStore {
    let record: QEMULaunchRecord?

    func loadLatest() async throws -> QEMULaunchRecord? {
        record
    }
}

private actor ScriptedQMP: QEMUQMPControlling {
    enum Step {
        case reply(QEMUQMPReply)
        case failure(QEMUQMPClientError)
    }

    private var steps: [Step]
    private(set) var commands: [QEMUQMPCommand] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func execute(
        _ commands: [QEMUQMPCommand],
        socketPath: String,
        idleTimeoutSeconds: Int
    ) async throws -> [QEMUQMPReply] {
        self.commands.append(contentsOf: commands)
        guard let step = steps.isEmpty ? nil : steps.removeFirst() else {
            throw QEMUQMPClientError.noReply(command: commands.first?.label ?? "unknown")
        }

        switch step {
        case .reply(let reply):
            return [reply]
        case .failure(let error):
            throw error
        }
    }
}
