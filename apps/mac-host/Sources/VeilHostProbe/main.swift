import Foundation
import VeilHostCore

let rawURL = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"

guard let url = URL(string: rawURL) else {
    fputs("Invalid VEIL_AGENT_URL: \(rawURL)\n", stderr)
    exit(2)
}

do {
    let transport = URLSessionWebSocketTransport(url: url)
    let client = VeilHostClient(transport: transport)
    let result = try await client.launchNotepad()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)

    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fputs("veil-host-probe failed: \(error)\n", stderr)
    exit(1)
}
