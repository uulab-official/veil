import Foundation

/// The on-disk format of the Windows system disk.
///
/// New disks are qcow2, like UTM's, so they grow with use and can hold QEMU internal snapshots.
/// Disks made before Veil switched stay raw and keep booting as raw: the format is read from the
/// file itself, never assumed from the profile.
public enum QEMUDiskImageFormat: String, Codable, Equatable, Sendable {
    case raw
    case qcow2

    /// Every qcow2 image starts with "QFI\xfb" (QEMU's docs/interop/qcow2.rst).
    static let qcow2Magic: [UInt8] = [0x51, 0x46, 0x49, 0xFB]

    public var fileExtension: String {
        switch self {
        case .raw: "img"
        case .qcow2: "qcow2"
        }
    }

    /// The format of an existing image from its header, or from its extension when the file is not
    /// there yet (a disk about to be created, or a plan built for a missing disk).
    public static func detect(
        atPath path: String,
        readHeader: (String) -> Data? = QEMUDiskImageFormat.readHeader
    ) -> QEMUDiskImageFormat {
        if let header = readHeader(path) {
            return Array(header.prefix(qcow2Magic.count)) == qcow2Magic ? .qcow2 : .raw
        }
        return URL(fileURLWithPath: path).pathExtension.lowercased() == QEMUDiskImageFormat.qcow2.fileExtension
            ? .qcow2
            : .raw
    }

    public static func readHeader(_ path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        return try? handle.read(upToCount: qcow2Magic.count)
    }
}

/// What `qemu-img info` reports about the system disk.
public struct QEMUDiskImageInfo: Codable, Equatable, Sendable {
    public var format: QEMUDiskImageFormat
    /// The size Windows sees.
    public var virtualSizeBytes: Int64
    /// The space the image takes on the Mac.
    public var actualSizeBytes: Int64?

    public init(format: QEMUDiskImageFormat, virtualSizeBytes: Int64, actualSizeBytes: Int64?) {
        self.format = format
        self.virtualSizeBytes = virtualSizeBytes
        self.actualSizeBytes = actualSizeBytes
    }

    private struct Report: Decodable {
        var format: String
        var virtualSize: Int64
        var actualSize: Int64?

        enum CodingKeys: String, CodingKey {
            case format
            case virtualSize = "virtual-size"
            case actualSize = "actual-size"
        }
    }

    static func parse(_ json: String) -> QEMUDiskImageInfo? {
        guard let report = try? JSONDecoder().decode(Report.self, from: Data(json.utf8)),
              let format = QEMUDiskImageFormat(rawValue: report.format) else {
            return nil
        }
        return QEMUDiskImageInfo(format: format, virtualSizeBytes: report.virtualSize, actualSizeBytes: report.actualSize)
    }
}

public enum QEMUDiskImageError: Error, LocalizedError, Equatable, Sendable {
    case toolUnavailable
    case commandFailed(command: String, message: String)
    case unreadableInfo(String)
    case shrinkNotSupported(currentBytes: Int64, requestedBytes: Int64)
    case alreadyQCOW2
    case destinationExists(String)
    case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .toolUnavailable:
            "qemu-img was not found. It ships inside Veil.app; for a development build, install QEMU with Homebrew."
        case .commandFailed(let command, let message):
            "\(command) failed: \(message)"
        case .unreadableInfo(let path):
            "qemu-img could not describe the disk at \(path)."
        case .shrinkNotSupported(let current, let requested):
            "The disk can only grow. It is \(ByteCountFormatter.string(fromByteCount: current, countStyle: .binary)) and \(ByteCountFormatter.string(fromByteCount: requested, countStyle: .binary)) was requested."
        case .alreadyQCOW2:
            "The disk is already qcow2."
        case .destinationExists(let path):
            "A file already exists at \(path), so the converted disk would overwrite it."
        case .insufficientSpace(let required, let available):
            "Converting needs about \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) free, but only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        }
    }
}

/// Runs `qemu-img` against the Windows system disk.
///
/// Every write here (create, resize, convert, offline snapshots) needs QEMU stopped. Veil launches
/// the system disk with `file.locking=off`, so qemu-img cannot refuse a disk in use on its own; the
/// callers check the runtime state first.
public struct QEMUDiskImageTool: Sendable {
    public static let environmentKey = "VEIL_QEMU_IMG"

    public let toolPath: String
    private let processRunner: @Sendable (String, [String]) -> QEMUProcessOutcome

    public init(
        toolPath: String,
        processRunner: @escaping @Sendable (String, [String]) -> QEMUProcessOutcome = QEMUDiskImageTool.runProcess
    ) {
        self.toolPath = toolPath
        self.processRunner = processRunner
    }

    /// The bundled qemu-img first, then one beside every QEMU Veil would launch. UTM's QEMU is a
    /// framework without qemu-img, so it adds no candidate.
    public static func candidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledRuntimeDirectory: URL? = VeilBundledRuntime.directory()
    ) -> [String] {
        let override = environment[environmentKey].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let candidates = [override].compactMap { $0 }.filter { !$0.isEmpty }
            + [VeilBundledRuntime.path(VeilBundledRuntime.qemuImage, in: bundledRuntimeDirectory)].compactMap { $0 }
            + VMRuntimeProviderProbe.qemuExecutablePaths(
                environment: environment,
                homeDirectory: homeDirectory,
                bundledRuntimeDirectory: bundledRuntimeDirectory
            )
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("qemu-img").path }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    public static func located(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledRuntimeDirectory: URL? = VeilBundledRuntime.directory(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> QEMUDiskImageTool? {
        candidatePaths(environment: environment, homeDirectory: homeDirectory, bundledRuntimeDirectory: bundledRuntimeDirectory)
            .first(where: isExecutable)
            .map { QEMUDiskImageTool(toolPath: $0) }
    }

    /// A sparse qcow2 image of `sizeBytes`, which takes almost no space until Windows writes to it.
    public func createQCOW2(path: String, sizeBytes: Int64) throws {
        try run(["create", "-q", "-f", QEMUDiskImageFormat.qcow2.rawValue, path, String(sizeBytes)], command: "qemu-img create")
    }

    /// `-U` reads the header without taking a lock, so the size can be shown while Windows runs.
    public func info(path: String) throws -> QEMUDiskImageInfo {
        let output = try run(["info", "-U", "--output=json", path], command: "qemu-img info")
        guard let info = QEMUDiskImageInfo.parse(output) else {
            throw QEMUDiskImageError.unreadableInfo(path)
        }
        return info
    }

    /// Grows the disk Windows sees. Windows still has to extend its partition in Disk Management.
    public func grow(path: String, format: QEMUDiskImageFormat, currentBytes: Int64, newSizeBytes: Int64) throws {
        guard newSizeBytes > currentBytes else {
            throw QEMUDiskImageError.shrinkNotSupported(currentBytes: currentBytes, requestedBytes: newSizeBytes)
        }
        try run(["resize", "-q", "-f", format.rawValue, path, String(newSizeBytes)], command: "qemu-img resize")
    }

    /// Copies a raw disk into a new qcow2 file. Unwritten (sparse) regions stay unallocated.
    public func convertToQCOW2(source: String, destination: String) throws {
        try run(
            ["convert", "-f", QEMUDiskImageFormat.raw.rawValue, "-O", QEMUDiskImageFormat.qcow2.rawValue, source, destination],
            command: "qemu-img convert"
        )
    }

    // Offline snapshots hold the disk only; Windows boots fresh from them, like after a power cut.

    public func listSnapshots(path: String) throws -> [VMSnapshotSummary] {
        QEMUSnapshotListParser.parse(try run(["snapshot", "-U", "-l", path], command: "qemu-img snapshot -l"))
    }

    public func createSnapshot(path: String, tag: String) throws {
        try run(["snapshot", "-c", QEMUSnapshotTagPolicy.validate(tag), path], command: "qemu-img snapshot -c")
    }

    public func applySnapshot(path: String, tag: String) throws {
        try run(["snapshot", "-a", QEMUSnapshotTagPolicy.validate(tag), path], command: "qemu-img snapshot -a")
    }

    public func deleteSnapshot(path: String, tag: String) throws {
        try run(["snapshot", "-d", QEMUSnapshotTagPolicy.validate(tag), path], command: "qemu-img snapshot -d")
    }

    @discardableResult
    private func run(_ arguments: [String], command: String) throws -> String {
        let outcome = processRunner(toolPath, arguments)
        guard outcome.terminationStatus == 0 else {
            if outcome.terminationStatus == nil {
                throw QEMUDiskImageError.toolUnavailable
            }
            let message = outcome.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw QEMUDiskImageError.commandFailed(
                command: command,
                message: message.isEmpty ? "exit code \(outcome.terminationStatus.map(String.init) ?? "unknown")" : message
            )
        }
        return outcome.standardOutput
    }

    /// Like `QEMUQMPClient.runProcess`, but keeps stderr, where qemu-img prints its errors.
    public static func runProcess(executablePath: String, arguments: [String]) -> QEMUProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return QEMUProcessOutcome(terminationStatus: nil, standardOutput: "")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return QEMUProcessOutcome(
            terminationStatus: process.terminationStatus,
            standardOutput: String(decoding: data, as: UTF8.self)
        )
    }
}
