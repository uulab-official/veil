import Foundation

public struct QEMUPointerTapRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var qmpSocketPath: String
    public var normalizedX: Double
    public var normalizedY: Double
    public var absoluteX: Int
    public var absoluteY: Int
    public var commands: [String]
    public var terminationStatus: Int32?
    public var didLaunchSender: Bool
    public var sentAt: Date

    public init(
        kind: String = "qemuPointerTap",
        qmpSocketPath: String,
        normalizedX: Double,
        normalizedY: Double,
        absoluteX: Int,
        absoluteY: Int,
        commands: [String],
        terminationStatus: Int32?,
        didLaunchSender: Bool,
        sentAt: Date
    ) {
        self.kind = kind
        self.qmpSocketPath = qmpSocketPath
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.absoluteX = absoluteX
        self.absoluteY = absoluteY
        self.commands = commands
        self.terminationStatus = terminationStatus
        self.didLaunchSender = didLaunchSender
        self.sentAt = sentAt
    }
}

public enum QEMUPointerEventSenderError: Error, LocalizedError, Equatable, Sendable {
    case missingLaunchRecord
    case qmpUnavailable
    case normalizedCoordinateOutOfRange(axis: String, value: Double)

    public var errorDescription: String? {
        switch self {
        case .missingLaunchRecord:
            "No QEMU launch record found. Start Windows first."
        case .qmpUnavailable:
            "QEMU pointer input requires an active QMP socket. Start Windows from Veil and try again."
        case .normalizedCoordinateOutOfRange(let axis, let value):
            "Console pointer \(axis) coordinate \(value) is outside the valid 0...1 preview range."
        }
    }
}

public protocol QEMUPointerEventSending: Sendable {
    func sendTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord
}

public struct QEMUPointerEventSender: QEMUPointerEventSending {
    private let launchRecordStore: any QEMULaunchRecordStore
    private let fileExists: @Sendable (String) -> Bool
    private let processRunner: @Sendable (String, [String]) -> Int32?
    private let now: @Sendable () -> Date

    public init(
        launchRecordStore: any QEMULaunchRecordStore,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        processRunner: @escaping @Sendable (String, [String]) -> Int32? = QEMUKeySequenceSender.runProcess,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.launchRecordStore = launchRecordStore
        self.fileExists = fileExists
        self.processRunner = processRunner
        self.now = now
    }

    public func sendTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord {
        guard let launchRecord = try await launchRecordStore.loadLatest() else {
            throw QEMUPointerEventSenderError.missingLaunchRecord
        }
        guard let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !qmpSocketPath.isEmpty,
              fileExists(qmpSocketPath) else {
            throw QEMUPointerEventSenderError.qmpUnavailable
        }

        let absoluteX = try Self.absoluteCoordinate(for: normalizedX, axis: "x")
        let absoluteY = try Self.absoluteCoordinate(for: normalizedY, axis: "y")
        let commands = [
            try QEMUQMPPointerCommandBuilder.absoluteMoveCommand(x: absoluteX, y: absoluteY),
            try QEMUQMPPointerCommandBuilder.leftButtonCommand(isDown: true),
            try QEMUQMPPointerCommandBuilder.leftButtonCommand(isDown: false)
        ]
        let status = processRunner(
            "/bin/sh",
            [
                "-c",
                "printf '%s\\n%s\\n%s\\n%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" | /usr/bin/nc -w 1 -U \"$0\"",
                qmpSocketPath,
                QEMUQMPKeyboardCommandBuilder.capabilitiesCommand(),
                commands[0],
                commands[1],
                commands[2]
            ]
        )

        return QEMUPointerTapRecord(
            qmpSocketPath: qmpSocketPath,
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            absoluteX: absoluteX,
            absoluteY: absoluteY,
            commands: commands,
            terminationStatus: status,
            didLaunchSender: status != nil,
            sentAt: now()
        )
    }

    private static func absoluteCoordinate(for normalized: Double, axis: String) throws -> Int {
        guard normalized.isFinite, (0...1).contains(normalized) else {
            throw QEMUPointerEventSenderError.normalizedCoordinateOutOfRange(axis: axis, value: normalized)
        }

        return Int((normalized * Double(QEMUQMPPointerCommandBuilder.maximumAbsoluteCoordinate)).rounded())
    }
}
