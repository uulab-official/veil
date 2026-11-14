import Foundation
import Testing
@testable import VeilHostCore

@Suite("Windows agent token")
struct GuestAgentAccessTokenTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-token-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Agent Access, test", isDirectory: true)
            .appendingPathComponent("agent-token.smbios")
    }

    @Test("A token is created once, owner-only, and kept")
    func createsOnce() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(GuestAgentAccessToken.load(fileURL: file) == nil)

        let token = try GuestAgentAccessToken.loadOrCreate(fileURL: file)
        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isHexDigit })
        let again = try GuestAgentAccessToken.loadOrCreate(fileURL: file)
        #expect(again == token)
        #expect(GuestAgentAccessToken.load(fileURL: file) == token)

        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents == GuestAgentAccessToken.oemStringPrefix + token)
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        let folderMode = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(folderMode == 0o700)
    }

    @Test("A file that is not a token is not read as one")
    func rejectsOtherContents() throws {
        let file = temporaryFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        try Data("org.uulab.veil.agent-token=short".utf8).write(to: file)
        #expect(GuestAgentAccessToken.load(fileURL: file) == nil)
    }

    @Test("QEMU gets the file's path, with commas doubled, never the token")
    func smbiosArgumentsUseThePath() throws {
        let file = URL(fileURLWithPath: "/Users/a/Library/Application Support/Veil/Agent Access, x/agent-token.smbios")
        #expect(GuestAgentAccessToken.smbiosArguments(fileURL: file) == [
            "-smbios", "type=11,path=/Users/a/Library/Application Support/Veil/Agent Access,, x/agent-token.smbios",
        ])
    }

    @Test("Connections carry the token in their header")
    func requestCarriesToken() {
        let url = URL(string: "ws://127.0.0.1:18444/")!
        #expect(GuestAgentAccessToken.request(for: url, token: "abc").value(forHTTPHeaderField: "X-Veil-Agent-Token") == "abc")
        #expect(GuestAgentAccessToken.request(for: url, token: nil).value(forHTTPHeaderField: "X-Veil-Agent-Token") == nil)
    }
}

@Suite("Windows agent token, read at connection time")
struct GuestAgentAccessTokenCurrentTests {
    @Test("A token created after Veil started is picked up by the next connection")
    func picksUpANewToken() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("agent-token-current-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("agent-token.smbios")
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(GuestAgentAccessToken.current(fileURL: file, now: start) == nil)
        let token = try GuestAgentAccessToken.loadOrCreate(fileURL: file)
        // Within the cache's two seconds the answer stands; after them the new file is read.
        #expect(GuestAgentAccessToken.current(fileURL: file, now: start.addingTimeInterval(1)) == nil)
        #expect(GuestAgentAccessToken.current(fileURL: file, now: start.addingTimeInterval(3)) == token)
    }
}
