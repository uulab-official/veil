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
    case diagnoseAgent
    case overview
    case launchNotepad
    case launchNotepadFrame
}

func parseMode(_ arguments: [String]) -> ProbeMode? {
    guard let first = arguments.first else {
        return .health
    }

    switch first {
    case "--health", "health":
        return .health
    case "--diagnose-agent", "diagnose-agent", "diagnose":
        return .diagnoseAgent
    case "--overview", "overview":
        return .overview
    case "--launch-notepad", "launch-notepad":
        return .launchNotepad
    case "--launch-notepad-frame", "launch-notepad-frame":
        return .launchNotepadFrame
    case "--help", "-h", "help":
        return nil
    default:
        return nil
    }
}

func printUsage() {
    FileHandle.standardError.write(Data("""
    Usage: veil-host-probe [--health|--diagnose-agent|--overview|--launch-notepad|--launch-notepad-frame]

      --health          Request only agent.health.response. This is the default.
      --diagnose-agent  Print a connection diagnostic JSON with next actions.
      --overview        Request health and app list.
      --launch-notepad  Run the full health -> app list -> Notepad launch acceptance flow.
      --launch-notepad-frame
                        Launch Notepad, subscribe to its HWND stream, and wait for the first PNG frame.

    Set VEIL_AGENT_URL to override the endpoint. Default: ws://127.0.0.1:18444

    """.utf8))
}

struct NotepadFrameProbeResult: Encodable {
    var launchResult: NotepadLaunchResult
    var frame: WindowFrameEvent
}

enum HostProbeError: Error, LocalizedError {
    case frameTimeout(windowId: String)

    var errorDescription: String? {
        switch self {
        case .frameTimeout(let windowId):
            "Timed out waiting for the first window.frame event for \(windowId)."
        }
    }
}

func firstFrame(
    from eventSource: any HostEventSource,
    windowId: String,
    timeoutNanoseconds: UInt64 = 10_000_000_000
) async throws -> WindowFrameEvent {
    try await withThrowingTaskGroup(of: WindowFrameEvent.self) { group in
        group.addTask {
            for try await message in eventSource.eventMessages() {
                let envelope = try JSONDecoder.veilProtocol.decode(ProtocolMessageEnvelope.self, from: message)
                guard envelope.type == .windowFrame else {
                    continue
                }

                let frame = try JSONDecoder.veilProtocol.decode(WindowFrameEvent.self, from: message)
                if frame.windowId == windowId {
                    return frame
                }
            }

            throw HostProbeError.frameTimeout(windowId: windowId)
        }

        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw HostProbeError.frameTimeout(windowId: windowId)
        }

        let frame = try await group.next()!
        group.cancelAll()
        return frame
    }
}

func runNotepadFrameProbe(
    client: VeilHostClient,
    eventSource: any HostEventSource
) async throws -> NotepadFrameProbeResult {
    let launchResult = try await client.launchNotepad()
    async let frame = firstFrame(from: eventSource, windowId: launchResult.window.windowId)
    try? await Task.sleep(nanoseconds: 200_000_000)
    try await client.subscribeWindowFrames(windowId: launchResult.window.windowId)
    return try await NotepadFrameProbeResult(launchResult: launchResult, frame: frame)
}

guard let mode = parseMode(arguments) else {
    printUsage()
    exit(arguments.first == "--help" || arguments.first == "-h" || arguments.first == "help" ? 0 : 2)
}

do {
    let transport = switch mode {
    case .diagnoseAgent:
        URLSessionWebSocketTransport(url: url, requestTimeout: 5)
    case .health, .overview, .launchNotepad, .launchNotepadFrame:
        URLSessionWebSocketTransport(url: url)
    }
    let client = VeilHostClient(transport: transport)
    let result: any Encodable = switch mode {
    case .health:
        try await client.loadHealth()
    case .diagnoseAgent:
        await client.diagnoseAgentConnection(endpoint: rawURL)
    case .overview:
        try await client.loadOverview()
    case .launchNotepad:
        try await client.launchNotepad()
    case .launchNotepadFrame:
        try await runNotepadFrameProbe(client: client, eventSource: transport)
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
