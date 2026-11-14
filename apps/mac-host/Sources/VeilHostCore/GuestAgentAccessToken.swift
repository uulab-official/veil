import Foundation
import Security

/// The secret that keeps other accounts on the Mac off the Windows agent.
///
/// The agent's port is forwarded to 127.0.0.1, which every account on the Mac can open, and its connection
/// types into Windows, starts programs, and reads the clipboard. Veil keeps one random token per Mac user in
/// a file only that user can read, hands it to Windows as an SMBIOS OEM string through
/// `-smbios type=11,path=` (the path, so the token is not in QEMU's arguments, which other accounts can
/// list), and sends it with every connection in `X-Veil-Agent-Token`. An agent that finds the token in its
/// SMBIOS tables refuses connections without it; see `AgentAccessToken` in the agent.
///
/// Windows reads SMBIOS when it starts, so a token takes effect from the next Windows start, not on resume.
public enum GuestAgentAccessToken {
    public static let headerName = "X-Veil-Agent-Token"
    public static let oemStringPrefix = "org.uulab.veil.agent-token="

    public static var defaultFileURL: URL {
        VeilApplicationSupport.directory
            .appendingPathComponent("Agent Access", isDirectory: true)
            .appendingPathComponent("agent-token.smbios")
    }

    /// The stored token, or nil when there is none yet.
    public static func load(fileURL: URL = defaultFileURL) -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              text.hasPrefix(oemStringPrefix) else {
            return nil
        }
        let token = String(text.dropFirst(oemStringPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.count >= 32 && token.allSatisfy(\.isHexDigit) ? token : nil
    }

    /// The stored token, created first if there is none. The folder is owner-only (0700) and the file
    /// owner-read-write (0600). An existing token is never replaced: a running Windows holds the one it
    /// started with, and a new one would lock Veil out of it until Windows restarts.
    public static func loadOrCreate(fileURL: URL = defaultFileURL) throws -> String {
        if let token = load(fileURL: fileURL) {
            return token
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        // Written without a newline: QEMU puts the file's bytes into the OEM string as they are.
        let created = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data((oemStringPrefix + token).utf8),
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw CocoaError(.fileWriteUnknown)
        }
        return token
    }

    /// QEMU's arguments for a cold boot. QEMU option values escape a comma by doubling it.
    public static func smbiosArguments(fileURL: URL = defaultFileURL) -> [String] {
        ["-smbios", "type=11,path=\(fileURL.path.replacingOccurrences(of: ",", with: ",,"))"]
    }

    /// A WebSocket request carrying the token, when there is one.
    public static func request(for url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let token {
            request.setValue(token, forHTTPHeaderField: headerName)
        }
        return request
    }
}
