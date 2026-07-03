import Foundation

public struct QEMULaunchRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var provider: String
    public var isServerBacked: Bool
    public var pid: Int32?
    public var executablePath: String
    public var arguments: [String]
    public var processLogPath: String
    public var monitorSocketPath: String
    public var qmpSocketPath: String?
    public var consoleScreenshotPath: String?
    public var startedAt: Date

    public init(
        kind: String = "qemuWindowsArmLaunch",
        provider: String = "QEMU/HVF",
        isServerBacked: Bool = false,
        pid: Int32?,
        executablePath: String,
        arguments: [String],
        processLogPath: String,
        monitorSocketPath: String,
        qmpSocketPath: String? = nil,
        consoleScreenshotPath: String? = nil,
        startedAt: Date
    ) {
        self.kind = kind
        self.provider = provider
        self.isServerBacked = isServerBacked
        self.pid = pid
        self.executablePath = executablePath
        self.arguments = arguments
        self.processLogPath = processLogPath
        self.monitorSocketPath = monitorSocketPath
        self.qmpSocketPath = qmpSocketPath
        self.consoleScreenshotPath = consoleScreenshotPath
        self.startedAt = startedAt
    }
}

public protocol QEMULaunchRecordStore: Sendable {
    func loadLatest() async throws -> QEMULaunchRecord?
}

public struct JSONQEMULaunchRecordStore: QEMULaunchRecordStore {
    private let directory: URL
    private let fileName: String

    public init(
        directory: URL = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true),
        fileName: String = "qemu-launch-latest.json"
    ) {
        self.directory = directory
        self.fileName = fileName
    }

    public func loadLatest() async throws -> QEMULaunchRecord? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
    }
}

public final class QEMUVMRuntimeBooter: VMRuntimeBooting, @unchecked Sendable {
    public static let shared = QEMUVMRuntimeBooter()

    private let diagnosticsDirectory: URL
    private let planBuilder: @Sendable (VMProfile) throws -> QEMUWindowsBootPlan
    private let tpmEmulatorRunner: @Sendable (QEMUWindowsBootPlan) throws -> Void
    private let processRunner: @Sendable (Process) throws -> Void
    private let frontmostRunner: @Sendable () -> Void
    private let bootKeySender: @Sendable (URL) -> Bool
    private let consoleScreenshotCapturer: @Sendable (URL, URL) -> Void
    private var process: Process?
    private var monitorSocketURL: URL?
    private var qmpSocketURL: URL?

    public init(
        diagnosticsDirectory: URL = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory(),
        planBuilder: @escaping @Sendable (VMProfile) throws -> QEMUWindowsBootPlan = QEMUVMRuntimeBooter.makePlan(for:),
        tpmEmulatorRunner: @escaping @Sendable (QEMUWindowsBootPlan) throws -> Void = QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded,
        processRunner: @escaping @Sendable (Process) throws -> Void = { try $0.run() },
        frontmostRunner: @escaping @Sendable () -> Void = QEMUVMRuntimeBooter.bringQEMUToFrontIfAllowed,
        bootKeySender: @escaping @Sendable (URL) -> Bool = QEMUVMRuntimeBooter.sendWindowsInstallerBootKey,
        consoleScreenshotCapturer: @escaping @Sendable (URL, URL) -> Void = QEMUVMRuntimeBooter.captureConsoleScreenshot
    ) {
        self.diagnosticsDirectory = diagnosticsDirectory
        self.planBuilder = planBuilder
        self.tpmEmulatorRunner = tpmEmulatorRunner
        self.processRunner = processRunner
        self.frontmostRunner = frontmostRunner
        self.bootKeySender = bootKeySender
        self.consoleScreenshotCapturer = consoleScreenshotCapturer
    }

    public func runtimeState() async -> VMRuntimeState? {
        guard let process else {
            return nil
        }

        return process.isRunning ? .running : .stopped
    }

    public func start(profile: VMProfile) async throws -> VMRuntimeState {
        if process?.isRunning == true {
            frontmostRunner()
            return .running
        }

        let plan = try planBuilder(profile)
        let readiness = QEMUWindowsReadinessDoctor().makeReport(profile: profile, plan: plan)
        guard readiness.overallState == .ready else {
            throw VMRuntimeError.qemuNotReady(readiness.nextActions.joined(separator: " "))
        }
        let shouldSendInstallerBootKey = QEMUWindowsInstallerBootPolicy.shouldSendBootKey(
            profile: profile,
            virtualDiskAllocatedBytes: QEMUWindowsInstallerBootPolicy.allocatedFileSize(path: profile.virtualDiskPath)
        )

        let launchDirectory = try qemuLaunchDirectory()
        let stamp = Self.timestamp()
        let logURL = launchDirectory.appendingPathComponent("qemu-launch-\(stamp).log")
        let serialLogURL = launchDirectory.appendingPathComponent("qemu-launch-\(stamp).serial.log")
        let consoleScreenshotURL = launchDirectory.appendingPathComponent("qemu-console-\(stamp).png")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        let monitorSocketURL = Self.monitorSocketURL()
        let qmpSocketURL = Self.qmpSocketURL()
        try tpmEmulatorRunner(plan)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            bootDiskFirst: !shouldSendInstallerBootKey
        )
        process.standardOutput = logHandle
        process.standardError = logHandle
        try processRunner(process)
        self.process = process
        self.monitorSocketURL = monitorSocketURL
        self.qmpSocketURL = qmpSocketURL
        try writeLaunchRecord(
            process: process,
            plan: plan,
            arguments: process.arguments ?? [],
            processLogURL: logURL,
            monitorSocketURL: monitorSocketURL,
            qmpSocketURL: qmpSocketURL,
            consoleScreenshotURL: consoleScreenshotURL,
            directory: launchDirectory,
            stamp: stamp
        )
        frontmostRunner()
        if shouldSendInstallerBootKey {
            scheduleWindowsInstallerBootKeySend(monitorSocketURL: monitorSocketURL)
        }
        scheduleConsoleScreenshotCapture(monitorSocketURL: monitorSocketURL, imageURL: consoleScreenshotURL)
        return .running
    }

    public func stop() async throws -> VMRuntimeState {
        guard let process else {
            return .stopped
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        self.process = nil
        if let monitorSocketURL {
            try? FileManager.default.removeItem(at: monitorSocketURL)
        }
        if let qmpSocketURL {
            try? FileManager.default.removeItem(at: qmpSocketURL)
        }
        self.monitorSocketURL = nil
        self.qmpSocketURL = nil
        return .stopped
    }

    public func showConsoleIfRunning() -> Bool {
        guard process?.isRunning == true else {
            return false
        }

        frontmostRunner()
        return true
    }

    public static func makePlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: hostArchitecture(),
            minimumOSSupported: true
        )
    }

    private func qemuLaunchDirectory() throws -> URL {
        let directory = diagnosticsDirectory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeLaunchRecord(
        process: Process,
        plan: QEMUWindowsBootPlan,
        arguments: [String],
        processLogURL: URL,
        monitorSocketURL: URL,
        qmpSocketURL: URL,
        consoleScreenshotURL: URL,
        directory: URL,
        stamp: String
    ) throws {
        let pid = process.processIdentifier > 0 ? process.processIdentifier : nil
        let record = QEMULaunchRecord(
            pid: pid,
            executablePath: plan.executablePath,
            arguments: arguments,
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: directory.appendingPathComponent("qemu-launch-\(stamp).json"), options: .atomic)
        try data.write(to: directory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    public static func defaultDiagnosticsDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public static func bringQEMUToFrontIfAllowed() {
        guard ProcessInfo.processInfo.environment["VEIL_ALLOW_SYSTEM_EVENTS_FRONTMOST"] == "1" else {
            return
        }

        Thread.sleep(forTimeInterval: 0.5)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to set frontmost of process \"qemu-system-aarch64\" to true"
        ]
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
    }

    public static func startTPMEmulatorIfNeeded(plan: QEMUWindowsBootPlan) throws {
        guard let tpmEmulatorPath = plan.tpmEmulatorPath,
              let tpmStateDirectoryPath = plan.tpmStateDirectoryPath else {
            return
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: tpmStateDirectoryPath, withIntermediateDirectories: true)
        let socketURL = URL(fileURLWithPath: tpmStateDirectoryPath)
            .appendingPathComponent("swtpm.sock")
        let pidURL = URL(fileURLWithPath: tpmStateDirectoryPath)
            .appendingPathComponent("swtpm.pid")
        try? fileManager.removeItem(at: socketURL)
        try? fileManager.removeItem(at: pidURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tpmEmulatorPath)
        process.arguments = [
            "socket",
            "--tpm2",
            "--tpmstate", "dir=\(tpmStateDirectoryPath)",
            "--ctrl", "type=unixio,path=\(socketURL.path),terminate",
            "--pid", "file=\(pidURL.path)",
            "--daemon"
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VMRuntimeError.qemuNotReady("swtpm exited with code \(process.terminationStatus).")
        }
    }

    @discardableResult
    public static func sendWindowsInstallerBootKey(monitorSocketURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: monitorSocketURL.path) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf 'sendkey spc\\n' | /usr/bin/nc -U \"$0\"",
            monitorSocketURL.path
        ]
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func captureConsoleScreenshot(monitorSocketURL: URL, imageURL: URL) {
        guard FileManager.default.fileExists(atPath: monitorSocketURL.path) else {
            return
        }

        let rawImageURL = rawConsoleScreenshotURL(for: imageURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf 'screendump \"%s\"\\n' \"$1\" | /usr/bin/nc -U \"$0\"",
            monitorSocketURL.path,
            rawImageURL.path
        ]
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
        process.waitUntilExit()

        guard imageURL.pathExtension.lowercased() == "png",
              FileManager.default.fileExists(atPath: rawImageURL.path) else {
            return
        }

        convertConsoleScreenshotToPNG(rawImageURL: rawImageURL, pngURL: imageURL)
    }

    private static func rawConsoleScreenshotURL(for imageURL: URL) -> URL {
        guard imageURL.pathExtension.lowercased() == "png" else {
            return imageURL
        }

        return imageURL
            .deletingPathExtension()
            .appendingPathExtension("ppm")
    }

    private static func convertConsoleScreenshotToPNG(rawImageURL: URL, pngURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            "-s", "format", "png",
            rawImageURL.path,
            "--out", pngURL.path
        ]
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           FileManager.default.fileExists(atPath: pngURL.path) {
            try? FileManager.default.removeItem(at: rawImageURL)
        }
    }

    private func scheduleWindowsInstallerBootKeySend(monitorSocketURL: URL) {
        let bootKeySender = self.bootKeySender
        Task.detached {
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(1))
                _ = bootKeySender(monitorSocketURL)
            }
        }
    }

    private func scheduleConsoleScreenshotCapture(monitorSocketURL: URL, imageURL: URL) {
        let consoleScreenshotCapturer = self.consoleScreenshotCapturer
        Task.detached {
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(5))
                consoleScreenshotCapturer(monitorSocketURL, imageURL)
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    break
                }
            }
        }
    }

    private static func monitorSocketURL() -> URL {
        URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).sock")
    }

    private static func qmpSocketURL() -> URL {
        URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).qmp.sock")
    }

    private static func hostArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
