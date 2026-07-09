import Foundation
import Testing
@testable import VeilHostShell

struct ReviewEvidenceFolderStoreTests {
    @Test("prepares a review evidence folder with guide and fixed screenshot names")
    func preparesReviewEvidenceFolder() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        let folder = try ReviewEvidenceFolderStore.prepare(directory: baseDirectory)
        let readme = try String(contentsOf: folder.readme, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: folder.directory.path))
        #expect(FileManager.default.fileExists(atPath: folder.readme.path))
        #expect(folder.directory == baseDirectory)
        #expect(readme.contains("Veil Review Evidence"))
        #expect(readme.contains("app-runtime-review --evidence-dir"))
        #expect(readme.contains("app-runtime-review-verify --json --evidence-dir"))

        for fileName in ReviewEvidenceFolderStore.screenshotFileNames {
            #expect(readme.contains(fileName))
        }

        #expect(readme.contains("does not store Windows images, product keys, or disk contents"))
    }

    @Test("uses a stable UTC folder name for review evidence passes")
    func stableReviewEvidenceFolderName() {
        let date = Date(timeIntervalSince1970: 1_725_894_245)

        #expect(ReviewEvidenceFolderStore.folderName(for: date) == "2024-09-09-150405")
    }
}
