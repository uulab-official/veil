import Foundation

public final class QEMUVMRuntimeBooter: VMRuntimeBooting, @unchecked Sendable {
    public static let shared = QEMUVMRuntimeBooter()

    private let diagnosticsDirectory: URL
    private let planBuilder: @Sendable (VMProfile) throws -> QEMUWindowsBootPlan
    private let processRunner: @Sendable (Process) throws -> Void
    private let frontmostRunner: @Sendable () -> Void
    private let bootKeySender: @Sendable (URL) -> Void
    private var process: Process?
    private var monitorSocketURL: URL?

    public init(
        diagnosticsDirectory: URL = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory(),
        planBuilder: @escaping @Sendable (VMProfile) throws -> QEMUWindowsBootPlan = QEMUVMRuntimeBooter.makePlan(for:),
        processRunner: @escaping @Sendable (Process) throws -> Void = { try $0.run() },
        frontmostRunner: @escaping @Sendable () -> Void = QEMUVMRuntimeBooter.bringQEMUToFront,
        bootKeySender: @escaping @Sendable (URL) -> Void = QEMUVMRuntimeBooter.sendWindowsInstallerBootKey
    ) {
        self.diagnosticsDirectory = diagnosticsDirectory
        self.planBuilder = planBuilder
        self.processRunner = processRunner
        self.frontmostRunner = frontmostRunner
        self.bootKeySender = bootKeySender
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

        let logURL = try processLogURL()
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        let monitorSocketURL = Self.monitorSocketURL()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments + [
            "-monitor",
            "unix:\(monitorSocketURL.path),server,nowait"
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle
        try processRunner(process)
        self.process = process
        self.monitorSocketURL = monitorSocketURL
        frontmostRunner()
        scheduleWindowsInstallerBootKeySend(monitorSocketURL: monitorSocketURL)
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
        self.monitorSocketURL = nil
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

    private func processLogURL() throws -> URL {
        let directory = diagnosticsDirectory.appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("qemu-launch-\(stamp).log")
    }

    public static func defaultDiagnosticsDirectory() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("Veil Diagnostics", isDirectory: true)
    }

    public static func bringQEMUToFront() {
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

    public static func sendWindowsInstallerBootKey(monitorSocketURL: URL) {
        guard FileManager.default.fileExists(atPath: monitorSocketURL.path) else {
            return
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
        try? process.run()
    }

    private func scheduleWindowsInstallerBootKeySend(monitorSocketURL: URL) {
        let bootKeySender = self.bootKeySender
        Task.detached {
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(1))
                bootKeySender(monitorSocketURL)
            }
        }
    }

    private static func monitorSocketURL() -> URL {
        URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).sock")
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
