import Foundation

/// A non-Windows VM: its profile plus the optional hardware the generic planner reads.
public struct GuestVM: Codable, Equatable, Identifiable, Sendable {
    public var profile: VMProfile
    public var options: QEMUGuestBootOptions

    public var id: String { profile.id }

    public init(profile: VMProfile, options: QEMUGuestBootOptions = QEMUGuestBootOptions()) {
        self.profile = profile
        self.options = options
    }
}

/// Non-Windows guests, one folder each under `~/Virtual Machines/Veil Guests/<id>/`.
///
/// Kept beside the single Windows profile rather than inside it: the Windows profile store and
/// its VM folder belong to the app's one-click Windows path, and a Linux disk must never be what
/// that path finds when it looks for "the" VM.
public struct GuestVMStore: Sendable {
    public static let fileName = "guest.json"

    public let rootDirectory: URL

    public init(rootDirectory: URL = Self.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    public static var defaultRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Virtual Machines", isDirectory: true)
            .appendingPathComponent("Veil Guests", isDirectory: true)
    }

    public func directory(for id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    /// A new guest with its folder reserved but nothing on disk yet.
    public func makeGuest(
        _ guestOS: VMGuestOS,
        name: String,
        installerMediaPath: String?,
        options: QEMUGuestBootOptions = QEMUGuestBootOptions(),
        resources: VMResourcePlan? = nil,
        id: String = VMProfile.newGuestID()
    ) -> GuestVM {
        GuestVM(
            profile: .newGuest(
                guestOS,
                name: name,
                installerMediaPath: installerMediaPath,
                directory: directory(for: id),
                resources: resources,
                id: id
            ),
            options: options
        )
    }

    public func save(_ guest: GuestVM) throws {
        let directory = directory(for: guest.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(guest).write(to: directory.appendingPathComponent(Self.fileName), options: [.atomic])
    }

    public func load(id: String) throws -> GuestVM {
        try Self.load(from: directory(for: id).appendingPathComponent(Self.fileName))
    }

    public static func load(from url: URL) throws -> GuestVM {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GuestVM.self, from: Data(contentsOf: url))
    }

    public func list() -> [GuestVM] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)) ?? []
        return entries
            .compactMap { try? Self.load(from: $0.appendingPathComponent(Self.fileName)) }
            .sorted { $0.profile.createdAt < $1.profile.createdAt }
    }
}

public enum GuestVMLaunchError: Error, LocalizedError, Equatable, Sendable {
    case notLaunchable([String])
    case alreadyRunning(pid: Int32)
    case tpmEmulatorFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .notLaunchable(let warnings):
            "The guest cannot start yet. \(warnings.joined(separator: " "))"
        case .alreadyRunning(let pid):
            "This guest is already running as QEMU PID \(pid)."
        case .tpmEmulatorFailed(let status):
            "swtpm exited with code \(status)."
        }
    }
}

public struct GuestVMLaunchRecord: Codable, Equatable, Sendable {
    public var pid: Int32
    public var processLogPath: String
    public var monitorSocketPath: String
    public var arguments: [String]
}

/// Prepares a guest's disk and UEFI variables and starts its QEMU process.
///
/// This is deliberately small next to `QEMUVMRuntimeBooter`: no installer key automation, no
/// answer file, no agent, no suspend. The console is QEMU's own window (or none, for headless
/// measurement), the way UTM shows a generic VM.
public enum GuestVMLauncher {
    public enum Display: String, Sendable {
        case cocoa
        case none
    }

    /// Creates the sparse system disk and the per-VM UEFI variable store when they are missing.
    /// An existing disk is never touched.
    public static func prepare(_ guest: GuestVM, plan: QEMUGuestBootPlan) throws {
        let fileManager = FileManager.default
        guard let diskPath = guest.profile.virtualDiskPath else {
            throw QEMUGuestBootPlanError.missingVirtualDisk
        }
        let directory = URL(fileURLWithPath: diskPath).deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: diskPath) {
            fileManager.createFile(atPath: diskPath, contents: nil)
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: diskPath))
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(guest.profile.diskGB) * 1_024 * 1_024 * 1_024)
        }

        if !fileManager.fileExists(atPath: plan.firmwareVarsPath), plan.isFirmwareAvailable {
            try fileManager.copyItem(atPath: plan.firmwareVarsTemplatePath, toPath: plan.firmwareVarsPath)
            // Homebrew's templates are read-only; QEMU must be able to write the per-VM copy.
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plan.firmwareVarsPath)
            if plan.guestOS == .linuxArm64 {
                // The virt machine's second flash bank is exactly 64 MiB, and Veil's Secure Boot
                // variable store is shipped unpadded, so it is grown to the bank size like the
                // Windows path does.
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: plan.firmwareVarsPath))
                defer { try? handle.close() }
                try handle.truncate(atOffset: LocalVMRuntimeService.armUEFIVariablesStoreSizeBytes)
            }
        }
    }

    public static func launch(
        _ guest: GuestVM,
        plan: QEMUGuestBootPlan,
        display: Display = .cocoa,
        extraArguments: [String] = []
    ) throws -> GuestVMLaunchRecord {
        guard plan.isLaunchable else {
            throw GuestVMLaunchError.notLaunchable(plan.warnings)
        }
        if let pid = runningPID(virtualDiskPath: guest.profile.virtualDiskPath) {
            throw GuestVMLaunchError.alreadyRunning(pid: pid)
        }
        try prepare(guest, plan: plan)
        try startTPMEmulatorIfNeeded(plan: plan)

        let directory = URL(fileURLWithPath: plan.firmwareVarsPath).deletingLastPathComponent()
        let logURL = directory.appendingPathComponent("qemu.log")
        // Unix socket paths are capped at 104 bytes, and a VM folder under the home directory can
        // exceed that, so the monitor lives in the short per-user temporary directory.
        let monitorSocketURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("veil-guest-\(guest.id.suffix(12)).monitor")
        try? FileManager.default.removeItem(at: monitorSocketURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)

        let arguments = plan.arguments + [
            "-display", display.rawValue,
            "-monitor", "unix:\(monitorSocketURL.path),server,nowait"
        ] + extraArguments

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = arguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        return GuestVMLaunchRecord(
            pid: process.processIdentifier,
            processLogPath: logURL.path,
            monitorSocketPath: monitorSocketURL.path,
            arguments: arguments
        )
    }

    /// The QEMU process (aarch64 or x86_64) that has this disk open, if any.
    public static func runningPID(virtualDiskPath: String?) -> Int32? {
        guard let virtualDiskPath = QEMUGuestBootPlanner.nonEmpty(virtualDiskPath) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["axww", "-o", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            return nil
        }
        // Drained before waiting so a long process list cannot fill the pipe and deadlock.
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return runningPID(virtualDiskPath: virtualDiskPath, processListOutput: output)
    }

    static func runningPID(virtualDiskPath: String, processListOutput: String) -> Int32? {
        for line in processListOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<space]) else {
                continue
            }
            let command = trimmed[space...]
            if command.contains("qemu-system-"), command.contains("file=\(virtualDiskPath),") {
                return pid
            }
        }
        return nil
    }

    static func startTPMEmulatorIfNeeded(plan: QEMUGuestBootPlan) throws {
        guard let tpmEmulatorPath = plan.tpmEmulatorPath,
              let tpmStateDirectoryPath = plan.tpmStateDirectoryPath else {
            return
        }
        try FileManager.default.createDirectory(atPath: tpmStateDirectoryPath, withIntermediateDirectories: true)
        let socketPath = tpmStateDirectoryPath + "/swtpm.sock"
        try? FileManager.default.removeItem(atPath: socketPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tpmEmulatorPath)
        process.arguments = [
            "socket", "--tpm2",
            "--tpmstate", "dir=\(tpmStateDirectoryPath)",
            "--ctrl", "type=unixio,path=\(socketPath),terminate",
            "--daemon"
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GuestVMLaunchError.tpmEmulatorFailed(process.terminationStatus)
        }
    }
}
