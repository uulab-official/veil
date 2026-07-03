import Foundation

public struct QEMUKeySendResult: Codable, Equatable, Sendable {
    public var key: String
    public var transport: String
    public var socketPath: String
    public var monitorCommand: String
    public var terminationStatus: Int32?
    public var didLaunchSender: Bool

    public init(
        key: String,
        transport: String,
        socketPath: String,
        monitorCommand: String,
        terminationStatus: Int32?,
        didLaunchSender: Bool
    ) {
        self.key = key
        self.transport = transport
        self.socketPath = socketPath
        self.monitorCommand = monitorCommand
        self.terminationStatus = terminationStatus
        self.didLaunchSender = didLaunchSender
    }
}

public struct QEMUKeySendRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var monitorSocketPath: String
    public var keys: [String]
    public var results: [QEMUKeySendResult]
    public var sentAt: Date

    public init(
        kind: String = "qemuKeySend",
        monitorSocketPath: String,
        keys: [String],
        results: [QEMUKeySendResult],
        sentAt: Date
    ) {
        self.kind = kind
        self.monitorSocketPath = monitorSocketPath
        self.keys = keys
        self.results = results
        self.sentAt = sentAt
    }
}

public enum QEMUKeySequenceSenderError: Error, LocalizedError, Equatable, Sendable {
    case missingLaunchRecord
    case monitorUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingLaunchRecord:
            "No QEMU launch record found. Start Windows first."
        case .monitorUnavailable(let path):
            "QEMU monitor socket is not available: \(path)"
        }
    }
}

public struct QEMUKeySequenceSender: Sendable {
    private let launchRecordStore: any QEMULaunchRecordStore
    private let fileExists: @Sendable (String) -> Bool
    private let processRunner: @Sendable (String, [String]) -> Int32?
    private let now: @Sendable () -> Date

    public init(
        launchRecordStore: any QEMULaunchRecordStore,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        processRunner: @escaping @Sendable (String, [String]) -> Int32? = Self.runProcess,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.launchRecordStore = launchRecordStore
        self.fileExists = fileExists
        self.processRunner = processRunner
        self.now = now
    }

    public func send(steps: [QEMUKeySequenceStep]) async throws -> QEMUKeySendRecord {
        guard let launchRecord = try await launchRecordStore.loadLatest() else {
            throw QEMUKeySequenceSenderError.missingLaunchRecord
        }

        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canUseQMP = qmpSocketPath.map { !$0.isEmpty && fileExists($0) } ?? false
        guard canUseQMP || fileExists(launchRecord.monitorSocketPath) else {
            throw QEMUKeySequenceSenderError.monitorUnavailable(launchRecord.monitorSocketPath)
        }

        var results: [QEMUKeySendResult] = []
        for step in steps {
            let key = step.key
            if canUseQMP, let qmpSocketPath {
                let command = try QEMUQMPKeyboardCommandBuilder.inputEventCommand(for: key)
                results.append(sendQMPCommand(command, qmpSocketPath: qmpSocketPath, key: key))
            } else {
                let command = "sendkey \(key)"
                results.append(sendMonitorLine(command, monitorSocketPath: launchRecord.monitorSocketPath, key: key))
            }
            try? await Task.sleep(nanoseconds: UInt64(step.delayAfterSend * 1_000_000_000))
        }

        return QEMUKeySendRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            keys: steps.map(\.key),
            results: results,
            sentAt: now()
        )
    }

    private func sendMonitorLine(
        _ line: String,
        monitorSocketPath: String,
        key: String
    ) -> QEMUKeySendResult {
        let status = processRunner(
            "/bin/sh",
            [
                "-c",
                "printf '%s\\n' \"$1\" | /usr/bin/nc -w 1 -U \"$0\"",
                monitorSocketPath,
                line
            ]
        )
        return QEMUKeySendResult(
            key: key,
            transport: "hmp",
            socketPath: monitorSocketPath,
            monitorCommand: line,
            terminationStatus: status,
            didLaunchSender: status != nil
        )
    }

    private func sendQMPCommand(
        _ command: String,
        qmpSocketPath: String,
        key: String
    ) -> QEMUKeySendResult {
        let status = processRunner(
            "/bin/sh",
            [
                "-c",
                "printf '%s\\n%s\\n' \"$1\" \"$2\" | /usr/bin/nc -w 1 -U \"$0\"",
                qmpSocketPath,
                QEMUQMPKeyboardCommandBuilder.capabilitiesCommand(),
                command
            ]
        )
        return QEMUKeySendResult(
            key: key,
            transport: "qmp",
            socketPath: qmpSocketPath,
            monitorCommand: command,
            terminationStatus: status,
            didLaunchSender: status != nil
        )
    }

    public static func runProcess(executablePath: String, arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return nil
        }
    }
}
