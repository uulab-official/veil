import Darwin
import Foundation
import Testing
@testable import VeilHostCore

@Suite("Clipboard files from Windows")
struct ClipboardGuestFilesTests {
    private static let batch = "Veil Clipboard from Windows\\20261111-050102-4D5E6F"

    private func message(_ paths: [String], origin: String = "guest", shareName: String = "VeilShared") -> ClipboardFilesSet {
        ClipboardFilesSet(requestId: "evt_clipboard_12", origin: origin, sequence: 12, shareName: shareName, relativePaths: paths)
    }

    private func fixture() throws -> ClipboardFilesSet {
        let url = try #require(Bundle.module.url(forResource: "clipboard.files.set.guest", withExtension: "json"))
        return try JSONDecoder.veilProtocol.decode(ClipboardFilesSet.self, from: Data(contentsOf: url))
    }

    @Test("accepts the guest fixture and keeps its names")
    func acceptsFixture() throws {
        let plan = try ClipboardGuestFiles.plan(fixture())

        #expect(plan.fileNames == ["budget.xlsx"])
        #expect(plan.relativePaths == ["\(Self.batch)\\budget.xlsx"])
    }

    @Test("refuses paths outside one guest staging batch", arguments: [
        "Veil Clipboard\\20261111-050102-4D5E6F\\a.txt",
        "Veil Clipboard from Windows\\a.txt",
        "Veil Clipboard from Windows\\..\\a.txt",
        "Veil Clipboard from Windows\\20261111-050102-4d5e6f\\a.txt",
        "\(batch)\\sub\\a.txt",
        "\(batch)\\..",
        "\(batch)\\a.txt:stream",
        "\(batch)\\",
        "C:\\Users\\me\\a.txt",
        "\(batch)/../../a.txt",
    ])
    func refusesEscapingPaths(path: String) {
        #expect(throws: (any Error).self) {
            try ClipboardGuestFiles.plan(message([path]))
        }
    }

    @Test("refuses host origin, another share, two batches, duplicates, and too many files")
    func refusesShape() {
        #expect(throws: (any Error).self) { try ClipboardGuestFiles.plan(message(["\(Self.batch)\\a.txt"], origin: "host")) }
        #expect(throws: (any Error).self) { try ClipboardGuestFiles.plan(message(["\(Self.batch)\\a.txt"], shareName: "C$")) }
        #expect(throws: (any Error).self) { try ClipboardGuestFiles.plan(message([])) }
        #expect(throws: ClipboardGuestFilesRefusal.malformedPath("Veil Clipboard from Windows\\20261111-050103-4D5E6F\\b.txt")) {
            try ClipboardGuestFiles.plan(message([
                "\(Self.batch)\\a.txt",
                "Veil Clipboard from Windows\\20261111-050103-4D5E6F\\b.txt",
            ]))
        }
        #expect(throws: ClipboardGuestFilesRefusal.duplicateName("A.TXT")) {
            try ClipboardGuestFiles.plan(message(["\(Self.batch)\\a.txt", "\(Self.batch)\\A.TXT"]))
        }
        let many = (0...ClipboardGuestFiles.maximumFileCount).map { "\(Self.batch)\\f\($0).txt" }
        #expect(throws: ClipboardGuestFilesRefusal.tooManyFiles(count: many.count)) {
            try ClipboardGuestFiles.plan(message(many))
        }
    }

    @Test("applies the Mac name rules")
    func macNames() {
        #expect(ClipboardGuestFiles.macFileName(forGuestName: "report.pdf") == "report.pdf")
        #expect(ClipboardGuestFiles.macFileName(forGuestName: ".zshrc") == "_zshrc")
        #expect(ClipboardGuestFiles.macFileName(forGuestName: "invoice\u{202E}fdp.app") == nil)
        #expect(ClipboardGuestFiles.macFileName(forGuestName: "a\u{2066}b.txt") == nil)
        #expect(ClipboardGuestFiles.macFileName(forGuestName: String(repeating: "가", count: 90)) == nil)
        #expect(ClipboardGuestFiles.macFileName(forGuestName: "a/b.txt") == nil)
        #expect(ClipboardGuestFiles.macFileName(forGuestName: "CON.txt") == nil)
    }

    @Test("copies into a new quarantined batch that is not executable")
    func copiesQuarantined() throws {
        let sandbox = try Sandbox()
        try sandbox.stage("budget.xlsx", contents: "numbers")
        let script = try sandbox.stage("run.command", contents: "#!/bin/sh\necho hi\n")
        chmod(script.path, 0o755)

        let plan = try ClipboardGuestFiles.plan(message(["\(Self.batch)\\budget.xlsx", "\(Self.batch)\\run.command"]))
        let copies = try ClipboardGuestFiles.copy(
            plan,
            fromShareAt: sandbox.share,
            into: sandbox.destination,
            now: Date(timeIntervalSince1970: 0),
            batchSuffix: "ABCDEF"
        )

        #expect(copies.map(\.lastPathComponent) == ["budget.xlsx", "run.command"])
        #expect(copies.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == "19700101-000000-ABCDEF" })
        #expect(try String(contentsOf: copies[0], encoding: .utf8) == "numbers")
        for copy in copies {
            #expect(getxattr(copy.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
            var status = stat()
            #expect(stat(copy.path, &status) == 0)
            #expect(status.st_mode & 0o111 == 0)
        }
    }

    @Test("refuses a link in the share instead of following it to a host file")
    func refusesLinks() throws {
        let sandbox = try Sandbox()
        let secret = sandbox.root.appending(path: "secret.txt")
        try "host secret".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: sandbox.batchDirectory.appending(path: "a.txt"), withDestinationURL: secret)
        let plan = try ClipboardGuestFiles.plan(message(["\(Self.batch)\\a.txt"]))

        #expect(throws: ClipboardGuestFilesRefusal.notARegularFile(name: "a.txt")) {
            try ClipboardGuestFiles.copy(plan, fromShareAt: sandbox.share, into: sandbox.destination)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.destination.path).isEmpty)
    }

    @Test("refuses a linked batch folder and a folder in place of a file")
    func refusesLinkedFolders() throws {
        let sandbox = try Sandbox()
        let outside = sandbox.root.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "x".write(to: outside.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let linkedBatch = "20261111-050103-4D5E6F"
        try FileManager.default.createSymbolicLink(
            at: sandbox.stagingDirectory.appending(path: linkedBatch),
            withDestinationURL: outside
        )
        try FileManager.default.createDirectory(
            at: sandbox.batchDirectory.appending(path: "folder.txt", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        #expect(throws: ClipboardGuestFilesRefusal.notARegularFile(name: "a.txt")) {
            try ClipboardGuestFiles.copy(
                ClipboardGuestFiles.plan(message(["Veil Clipboard from Windows\\\(linkedBatch)\\a.txt"])),
                fromShareAt: sandbox.share,
                into: sandbox.destination
            )
        }
        #expect(throws: ClipboardGuestFilesRefusal.notARegularFile(name: "folder.txt")) {
            try ClipboardGuestFiles.copy(
                ClipboardGuestFiles.plan(message(["\(Self.batch)\\folder.txt"])),
                fromShareAt: sandbox.share,
                into: sandbox.destination
            )
        }
    }

    @Test("removes the partial batch when a later file is missing")
    func removesPartialBatch() throws {
        let sandbox = try Sandbox()
        try sandbox.stage("a.txt", contents: "a")
        let plan = try ClipboardGuestFiles.plan(message(["\(Self.batch)\\a.txt", "\(Self.batch)\\missing.txt"]))

        #expect(throws: ClipboardGuestFilesRefusal.notARegularFile(name: "missing.txt")) {
            try ClipboardGuestFiles.copy(plan, fromShareAt: sandbox.share, into: sandbox.destination)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.destination.path).isEmpty)
    }

    @Test("keeps the three newest batches and leaves other folders alone")
    func prunes() throws {
        let sandbox = try Sandbox()
        try sandbox.stage("a.txt", contents: "a")
        try FileManager.default.createDirectory(
            at: sandbox.destination.appending(path: "My things", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let plan = try ClipboardGuestFiles.plan(message(["\(Self.batch)\\a.txt"]))
        for second in 0..<5 {
            _ = try ClipboardGuestFiles.copy(
                plan,
                fromShareAt: sandbox.share,
                into: sandbox.destination,
                now: Date(timeIntervalSince1970: TimeInterval(second)),
                batchSuffix: "000000"
            )
        }

        let remaining = try FileManager.default.contentsOfDirectory(atPath: sandbox.destination.path).sorted()
        #expect(remaining == ["19700101-000002-000000", "19700101-000003-000000", "19700101-000004-000000", "My things"])
    }

    /// A share with a staged batch, and a destination root, in a fresh temporary folder.
    private struct Sandbox {
        let root: URL
        var share: URL { root.appending(path: "share", directoryHint: .isDirectory) }
        var stagingDirectory: URL { share.appending(path: ClipboardGuestFiles.guestDirectoryName, directoryHint: .isDirectory) }
        var batchDirectory: URL { stagingDirectory.appending(path: "20261111-050102-4D5E6F", directoryHint: .isDirectory) }
        var destination: URL { root.appending(path: "Downloads/Veil Clipboard", directoryHint: .isDirectory) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "veil-guest-files-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        @discardableResult
        func stage(_ name: String, contents: String) throws -> URL {
            let url = batchDirectory.appending(path: name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }
}
