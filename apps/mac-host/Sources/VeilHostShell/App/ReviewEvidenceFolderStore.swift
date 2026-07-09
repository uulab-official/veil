import Foundation
import VeilHostCore

struct ReviewEvidenceFolder {
    var directory: URL
    var readme: URL
    var manifest: URL
    var appCheckProof: URL
}

struct ReviewEvidenceFile: Codable, Equatable {
    var slotId: String
    var title: String
    var expectedFileName: String
    var path: String
    var expectedSurface: String
}

struct ReviewEvidenceAppCheckProofFile: Codable, Equatable {
    var expectedFileName: String
    var path: String
    var command: String
    var requiredKind: String
    var requiredStatus: String
}

struct ReviewEvidenceCaptureStep: Codable, Equatable {
    var order: Int
    var slotId: String
    var title: String
    var expectedFileName: String
    var instruction: String
    var captureCommand: String
    var supportingCommand: String?
}

struct ReviewEvidenceManifest: Codable, Equatable {
    var kind: String = "windowsAppRuntimeReviewEvidenceManifest"
    var generatedAt: Date
    var evidenceDirectory: String
    var manifestPath: String
    var readmePath: String
    var requiredScreenshotCount: Int
    var minimumScreenshotWidth: Int
    var minimumScreenshotHeight: Int
    var screenshotFiles: [ReviewEvidenceFile]
    var appCheckProofFile: ReviewEvidenceAppCheckProofFile
    var captureSteps: [ReviewEvidenceCaptureStep]
    var reviewCommand: String
    var verifyCommand: String
    var openEvidenceDirectoryCommand: String
    var nextActions: [String]
}

private struct ReviewEvidenceSlot {
    var id: String
    var title: String
    var expectedSurface: String
    var instruction: String
    var supportingCommand: String?
}

enum ReviewEvidenceFolderStore {
    static let minimumScreenshotWidth = 640
    static let minimumScreenshotHeight = 360

    private static let slots = [
        ReviewEvidenceSlot(
            id: "preBootLauncher",
            title: "Pre-Boot Launcher",
            expectedSurface: "One Veil launcher window with setup or start action visible.",
            instruction: "Capture the one-screen Veil launcher before opening the selected Windows app.",
            supportingCommand: "veil-vmctl app-runtime-status --json"
        ),
        ReviewEvidenceSlot(
            id: "firstAppLaunch",
            title: "First App Launch",
            expectedSurface: "A selected Windows app is opening, queued, or ready with one concrete next action.",
            instruction: "Start or queue the selected Windows app and capture the first visible launch state.",
            supportingCommand: "veil-vmctl app-runtime-action --json --action fulfill-pending"
        ),
        ReviewEvidenceSlot(
            id: "appWindowOnly",
            title: "App Window Only",
            expectedSurface: "The mirrored Windows app window is visible while the launcher is hidden unless recovery is needed.",
            instruction: "Capture the mirrored Windows app window after the launcher is hidden.",
            supportingCommand: "veil-vmctl app-window-proof --json --app-id winapp_notepad"
        ),
        ReviewEvidenceSlot(
            id: "menuRestore",
            title: "Menu Restore",
            expectedSurface: "Menu or Dock controls can bring forward, restore, reconnect, or close Windows app windows.",
            instruction: "Open the menu or Dock control and capture restore, reconnect, bring-forward, or close actions.",
            supportingCommand: "veil-vmctl app-runtime-action --json --action bring-forward"
        ),
        ReviewEvidenceSlot(
            id: "closeQuiet",
            title: "Close And Quiet",
            expectedSurface: "After the final Windows app window closes, the launcher returns or quiet Windows action is available.",
            instruction: "Close the final Windows app window and capture the returned launcher or quiet-Windows control.",
            supportingCommand: "veil-vmctl app-runtime-action --json --action reconnect-restore"
        )
    ]

    static var screenshotFileNames: [String] {
        slots.map { expectedFileName(slotId: $0.id) }
    }

    static let appCheckProofFileName = "mvp-proof.json"

    static func defaultDirectory(now: Date = Date()) -> URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("Review Evidence", isDirectory: true)
            .appendingPathComponent(folderName(for: now), isDirectory: true)
    }

    static func prepare(directory: URL? = nil, now: Date = Date()) throws -> ReviewEvidenceFolder {
        let targetDirectory = directory ?? defaultDirectory(now: now)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let manifestURL = targetDirectory.appendingPathComponent("review-manifest.json")
        let readmeURL = targetDirectory.appendingPathComponent("README.md")
        let manifest = manifest(
            directory: targetDirectory,
            manifestURL: manifestURL,
            readmeURL: readmeURL,
            generatedAt: now
        )
        let manifestData = try JSONEncoder.veilDiagnostics.encode(manifest)
        try manifestData.write(to: manifestURL, options: [.atomic])
        try readmeText(manifest: manifest).write(to: readmeURL, atomically: true, encoding: .utf8)
        return ReviewEvidenceFolder(
            directory: targetDirectory,
            readme: readmeURL,
            manifest: manifestURL,
            appCheckProof: targetDirectory.appendingPathComponent(appCheckProofFileName)
        )
    }

    static func manifest(
        directory: URL,
        manifestURL: URL,
        readmeURL: URL,
        generatedAt: Date
    ) -> ReviewEvidenceManifest {
        let evidencePath = directory.path
        let reviewCommand = reviewCommand(evidenceDirectory: evidencePath)
        let verifyCommand = verifyCommand(evidenceDirectory: evidencePath)
        let openEvidenceDirectoryCommand = openCommand(evidenceDirectory: evidencePath)
        let appCheckProofFile = appCheckProofFile(evidenceDirectory: evidencePath)
        let screenshotFiles = slots.map { slot in
            let fileName = expectedFileName(slotId: slot.id)
            return ReviewEvidenceFile(
                slotId: slot.id,
                title: slot.title,
                expectedFileName: fileName,
                path: directory.appendingPathComponent(fileName).path,
                expectedSurface: slot.expectedSurface
            )
        }
        let captureSteps = zip(slots.indices, slots).map { index, slot in
            let fileName = expectedFileName(slotId: slot.id)
            return ReviewEvidenceCaptureStep(
                order: index + 1,
                slotId: slot.id,
                title: slot.title,
                expectedFileName: fileName,
                instruction: slot.instruction,
                captureCommand: captureCommand(path: directory.appendingPathComponent(fileName).path),
                supportingCommand: supportingCommand(
                    slot: slot,
                    appCheckProofFile: appCheckProofFile
                )
            )
        }

        return ReviewEvidenceManifest(
            generatedAt: generatedAt,
            evidenceDirectory: evidencePath,
            manifestPath: manifestURL.path,
            readmePath: readmeURL.path,
            requiredScreenshotCount: slots.count,
            minimumScreenshotWidth: minimumScreenshotWidth,
            minimumScreenshotHeight: minimumScreenshotHeight,
            screenshotFiles: screenshotFiles,
            appCheckProofFile: appCheckProofFile,
            captureSteps: captureSteps,
            reviewCommand: reviewCommand,
            verifyCommand: verifyCommand,
            openEvidenceDirectoryCommand: openEvidenceDirectoryCommand,
            nextActions: [
                "Open the evidence folder with `\(openEvidenceDirectoryCommand)`.",
                "Capture the five required screenshots into the evidence directory as valid PNG files of at least 640 x 360.",
                "Run the saved app check proof command from `review-manifest.json` and keep `\(appCheckProofFile.expectedFileName)` in the evidence directory.",
                "Run `\(reviewCommand)` and confirm Screenshots is 5/5 attached.",
                "Run `\(verifyCommand)` before sharing evidence."
            ]
        )
    }

    static func readmeText(manifest: ReviewEvidenceManifest) -> String {
        let captureSteps = manifest.captureSteps
            .map { step in
                var lines = [
                    "\(step.order). \(step.title) -> `\(step.expectedFileName)`",
                    "   \(step.instruction)",
                    "   Capture: `\(step.captureCommand)`"
                ]
                if let supportingCommand = step.supportingCommand {
                    lines.append("   Command: `\(supportingCommand)`")
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n")
        let fileList = manifest.screenshotFiles
            .map { "- `\($0.expectedFileName)`: \($0.expectedSurface)" }
            .joined(separator: "\n")
        let expectedFiles = [
            fileList,
            "- `\(manifest.appCheckProofFile.expectedFileName)`: proved Windows app launch, frame, input, and clipboard JSON evidence"
        ].joined(separator: "\n")

        return """
        # Veil Windows App Review Evidence

        This folder stores one live Windows App Runtime review pass.

        Manifest:
        - `review-manifest.json`

        Checklist:
        - Open this folder with `\(manifest.openEvidenceDirectoryCommand)`.
        - Capture every PNG listed below into this folder as a valid PNG of at least \(manifest.minimumScreenshotWidth) x \(manifest.minimumScreenshotHeight).
        - Run `\(manifest.appCheckProofFile.command)` and keep `\(manifest.appCheckProofFile.expectedFileName)` in this folder.
        - Run `\(manifest.reviewCommand)`.
        - Confirm the review card reports `Screenshots: \(manifest.requiredScreenshotCount)/\(manifest.requiredScreenshotCount) attached`.
        - Run `\(manifest.verifyCommand)` before sharing evidence.
        - Keep `review-manifest.json`, `\(manifest.appCheckProofFile.expectedFileName)`, and the screenshots when sharing review evidence.

        Capture steps:
        \(captureSteps)

        Expected files:
        \(expectedFiles)

        Veil does not store Windows images, product keys, or disk contents in this folder.
        """
    }

    static func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    private static func expectedFileName(slotId: String) -> String {
        "\(slotId).png"
    }

    private static func captureCommand(path: String) -> String {
        "screencapture -i \(shellQuoted(path))"
    }

    private static func appCheckProofFile(evidenceDirectory: String) -> ReviewEvidenceAppCheckProofFile {
        let path = URL(fileURLWithPath: evidenceDirectory)
            .appendingPathComponent(appCheckProofFileName)
            .standardizedFileURL
            .path

        return ReviewEvidenceAppCheckProofFile(
            expectedFileName: appCheckProofFileName,
            path: path,
            command: "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved --output \(shellQuoted(path))",
            requiredKind: "windowsMVPProof",
            requiredStatus: "proved"
        )
    }

    private static func supportingCommand(
        slot: ReviewEvidenceSlot,
        appCheckProofFile: ReviewEvidenceAppCheckProofFile
    ) -> String? {
        if slot.id == "appWindowOnly" {
            return appCheckProofFile.command
        }

        return slot.supportingCommand
    }

    private static func reviewCommand(evidenceDirectory: String) -> String {
        "veil-vmctl app-runtime-review --evidence-dir \(shellQuoted(evidenceDirectory))"
    }

    private static func verifyCommand(evidenceDirectory: String) -> String {
        "veil-vmctl app-runtime-review-verify --json --evidence-dir \(shellQuoted(evidenceDirectory))"
    }

    private static func openCommand(evidenceDirectory: String) -> String {
        "open \(shellQuoted(evidenceDirectory))"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
