import Foundation
import Testing
@testable import VeilHostCore

@Suite("Clipboard image payload")
struct ClipboardImagePayloadTests {
    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder.veilProtocol.decode(T.self, from: Data(contentsOf: url))
    }

    @Test("verifies the host and guest image fixtures")
    func verifiesFixtures() throws {
        for name in ["clipboard.image.set.host", "clipboard.image.set.guest"] {
            let message: ClipboardImageSet = try fixture(name)
            let payload = try ClipboardImagePayload(message: message)

            #expect(message.type == .clipboardImageSet)
            #expect(payload.width == 2 && payload.height == 2)
            #expect(payload.png.count == message.byteLength)
            #expect(payload.sha256 == message.sha256)
        }
    }

    @Test("round-trips through the wire message")
    func roundTrips() throws {
        let message: ClipboardImageSet = try fixture("clipboard.image.set.host")
        let payload = try ClipboardImagePayload(message: message)
        let encoded = try JSONEncoder.veilProtocol.encode(
            payload.message(requestId: "req_clipboard_7", origin: "host", sequence: 7)
        )

        #expect(try JSONDecoder.veilProtocol.decode(ClipboardImageSet.self, from: encoded) == message)
    }

    @Test("rejects declarations that disagree with the bytes")
    func rejectsMismatches() throws {
        let message: ClipboardImageSet = try fixture("clipboard.image.set.host")

        var wrongHash = message
        wrongHash.sha256 = String(repeating: "a", count: 64)
        #expect(throws: ClipboardImagePayloadError.hashMismatch) { try ClipboardImagePayload(message: wrongHash) }

        var wrongLength = message
        wrongLength.byteLength = 75
        #expect(throws: ClipboardImagePayloadError.byteLengthMismatch(declared: 75, actual: 74)) {
            try ClipboardImagePayload(message: wrongLength)
        }

        var wrongSize = message
        wrongSize.width = 3
        #expect(throws: ClipboardImagePayloadError.dimensionsMismatch) { try ClipboardImagePayload(message: wrongSize) }

        var jpeg = message
        jpeg.format = "jpeg"
        #expect(throws: ClipboardImagePayloadError.unsupportedFormat("jpeg")) { try ClipboardImagePayload(message: jpeg) }
    }

    @Test("rejects oversized declarations before decoding them")
    func rejectsOversizedDeclarations() throws {
        let message: ClipboardImageSet = try fixture("clipboard.image.set.host")

        var tooLarge = message
        tooLarge.byteLength = ClipboardImagePayload.maximumByteCount + 1
        #expect(throws: ClipboardImagePayloadError.tooLarge(byteCount: ClipboardImagePayload.maximumByteCount + 1)) {
            try ClipboardImagePayload(message: tooLarge)
        }

        var tooManyPixels = message
        tooManyPixels.width = 16_384
        tooManyPixels.height = 16_384
        #expect(throws: ClipboardImagePayloadError.dimensionsOutOfBounds(width: 16_384, height: 16_384)) {
            try ClipboardImagePayload(message: tooManyPixels)
        }
    }

    @Test("rejects bytes that are not a PNG")
    func rejectsNonPNG() {
        #expect(throws: ClipboardImagePayloadError.notPNG) {
            try ClipboardImagePayload(png: Data("GIF89a not a png at all".utf8))
        }
    }

    @Test("rejects a PNG header that claims more pixels than allowed")
    func rejectsDecompressionBomb() {
        var header = Data(ClipboardImagePayload.signature)
        header.append(contentsOf: [0, 0, 0, 13] + Array("IHDR".utf8))
        header.append(contentsOf: [0, 0, 0x40, 0, 0, 0, 0x40, 0])  // 16384 × 16384
        #expect(throws: ClipboardImagePayloadError.dimensionsOutOfBounds(width: 16_384, height: 16_384)) {
            try ClipboardImagePayload(png: header)
        }
    }
}

@Suite("Clipboard file paste plan")
struct ClipboardFilePastePlanTests {
    private let now = Date(timeIntervalSince1970: 1_793_887_262)  // 2026-11-05 14:01:02 UTC

    private func regular(_ bytes: Int64 = 10) -> (URL) throws -> ClipboardFilePasteEntry {
        { _ in ClipboardFilePasteEntry(isRegularFile: true, byteCount: bytes) }
    }

    @Test("names each file inside one batch folder of the shared folder")
    func plansBatch() throws {
        let plan = try ClipboardFilePaste.plan(
            fileURLs: [URL(filePath: "/Users/me/report.pdf"), URL(filePath: "/Users/me/photo.png")],
            now: now,
            batchSuffix: "1A2B3C",
            entry: regular()
        )

        #expect(plan.batchName == "20261105-140102-1A2B3C")
        #expect(plan.relativePaths == [
            #"Veil Clipboard\20261105-140102-1A2B3C\report.pdf"#,
            #"Veil Clipboard\20261105-140102-1A2B3C\photo.png"#
        ])
    }

    @Test("refuses folders and links instead of copying what they reach")
    func refusesNonRegularFiles() {
        #expect(throws: ClipboardFilePasteRefusal.notARegularFile(name: "Projects")) {
            try ClipboardFilePaste.plan(
                fileURLs: [URL(filePath: "/Users/me/Projects")],
                entry: { _ in ClipboardFilePasteEntry(isRegularFile: false, byteCount: 0) }
            )
        }
    }

    @Test("refuses selections above the count and size bounds")
    func refusesLargeSelections() {
        let many = (0...ClipboardFilePaste.maximumFileCount).map { URL(filePath: "/tmp/file\($0).txt") }
        #expect(throws: ClipboardFilePasteRefusal.tooManyFiles(count: ClipboardFilePaste.maximumFileCount + 1)) {
            try ClipboardFilePaste.plan(fileURLs: many, entry: regular())
        }

        #expect(throws: ClipboardFilePasteRefusal.tooLarge(totalBytes: ClipboardFilePaste.maximumTotalBytes + 1)) {
            try ClipboardFilePaste.plan(
                fileURLs: [URL(filePath: "/tmp/huge.bin")],
                entry: regular(ClipboardFilePaste.maximumTotalBytes + 1)
            )
        }
    }

    @Test("refuses names Windows cannot hold and case-insensitive duplicates")
    func refusesWindowsNames() {
        for name in ["CON.txt", "report?.pdf", "trailing.", "a:b"] {
            #expect(throws: ClipboardFilePasteRefusal.nameNotAllowedInWindows(name: name)) {
                try ClipboardFilePaste.plan(fileURLs: [URL(filePath: "/tmp/\(name)")], entry: regular())
            }
        }
        #expect(throws: ClipboardFilePasteRefusal.duplicateName(name: "A.TXT")) {
            try ClipboardFilePaste.plan(
                fileURLs: [URL(filePath: "/one/a.txt"), URL(filePath: "/two/A.TXT")],
                entry: regular()
            )
        }
    }

    @Test("copies into the share and keeps only the newest batches it created")
    func copiesAndPrunes() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "veil-clipboard-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let source = root.appending(path: "source.txt")
        let share = root.appending(path: "share", directoryHint: .isDirectory)
        let clipboard = share.appending(path: ClipboardFilePaste.directoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: clipboard, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source)
        for old in ["20261101-000000-000001", "20261102-000000-000002", "20261103-000000-000003", "Keep Me"] {
            try fileManager.createDirectory(at: clipboard.appending(path: old), withIntermediateDirectories: true)
        }

        let plan = try ClipboardFilePaste.plan(fileURLs: [source], now: now, batchSuffix: "ABCDEF")
        try ClipboardFilePaste.copy(plan, intoShareAt: share)

        let copied = clipboard.appending(path: "20261105-140102-ABCDEF/source.txt")
        #expect(try Data(contentsOf: copied) == Data("hello".utf8))
        let remaining = try fileManager.contentsOfDirectory(atPath: clipboard.path).sorted()
        #expect(remaining == ["20261102-000000-000002", "20261103-000000-000003", "20261105-140102-ABCDEF", "Keep Me"])
    }

    @Test("clipboard sharing is on until the user turns it off, and file paste follows it")
    func preferenceDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "veil-clipboard-tests-\(UUID().uuidString)"))
        #expect(ClipboardSharingPreferences.isSharingEnabled(defaults))
        #expect(ClipboardSharingPreferences.isFilePasteEnabled(defaults))

        defaults.set(false, forKey: ClipboardSharingPreferences.sharingEnabledKey)
        #expect(!ClipboardSharingPreferences.isSharingEnabled(defaults))
        #expect(!ClipboardSharingPreferences.isFilePasteEnabled(defaults))
    }
}
