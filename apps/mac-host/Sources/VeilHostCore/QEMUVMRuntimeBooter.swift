import Foundation

public struct QEMULaunchRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var provider: String
    public var isServerBacked: Bool
    public var pid: Int32?
    public var executablePath: String
    public var arguments: [String]
    public var displayMode: QEMUWindowsBootDisplayMode?
    public var processLogPath: String
    public var monitorSocketPath: String
    public var qmpSocketPath: String?
    public var vncHost: String?
    public var vncPort: Int?
    public var consoleScreenshotPath: String?
    public var consoleScreenshotRefreshedAt: Date?
    public var startedAt: Date

    public init(
        kind: String = "qemuWindowsArmLaunch",
        provider: String = "QEMU/HVF",
        isServerBacked: Bool = false,
        pid: Int32?,
        executablePath: String,
        arguments: [String],
        displayMode: QEMUWindowsBootDisplayMode? = .nativeCocoa,
        processLogPath: String,
        monitorSocketPath: String,
        qmpSocketPath: String? = nil,
        vncHost: String? = nil,
        vncPort: Int? = nil,
        consoleScreenshotPath: String? = nil,
        consoleScreenshotRefreshedAt: Date? = nil,
        startedAt: Date
    ) {
        self.kind = kind
        self.provider = provider
        self.isServerBacked = isServerBacked
        self.pid = pid
        self.executablePath = executablePath
        self.arguments = arguments
        self.displayMode = displayMode
        self.processLogPath = processLogPath
        self.monitorSocketPath = monitorSocketPath
        self.qmpSocketPath = qmpSocketPath
        self.vncHost = vncHost
        self.vncPort = vncPort
        self.consoleScreenshotPath = consoleScreenshotPath
        self.consoleScreenshotRefreshedAt = consoleScreenshotRefreshedAt
        self.startedAt = startedAt
    }
}

public protocol QEMULaunchRecordStore: Sendable {
    func loadLatest() async throws -> QEMULaunchRecord?
}

public struct QEMURunningProcess: Codable, Equatable, Sendable {
    public var pid: Int32
    public var commandLine: String
    public var monitorSocketPath: String?
    public var qmpSocketPath: String?

    public init(
        pid: Int32,
        commandLine: String,
        monitorSocketPath: String? = nil,
        qmpSocketPath: String? = nil
    ) {
        self.pid = pid
        self.commandLine = commandLine
        self.monitorSocketPath = monitorSocketPath
        self.qmpSocketPath = qmpSocketPath
    }
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
    private let vncPortAllocator: @Sendable () -> Int?
    private let displayMode: QEMUWindowsBootDisplayMode
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
        consoleScreenshotCapturer: @escaping @Sendable (URL, URL) -> Void = QEMUVMRuntimeBooter.captureConsoleScreenshot,
        vncPortAllocator: @escaping @Sendable () -> Int? = QEMUVMRuntimeBooter.allocateLoopbackVNCPort,
        displayMode: QEMUWindowsBootDisplayMode = .nativeCocoa
    ) {
        self.diagnosticsDirectory = diagnosticsDirectory
        self.planBuilder = planBuilder
        self.tpmEmulatorRunner = tpmEmulatorRunner
        self.processRunner = processRunner
        self.frontmostRunner = frontmostRunner
        self.bootKeySender = bootKeySender
        self.consoleScreenshotCapturer = consoleScreenshotCapturer
        self.vncPortAllocator = vncPortAllocator
        self.displayMode = displayMode
    }

    public var supportsNativeDisplayWindow: Bool {
        displayMode == .nativeCocoa
    }

    public func runtimeState() async -> VMRuntimeState? {
        guard let process else {
            return nil
        }

        return process.isRunning ? .running : .stopped
    }

    public func start(profile: VMProfile) async throws -> VMRuntimeState {
        if process?.isRunning == true {
            if displayMode == .nativeCocoa {
                frontmostRunner()
            }
            return .running
        }

        if let runningProcess = Self.runningProcess(attachedToVirtualDiskPath: profile.virtualDiskPath) {
            throw VMRuntimeError.qemuAlreadyRunning(pid: runningProcess.pid)
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
        let vncPort = displayMode == .vncLoopback ? vncPortAllocator() : nil
        if displayMode == .vncLoopback, vncPort == nil {
            throw VMRuntimeError.qemuDisplayPortUnavailable
        }
        let vncDisplay = vncPort.map { max($0 - 5_900, 0) }
        try tpmEmulatorRunner(plan)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            bootDiskFirst: !shouldSendInstallerBootKey,
            displayMode: displayMode,
            vncDisplay: vncDisplay
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
            vncPort: vncPort,
            consoleScreenshotURL: consoleScreenshotURL,
            directory: launchDirectory,
            stamp: stamp
        )
        if displayMode == .nativeCocoa {
            frontmostRunner()
        }
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
        guard displayMode == .nativeCocoa, process?.isRunning == true else {
            return false
        }

        frontmostRunner()
        return true
    }

    public func installGuestAgentFromAttachedMedia() async throws -> QEMUKeySendRecord {
        let launchRecordStore = JSONQEMULaunchRecordStore(
            directory: diagnosticsDirectory.appendingPathComponent("QEMU Launch", isDirectory: true)
        )
        let steps: [QEMUKeySequenceStep]
        do {
            let pointerSender = QEMUPointerEventSender(launchRecordStore: launchRecordStore)
            _ = try await pointerSender.sendTap(
                normalizedX: QEMUGuestAgentInstallKeySequence.startButtonTapNormalizedX,
                normalizedY: QEMUGuestAgentInstallKeySequence.startButtonTapNormalizedY
            )
            try? await Task.sleep(nanoseconds: 800_000_000)
            steps = try QEMUGuestAgentInstallKeySequence.stepsAfterRunOpened
        } catch {
            steps = try QEMUGuestAgentInstallKeySequence.steps
        }

        let sender = QEMUKeySequenceSender(
            launchRecordStore: launchRecordStore
        )
        return try await sender.send(steps: steps)
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
        vncPort: Int?,
        consoleScreenshotURL: URL,
        directory: URL,
        stamp: String
    ) throws {
        let pid = process.processIdentifier > 0 ? process.processIdentifier : nil
        let record = QEMULaunchRecord(
            pid: pid,
            executablePath: plan.executablePath,
            arguments: arguments,
            displayMode: displayMode,
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            vncHost: vncPort == nil ? nil : "127.0.0.1",
            vncPort: vncPort,
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

    public static func runningProcess(attachedToVirtualDiskPath virtualDiskPath: String?) -> QEMURunningProcess? {
        guard let virtualDiskPath = normalizedNonEmptyPath(virtualDiskPath) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "/bin/ps axww -o pid=,command= | /usr/bin/grep qemu-system-aarch64 || true"
        ]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return runningProcess(
            attachedToVirtualDiskPath: virtualDiskPath,
            processListOutput: output
        )
    }

    static func runningProcess(
        attachedToVirtualDiskPath virtualDiskPath: String?,
        processListOutput: String
    ) -> QEMURunningProcess? {
        guard let virtualDiskPath = normalizedNonEmptyPath(virtualDiskPath) else {
            return nil
        }

        for line in processListOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmedLine.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                continue
            }
            let pidText = trimmedLine[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let commandLine = String(trimmedLine[separator...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(pidText),
                  commandLine.contains("qemu-system-aarch64"),
                  commandLine.contains(virtualDiskPath) else {
                continue
            }

            return QEMURunningProcess(
                pid: pid,
                commandLine: commandLine,
                monitorSocketPath: socketPath(after: "-monitor", in: commandLine),
                qmpSocketPath: socketPath(after: "-qmp", in: commandLine)
            )
        }

        return nil
    }

    private static func normalizedNonEmptyPath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        return path
    }

    private static func socketPath(after flag: String, in commandLine: String) -> String? {
        let parts = commandLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let flagIndex = parts.firstIndex(of: flag),
              parts.indices.contains(flagIndex + 1) else {
            return nil
        }

        let endpoint = parts[flagIndex + 1]
        guard endpoint.hasPrefix("unix:") else {
            return nil
        }

        let withoutScheme = endpoint.dropFirst("unix:".count)
        return String(withoutScheme.split(separator: ",", maxSplits: 1).first ?? "")
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

    public static func allocateLoopbackVNCPort() -> Int? {
        for port in 5_900...5_999 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
            process.standardOutput = nil
            process.standardError = nil

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    return port
                }
            } catch {
                return port
            }
        }

        return nil
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
