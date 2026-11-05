import Foundation
import Testing

@testable import VeilHostCore

private final class TransferRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    var count: Int {
        lock.withLock { urls.count }
    }

    var sources: [URL] {
        lock.withLock { urls }
    }

    func record(_ url: URL) {
        lock.withLock { urls.append(url) }
    }
}

@Suite("VirtIO driver media")
struct VirtioWinDriverMediaTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Hashes by content so a test can stand in for the real ISO with a few bytes.
    private static let fakeHasher: @Sendable (URL) throws -> String = { url in
        let text = try String(contentsOf: url, encoding: .utf8)
        return text == "good" ? VirtioWinDriverMedia.sha256 : String(repeating: "0", count: 64)
    }

    @Test("pins one Fedora release over HTTPS")
    func pinsFedoraRelease() {
        #expect(VirtioWinDriverMedia.downloadURL.absoluteString.hasPrefix("https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-\(VirtioWinDriverMedia.version)-"))
        #expect(VirtioWinDriverMedia.fileName == "virtio-win-\(VirtioWinDriverMedia.version).iso")
        #expect(VirtioWinDriverMedia.sha256.count == 64)
        #expect(VirtioWinDriverMedia.sha256 == VirtioWinDriverMedia.sha256.lowercased())
    }

    @Test("downloads only from HTTPS fedorapeople.org virtio-win paths")
    func downloadURLPolicy() {
        #expect(VirtioWinDriverMedia.allowsDownload(from: VirtioWinDriverMedia.downloadURL))
        #expect(!VirtioWinDriverMedia.allowsDownload(from: URL(string: "http://fedorapeople.org/groups/virt/virtio-win/virtio-win.iso")))
        #expect(!VirtioWinDriverMedia.allowsDownload(from: URL(string: "https://fedorapeople.org.example.com/groups/virt/virtio-win/virtio-win.iso")))
        #expect(!VirtioWinDriverMedia.allowsDownload(from: URL(string: "https://fedorapeople.org/~someone/virtio-win.iso")))
        #expect(!VirtioWinDriverMedia.allowsDownload(from: nil))
    }

    @Test("hashes a file with SHA-256")
    func hashesFile() throws {
        let file = try temporaryDirectory().appendingPathComponent("abc")
        try Data("abc".utf8).write(to: file)

        #expect(try VirtioWinDriverMedia.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("a verified download lands under its pinned name and is reused")
    func downloadsOnceAndReuses() async throws {
        let directory = try temporaryDirectory()
        let recorder = TransferRecorder()
        let provider = VirtioWinDriverMediaProvider(
            directory: { directory },
            transfer: { source, destination in
                recorder.record(source)
                try Data("good".utf8).write(to: destination)
            },
            hasher: Self.fakeHasher
        )

        await provider.prefetch()
        async let first = provider.ensureMedia()
        async let second = provider.ensureMedia()
        let urls = try await [first, second]

        #expect(urls.allSatisfy { $0 == directory.appendingPathComponent(VirtioWinDriverMedia.fileName) })
        #expect(recorder.sources == [VirtioWinDriverMedia.downloadURL])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(VirtioWinDriverMedia.fileName).download").path))

        // A new process finds the verified file and does not download it again.
        let restarted = VirtioWinDriverMediaProvider(
            directory: { directory },
            transfer: { source, _ in recorder.record(source) },
            hasher: Self.fakeHasher
        )
        _ = try await restarted.ensureMedia()
        #expect(recorder.count == 1)
    }

    @Test("cached media is offered only when already on disk and matching the pin, without downloading")
    func cachedMediaNeverDownloads() async throws {
        let directory = try temporaryDirectory()
        let recorder = TransferRecorder()
        let provider = VirtioWinDriverMediaProvider(
            directory: { directory },
            transfer: { source, _ in recorder.record(source) },
            hasher: Self.fakeHasher
        )

        #expect(await provider.cachedMedia() == nil)

        let destination = directory.appendingPathComponent(VirtioWinDriverMedia.fileName)
        try Data("tampered".utf8).write(to: destination)
        #expect(await provider.cachedMedia() == nil)

        try Data("good".utf8).write(to: destination)
        #expect(await provider.cachedMedia() == destination)
        #expect(recorder.count == 0)
    }

    @Test("a download that misses the pinned SHA-256 is removed and can be retried")
    func rejectsMismatchedDownload() async throws {
        let directory = try temporaryDirectory()
        let recorder = TransferRecorder()
        let provider = VirtioWinDriverMediaProvider(
            directory: { directory },
            transfer: { source, destination in
                recorder.record(source)
                try Data((recorder.count == 1 ? "tampered" : "good").utf8).write(to: destination)
            },
            hasher: Self.fakeHasher
        )

        await #expect(throws: VirtioWinDriverMediaError.self) {
            try await provider.ensureMedia()
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) == [])

        let url = try await provider.ensureMedia()
        #expect(url.lastPathComponent == VirtioWinDriverMedia.fileName)
        #expect(recorder.count == 2)
    }

    @Test("a stale file that no longer matches the pin is downloaded again")
    func replacesStaleFile() async throws {
        let directory = try temporaryDirectory()
        try Data("stale".utf8).write(to: directory.appendingPathComponent(VirtioWinDriverMedia.fileName))
        let recorder = TransferRecorder()
        let provider = VirtioWinDriverMediaProvider(
            directory: { directory },
            transfer: { source, destination in
                recorder.record(source)
                try Data("good".utf8).write(to: destination)
            },
            hasher: Self.fakeHasher
        )

        let url = try await provider.ensureMedia()

        #expect(try String(contentsOf: url, encoding: .utf8) == "good")
        #expect(recorder.count == 1)
    }

    @Test("the answer file installs NetKVM from the virtio-win volume in the specialize pass")
    func answerFileInstallsNetKVM() throws {
        let answerFile = LocalVMRuntimeService.automaticInstallAnswerFile(accountName: "Jamie")
        let specialize = try #require(answerFile.range(of: "<settings pass=\"specialize\">"))
        let oobe = try #require(answerFile.range(of: "<settings pass=\"oobeSystem\">"))
        let command = LocalVMRuntimeService.virtioDriverInstallCommand
        let commandRange = try #require(answerFile.range(of: "<Path>\(LocalVMRuntimeService.xmlEscaped(command))</Path>"))

        #expect(commandRange.lowerBound > specialize.upperBound)
        #expect(commandRange.upperBound < oobe.lowerBound)
        #expect(answerFile.contains("<Order>2</Order>\n          <Path>powershell -NoProfile"))
        #expect(command.count <= LocalVMRuntimeService.runSynchronousPathMaximumLength)
        #expect(command.contains("$_.VolumeLabel -like 'virtio-win*'"))
        #expect(command.contains("pnputil /add-driver ($d.Name+'NetKVM\\w11\\ARM64\\*.inf') /install"))
        #expect(command.hasSuffix("exit 0\""))
        // The output redirection is escaped in the XML and reaches Windows Setup as `*>>`.
        #expect(answerFile.contains("/install *&gt;&gt;$env:windir"))
    }
}
