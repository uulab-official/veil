import Foundation

public protocol AutomaticInstallMediaBuilding: Sendable {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws
}

public struct HdiutilAutomaticInstallMediaBuilder: AutomaticInstallMediaBuilding {
    private let processRunner: @Sendable (String, [String]) throws -> Int32

    public init(
        processRunner: @escaping @Sendable (String, [String]) throws -> Int32 = Self.runProcess
    ) {
        self.processRunner = processRunner
    }

    public func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: answerFileURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("Autounattend.xml is missing.")
        }

        let agentBundleURL = answerFileURL.deletingLastPathComponent()
            .appendingPathComponent("Veil Guest Agent", isDirectory: true)
        if Self.mediaIsCurrent(
            mediaURL: mediaURL,
            answerFileURL: answerFileURL,
            agentBundleURL: agentBundleURL
        ) {
            return
        }

        let buildID = UUID().uuidString
        let stagingDirectory = mediaURL.deletingLastPathComponent()
            .appendingPathComponent(".veil-auto-install-media-\(buildID)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        try fileManager.copyItem(
            at: answerFileURL,
            to: stagingDirectory.appendingPathComponent("Autounattend.xml")
        )
        if fileManager.fileExists(atPath: agentBundleURL.path) {
            try fileManager.copyItem(
                at: agentBundleURL,
                to: stagingDirectory.appendingPathComponent("Veil Guest Agent", isDirectory: true)
            )
        }

        let temporaryOutputURL = mediaURL.deletingLastPathComponent()
            .appendingPathComponent("\(mediaURL.deletingPathExtension().lastPathComponent)-\(buildID)")
            .appendingPathExtension("iso.tmp")
        let generatedURL = temporaryOutputURL.appendingPathExtension("iso")
        defer {
            try? fileManager.removeItem(at: temporaryOutputURL)
            try? fileManager.removeItem(at: generatedURL)
        }

        let exitCode = try processRunner(
            "/usr/bin/hdiutil",
            [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                "VEIL_AUTO",
                "-o",
                temporaryOutputURL.path,
                stagingDirectory.path
            ]
        )

        guard exitCode == 0 else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("hdiutil exited with code \(exitCode).")
        }

        if fileManager.fileExists(atPath: generatedURL.path) {
            try? fileManager.removeItem(at: mediaURL)
            try fileManager.moveItem(at: generatedURL, to: mediaURL)
        } else if fileManager.fileExists(atPath: temporaryOutputURL.path) {
            try? fileManager.removeItem(at: mediaURL)
            try fileManager.moveItem(at: temporaryOutputURL, to: mediaURL)
        } else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("hdiutil did not produce an ISO image.")
        }
    }

    private static func mediaIsCurrent(mediaURL: URL, answerFileURL: URL, agentBundleURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: mediaURL.path),
              let mediaDate = try? fileManager.attributesOfItem(atPath: mediaURL.path)[.modificationDate] as? Date,
              let answerDate = try? fileManager.attributesOfItem(atPath: answerFileURL.path)[.modificationDate] as? Date else {
            return false
        }

        let payloadDate = max(answerDate, latestModificationDate(in: agentBundleURL) ?? answerDate)
        return mediaDate >= payloadDate
    }

    private static func latestModificationDate(in url: URL) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        var latest = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            ?? Date.distantPast
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return latest
        }

        for case let fileURL as URL in enumerator {
            guard let modificationDate = try? fileURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else {
                continue
            }
            latest = max(latest, modificationDate)
        }
        return latest
    }

    public static func runProcess(executablePath: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
