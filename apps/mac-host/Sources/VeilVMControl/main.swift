import Foundation
import Darwin
import VeilHostCore

enum VMControlError: Error, LocalizedError {
    case missingCommand
    case unsupportedCommand(String)
    case missingInstallerPath
    case installerNotFound(String)
    case driverMediaNotFound(String)
    case missingProfileForQEMUPlan
    case qemuNotReady([String])
    case missingQEMULaunchRecord
    case qemuMonitorUnavailable(String)
    case qemuScreenshotCaptureFailed(String)
    case missingQEMUKeySequence
    case missingQEMUText
    case missingQEMUPointerCoordinate
    case qemuAlreadyRunning(pid: Int32, monitorSocketPath: String)
    case missingForceStopAcknowledgement

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            Self.usage
        case .unsupportedCommand(let command):
            "Unsupported command '\(command)'. \(Self.usage)"
        case .missingInstallerPath:
            "Missing installer path. \(Self.usage)"
        case .installerNotFound(let path):
            "Installer file does not exist: \(path)"
        case .driverMediaNotFound(let path):
            "Driver media file does not exist: \(path)"
        case .missingProfileForQEMUPlan:
            "No prepared VM profile found. Run veil-vmctl prepare --installer /path/to/Windows.iso first."
        case .qemuNotReady(let nextActions):
            "QEMU/HVF is not ready. \(nextActions.joined(separator: " "))"
        case .missingQEMULaunchRecord:
            "No QEMU launch record found. Run veil-vmctl qemu-start first."
        case .qemuMonitorUnavailable(let path):
            "QEMU monitor socket is not available: \(path)"
        case .qemuScreenshotCaptureFailed(let path):
            "QEMU console screenshot could not be captured: \(path)"
        case .missingQEMUKeySequence:
            "Missing QEMU key sequence. Pass keys such as shift-f10, esc, tab, ret, or spc."
        case .missingQEMUText:
            "Missing QEMU text. Pass qemu-type-text --text \"...\" with bounded ASCII input."
        case .missingQEMUPointerCoordinate:
            "Missing QEMU pointer coordinates. Pass --x and --y as absolute values from 0 to 32767."
        case .qemuAlreadyRunning(let pid, let monitorSocketPath):
            "QEMU is already running as PID \(pid). Use qemu-capture to inspect it or qemu-powerdown to request a safe shutdown before starting another VM. Monitor socket: \(monitorSocketPath)"
        case .missingForceStopAcknowledgement:
            "Force stop can interrupt Windows disk writes. Re-run with \(QEMUForceStopAuthorization.acknowledgementFlag) only when the VM cannot shut down normally."
        }
    }

    private static let usage = "Usage: veil-vmctl prepare --installer /path/to/Windows.iso [--drivers /path/to/virtio-win.iso] | veil-vmctl providers [--json] | veil-vmctl qemu-plan [--json] | veil-vmctl qemu-doctor [--json] | veil-vmctl qemu-smoke [--json] [--seconds 45] | veil-vmctl qemu-start [--json] [--wait-seconds 15] | veil-vmctl qemu-capture [--json] [--output /path/to/console.png] | veil-vmctl qemu-powerdown [--json] [--wait-seconds 30] | veil-vmctl qemu-force-stop [--json] --i-understand-data-loss [--wait-seconds 10] | veil-vmctl qemu-sendkey [--json] key [key ...] | veil-vmctl qemu-type-text [--json] --text \"...\" | veil-vmctl qemu-click [--json] --x 0...32767 --y 0...32767 | veil-vmctl qemu-oobe-bypass [--json] | veil-vmctl qemu-install-agent [--json]"
}

struct VMControlArguments {
    enum Command: Equatable {
        case prepare(installerPath: String, driverMediaPath: String?)
        case providers(json: Bool)
        case qemuPlan(json: Bool)
        case qemuDoctor(json: Bool)
        case qemuSmoke(json: Bool, seconds: Int)
        case qemuStart(json: Bool, waitSeconds: Int)
        case qemuCapture(json: Bool, outputPath: String?)
        case qemuPowerDown(json: Bool, waitSeconds: Int)
        case qemuForceStop(json: Bool, waitSeconds: Int, isAuthorized: Bool)
        case qemuSendKey(json: Bool, keys: [String])
        case qemuTypeText(json: Bool, text: String)
        case qemuClick(json: Bool, x: Int, y: Int)
        case qemuOOBEBypass(json: Bool)
        case qemuInstallAgent(json: Bool)
    }

    var command: Command

    static func parse(_ arguments: [String]) throws -> VMControlArguments {
        guard let command = arguments.first else {
            throw VMControlError.missingCommand
        }

        if command == "providers" {
            return VMControlArguments(command: .providers(json: arguments.contains("--json")))
        }

        if command == "qemu-plan" {
            return VMControlArguments(command: .qemuPlan(json: arguments.contains("--json")))
        }

        if command == "qemu-doctor" {
            return VMControlArguments(command: .qemuDoctor(json: arguments.contains("--json")))
        }

        if command == "qemu-smoke" {
            let seconds = secondsArgument(from: arguments) ?? 45
            return VMControlArguments(command: .qemuSmoke(json: arguments.contains("--json"), seconds: seconds))
        }

        if command == "qemu-start" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 15
            return VMControlArguments(command: .qemuStart(json: arguments.contains("--json"), waitSeconds: waitSeconds))
        }

        if command == "qemu-capture" {
            return VMControlArguments(
                command: .qemuCapture(
                    json: arguments.contains("--json"),
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "qemu-powerdown" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 30
            return VMControlArguments(command: .qemuPowerDown(json: arguments.contains("--json"), waitSeconds: waitSeconds))
        }

        if command == "qemu-force-stop" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 10
            return VMControlArguments(
                command: .qemuForceStop(
                    json: arguments.contains("--json"),
                    waitSeconds: waitSeconds,
                    isAuthorized: QEMUForceStopAuthorization.isAuthorized(arguments: arguments)
                )
            )
        }

        if command == "qemu-sendkey" {
            let keys = arguments
                .dropFirst()
                .filter { !$0.hasPrefix("--") }
            guard !keys.isEmpty else {
                throw VMControlError.missingQEMUKeySequence
            }
            return VMControlArguments(command: .qemuSendKey(json: arguments.contains("--json"), keys: Array(keys)))
        }

        if command == "qemu-type-text" {
            guard let text = stringArgument(named: "--text", from: arguments),
                  !text.isEmpty else {
                throw VMControlError.missingQEMUText
            }
            return VMControlArguments(command: .qemuTypeText(json: arguments.contains("--json"), text: text))
        }

        if command == "qemu-click" {
            guard let x = intArgument(named: "--x", from: arguments),
                  let y = intArgument(named: "--y", from: arguments) else {
                throw VMControlError.missingQEMUPointerCoordinate
            }
            return VMControlArguments(command: .qemuClick(json: arguments.contains("--json"), x: x, y: y))
        }

        if command == "qemu-oobe-bypass" {
            return VMControlArguments(command: .qemuOOBEBypass(json: arguments.contains("--json")))
        }

        if command == "qemu-install-agent" {
            return VMControlArguments(command: .qemuInstallAgent(json: arguments.contains("--json")))
        }

        guard command == "prepare" else {
            throw VMControlError.unsupportedCommand(command)
        }

        guard let installerFlagIndex = arguments.firstIndex(of: "--installer"),
              arguments.indices.contains(installerFlagIndex + 1) else {
            throw VMControlError.missingInstallerPath
        }

        return VMControlArguments(
            command: .prepare(
                installerPath: arguments[installerFlagIndex + 1],
                driverMediaPath: stringArgument(named: "--drivers", from: arguments)
            )
        )
    }

    private static func secondsArgument(from arguments: [String]) -> Int? {
        guard let secondsFlagIndex = arguments.firstIndex(of: "--seconds"),
              arguments.indices.contains(secondsFlagIndex + 1) else {
            return nil
        }

        return Int(arguments[secondsFlagIndex + 1])
    }

    private static func waitSecondsArgument(from arguments: [String]) -> Int? {
        guard let secondsFlagIndex = arguments.firstIndex(of: "--wait-seconds"),
              arguments.indices.contains(secondsFlagIndex + 1) else {
            return nil
        }

        return Int(arguments[secondsFlagIndex + 1])
    }

    private static func stringArgument(named name: String, from arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: name),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        return arguments[flagIndex + 1]
    }

    private static func intArgument(named name: String, from arguments: [String]) -> Int? {
        stringArgument(named: name, from: arguments).flatMap(Int.init)
    }
}

struct QEMUConsoleCaptureRecord: Codable, Equatable {
    var kind: String = "qemuConsoleCapture"
    var monitorSocketPath: String
    var consoleScreenshotPath: String
    var capturedAt: Date
}

struct QEMUKeySendResult: Codable, Equatable {
    var key: String
    var transport: String
    var socketPath: String
    var monitorCommand: String
    var terminationStatus: Int32?
    var didLaunchSender: Bool
}

struct QEMUKeySendRecord: Codable, Equatable {
    var kind: String = "qemuKeySend"
    var monitorSocketPath: String
    var keys: [String]
    var results: [QEMUKeySendResult]
    var sentAt: Date
}

struct QEMUPointerClickRecord: Codable, Equatable {
    var kind: String = "qemuPointerClick"
    var monitorSocketPath: String
    var qmpSocketPath: String
    var x: Int
    var y: Int
    var results: [QEMUKeySendResult]
    var sentAt: Date
}

struct QEMUPowerDownRecord: Codable, Equatable {
    var kind: String = "qemuPowerDown"
    var pid: Int32?
    var monitorSocketPath: String
    var qmpSocketPath: String?
    var transport: String
    var socketPath: String
    var command: String
    var didLaunchSender: Bool
    var terminationStatus: Int32?
    var waitedSeconds: Int
    var didExitWithinWait: Bool
    var requestedAt: Date
}

struct QEMUForceStopRecord: Codable, Equatable {
    var kind: String = "qemuForceStop"
    var pid: Int32?
    var signal: String
    var didSignalProcess: Bool
    var waitedSeconds: Int
    var didExitWithinWait: Bool
    var requestedAt: Date
}

@main
struct VeilVMControl {
    static func main() async {
        do {
            let arguments = try VMControlArguments.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(arguments)
        } catch {
            let message: String
            if let localized = error as? LocalizedError,
               let description = localized.errorDescription {
                message = description
            } else {
                message = String(describing: error)
            }

            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: VMControlArguments) async throws {
        switch arguments.command {
        case .prepare(let installerPath, let driverMediaPath):
            try await prepare(installerPath: installerPath, driverMediaPath: driverMediaPath)
        case .providers(let json):
            try printProviders(json: json)
        case .qemuPlan(let json):
            try await printQEMUPlan(json: json)
        case .qemuDoctor(let json):
            try await printQEMUDoctor(json: json)
        case .qemuSmoke(let json, let seconds):
            try await printQEMUSmoke(json: json, seconds: seconds)
        case .qemuStart(let json, let waitSeconds):
            try await startQEMU(json: json, waitSeconds: waitSeconds)
        case .qemuCapture(let json, let outputPath):
            try await captureQEMUConsole(json: json, outputPath: outputPath)
        case .qemuPowerDown(let json, let waitSeconds):
            try await powerDownQEMU(json: json, waitSeconds: waitSeconds)
        case .qemuForceStop(let json, let waitSeconds, let isAuthorized):
            try await forceStopQEMU(json: json, waitSeconds: waitSeconds, isAuthorized: isAuthorized)
        case .qemuSendKey(let json, let keys):
            try await sendQEMUKeys(json: json, keys: keys)
        case .qemuTypeText(let json, let text):
            try await typeQEMUText(json: json, text: text)
        case .qemuClick(let json, let x, let y):
            try await clickQEMU(json: json, x: x, y: y)
        case .qemuOOBEBypass(let json):
            try await sendQEMUOOBEBypass(json: json)
        case .qemuInstallAgent(let json):
            try await sendQEMUGuestAgentInstall(json: json)
        }
    }

    private static func prepare(installerPath: String, driverMediaPath: String?) async throws {
        let installerURL = URL(fileURLWithPath: installerPath)
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            throw VMControlError.installerNotFound(installerURL.path)
        }

        let driverMediaURL = driverMediaPath.map(URL.init(fileURLWithPath:))
        if let driverMediaURL,
           !FileManager.default.fileExists(atPath: driverMediaURL.path) {
            throw VMControlError.driverMediaNotFound(driverMediaURL.path)
        }

        let service = LocalVMRuntimeService()
        let preparedSnapshot = try await service.prepareDefaultVM()
        let configuredSnapshot = try await service.updateProfilePaths(
            installerMediaPath: installerURL.path,
            driverMediaPath: driverMediaURL?.path ?? preparedSnapshot.driverMediaPath,
            virtualDiskPath: preparedSnapshot.virtualDiskPath
        )
        let diagnosticsURL = try await service.exportDiagnostics(to: diagnosticsDirectory())
        let profile = try await JSONVMProfileStore().load()

        print("Veil VM prepared")
        print("Profile: \(configuredSnapshot.profileName ?? "Not configured")")
        print("Installer: \(configuredSnapshot.installerMediaPath ?? "Not selected")")
        print("Drivers: \(configuredSnapshot.driverMediaPath ?? "Not selected")")
        print("Virtual disk: \(configuredSnapshot.virtualDiskPath ?? "Not selected")")
        print("Shared folder: \(profile?.sharedFolderPath ?? "Not configured")")
        print("Boot ready: \(configuredSnapshot.bootReady ? "yes" : "no")")
        print("Detail: \(configuredSnapshot.detail)")
        print("Diagnostics: \(diagnosticsURL.path)")
    }

    private static func printProviders(json: Bool) throws {
        let architecture = hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let providers = VMRuntimeProviderProbe().localProviders(
            architecture: architecture,
            minimumOSSupported: minimumOSSupported
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(providers)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        for provider in providers {
            let pathSuffix = provider.executablePath.map { " at \($0)" } ?? ""
            print("\(provider.displayName): \(provider.status.rawValue), \(provider.mode), \(provider.acceleration)\(pathSuffix)")
            print("  \(provider.detail)")
        }
    }

    private static func printQEMUPlan(json: Bool) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let plan = try makeQEMUPlan(for: profile)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(plan)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print(plan.summary)
        print("\(plan.executablePath) \(plan.arguments.map(shellQuoted).joined(separator: " "))")
        if !plan.warnings.isEmpty {
            print("Warnings:")
            for warning in plan.warnings {
                print("  - \(warning)")
            }
        }
    }

    private static func printQEMUDoctor(json: Bool) async throws {
        let profile = try await JSONVMProfileStore().load()
        let plan = try? profile.map(makeQEMUPlan(for:))
        let report = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF readiness: \(report.overallState.rawValue)")
        for check in report.checks {
            print("\(check.title): \(check.state.rawValue)")
            print("  \(check.detail)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func printQEMUSmoke(json: Bool, seconds: Int) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let boundedSeconds = min(max(seconds, 5), 120)
        let plan = try makeQEMUPlan(for: profile)
        let logDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Smoke", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let serialLogURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).serial.log")
        let processLogURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).process.log")
        let consoleScreenshotURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).console.png")
        let monitorSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("veil-qemu-smoke-\(UUID().uuidString.prefix(8)).sock")
        let qmpSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("veil-qemu-smoke-\(UUID().uuidString.prefix(8)).qmp.sock")
        let arguments = QEMUWindowsBootSmokePlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path
        )
        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)

        let processOutput = try runBoundedQEMU(
            executablePath: plan.executablePath,
            arguments: arguments,
            seconds: boundedSeconds,
            processLogURL: processLogURL,
            monitorSocketURL: monitorSocketURL,
            consoleScreenshotURL: consoleScreenshotURL
        )
        try? FileManager.default.removeItem(at: monitorSocketURL)
        try? FileManager.default.removeItem(at: qmpSocketURL)
        let serialOutput = (try? String(contentsOf: serialLogURL, encoding: .utf8)) ?? ""
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: boundedSeconds,
            processOutput: processOutput.output,
            serialOutput: serialOutput,
            didRemainRunningUntilTimeout: processOutput.didRemainRunningUntilTimeout,
            serialLogPath: serialLogURL.path,
            processLogPath: processLogURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            runEvidence: processOutput.bootPromptKeySendCount > 0 ? ["boot-prompt-key-sent"] : []
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF smoke: \(report.outcome.rawValue)")
        print(report.detail)
        print("Evidence: \(report.evidence.joined(separator: ", "))")
        print("Serial log: \(report.serialLogPath)")
        print("Process log: \(report.processLogPath)")
        print("Console screenshot: \(report.consoleScreenshotPath)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func startQEMU(json: Bool, waitSeconds: Int) async throws {
        try rejectDuplicateQEMULaunchIfNeeded()

        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let plan = try makeQEMUPlan(for: profile)
        let readiness = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )
        guard readiness.overallState == .ready else {
            throw VMControlError.qemuNotReady(readiness.nextActions)
        }
        let shouldSendInstallerBootKey = QEMUWindowsInstallerBootPolicy.shouldSendBootKey(
            profile: profile,
            virtualDiskAllocatedBytes: QEMUWindowsInstallerBootPolicy.allocatedFileSize(path: profile.virtualDiskPath)
        )

        let logDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let processLogURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).log")
        let serialLogURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).serial.log")
        let consoleScreenshotURL = logDirectory.appendingPathComponent("qemu-console-\(stamp).png")
        let monitorSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).sock")
        let qmpSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).qmp.sock")
        FileManager.default.createFile(atPath: processLogURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: processLogURL)
        let launchArguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            bootDiskFirst: !shouldSendInstallerBootKey
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = launchArguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)
        try process.run()
        bringQEMUToFront()
        driveInitialQEMULaunch(
            process: process,
            waitSeconds: waitSeconds,
            shouldSendInstallerBootKey: shouldSendInstallerBootKey,
            monitorSocketURL: monitorSocketURL,
            consoleScreenshotURL: consoleScreenshotURL
        )

        let record = QEMULaunchRecord(
            provider: plan.provider,
            pid: process.processIdentifier,
            executablePath: plan.executablePath,
            arguments: launchArguments,
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date()
        )
        try writeQEMULaunchRecord(record, directory: logDirectory, stamp: stamp)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF Windows VM launched")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Executable: \(record.executablePath)")
        print("Process log: \(record.processLogPath)")
        print("Serial log: \(serialLogURL.path)")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("QMP socket: \(record.qmpSocketPath ?? "not attached")")
        print("Console screenshot: \(record.consoleScreenshotPath ?? "pending")")
    }

    private static func writeQEMULaunchRecord(
        _ record: QEMULaunchRecord,
        directory: URL,
        stamp: String
    ) throws {
        let data = try JSONEncoder.veilDiagnostics.encode(record)
        try data.write(to: directory.appendingPathComponent("qemu-launch-\(stamp).json"), options: .atomic)
        try data.write(to: directory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)
    }

    private static func captureQEMUConsole(json: Bool, outputPath: String?) async throws {
        let directory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        let latestURL = directory.appendingPathComponent("qemu-launch-latest.json")
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            throw VMControlError.missingQEMULaunchRecord
        }

        let data = try Data(contentsOf: latestURL)
        var launchRecord = try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
        guard FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        let screenshotURL: URL
        if let outputPath,
           !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            screenshotURL = URL(fileURLWithPath: outputPath)
        } else if let path = launchRecord.consoleScreenshotPath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            screenshotURL = URL(fileURLWithPath: path)
        } else {
            let stamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            screenshotURL = directory.appendingPathComponent("qemu-console-\(stamp).png")
        }

        try FileManager.default.createDirectory(
            at: screenshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        QEMUVMRuntimeBooter.captureConsoleScreenshot(
            monitorSocketURL: URL(fileURLWithPath: launchRecord.monitorSocketPath),
            imageURL: screenshotURL
        )
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw VMControlError.qemuScreenshotCaptureFailed(screenshotURL.path)
        }

        launchRecord.consoleScreenshotPath = screenshotURL.path
        let launchData = try JSONEncoder.veilDiagnostics.encode(launchRecord)
        try launchData.write(to: latestURL, options: .atomic)

        let captureRecord = QEMUConsoleCaptureRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            consoleScreenshotPath: screenshotURL.path,
            capturedAt: Date()
        )
        if json {
            let captureData = try JSONEncoder.veilDiagnostics.encode(captureRecord)
            print(String(decoding: captureData, as: UTF8.self))
            return
        }

        print("QEMU console screenshot captured")
        print("Monitor socket: \(captureRecord.monitorSocketPath)")
        print("Console screenshot: \(captureRecord.consoleScreenshotPath)")
    }

    private static func powerDownQEMU(json: Bool, waitSeconds: Int) async throws {
        let launchRecord = try latestQEMULaunchRecord()
        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canUseQMP = qmpSocketPath.map { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) } ?? false
        guard canUseQMP || FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        let sender: QEMUKeySendResult
        if canUseQMP, let qmpSocketPath {
            let command = try QEMUQMPControlCommandBuilder.powerDownCommand()
            sender = sendQMPCommand(command, qmpSocketPath: qmpSocketPath, key: "system_powerdown")
        } else {
            sender = sendQEMUMonitorLine(
                "system_powerdown",
                monitorSocketPath: launchRecord.monitorSocketPath,
                key: "system_powerdown"
            )
        }
        let boundedWaitSeconds = min(max(waitSeconds, 0), 120)
        let didExit = await waitForProcessExit(pid: launchRecord.pid, timeoutSeconds: boundedWaitSeconds)
        let record = QEMUPowerDownRecord(
            pid: launchRecord.pid,
            monitorSocketPath: launchRecord.monitorSocketPath,
            qmpSocketPath: launchRecord.qmpSocketPath,
            transport: sender.transport,
            socketPath: sender.socketPath,
            command: sender.monitorCommand,
            didLaunchSender: sender.didLaunchSender,
            terminationStatus: sender.terminationStatus,
            waitedSeconds: boundedWaitSeconds,
            didExitWithinWait: didExit,
            requestedAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU powerdown requested")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Transport: \(record.transport)")
        print("Socket: \(record.socketPath)")
        print("Sender status: \(record.terminationStatus.map(String.init) ?? "not launched")")
        print("Exited within wait: \(record.didExitWithinWait ? "yes" : "no")")
    }

    private static func forceStopQEMU(json: Bool, waitSeconds: Int, isAuthorized: Bool) async throws {
        guard isAuthorized else {
            throw VMControlError.missingForceStopAcknowledgement
        }

        let launchRecord = try latestQEMULaunchRecord()
        let boundedWaitSeconds = min(max(waitSeconds, 0), 120)
        let didSignal: Bool
        if let pid = launchRecord.pid, isProcessRunning(pid: pid) {
            didSignal = Darwin.kill(pid, SIGTERM) == 0
        } else {
            didSignal = false
        }

        let didExit = await waitForProcessExit(pid: launchRecord.pid, timeoutSeconds: boundedWaitSeconds)
        let record = QEMUForceStopRecord(
            pid: launchRecord.pid,
            signal: "SIGTERM",
            didSignalProcess: didSignal,
            waitedSeconds: boundedWaitSeconds,
            didExitWithinWait: didExit,
            requestedAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU force stop requested")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Signal: \(record.signal)")
        print("Signaled: \(record.didSignalProcess ? "yes" : "no")")
        print("Exited within wait: \(record.didExitWithinWait ? "yes" : "no")")
    }

    private static func sendQEMUOOBEBypass(json: Bool) async throws {
        try await sendQEMUKeySteps(json: json, steps: QEMUOOBEBypassKeySequence.steps)
    }

    private static func sendQEMUGuestAgentInstall(json: Bool) async throws {
        try await sendQEMUKeySteps(json: json, steps: QEMUGuestAgentInstallKeySequence.steps)
    }

    private static func sendQEMUKeys(
        json: Bool,
        keys: [String],
        delayAfterFirstKey: TimeInterval = 0.08
    ) async throws {
        let steps = keys.enumerated().map { index, key in
            QEMUKeySequenceStep(
                key: key,
                delayAfterSend: index == 0 ? delayAfterFirstKey : 0.08
            )
        }
        try await sendQEMUKeySteps(json: json, steps: steps)
    }

    private static func sendQEMUKeySteps(
        json: Bool,
        steps: [QEMUKeySequenceStep]
    ) async throws {
        let launchRecord = try latestQEMULaunchRecord()
        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canUseQMP = qmpSocketPath.map { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) } ?? false
        guard canUseQMP || FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        var results: [QEMUKeySendResult] = []
        for step in steps {
            let key = step.key
            if canUseQMP, let qmpSocketPath {
                let command = try QEMUQMPKeyboardCommandBuilder.inputEventCommand(for: key)
                results.append(sendQMPCommand(command, qmpSocketPath: qmpSocketPath, key: key))
            } else {
                let command = "sendkey \(key)"
                results.append(sendQEMUMonitorLine(command, monitorSocketPath: launchRecord.monitorSocketPath, key: key))
            }
            try? await Task.sleep(nanoseconds: UInt64(step.delayAfterSend * 1_000_000_000))
        }

        let record = QEMUKeySendRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            keys: steps.map(\.key),
            results: results,
            sentAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU key sequence sent")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("Keys: \(record.keys.joined(separator: ", "))")
    }

    private static func typeQEMUText(json: Bool, text: String) async throws {
        let steps = try QEMUQMPKeyboardCommandBuilder
            .keySequence(forText: text)
            .map { QEMUKeySequenceStep(key: $0, delayAfterSend: 0.035) }
        try await sendQEMUKeySteps(json: json, steps: steps)
    }

    private static func clickQEMU(json: Bool, x: Int, y: Int) async throws {
        let launchRecord = try latestQEMULaunchRecord()
        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let qmpSocketPath,
              !qmpSocketPath.isEmpty,
              FileManager.default.fileExists(atPath: qmpSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.qmpSocketPath ?? launchRecord.monitorSocketPath)
        }

        let moveCommand = try QEMUQMPPointerCommandBuilder.absoluteMoveCommand(x: x, y: y)
        let downCommand = try QEMUQMPPointerCommandBuilder.leftButtonCommand(isDown: true)
        let upCommand = try QEMUQMPPointerCommandBuilder.leftButtonCommand(isDown: false)
        let results = [
            sendQMPCommand(moveCommand, qmpSocketPath: qmpSocketPath, key: "mouse-move"),
            sendQMPCommand(downCommand, qmpSocketPath: qmpSocketPath, key: "mouse-left-down"),
            sendQMPCommand(upCommand, qmpSocketPath: qmpSocketPath, key: "mouse-left-up")
        ]
        let record = QEMUPointerClickRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            qmpSocketPath: qmpSocketPath,
            x: x,
            y: y,
            results: results,
            sentAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU pointer click sent")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("QMP socket: \(record.qmpSocketPath)")
        print("Absolute coordinate: \(record.x), \(record.y)")
    }

    private static func latestQEMULaunchRecord() throws -> QEMULaunchRecord {
        let latestURL = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
            .appendingPathComponent("qemu-launch-latest.json")
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            throw VMControlError.missingQEMULaunchRecord
        }

        let data = try Data(contentsOf: latestURL)
        return try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
    }

    private static func rejectDuplicateQEMULaunchIfNeeded() throws {
        guard let launchRecord = try? latestQEMULaunchRecord(),
              let pid = launchRecord.pid,
              isProcessRunning(pid: pid) else {
            return
        }

        throw VMControlError.qemuAlreadyRunning(
            pid: pid,
            monitorSocketPath: launchRecord.monitorSocketPath
        )
    }

    private static func isProcessRunning(pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private static func waitForProcessExit(pid: Int32?, timeoutSeconds: Int) async -> Bool {
        guard let pid else {
            return false
        }

        if !isProcessRunning(pid: pid) {
            return true
        }

        guard timeoutSeconds > 0 else {
            return false
        }

        for _ in 0..<timeoutSeconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !isProcessRunning(pid: pid) {
                return true
            }
        }
        return false
    }

    private static func sendQEMUMonitorLine(
        _ line: String,
        monitorSocketPath: String,
        key: String
    ) -> QEMUKeySendResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf '%s\\n' \"$1\" | /usr/bin/nc -w 1 -U \"$0\"",
            monitorSocketPath,
            line
        ]
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            return QEMUKeySendResult(
                key: key,
                transport: "hmp",
                socketPath: monitorSocketPath,
                monitorCommand: line,
                terminationStatus: process.terminationStatus,
                didLaunchSender: true
            )
        } catch {
            return QEMUKeySendResult(
                key: key,
                transport: "hmp",
                socketPath: monitorSocketPath,
                monitorCommand: line,
                terminationStatus: nil,
                didLaunchSender: false
            )
        }
    }

    private static func sendQMPCommand(
        _ command: String,
        qmpSocketPath: String,
        key: String
    ) -> QEMUKeySendResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf '%s\\n%s\\n' \"$1\" \"$2\" | /usr/bin/nc -w 1 -U \"$0\"",
            qmpSocketPath,
            QEMUQMPKeyboardCommandBuilder.capabilitiesCommand(),
            command
        ]
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            return QEMUKeySendResult(
                key: key,
                transport: "qmp",
                socketPath: qmpSocketPath,
                monitorCommand: command,
                terminationStatus: process.terminationStatus,
                didLaunchSender: true
            )
        } catch {
            return QEMUKeySendResult(
                key: key,
                transport: "qmp",
                socketPath: qmpSocketPath,
                monitorCommand: command,
                terminationStatus: nil,
                didLaunchSender: false
            )
        }
    }

    private static func driveInitialQEMULaunch(
        process: Process,
        waitSeconds: Int,
        shouldSendInstallerBootKey: Bool,
        monitorSocketURL: URL,
        consoleScreenshotURL: URL
    ) {
        let boundedSeconds = min(max(waitSeconds, 0), 120)
        let startDate = Date()
        let deadline = startDate.addingTimeInterval(TimeInterval(boundedSeconds))
        var bootPromptAutomation = QEMUWindowsBootPromptAutomation()

        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if shouldSendInstallerBootKey {
                _ = bootPromptAutomation.tick(
                    elapsedSeconds: Int(Date().timeIntervalSince(startDate)),
                    monitorSocketURL: monitorSocketURL,
                    sendBootKey: QEMUVMRuntimeBooter.sendWindowsInstallerBootKey
                )
            }
        }

        if process.isRunning {
            QEMUVMRuntimeBooter.captureConsoleScreenshot(
                monitorSocketURL: monitorSocketURL,
                imageURL: consoleScreenshotURL
            )
        }
    }

    private static func bringQEMUToFront() {
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

    private static func runBoundedQEMU(
        executablePath: String,
        arguments: [String],
        seconds: Int,
        processLogURL: URL,
        monitorSocketURL: URL,
        consoleScreenshotURL: URL
    ) throws -> (output: String, didRemainRunningUntilTimeout: Bool, bootPromptKeySendCount: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let startDate = Date()
        var bootPromptAutomation = QEMUWindowsBootPromptAutomation()
        var bootPromptKeySendCount = 0
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let didSendBootKey = bootPromptAutomation.tick(
                elapsedSeconds: Int(Date().timeIntervalSince(startDate)),
                monitorSocketURL: monitorSocketURL,
                sendBootKey: QEMUVMRuntimeBooter.sendWindowsInstallerBootKey
            )
            if didSendBootKey {
                bootPromptKeySendCount += 1
            }
        }

        let didRemainRunningUntilTimeout = process.isRunning
        if process.isRunning {
            QEMUVMRuntimeBooter.captureConsoleScreenshot(
                monitorSocketURL: monitorSocketURL,
                imageURL: consoleScreenshotURL
            )
            Thread.sleep(forTimeInterval: 0.5)
        }

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        try data.write(to: processLogURL, options: [.atomic])
        return (
            String(data: data, encoding: .utf8) ?? "",
            didRemainRunningUntilTimeout,
            bootPromptKeySendCount
        )
    }

    private static func makeQEMUPlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: hostArchitecture(),
            minimumOSSupported: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            )
        )
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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

    private static func diagnosticsDirectory() -> URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    }

}
