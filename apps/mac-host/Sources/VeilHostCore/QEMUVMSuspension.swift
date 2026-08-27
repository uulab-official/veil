import Foundation

/// Evidence that a Windows VM was suspended to a local memory-state file.
///
/// This record is metadata only -- paths, machine fingerprint, and migration status -- so it is
/// safe to keep next to the other diagnostics records. The suspended guest memory itself is
/// deliberately written next to the virtual disk instead, because it contains guest RAM and must
/// never be swept into a diagnostics bundle.
public struct VMSuspensionRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var provider: String
    public var stateFilePath: String
    public var stateFileByteCount: Int64?
    public var virtualDiskPath: String?
    public var executablePath: String
    /// Fingerprint of the machine-shaping QEMU arguments that produced this state file. Resume
    /// refuses to load a stream whose machine no longer matches.
    public var machineFingerprint: String
    public var displayMode: QEMUWindowsBootDisplayMode?
    public var migrationStatus: String
    public var suspendedAt: Date

    public init(
        kind: String = "qemuWindowsArmSuspension",
        provider: String = "QEMU/HVF",
        stateFilePath: String,
        stateFileByteCount: Int64? = nil,
        virtualDiskPath: String? = nil,
        executablePath: String,
        machineFingerprint: String,
        displayMode: QEMUWindowsBootDisplayMode? = nil,
        migrationStatus: String,
        suspendedAt: Date
    ) {
        self.kind = kind
        self.provider = provider
        self.stateFilePath = stateFilePath
        self.stateFileByteCount = stateFileByteCount
        self.virtualDiskPath = virtualDiskPath
        self.executablePath = executablePath
        self.machineFingerprint = machineFingerprint
        self.displayMode = displayMode
        self.migrationStatus = migrationStatus
        self.suspendedAt = suspendedAt
    }
}

public protocol VMSuspensionRecordStore: Sendable {
    func loadLatest() async throws -> VMSuspensionRecord?
    func save(_ record: VMSuspensionRecord) async throws
    func clear() async throws
}

public struct JSONVMSuspensionRecordStore: VMSuspensionRecordStore {
    private let directory: URL
    private let fileName: String

    public init(
        directory: URL = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("QEMU Suspend", isDirectory: true),
        fileName: String = "qemu-suspend-latest.json"
    ) {
        self.directory = directory
        self.fileName = fileName
    }

    private var recordURL: URL {
        directory.appendingPathComponent(fileName)
    }

    public func loadLatest() async throws -> VMSuspensionRecord? {
        guard FileManager.default.fileExists(atPath: recordURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: recordURL)
        return try JSONDecoder.veilDiagnostics.decode(VMSuspensionRecord.self, from: data)
    }

    public func save(_ record: VMSuspensionRecord) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.veilDiagnostics.encode(record)
        try data.write(to: recordURL, options: .atomic)
    }

    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: recordURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: recordURL)
    }
}

public enum VMSuspensionError: Error, LocalizedError, Equatable, Sendable {
    case runtimeNotRunning
    case qmpUnavailable
    case memoryStateSaveRejected(String)
    case memoryStateSaveFailed(status: String)
    case memoryStateSaveTimedOut(seconds: Int, latestStatus: String)
    case noSuspendedState
    case suspendedStateFileMissing(String)
    case machineConfigurationChanged(expected: String, actual: String)
    /// The stored fingerprint predates the current scheme, so the machine cannot be proven unchanged
    /// even if it is. Distinguished from ``machineConfigurationChanged`` so the message does not blame
    /// a configuration the user never touched.
    case machineFingerprintSchemeSuperseded(stored: String)

    public var errorDescription: String? {
        switch self {
        case .runtimeNotRunning:
            "No running Windows VM was found to suspend. Start the VM first."
        case .qmpUnavailable:
            "The running Windows VM's QMP control channel is unavailable or timed out, so its session cannot be suspended safely. Leave it running or stop it, then retry."
        case .memoryStateSaveRejected(let message):
            "QEMU rejected the Windows VM memory state save: \(message)"
        case .memoryStateSaveFailed(let status):
            "The Windows VM memory state save ended in state '\(status)'. The VM is still paused; resume or stop it before retrying."
        case .memoryStateSaveTimedOut(let seconds, let latestStatus):
            "The Windows VM memory state save did not finish within \(seconds) seconds (last reported state '\(latestStatus)'). The VM is still paused."
        case .noSuspendedState:
            "No suspended Windows VM state was found. Start the VM instead of resuming it."
        case .suspendedStateFileMissing(let path):
            "The suspended Windows VM memory state file is missing: \(path). Start the VM instead of resuming it."
        case .machineConfigurationChanged(let expected, let actual):
            "The Windows VM configuration changed since it was suspended (expected \(expected), found \(actual)). Discard the suspended state and start the VM instead."
        case .machineFingerprintSchemeSuperseded(let stored):
            "This session was suspended by an earlier version of Veil that recorded the machine differently (\(stored)), so Veil cannot prove the machine is unchanged. Your Windows configuration is probably fine, but resuming without that proof risks corrupting the guest. Start the VM normally; this only affects sessions suspended before the upgrade."
        }
    }
}

/// Stable fingerprint of the machine-shaping QEMU arguments.
///
/// A saved migration stream can only be loaded by a QEMU whose machine and device configuration
/// matches the one that produced it. Rather than trusting that the stored profile never changed
/// between suspend and resume, Veil records this fingerprint and refuses a mismatched resume.
/// Per-launch plumbing is excluded because it legitimately differs on every start without changing
/// the guest-visible machine.
public enum QEMUBootArgumentsFingerprint {
    /// Current scheme identifier.
    ///
    /// Versioned because the set of arguments considered machine-shaping changed once host port
    /// forwarding was excluded. A record written under the old scheme cannot be compared against a
    /// value computed under this one, and silently treating the mismatch as a changed machine would
    /// blame the user's configuration for a Veil upgrade.
    public static let schemeIdentifier = "fnv1a64/2"
    static let legacySchemeIdentifier = "fnv1a64"

    static let perLaunchFlags: Set<String> = [
        "-serial",
        "-monitor",
        "-qmp",
        "-vnc",
        "-display",
        "-incoming"
    ]

    /// Flags whose value can carry host-side port forwarding clauses.
    static let forwardingCarryingFlags: Set<String> = [
        "-netdev",
        "-nic"
    ]

    /// Clauses that map host ports into the guest network without changing the guest-visible machine.
    ///
    /// Excluded from the fingerprint on purpose. A `hostfwd`/`guestfwd` rule is slirp-side plumbing:
    /// the guest sees an identical NIC with an identical MAC and address either way, and QEMU
    /// migration does not serialize forwarding rules. Hashing them bought no protection and made
    /// turning the shared folder on or off silently invalidate a suspended Windows session. Device
    /// topology is a different question and stays hashed.
    static let hostForwardingComponentPrefixes = [
        "hostfwd=",
        "guestfwd="
    ]

    public static func value(for arguments: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        // U+0001 separator so ["-m", "8192M"] can never collide with ["-m8192M"].
        for byte in Array(machineShapingArguments(arguments).joined(separator: "\u{1}").utf8) {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        let hex = String(hash, radix: 16)
        return schemeIdentifier + ":" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    /// Whether a stored fingerprint was written by a Veil that used a different definition of
    /// "machine-shaping", which makes it incomparable rather than merely different.
    public static func isFromSupersededScheme(_ storedValue: String) -> Bool {
        !storedValue.hasPrefix(schemeIdentifier + ":")
            && storedValue.hasPrefix(legacySchemeIdentifier + ":")
    }

    static func machineShapingArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]

            if perLaunchFlags.contains(argument) {
                // Skip the flag and its value. Guarded so a trailing flag cannot run past the end.
                index += arguments.index(after: index) < arguments.endIndex ? 2 : 1
                continue
            }

            let valueIndex = arguments.index(after: index)
            if forwardingCarryingFlags.contains(argument), valueIndex < arguments.endIndex {
                result.append(argument)
                result.append(withoutHostForwarding(arguments[valueIndex]))
                index += 2
                continue
            }

            result.append(argument)
            index += 1
        }

        return result
    }

    /// Strips forwarding clauses from a comma-separated QEMU option value, preserving everything else
    /// in place so two values that differ only in forwarding hash identically.
    static func withoutHostForwarding(_ value: String) -> String {
        value
            .split(separator: ",", omittingEmptySubsequences: false)
            .filter { component in
                !hostForwardingComponentPrefixes.contains { prefix in
                    component.hasPrefix(prefix)
                }
            }
            .joined(separator: ",")
    }
}

/// Suspends a running QEMU/HVF Windows VM to a local memory-state file.
///
/// QEMU's internal `savevm` snapshots need a qcow2 image, and Veil's default system disk is raw
/// (`if=none,id=system,format=raw`), so suspend uses the migration path instead: pause the guest,
/// stream RAM plus device state through `migrate` to a file, then quit the process. The raw disk is
/// never rewritten, which is why this works on the shipping disk format.
public struct QEMUVMSuspensionController: Sendable {
    public static let defaultPollAttempts = 240
    public static let defaultPollIntervalNanoseconds: UInt64 = 500_000_000
    /// QMP commands that change VM state must tolerate a busy Windows guest. The old two-second
    /// transport window could expire after QEMU had already processed `stop`, leaving the guest
    /// paused while Veil incorrectly reported that QMP was unavailable.
    static let qmpControlIdleTimeoutSeconds = 10

    /// Terminal QEMU migration states. Anything else means the save is still in flight.
    static let completedMigrationStatus = "completed"
    static let failedMigrationStatuses: Set<String> = ["failed", "cancelled"]

    private let qmp: any QEMUQMPControlling
    private let fileByteCount: @Sendable (String) -> Int64?
    private let now: @Sendable () -> Date
    private let sleeper: @Sendable (UInt64) async -> Void

    public init(
        qmp: any QEMUQMPControlling = QEMUQMPClient(),
        fileByteCount: @escaping @Sendable (String) -> Int64? = QEMUVMSuspensionController.byteCount(atPath:),
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            _ = try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.qmp = qmp
        self.fileByteCount = fileByteCount
        self.now = now
        self.sleeper = sleeper
    }

    public func suspend(
        launchRecord: QEMULaunchRecord,
        planArguments: [String],
        virtualDiskPath: String?,
        stateFilePath: String,
        pollAttempts: Int = QEMUVMSuspensionController.defaultPollAttempts,
        pollIntervalNanoseconds: UInt64 = QEMUVMSuspensionController.defaultPollIntervalNanoseconds
    ) async throws -> VMSuspensionRecord {
        guard let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !qmpSocketPath.isEmpty else {
            throw VMSuspensionError.qmpUnavailable
        }

        // Pausing first makes the migration converge immediately: there is no dirty-page race to
        // chase because the guest is not running while the stream is written. QEMU can process the
        // state change just before the transport timeout, so verify the resulting state before
        // surfacing an unavailable-channel error.
        do {
            try await stopGuest(qmpSocketPath: qmpSocketPath)
        } catch let error as QEMUQMPClientError {
            switch error {
            case .socketUnavailable, .transportUnavailable, .noReply:
                throw VMSuspensionError.qmpUnavailable
            case .commandFailed:
                throw VMSuspensionError.memoryStateSaveRejected(error.localizedDescription)
            }
        }

        // A stale state file from an earlier suspend would otherwise be appended to by `cat >`'s
        // truncation only if the redirect succeeds; remove it up front so a failed save cannot look
        // like a usable stream.
        try? FileManager.default.removeItem(atPath: stateFilePath)

        do {
            try await qmp.run(
                .saveMemoryState(filePath: stateFilePath),
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            )
        } catch {
            throw VMSuspensionError.memoryStateSaveRejected(error.localizedDescription)
        }

        let migrationStatus = try await waitForMemoryStateSave(
            qmpSocketPath: qmpSocketPath,
            pollAttempts: pollAttempts,
            pollIntervalNanoseconds: pollIntervalNanoseconds
        )

        // QEMU exits as it acknowledges `quit`, so a missing reply here is the expected outcome
        // rather than a failure. The suspension is already durable at this point.
        _ = try? await qmp.execute([.quit], socketPath: qmpSocketPath, idleTimeoutSeconds: 2)

        return VMSuspensionRecord(
            stateFilePath: stateFilePath,
            stateFileByteCount: fileByteCount(stateFilePath),
            virtualDiskPath: virtualDiskPath,
            executablePath: launchRecord.executablePath,
            machineFingerprint: QEMUBootArgumentsFingerprint.value(for: planArguments),
            displayMode: launchRecord.displayMode,
            migrationStatus: migrationStatus,
            suspendedAt: now()
        )
    }

    /// Loads a saved memory-state stream into an already-launched, `-incoming` QEMU and unpauses it.
    ///
    /// The caller launches QEMU; this only drives the QMP side, so the launch path stays owned by
    /// the booter that already knows how to build arguments and write launch records.
    public func resumeLoadedMachine(
        qmpSocketPath: String,
        socketWaitAttempts: Int = 60,
        socketWaitIntervalNanoseconds: UInt64 = 250_000_000
    ) async throws {
        var lastError: any Error = VMSuspensionError.qmpUnavailable
        for attempt in 0..<max(1, socketWaitAttempts) {
            if attempt > 0 {
                await sleeper(socketWaitIntervalNanoseconds)
            }

            do {
                // `-incoming` QEMU starts paused with the stream already applied, so `cont` is what
                // actually hands the CPU back to Windows.
                try await qmp.run(.cont, socketPath: qmpSocketPath)
                return
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    public func runState(qmpSocketPath: String) async -> String? {
        guard let reply = try? await qmp.run(.queryStatus, socketPath: qmpSocketPath) else {
            return nil
        }

        return reply.statusReturn
    }

    private func waitForMemoryStateSave(
        qmpSocketPath: String,
        pollAttempts: Int,
        pollIntervalNanoseconds: UInt64
    ) async throws -> String {
        let attempts = max(1, pollAttempts)
        var latestStatus = "unknown"

        for attempt in 0..<attempts {
            if attempt > 0 {
                await sleeper(pollIntervalNanoseconds)
            }

            guard let reply = try? await qmp.run(
                .queryMigrate,
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            ),
                  let status = reply.statusReturn else {
                continue
            }

            latestStatus = status
            if status == Self.completedMigrationStatus {
                return status
            }
            if Self.failedMigrationStatuses.contains(status) {
                throw VMSuspensionError.memoryStateSaveFailed(status: status)
            }
        }

        throw VMSuspensionError.memoryStateSaveTimedOut(
            seconds: Int((Double(attempts) * Double(pollIntervalNanoseconds) / 1_000_000_000).rounded()),
            latestStatus: latestStatus
        )
    }

    /// Sends `stop` and distinguishes a transport timeout from a command that was not applied.
    /// QMP may acknowledge the state transition after the local `nc` process has already timed out;
    /// querying the VM state prevents a safe, paused guest from being mistaken for a lost VM.
    private func stopGuest(qmpSocketPath: String) async throws {
        do {
            try await qmp.run(
                .stop,
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            )
        } catch let error as QEMUQMPClientError {
            switch error {
            case .socketUnavailable, .transportUnavailable, .noReply:
                if let status = try? await qmp.run(
                    .queryStatus,
                    socketPath: qmpSocketPath,
                    idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
                ), status.isRunning == false || status.statusReturn == "paused" {
                    return
                }
            case .commandFailed:
                break
            }
            throw error
        }
    }

    /// Default memory-state file path: alongside the virtual disk, never inside diagnostics.
    ///
    /// `.vmsave` is already covered by the repository `.gitignore`, so a suspended VM cannot be
    /// committed by accident.
    public static func defaultStateFilePath(virtualDiskPath: String) -> String {
        URL(fileURLWithPath: virtualDiskPath)
            .deletingPathExtension()
            .appendingPathExtension("vmsave")
            .path
    }

    public static func byteCount(atPath path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }
}

public enum VMSessionActionKind: String, Codable, Equatable, Sendable {
    case suspend
    case resume
    case status
}

public enum VMSessionActionStatus: String, Codable, Equatable, Sendable {
    /// The Windows session is persisted to a memory-state file and QEMU has exited.
    case suspended
    /// A persisted session was loaded and the guest is executing again.
    case resumed
    case running
    case stopped
    /// The provider or profile cannot persist a session at all.
    case unavailable
    case failed
}

/// How -- and whether -- the active provider can persist a live Windows session.
///
/// `memoryStateFile` is the only supported mode, and that choice is deliberate: QEMU's internal
/// `savevm` snapshots require a qcow2 image, while Veil's shipping system disk is raw. Streaming RAM
/// and device state through the migration path works on the disk format Veil actually ships.
public struct VMSessionPersistenceSummary: Codable, Equatable, Sendable {
    public static let memoryStateFileMode = "memoryStateFile"
    public static let unsupportedMode = "unsupported"

    public var isSupported: Bool
    public var mode: String
    public var stateFilePath: String?
    public var stateFileByteCount: Int64?
    public var machineFingerprint: String?
    public var suspendedAt: Date?
    public var detail: String

    public init(
        isSupported: Bool,
        mode: String,
        stateFilePath: String? = nil,
        stateFileByteCount: Int64? = nil,
        machineFingerprint: String? = nil,
        suspendedAt: Date? = nil,
        detail: String
    ) {
        self.isSupported = isSupported
        self.mode = mode
        self.stateFilePath = stateFilePath
        self.stateFileByteCount = stateFileByteCount
        self.machineFingerprint = machineFingerprint
        self.suspendedAt = suspendedAt
        self.detail = detail
    }
}

public struct VMSessionActionReport: Codable, Equatable, Sendable {
    public var kind: String
    public var action: VMSessionActionKind
    public var generatedAt: Date
    public var status: VMSessionActionStatus
    public var state: VMRuntimeState
    public var provider: String
    public var canSuspend: Bool
    public var canResume: Bool
    public var persistence: VMSessionPersistenceSummary
    public var errorMessage: String?
    public var nextActions: [String]

    public init(
        kind: String = "vmSessionAction",
        action: VMSessionActionKind,
        generatedAt: Date,
        status: VMSessionActionStatus,
        state: VMRuntimeState,
        provider: String,
        canSuspend: Bool,
        canResume: Bool,
        persistence: VMSessionPersistenceSummary,
        errorMessage: String? = nil,
        nextActions: [String]
    ) {
        self.kind = kind
        self.action = action
        self.generatedAt = generatedAt
        self.status = status
        self.state = state
        self.provider = provider
        self.canSuspend = canSuspend
        self.canResume = canResume
        self.persistence = persistence
        self.errorMessage = errorMessage
        self.nextActions = nextActions
    }
}

public enum VMSessionActionReportFactory {
    public static let suspendCommand = "veil-vmctl vm-suspend --json"
    public static let resumeCommand = "veil-vmctl vm-resume --json"
    public static let statusCommand = "veil-vmctl vm-session-status --json"
    public static let startCommand = "veil-vmctl qemu-start --json"
    static let nonMigratableStorageDetail = "Suspend is disabled for this QEMU machine because its active NVMe storage device is not migratable. Stop and start Windows normally. A future storage-device migration is required before suspend/resume can be enabled."

    public static func make(
        action: VMSessionActionKind,
        snapshot: VMRuntimeSnapshot,
        generatedAt: Date,
        errorMessage: String? = nil
    ) -> VMSessionActionReport {
        let persistence = persistenceSummary(snapshot: snapshot)
        let canSuspend = errorMessage == nil && snapshot.state == .running && persistence.isSupported
        let canResume = snapshot.state == .suspended && snapshot.suspendedSession != nil
        let status = self.status(
            action: action,
            snapshot: snapshot,
            persistence: persistence,
            errorMessage: errorMessage
        )

        return VMSessionActionReport(
            action: action,
            generatedAt: generatedAt,
            status: status,
            state: snapshot.state,
            provider: snapshot.runtimeProvider?.displayName ?? "Unknown local provider",
            canSuspend: canSuspend,
            canResume: canResume,
            persistence: persistence,
            errorMessage: errorMessage,
            nextActions: nextActions(
                status: status,
                canSuspend: canSuspend,
                canResume: canResume,
                persistence: persistence
            )
        )
    }

    static func persistenceSummary(snapshot: VMRuntimeSnapshot) -> VMSessionPersistenceSummary {
        guard snapshot.runtimeProvider?.kind == .qemuHypervisor else {
            return VMSessionPersistenceSummary(
                isSupported: false,
                mode: VMSessionPersistenceSummary.unsupportedMode,
                detail: "Session persistence is implemented for the local QEMU/HVF provider only. The Apple Virtualization fallback can start and stop Windows but cannot yet persist a running session."
            )
        }

        guard let virtualDiskPath = snapshot.virtualDiskPath else {
            return VMSessionPersistenceSummary(
                isSupported: false,
                mode: VMSessionPersistenceSummary.unsupportedMode,
                detail: "No virtual disk is configured, so there is nowhere to keep a suspended Windows session."
            )
        }

        if hasNonMigratableStorageDevice(snapshot: snapshot) {
            return VMSessionPersistenceSummary(
                isSupported: false,
                mode: VMSessionPersistenceSummary.unsupportedMode,
                detail: nonMigratableStorageDetail
            )
        }

        if let record = snapshot.suspendedSession {
            return VMSessionPersistenceSummary(
                isSupported: true,
                mode: VMSessionPersistenceSummary.memoryStateFileMode,
                stateFilePath: record.stateFilePath,
                stateFileByteCount: record.stateFileByteCount,
                machineFingerprint: record.machineFingerprint,
                suspendedAt: record.suspendedAt,
                detail: "A suspended Windows session is stored as a QEMU memory-state stream next to the virtual disk. The raw system disk is untouched by suspend."
            )
        }

        return VMSessionPersistenceSummary(
            isSupported: true,
            mode: VMSessionPersistenceSummary.memoryStateFileMode,
            stateFilePath: QEMUVMSuspensionController.defaultStateFilePath(virtualDiskPath: virtualDiskPath),
            detail: "Suspend streams guest memory and device state to a local file so the Windows session survives a QEMU exit. Veil does not use QEMU internal snapshots here because the system disk is raw."
        )
    }

    static func hasNonMigratableStorageDevice(snapshot: VMRuntimeSnapshot) -> Bool {
        if let commandLine = snapshot.runningQEMUProcess?.commandLine,
           commandLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains(where: {
               $0 == "nvme" || $0.hasPrefix("nvme,")
           }) {
            return true
        }

        return snapshot.deviceSummary?.storageDevices.contains {
            $0.attachment.caseInsensitiveCompare("NVMe") == .orderedSame
        } == true
    }

    private static func status(
        action: VMSessionActionKind,
        snapshot: VMRuntimeSnapshot,
        persistence: VMSessionPersistenceSummary,
        errorMessage: String?
    ) -> VMSessionActionStatus {
        if errorMessage != nil {
            return persistence.isSupported ? .failed : .unavailable
        }

        switch action {
        case .suspend:
            guard persistence.isSupported else {
                return .unavailable
            }
            return snapshot.state == .suspended ? .suspended : .failed
        case .resume:
            guard persistence.isSupported else {
                return .unavailable
            }
            return snapshot.state == .running ? .resumed : .failed
        case .status:
            switch snapshot.state {
            case .running, .starting:
                return .running
            case .suspended:
                return .suspended
            case .stopped:
                return .stopped
            case .failed:
                return .failed
            case .notConfigured, .unsupported:
                return .unavailable
            }
        }
    }

    private static func nextActions(
        status: VMSessionActionStatus,
        canSuspend: Bool,
        canResume: Bool,
        persistence: VMSessionPersistenceSummary
    ) -> [String] {
        var actions: [String] = []

        if canResume {
            actions.append("Run \(resumeCommand) to continue the suspended Windows session with its apps still open.")
        }
        if canSuspend {
            actions.append("Run \(suspendCommand) to persist the Windows session instead of shutting Windows down.")
        }

        switch status {
        case .stopped:
            actions.append("Run \(startCommand) to boot Windows before a session can be suspended.")
        case .failed:
            actions.append("Run \(statusCommand) to re-read the current session state before retrying.")
        case .unavailable:
            actions.append(persistence.detail)
        case .suspended, .resumed, .running:
            break
        }

        if !persistence.isSupported && !actions.contains(persistence.detail) {
            actions.append(persistence.detail)
        }

        if actions.isEmpty {
            actions.append("Run \(statusCommand) to inspect the current Windows session state.")
        }

        return actions
    }
}
