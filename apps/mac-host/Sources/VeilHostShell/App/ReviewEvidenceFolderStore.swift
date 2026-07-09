import Foundation
import VeilHostCore

struct ReviewEvidenceFolder {
    var directory: URL
    var readme: URL
}

enum ReviewEvidenceFolderStore {
    static let screenshotFileNames = [
        "preBootLauncher.png",
        "firstAppLaunch.png",
        "appWindowOnly.png",
        "menuRestore.png",
        "closeQuiet.png"
    ]

    static func defaultDirectory(now: Date = Date()) -> URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("Review Evidence", isDirectory: true)
            .appendingPathComponent(folderName(for: now), isDirectory: true)
    }

    static func prepare(directory: URL = defaultDirectory()) throws -> ReviewEvidenceFolder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let readmeURL = directory.appendingPathComponent("README.md")
        try readmeText(directory: directory).write(to: readmeURL, atomically: true, encoding: .utf8)
        return ReviewEvidenceFolder(directory: directory, readme: readmeURL)
    }

    static func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    static func readmeText(directory: URL) -> String {
        let evidencePath = directory.path
        let fileList = screenshotFileNames
            .map { "- `\($0)`" }
            .joined(separator: "\n")

        return """
        # Veil Review Evidence

        Capture the current Windows app flow into this folder.

        Required screenshots:
        \(fileList)

        Next steps:
        - Save each screenshot as a PNG in this folder.
        - Run `veil-vmctl app-runtime-review --evidence-dir '\(evidencePath)'`.
        - Run `veil-vmctl app-runtime-review-verify --json --evidence-dir '\(evidencePath)'`.
        - Share this folder only after verification says the evidence is ready.

        Veil does not store Windows images, product keys, or disk contents in this folder.
        """
    }
}
