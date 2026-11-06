import Foundation

/// The Windows guest tools (the Veil agent bundle) that Veil installs into Windows.
public enum GuestToolsBundle {
    public static let resourceDirectoryName = "WindowsAgent"
    public static let versionFileName = "veil-agent-version.txt"

    /// The tools inside the app when it was built with them; otherwise this repository's
    /// `apps/windows-agent`, which only exists on a development Mac.
    public static func sourceURL(resourceURL: URL? = Bundle.main.resourceURL) -> URL {
        if let bundledURL = resourceURL?.appendingPathComponent(resourceDirectoryName, isDirectory: true),
           FileManager.default.fileExists(atPath: bundledURL.appendingPathComponent("scripts").path) {
            return bundledURL
        }
        return repositoryURL
    }

    /// The stamped `agentVersion` of the agent in a tools folder, such as `0.1.0+3f9c2a1b7d04`.
    public static func version(at sourceURL: URL) -> String? {
        let versionURL = sourceURL
            .appendingPathComponent("app", isDirectory: true)
            .appendingPathComponent(versionFileName)
        guard let text = try? String(contentsOf: versionURL, encoding: .utf8) else {
            return nil
        }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    public static var bundledVersion: String? {
        version(at: sourceURL())
    }

    static var repositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("windows-agent", isDirectory: true)
    }
}

public enum GuestToolsUpdatePolicy {
    /// Tools are outdated when Veil ships a stamped build and the connected agent reports any other
    /// version, including an unstamped one from before build ids. Without a stamped bundle (a
    /// development build made without the .NET SDK) nothing is called outdated.
    public static func isOutdated(installedVersion: String?, bundledVersion: String?) -> Bool {
        guard let installedVersion, let bundledVersion, bundledVersion.contains("+") else {
            return false
        }
        return installedVersion != bundledVersion
    }
}

/// A disc that carries the current tools to a Windows that is already running. VEIL_AUTO stays
/// attached for the whole session, so the update goes into the removable CD drive instead, with its
/// own `U.cmd` entry point that an older VEIL_AUTO does not have.
public enum GuestToolsUpdateMedia {
    public static let fileName = "VeilToolsUpdate.iso"
    public static let volumeName = "VEIL_TOOLS"
    public static let entryPointName = "U.cmd"

    public static func build(
        agentBundleURL: URL,
        mediaURL: URL,
        processRunner: (String, [String]) throws -> Int32 = HdiutilAutomaticInstallMediaBuilder.runProcess
    ) throws {
        let fileManager = FileManager.default
        let buildID = UUID().uuidString
        let parentURL = mediaURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(".veil-tools-update-\(buildID)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        let stagedBundleURL = stagingURL.appendingPathComponent("Veil Guest Agent", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: agentBundleURL, to: stagedBundleURL)
        let repairEntryPoint = stagedBundleURL.appendingPathComponent("V.cmd")
        guard fileManager.fileExists(atPath: repairEntryPoint.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("The Veil tools bundle has no V.cmd.")
        }
        try fileManager.copyItem(at: repairEntryPoint, to: stagedBundleURL.appendingPathComponent(entryPointName))

        let outputURL = parentURL.appendingPathComponent(".veil-tools-update-\(buildID).iso")
        defer {
            try? fileManager.removeItem(at: outputURL)
        }
        let exitCode = try processRunner(
            "/usr/bin/hdiutil",
            ["makehybrid", "-iso", "-joliet", "-default-volume-name", volumeName, "-o", outputURL.path, stagingURL.path]
        )
        guard exitCode == 0, fileManager.fileExists(atPath: outputURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("hdiutil could not build the tools update disc (exit \(exitCode)).")
        }
        // A running QEMU keeps its open copy, so replacing the file never changes a disc in use.
        try? fileManager.removeItem(at: mediaURL)
        try fileManager.moveItem(at: outputURL, to: mediaURL)
    }
}
