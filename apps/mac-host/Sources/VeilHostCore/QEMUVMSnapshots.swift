import Foundation

public enum VMSnapshotSupportState: String, Codable, Equatable, Sendable {
    case supported
    /// The system disk is raw. QEMU internal snapshots need a format that can store snapshot data
    /// inside the image, which raw cannot do.
    case unsupportedDiskFormat
    case unsupportedProvider
    case notConfigured
}

/// Whether the current VM can hold QEMU internal snapshots, and if not, exactly why.
///
/// This is deliberately separate from session suspend/resume. Suspend streams RAM to a sidecar file
/// and therefore works on Veil's shipping raw disk; snapshots store guest state *inside* the disk
/// image and therefore require qcow2. Reporting one capability for both would let the UI offer a
/// snapshot action that can never succeed.
public struct VMSnapshotCapability: Codable, Equatable, Sendable {
    public static let requiredDiskFormat = "qcow2"

    public var state: VMSnapshotSupportState
    public var isSupported: Bool
    public var systemDiskFormat: String?
    public var requiredDiskFormat: String
    public var systemDiskPath: String?
    public var convertedDiskPath: String?
    public var conversionCommand: String?
    public var detail: String

    public init(
        state: VMSnapshotSupportState,
        systemDiskFormat: String? = nil,
        requiredDiskFormat: String = VMSnapshotCapability.requiredDiskFormat,
        systemDiskPath: String? = nil,
        convertedDiskPath: String? = nil,
        conversionCommand: String? = nil,
        detail: String
    ) {
        self.state = state
        self.isSupported = state == .supported
        self.systemDiskFormat = systemDiskFormat
        self.requiredDiskFormat = requiredDiskFormat
        self.systemDiskPath = systemDiskPath
        self.convertedDiskPath = convertedDiskPath
        self.conversionCommand = conversionCommand
        self.detail = detail
    }
}

/// One QEMU internal snapshot as reported by `info snapshots` / `qemu-img snapshot -l`.
public struct VMSnapshotSummary: Codable, Equatable, Sendable {
    public var id: String
    public var tag: String
    public var vmStateSize: String
    public var createdAt: String
    public var vmClock: String

    public init(
        id: String,
        tag: String,
        vmStateSize: String,
        createdAt: String,
        vmClock: String
    ) {
        self.id = id
        self.tag = tag
        self.vmStateSize = vmStateSize
        self.createdAt = createdAt
        self.vmClock = vmClock
    }
}

public enum VMSnapshotActionKind: String, Codable, Equatable, Sendable {
    case list
    case create
    case restore
    case delete
}

public enum VMSnapshotActionStatus: String, Codable, Equatable, Sendable {
    case succeeded
    /// The action cannot be attempted at all: wrong disk format, wrong provider, or no profile.
    case unavailable
    case failed
}

public struct VMSnapshotActionReport: Codable, Equatable, Sendable {
    public var kind: String
    public var action: VMSnapshotActionKind
    public var generatedAt: Date
    public var status: VMSnapshotActionStatus
    public var vmState: VMRuntimeState
    public var provider: String
    public var capability: VMSnapshotCapability
    public var requestedTag: String?
    public var snapshots: [VMSnapshotSummary]
    public var errorMessage: String?
    public var nextActions: [String]

    public init(
        kind: String = "vmSnapshotAction",
        action: VMSnapshotActionKind,
        generatedAt: Date,
        status: VMSnapshotActionStatus,
        vmState: VMRuntimeState,
        provider: String,
        capability: VMSnapshotCapability,
        requestedTag: String? = nil,
        snapshots: [VMSnapshotSummary] = [],
        errorMessage: String? = nil,
        nextActions: [String]
    ) {
        self.kind = kind
        self.action = action
        self.generatedAt = generatedAt
        self.status = status
        self.vmState = vmState
        self.provider = provider
        self.capability = capability
        self.requestedTag = requestedTag
        self.snapshots = snapshots
        self.errorMessage = errorMessage
        self.nextActions = nextActions
    }
}

public enum VMSnapshotError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case unsupportedProvider
    case unsupportedDiskFormat(format: String?)
    case invalidTag(String)
    case vmNotRunning(VMSnapshotActionKind)
    case qmpUnavailable
    case monitorRejected(command: String, message: String)
    case snapshotToolUnavailable(String)
    case snapshotNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No Windows VM profile is configured, so there is no disk to snapshot."
        case .unsupportedProvider:
            "Snapshots are implemented for the local QEMU/HVF provider only."
        case .unsupportedDiskFormat(let format):
            "Snapshots require a \(VMSnapshotCapability.requiredDiskFormat) system disk, but this VM uses \(format ?? "an unknown format"). Convert the disk first."
        case .invalidTag(let tag):
            "Snapshot name '\(tag)' is not allowed. Use letters, digits, dot, dash, or underscore with no spaces."
        case .vmNotRunning(let action):
            "Windows must be running to \(action.rawValue) a snapshot, so guest memory and disk state stay consistent. Start or resume the VM first."
        case .qmpUnavailable:
            "The running Windows VM has no reachable QMP control socket, so snapshots cannot be driven."
        case .monitorRejected(let command, let message):
            "QEMU rejected '\(command)': \(message)"
        case .snapshotToolUnavailable(let path):
            "qemu-img was not found at \(path), so the snapshot list cannot be read while the VM is off."
        case .snapshotNotFound(let tag):
            "No snapshot named '\(tag)' exists on the Windows system disk."
        }
    }
}

/// Parses QEMU's snapshot table, shared by `info snapshots` (running VM) and `qemu-img snapshot -l`
/// (stopped VM) because both print the same columns.
public enum QEMUSnapshotListParser {
    static let emptyMarkers = ["there is no snapshot available", "no snapshot"]

    public static func parse(_ output: String) -> [VMSnapshotSummary] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                summary(from: line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    static func summary(from line: String) -> VMSnapshotSummary? {
        guard !line.isEmpty else {
            return nil
        }

        let lowercased = line.lowercased()
        if lowercased.hasPrefix("list of snapshots")
            || lowercased.hasPrefix("snapshot list")
            || lowercased.hasPrefix("id ")
            || lowercased.hasPrefix("id\t")
            || emptyMarkers.contains(where: { lowercased.contains($0) }) {
            return nil
        }

        // Columns: ID TAG "VM SIZE"(value unit) "DATE"(date time) "VM CLOCK" [ICOUNT].
        // A tag containing whitespace would break this positional read, which is exactly why
        // `QEMUSnapshotTagPolicy` refuses to create one.
        let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard columns.count >= 7 else {
            return nil
        }

        return VMSnapshotSummary(
            id: columns[0],
            tag: columns[1],
            vmStateSize: "\(columns[2]) \(columns[3])",
            createdAt: "\(columns[4]) \(columns[5])",
            vmClock: columns[6]
        )
    }
}

/// Snapshot names are interpolated into a QEMU monitor command line, so they are restricted to a
/// character set that cannot introduce a second command or an argument boundary.
public enum QEMUSnapshotTagPolicy {
    static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    public static let maximumLength = 64

    public static func validate(_ tag: String) throws -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maximumLength,
              trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw VMSnapshotError.invalidTag(tag)
        }

        return trimmed
    }
}

/// Drives QEMU internal snapshots.
///
/// Create, restore, and delete go through QMP `human-monitor-command` (`savevm`/`loadvm`/`delvm`)
/// against a running machine, because those commands keep guest RAM and disk state consistent with
/// each other. Listing also works while the VM is off, through `qemu-img`, so a user can inspect
/// what they have without booting Windows.
public struct QEMUSnapshotController: Sendable {
    private let qmp: any QEMUQMPControlling
    private let fileExists: @Sendable (String) -> Bool
    private let processRunner: @Sendable (String, [String]) -> QEMUProcessOutcome

    public init(
        qmp: any QEMUQMPControlling = QEMUQMPClient(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        processRunner: @escaping @Sendable (String, [String]) -> QEMUProcessOutcome = QEMUQMPClient.runProcess
    ) {
        self.qmp = qmp
        self.fileExists = fileExists
        self.processRunner = processRunner
    }

    public func list(qmpSocketPath: String) async throws -> [VMSnapshotSummary] {
        let output = try await monitorText("info snapshots", qmpSocketPath: qmpSocketPath)
        return QEMUSnapshotListParser.parse(output)
    }

    public func listOffline(systemDiskPath: String, qemuExecutablePath: String) throws -> [VMSnapshotSummary] {
        let toolPath = Self.snapshotToolPath(forQEMUExecutablePath: qemuExecutablePath)
        guard fileExists(toolPath) else {
            throw VMSnapshotError.snapshotToolUnavailable(toolPath)
        }

        let outcome = processRunner(toolPath, ["snapshot", "-l", systemDiskPath])
        guard outcome.terminationStatus == 0 else {
            throw VMSnapshotError.monitorRejected(
                command: "qemu-img snapshot -l",
                message: outcome.standardOutput.isEmpty
                    ? "qemu-img exited with code \(outcome.terminationStatus.map(String.init) ?? "unknown")."
                    : outcome.standardOutput
            )
        }

        return QEMUSnapshotListParser.parse(outcome.standardOutput)
    }

    @discardableResult
    public func create(tag: String, qmpSocketPath: String) async throws -> String {
        let validated = try QEMUSnapshotTagPolicy.validate(tag)
        _ = try await monitorText("savevm \(validated)", qmpSocketPath: qmpSocketPath)
        return validated
    }

    @discardableResult
    public func restore(tag: String, qmpSocketPath: String) async throws -> String {
        let validated = try QEMUSnapshotTagPolicy.validate(tag)
        _ = try await monitorText("loadvm \(validated)", qmpSocketPath: qmpSocketPath)
        return validated
    }

    @discardableResult
    public func delete(tag: String, qmpSocketPath: String) async throws -> String {
        let validated = try QEMUSnapshotTagPolicy.validate(tag)
        _ = try await monitorText("delvm \(validated)", qmpSocketPath: qmpSocketPath)
        return validated
    }

    /// Runs an HMP command and surfaces monitor-level failures.
    ///
    /// `human-monitor-command` reports command failures inside the returned *text*, not as a QMP
    /// error, so a successful QMP round trip carrying "Error: ..." has to be treated as a failure or
    /// a refused snapshot would look like a completed one.
    private func monitorText(_ command: String, qmpSocketPath: String) async throws -> String {
        let reply: QEMUQMPReply
        do {
            reply = try await qmp.run(.humanMonitor(command), socketPath: qmpSocketPath)
        } catch let error as QEMUQMPClientError {
            switch error {
            case .socketUnavailable, .transportUnavailable:
                throw VMSnapshotError.qmpUnavailable
            case .noReply, .commandFailed:
                throw VMSnapshotError.monitorRejected(command: command, message: error.localizedDescription)
            }
        }

        let text = reply.textReturn ?? ""
        if let failure = Self.monitorFailureMessage(in: text) {
            if failure.lowercased().contains("snapshot") && failure.lowercased().contains("not found") {
                throw VMSnapshotError.snapshotNotFound(command.split(separator: " ").last.map(String.init) ?? command)
            }
            throw VMSnapshotError.monitorRejected(command: command, message: failure)
        }

        return text
    }

    static func monitorFailureMessage(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            if lowercased.hasPrefix("error")
                || lowercased.contains("does not support")
                || lowercased.contains("not found")
                || lowercased.contains("could not")
                || lowercased.contains("failed") {
                return trimmed
            }
        }

        return nil
    }

    /// `qemu-img` ships next to `qemu-system-aarch64` in every supported install layout, so it is
    /// resolved from the executable Veil already discovered instead of probing paths again.
    static func snapshotToolPath(forQEMUExecutablePath path: String) -> String {
        URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .appendingPathComponent("qemu-img")
            .path
    }
}

public enum VMSnapshotCapabilityFactory {
    public static let listCommand = "veil-vmctl vm-snapshot-list --json"
    public static let createCommand = "veil-vmctl vm-snapshot-create --json --name <name>"
    public static let restoreCommand = "veil-vmctl vm-snapshot-restore --json --name <name>"
    public static let deleteCommand = "veil-vmctl vm-snapshot-delete --json --name <name>"

    public static func make(
        snapshot: VMRuntimeSnapshot,
        planArguments: [String]?
    ) -> VMSnapshotCapability {
        guard let virtualDiskPath = snapshot.virtualDiskPath else {
            return VMSnapshotCapability(
                state: .notConfigured,
                detail: "No Windows virtual disk is configured yet, so there is nothing to snapshot."
            )
        }

        guard snapshot.runtimeProvider?.kind == .qemuHypervisor else {
            return VMSnapshotCapability(
                state: .unsupportedProvider,
                systemDiskPath: virtualDiskPath,
                detail: "Snapshots are implemented for the local QEMU/HVF provider only. The Apple Virtualization fallback has no equivalent internal-snapshot format."
            )
        }

        let format = planArguments.flatMap(systemDiskFormat(in:))
        guard format == VMSnapshotCapability.requiredDiskFormat else {
            let convertedPath = convertedDiskPath(for: virtualDiskPath)
            return VMSnapshotCapability(
                state: .unsupportedDiskFormat,
                systemDiskFormat: format,
                systemDiskPath: virtualDiskPath,
                convertedDiskPath: convertedPath,
                conversionCommand: conversionCommand(from: virtualDiskPath, to: convertedPath),
                detail: "Veil's default system disk is \(format ?? "an unknown format"), and QEMU internal snapshots can only be stored inside a \(VMSnapshotCapability.requiredDiskFormat) image. Suspend and resume still work on this disk because they stream guest memory to a separate file."
            )
        }

        return VMSnapshotCapability(
            state: .supported,
            systemDiskFormat: format,
            systemDiskPath: virtualDiskPath,
            detail: "The Windows system disk is \(VMSnapshotCapability.requiredDiskFormat), so QEMU internal snapshots can store guest memory and disk state together."
        )
    }

    /// Reads the disk format from the system drive argument, handling both the plan form
    /// (`if=none,id=system,format=raw,file=...`) and the lock-safe launch form
    /// (`driver=raw,file.driver=file,...,id=system`).
    static func systemDiskFormat(in arguments: [String]) -> String? {
        guard let argument = arguments.first(where: { $0.contains("id=system") }) else {
            return nil
        }

        for key in ["format=", "driver="] {
            for field in argument.split(separator: ",", omittingEmptySubsequences: true) {
                let text = String(field)
                guard text.hasPrefix(key) else {
                    continue
                }

                let value = String(text.dropFirst(key.count))
                if !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    static func convertedDiskPath(for virtualDiskPath: String) -> String {
        URL(fileURLWithPath: virtualDiskPath)
            .deletingPathExtension()
            .appendingPathExtension(VMSnapshotCapability.requiredDiskFormat)
            .path
    }

    static func conversionCommand(from source: String, to destination: String) -> String {
        "qemu-img convert -p -O \(VMSnapshotCapability.requiredDiskFormat) \(QEMUQMPCommand.shellSingleQuoted(source)) \(QEMUQMPCommand.shellSingleQuoted(destination))"
    }
}

public enum VMSnapshotActionReportFactory {
    public static func make(
        action: VMSnapshotActionKind,
        snapshot: VMRuntimeSnapshot,
        capability: VMSnapshotCapability,
        generatedAt: Date,
        requestedTag: String? = nil,
        snapshots: [VMSnapshotSummary] = [],
        errorMessage: String? = nil
    ) -> VMSnapshotActionReport {
        let status: VMSnapshotActionStatus
        if !capability.isSupported {
            status = .unavailable
        } else if errorMessage != nil {
            status = .failed
        } else {
            status = .succeeded
        }

        return VMSnapshotActionReport(
            action: action,
            generatedAt: generatedAt,
            status: status,
            vmState: snapshot.state,
            provider: snapshot.runtimeProvider?.displayName ?? "Unknown local provider",
            capability: capability,
            requestedTag: requestedTag,
            snapshots: snapshots,
            errorMessage: errorMessage,
            nextActions: nextActions(
                action: action,
                status: status,
                vmState: snapshot.state,
                capability: capability,
                snapshots: snapshots
            )
        )
    }

    private static func nextActions(
        action: VMSnapshotActionKind,
        status: VMSnapshotActionStatus,
        vmState: VMRuntimeState,
        capability: VMSnapshotCapability,
        snapshots: [VMSnapshotSummary]
    ) -> [String] {
        var actions: [String] = []

        switch status {
        case .unavailable:
            actions.append(capability.detail)
            if let conversionCommand = capability.conversionCommand,
               let convertedDiskPath = capability.convertedDiskPath {
                actions.append("Convert the system disk with: \(conversionCommand)")
                actions.append("Then point the VM profile's virtual disk at \(convertedDiskPath) and keep the original file until Windows boots from the converted disk.")
            }
            actions.append("Use veil-vmctl vm-suspend --json when you only need to keep the current Windows session, which works on the current disk format.")
        case .failed:
            if vmState != .running, action != .list {
                actions.append("Start or resume Windows first; \(action.rawValue) needs a running machine so guest memory and disk state stay consistent.")
            }
            actions.append("Run \(VMSnapshotCapabilityFactory.listCommand) to re-read the snapshots that exist on the system disk.")
        case .succeeded:
            switch action {
            case .list:
                actions.append(
                    snapshots.isEmpty
                        ? "Run \(VMSnapshotCapabilityFactory.createCommand) while Windows is running to capture the first snapshot."
                        : "Run \(VMSnapshotCapabilityFactory.restoreCommand) to return Windows to one of the listed snapshots."
                )
            case .create:
                actions.append("Run \(VMSnapshotCapabilityFactory.listCommand) to confirm the new snapshot is recorded on the system disk.")
            case .restore:
                actions.append("Windows resumed from the snapshot. Reconnect the guest agent with veil-vmctl guest-agent-wait --json before launching Windows apps.")
            case .delete:
                actions.append("Run \(VMSnapshotCapabilityFactory.listCommand) to confirm the snapshot was removed and space was reclaimed.")
            }
        }

        return actions
    }
}
