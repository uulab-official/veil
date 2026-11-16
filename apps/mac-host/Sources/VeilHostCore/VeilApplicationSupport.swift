import Foundation

/// Root of Veil's per-user state (profiles, diagnostics, launch intents, QEMU records).
///
/// Every default store resolves through here so that a test process can never write into
/// the real `~/Library/Application Support/Veil`. A stray boot report or restore intent
/// written by a test used to make a first-run Mac claim Windows was installed and running.
public enum VeilApplicationSupport {
    public static let directoryEnvironmentKey = "VEIL_APPLICATION_SUPPORT_DIRECTORY"

    public static var directory: URL {
        resolvedDirectory
    }

    private static let resolvedDirectory: URL = resolve(
        environment: ProcessInfo.processInfo.environment,
        isTestProcess: isRunningUnderTests
    )

    static func resolve(environment: [String: String], isTestProcess: Bool) -> URL {
        if let override = environment[directoryEnvironmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        if isTestProcess {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("VeilTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
                .appendingPathComponent("Veil", isDirectory: true)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return base.appendingPathComponent("Veil", isDirectory: true)
    }

    static var isRunningUnderTests: Bool {
        let processName = ProcessInfo.processInfo.processName
        if processName == "xctest" || processName == "swiftpm-testing-helper" {
            return true
        }

        if Bundle.main.bundlePath.hasSuffix(".xctest") {
            return true
        }

        return Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }
}
