import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

struct ReviewEvidenceFolderStoreTests {
    @Test("prepares a review evidence folder with guide, manifest, and fixed screenshot names")
    func preparesReviewEvidenceFolder() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_725_894_245)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        let folder = try ReviewEvidenceFolderStore.prepare(directory: baseDirectory, now: now)
        let readme = try String(contentsOf: folder.readme, encoding: .utf8)
        let manifestData = try Data(contentsOf: folder.manifest)
        let manifest = try JSONDecoder.veilDiagnostics.decode(ReviewEvidenceManifest.self, from: manifestData)

        #expect(FileManager.default.fileExists(atPath: folder.directory.path))
        #expect(FileManager.default.fileExists(atPath: folder.readme.path))
        #expect(FileManager.default.fileExists(atPath: folder.manifest.path))
        #expect(folder.directory == baseDirectory)
        #expect(readme.contains("Veil Windows App Review Evidence"))
        #expect(readme.contains("review-manifest.json"))
        #expect(readme.contains("app-runtime-review --evidence-dir"))
        #expect(readme.contains("app-runtime-review-verify --json --evidence-dir"))

        #expect(manifest.kind == "windowsAppRuntimeReviewEvidenceManifest")
        #expect(manifest.generatedAt == now)
        #expect(manifest.evidenceDirectory == baseDirectory.path)
        #expect(manifest.manifestPath == folder.manifest.path)
        #expect(manifest.readmePath == folder.readme.path)
        #expect(manifest.requiredScreenshotCount == 5)
        #expect(manifest.minimumScreenshotWidth == 640)
        #expect(manifest.minimumScreenshotHeight == 360)
        #expect(manifest.screenshotFiles.map(\.expectedFileName) == ReviewEvidenceFolderStore.screenshotFileNames)
        #expect(manifest.captureSteps.map(\.expectedFileName) == ReviewEvidenceFolderStore.screenshotFileNames)
        #expect(manifest.captureSteps.map(\.order) == [1, 2, 3, 4, 5])
        #expect(manifest.reviewCommand.contains("app-runtime-review --evidence-dir"))
        #expect(manifest.verifyCommand.contains("app-runtime-review-verify --json --evidence-dir"))
        #expect(manifest.openEvidenceDirectoryCommand.contains("open "))
        #expect(manifest.nextActions.contains { $0.contains("5/5 attached") })
        #expect(manifest.nextActions.contains { $0.contains("640 x 360") })

        for fileName in ReviewEvidenceFolderStore.screenshotFileNames {
            #expect(readme.contains(fileName))
            #expect(manifest.screenshotFiles.contains { file in
                file.expectedFileName == fileName
                    && file.path == baseDirectory.appendingPathComponent(fileName).path
                    && file.expectedSurface.isEmpty == false
            })
            #expect(manifest.captureSteps.contains { step in
                step.expectedFileName == fileName
                    && step.captureCommand.contains("screencapture -i")
                    && step.captureCommand.contains(baseDirectory.appendingPathComponent(fileName).path)
                    && step.instruction.isEmpty == false
            })
        }

        #expect(readme.contains("does not store Windows images, product keys, or disk contents"))
    }

    @Test("quotes paths with apostrophes in review evidence commands")
    func quotesReviewEvidencePaths() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Veil User's Review", isDirectory: true)
        let manifest = ReviewEvidenceFolderStore.manifest(
            directory: directory,
            manifestURL: directory.appendingPathComponent("review-manifest.json"),
            readmeURL: directory.appendingPathComponent("README.md"),
            generatedAt: Date(timeIntervalSince1970: 1_725_894_245)
        )

        #expect(manifest.reviewCommand.contains("'\\''"))
        #expect(manifest.verifyCommand.contains("'\\''"))
        #expect(manifest.openEvidenceDirectoryCommand.contains("'\\''"))
        #expect(manifest.captureSteps.allSatisfy { $0.captureCommand.contains("'\\''") })
    }

    @Test("uses a stable UTC folder name for review evidence passes")
    func stableReviewEvidenceFolderName() {
        let date = Date(timeIntervalSince1970: 1_725_894_245)

        #expect(ReviewEvidenceFolderStore.folderName(for: date) == "2024-09-09-150405")
    }
}
