import Foundation

public struct VMRuntimeProviderProbe: Sendable {
    public static let qemuEnvironmentKey = "VEIL_QEMU_SYSTEM_AARCH64"
    public static let defaultQEMUExecutablePaths = [
        "/opt/homebrew/bin/qemu-system-aarch64",
        "/usr/local/bin/qemu-system-aarch64",
        "/opt/local/bin/qemu-system-aarch64"
    ]

    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileExists: @Sendable (String) -> Bool
    private let executableVersion: @Sendable (String) -> String?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        executableVersion: @escaping @Sendable (String) -> String? = Self.qemuVersionOutput(executablePath:)
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileExists = fileExists
        self.executableVersion = executableVersion
    }

    public func localProviders(
        architecture: String,
        minimumOSSupported: Bool
    ) -> [VMRuntimeProviderSummary] {
        [
            appleVirtualizationProvider(
                architecture: architecture,
                minimumOSSupported: minimumOSSupported
            ),
            qemuHypervisorProvider()
        ]
    }

    private func appleVirtualizationProvider(
        architecture: String,
        minimumOSSupported: Bool
    ) -> VMRuntimeProviderSummary {
        let isAvailable = architecture == "arm64" && minimumOSSupported
        return VMRuntimeProviderSummary(
            kind: .appleVirtualization,
            displayName: "Apple Virtualization",
            mode: "Local VM runtime",
            acceleration: "Apple Hypervisor",
            isServerBacked: false,
            status: isAvailable ? .active : .unavailable,
            detail: isAvailable
                ? "Runs locally inside Veil.app with no server VM backend."
                : "Requires macOS 15+ on Apple Silicon."
        )
    }

    private func qemuHypervisorProvider() -> VMRuntimeProviderSummary {
        if let executablePath = qemuExecutablePath() {
            return VMRuntimeProviderSummary(
                kind: .qemuHypervisor,
                displayName: "QEMU/HVF",
                mode: "Local compatibility provider",
                acceleration: "HVF",
                isServerBacked: false,
                status: .active,
                detail: "qemu-system-aarch64 found locally for UTM-style Windows compatibility experiments.",
                executablePath: executablePath,
                executableVersion: Self.firstVersionLine(from: executableVersion(executablePath))
            )
        }

        return VMRuntimeProviderSummary(
            kind: .qemuHypervisor,
            displayName: "QEMU/HVF",
            mode: "Local compatibility provider",
            acceleration: "HVF",
            isServerBacked: false,
            status: .planned,
            detail: "qemu-system-aarch64 not found. Install QEMU locally or set VEIL_QEMU_SYSTEM_AARCH64 to a local executable path."
        )
    }

    private func qemuExecutablePath() -> String? {
        if let overridePath = environment[Self.qemuEnvironmentKey],
           !overridePath.isEmpty,
           fileExists(overridePath) {
            return overridePath
        }

        // Finder-launched apps do not inherit a shell's PATH. Veil's optional runtime bridge is
        // therefore checked before Homebrew/MacPorts locations, while the bridge's version probe
        // prevents a stale or partially copied wrapper from being reported as an active provider.
        let managedPath = Self.managedQEMUExecutablePath(homeDirectory: homeDirectory)
        if fileExists(managedPath),
           executableVersion(managedPath) != nil {
            return managedPath
        }

        return Self.defaultQEMUExecutablePaths.first(where: fileExists)
            ?? Self.userPrefixQEMUExecutablePaths(environment: environment, homeDirectory: homeDirectory)
                .first(where: fileExists)
    }

    public static func qemuExecutablePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        [managedQEMUExecutablePath(homeDirectory: homeDirectory)]
            + defaultQEMUExecutablePaths
            + userPrefixQEMUExecutablePaths(environment: environment, homeDirectory: homeDirectory)
    }

    /// Homebrew prefixes outside `/opt/homebrew` and `/usr/local`, such as `~/homebrew` on Macs where
    /// the system prefix is not writable. Finder-launched apps never inherit the shell's PATH, so a
    /// QEMU installed there was invisible and Veil silently fell back to the console-only provider.
    /// These prefixes are probed only after the standard locations.
    public static func userPackagePrefixes(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let standardPrefixes: Set<String> = ["/opt/homebrew", "/usr/local", "/opt/local"]
        let candidates = [environment["HOMEBREW_PREFIX"]].compactMap { $0 }
            + ["homebrew", ".homebrew"].map { homeDirectory.appendingPathComponent($0, isDirectory: true).path }
        var seen = Set<String>()
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !standardPrefixes.contains($0) && seen.insert($0).inserted }
    }

    static func userPrefixQEMUExecutablePaths(
        environment: [String: String],
        homeDirectory: URL
    ) -> [String] {
        userPackagePrefixes(environment: environment, homeDirectory: homeDirectory)
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("bin/qemu-system-aarch64").path }
    }

    private static func managedQEMUExecutablePath(homeDirectory: URL) -> String {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Veil/Runtime/bin", isDirectory: true)
            .appendingPathComponent("qemu-system-aarch64")
            .path
    }

    private static func firstVersionLine(from output: String?) -> String? {
        output?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func qemuVersionOutput(executablePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
