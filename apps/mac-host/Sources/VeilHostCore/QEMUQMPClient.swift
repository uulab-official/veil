import Foundation

/// Result of one local helper-process invocation, including captured stdout.
///
/// Modeled as a struct rather than a tuple so the injected runner closure stays `Sendable` under
/// strict concurrency. `terminationStatus` is `nil` when the process could not be launched at all,
/// which is a different failure from "launched and exited non-zero".
public struct QEMUProcessOutcome: Equatable, Sendable {
    public var terminationStatus: Int32?
    public var standardOutput: String

    public init(terminationStatus: Int32?, standardOutput: String) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
    }
}

/// One QEMU Machine Protocol command.
///
/// Veil deliberately models only the commands the Windows App Runtime needs -- runtime state,
/// pause/resume, memory-state save, and the HMP bridge used for internal disk snapshots -- instead
/// of exposing a general QEMU control surface. Adding a case here is a protocol-boundary decision,
/// not a convenience.
public enum QEMUQMPCommand: Equatable, Sendable {
    /// Required handshake before any other command on a freshly opened QMP connection.
    case capabilities
    case queryStatus
    /// Pauses guest vCPUs. The QEMU process keeps running and RAM stays resident.
    case stop
    /// Resumes paused guest vCPUs.
    case cont
    /// Streams RAM plus device state to a local file through QEMU's migration machinery. This is
    /// how Veil persists a suspended VM without requiring a qcow2 disk: only guest memory and
    /// device state move to the file, the raw system disk is untouched.
    case saveMemoryState(filePath: String)
    case queryMigrate
    /// Escape hatch for monitor-only features that have no stable QMP equivalent, notably the
    /// `savevm`/`loadvm`/`delvm`/`info snapshots` internal-snapshot family.
    case humanMonitor(String)
    case quit

    public var executeName: String {
        switch self {
        case .capabilities:
            "qmp_capabilities"
        case .queryStatus:
            "query-status"
        case .stop:
            "stop"
        case .cont:
            "cont"
        case .saveMemoryState:
            "migrate"
        case .queryMigrate:
            "query-migrate"
        case .humanMonitor:
            "human-monitor-command"
        case .quit:
            "quit"
        }
    }

    /// Human-readable label used in error messages so a failure names the intent, not the wire verb.
    public var label: String {
        switch self {
        case .capabilities:
            "QMP capabilities handshake"
        case .queryStatus:
            "VM run state query"
        case .stop:
            "VM pause"
        case .cont:
            "VM resume"
        case .saveMemoryState(let filePath):
            "VM memory state save to \(filePath)"
        case .queryMigrate:
            "VM memory state save progress query"
        case .humanMonitor(let command):
            "QEMU monitor command '\(command)'"
        case .quit:
            "QEMU process quit"
        }
    }

    private var argumentsJSONObject: [String: Any]? {
        switch self {
        case .saveMemoryState(let filePath):
            // QEMU hands everything after `exec:` to /bin/sh, so the path has to be shell quoted
            // here. Spaces are the normal case: the default disk lives in "Virtual Machines/Veil".
            return ["uri": "exec:cat > \(Self.shellSingleQuoted(filePath))"]
        case .humanMonitor(let command):
            return ["command-line": command]
        default:
            return nil
        }
    }

    public func jsonLine(id: String) throws -> String {
        var object: [String: Any] = [
            "execute": executeName,
            "id": id
        ]
        if let argumentsJSONObject {
            object["arguments"] = argumentsJSONObject
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// One parsed QMP reply.
///
/// QMP returns either `return` or `error` for each command, correlated by the `id` the client sent.
/// Only the return shapes Veil actually reads are decoded: a bare string (`human-monitor-command`)
/// and the `status`/`running` fields (`query-status`, `query-migrate`).
public struct QEMUQMPReply: Equatable, Sendable {
    public var id: String?
    public var isSuccess: Bool
    public var errorClass: String?
    public var errorMessage: String?
    public var textReturn: String?
    public var statusReturn: String?
    public var isRunning: Bool?

    public init(
        id: String?,
        isSuccess: Bool,
        errorClass: String? = nil,
        errorMessage: String? = nil,
        textReturn: String? = nil,
        statusReturn: String? = nil,
        isRunning: Bool? = nil
    ) {
        self.id = id
        self.isSuccess = isSuccess
        self.errorClass = errorClass
        self.errorMessage = errorMessage
        self.textReturn = textReturn
        self.statusReturn = statusReturn
        self.isRunning = isRunning
    }
}

public enum QEMUQMPClientError: Error, LocalizedError, Equatable, Sendable {
    case socketUnavailable(String)
    case transportUnavailable(String)
    case noReply(command: String)
    case commandFailed(command: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .socketUnavailable(let path):
            "QEMU QMP socket is not available: \(path)"
        case .transportUnavailable(let path):
            "QEMU did not answer on its QMP socket: \(path)"
        case .noReply(let command):
            "QEMU accepted no reply for \(command)."
        case .commandFailed(let command, let message):
            "\(command) failed: \(message)"
        }
    }
}

public protocol QEMUQMPControlling: Sendable {
    func execute(
        _ commands: [QEMUQMPCommand],
        socketPath: String,
        idleTimeoutSeconds: Int
    ) async throws -> [QEMUQMPReply]
}

public extension QEMUQMPControlling {
    /// Runs one command and fails loudly when QEMU rejects it, so callers cannot silently continue
    /// past a refused pause, resume, or snapshot.
    @discardableResult
    func run(
        _ command: QEMUQMPCommand,
        socketPath: String,
        idleTimeoutSeconds: Int = 2
    ) async throws -> QEMUQMPReply {
        let replies = try await execute([command], socketPath: socketPath, idleTimeoutSeconds: idleTimeoutSeconds)
        guard let reply = replies.first else {
            throw QEMUQMPClientError.noReply(command: command.label)
        }
        guard reply.isSuccess else {
            throw QEMUQMPClientError.commandFailed(
                command: command.label,
                message: reply.errorMessage ?? reply.errorClass ?? "QEMU returned an unspecified QMP error."
            )
        }

        return reply
    }
}

/// Request/response QMP client over QEMU's unix socket.
///
/// The pre-existing key and pointer senders write to QMP and discard whatever QEMU answers, which
/// is fine for fire-and-forget input but cannot support pause, resume, or snapshot work where the
/// reply *is* the result. This client keeps the same `nc`-based transport as the rest of the QEMU
/// boundary -- no new dependency, no raw socket code -- but captures stdout and correlates each
/// reply by the `id` it sent.
///
/// Each call opens a fresh connection, so it re-sends `qmp_capabilities` every time. That is
/// required: QMP capability negotiation is per-connection, while VM run state is not.
public struct QEMUQMPClient: QEMUQMPControlling {
    public static let handshakeId = "veil-qmp-capabilities"

    private let fileExists: @Sendable (String) -> Bool
    private let processRunner: @Sendable (String, [String]) -> QEMUProcessOutcome

    public init(
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        processRunner: @escaping @Sendable (String, [String]) -> QEMUProcessOutcome = QEMUQMPClient.runProcess
    ) {
        self.fileExists = fileExists
        self.processRunner = processRunner
    }

    public func execute(
        _ commands: [QEMUQMPCommand],
        socketPath: String,
        idleTimeoutSeconds: Int = 2
    ) async throws -> [QEMUQMPReply] {
        guard !commands.isEmpty else {
            return []
        }

        let trimmedSocketPath = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSocketPath.isEmpty, fileExists(trimmedSocketPath) else {
            throw QEMUQMPClientError.socketUnavailable(socketPath)
        }

        var lines = [try QEMUQMPCommand.capabilities.jsonLine(id: Self.handshakeId)]
        var commandIds: [String] = []
        for (index, command) in commands.enumerated() {
            let id = "veil-qmp-\(index)"
            commandIds.append(id)
            lines.append(try command.jsonLine(id: id))
        }

        let outcome = processRunner(
            "/bin/sh",
            ["-c", Self.transportScript(idleTimeoutSeconds: idleTimeoutSeconds), trimmedSocketPath] + lines
        )
        let replies = Self.parseReplies(from: outcome.standardOutput)
        guard !replies.isEmpty else {
            throw QEMUQMPClientError.transportUnavailable(trimmedSocketPath)
        }

        return try zip(commands, commandIds).map { command, id in
            guard let reply = replies.first(where: { $0.id == id }) else {
                throw QEMUQMPClientError.noReply(command: command.label)
            }
            return reply
        }
    }

    static func transportScript(idleTimeoutSeconds: Int) -> String {
        // `nc` never sees a close from QEMU, so the idle timeout is what ends the session after the
        // replies land. Clamped to at least 1 because `-w 0` means "wait forever" on macOS.
        "printf '%s\\n' \"$@\" | /usr/bin/nc -w \(max(1, idleTimeoutSeconds)) -U \"$0\""
    }

    /// Parses newline-delimited QMP JSON, skipping the greeting and asynchronous events.
    public static func parseReplies(from output: String) -> [QEMUQMPReply] {
        // QEMU's unix-socket transport returns CRLF. On Swift's String model a CRLF pair can be
        // represented as one extended grapheme cluster, so splitting directly on `\n` can leave the
        // whole response as one line and make a healthy QMP socket look silent. Normalize line
        // endings before parsing so both QEMU output and fixture output follow the same path.
        output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> QEMUQMPReply? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }

                // `{"QMP": {...}}` is the greeting and `{"event": ...}` is asynchronous state
                // notification. Neither answers a command.
                if object["QMP"] != nil || object["event"] != nil {
                    return nil
                }

                let id = object["id"] as? String
                if let error = object["error"] as? [String: Any] {
                    return QEMUQMPReply(
                        id: id,
                        isSuccess: false,
                        errorClass: error["class"] as? String,
                        errorMessage: error["desc"] as? String
                    )
                }

                guard let returnValue = object["return"] else {
                    return nil
                }

                let returnObject = returnValue as? [String: Any]
                return QEMUQMPReply(
                    id: id,
                    isSuccess: true,
                    textReturn: returnValue as? String,
                    statusReturn: returnObject?["status"] as? String,
                    isRunning: returnObject?["running"] as? Bool
                )
            }
    }

    /// Asynchronous event names seen in one session, useful as suspend/resume evidence.
    public static func parseEventNames(from output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }

                return object["event"] as? String
            }
    }

    public static func runProcess(executablePath: String, arguments: [String]) -> QEMUProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return QEMUProcessOutcome(terminationStatus: nil, standardOutput: "")
        }

        // Drained before waiting so a reply larger than the pipe buffer cannot deadlock the wait.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return QEMUProcessOutcome(
            terminationStatus: process.terminationStatus,
            standardOutput: String(decoding: data, as: UTF8.self)
        )
    }
}
