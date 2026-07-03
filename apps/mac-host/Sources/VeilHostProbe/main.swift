import Foundation
import VeilHostCore

let rawURL = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())

guard let url = URL(string: rawURL) else {
    fputs("Invalid VEIL_AGENT_URL: \(rawURL)\n", stderr)
    exit(2)
}

enum ProbeMode {
    case health
    case overview
    case launchNotepad
}

func parseMode(_ arguments: [String]) -> ProbeMode? {
    guard let first = arguments.first else {
        return .health
    }

    switch first {
    case "--health", "health":
        return .health
    case "--overview", "overview":
        return .overview
    case "--launch-notepad", "launch-notepad":
        return .launchNotepad
    case "--help", "-h", "help":
        return nil
    default:
        return nil
    }
}

func printUsage() {
    FileHandle.standardError.write(Data("""
    Usage: veil-host-probe [--health|--overview|--launch-notepad]

      --health          Request only agent.health.response. This is the default.
      --overview        Request health and app list.
      --launch-notepad  Run the full health -> app list -> Notepad launch acceptance flow.

    Set VEIL_AGENT_URL to override the endpoint. Default: ws://127.0.0.1:18444

    """.utf8))
}

guard let mode = parseMode(arguments) else {
    printUsage()
    exit(arguments.first == "--help" || arguments.first == "-h" || arguments.first == "help" ? 0 : 2)
}

do {
    let transport = URLSessionWebSocketTransport(url: url)
    let client = VeilHostClient(transport: transport)
    let result: any Encodable = switch mode {
    case .health:
        try await client.loadHealth()
    case .overview:
        try await client.loadOverview()
    case .launchNotepad:
        try await client.launchNotepad()
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)

    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fputs("veil-host-probe failed: \(error)\n", stderr)
    exit(1)
}
