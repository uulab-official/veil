import Foundation

public protocol HostTransport: Sendable {
    func send(_ message: Data, expectedReplies: Int) async throws -> [Data]
}

public protocol HostEventSource: Sendable {
    func eventMessages() -> AsyncThrowingStream<Data, any Error>
}

public enum VeilHostError: Error, Equatable, LocalizedError, Sendable {
    case notepadMissing
    case notepadWindowMismatch
    case missingReply(String)
    case unsupportedHarnessApp

    public var errorDescription: String? {
        switch self {
        case .notepadMissing:
            "Notepad is not available from the Windows agent."
        case .notepadWindowMismatch:
            "The Windows agent launched Notepad, but the tracked HWND did not match the launch response."
        case .missingReply(let context):
            "The Windows agent did not return the expected reply: \(context)."
        case .unsupportedHarnessApp:
            "The current harness can only launch Notepad."
        }
    }
}

public struct NotepadLaunchResult: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]
    public var launch: AppLaunchResponse
    public var window: WindowCreatedEvent
    public var connectionMode: HostConnectionMode
    public var connectionDetail: String?

    public init(
        health: AgentHealthResponse,
        apps: [WindowsApp],
        launch: AppLaunchResponse,
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode = .agent,
        connectionDetail: String? = nil
    ) {
        self.health = health
        self.apps = apps
        self.launch = launch
        self.window = window
        self.connectionMode = connectionMode
        self.connectionDetail = connectionDetail
    }
}

public struct VeilHostClient: HostDashboardService, Sendable {
    private let transport: any HostTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        transport: any HostTransport,
        encoder: JSONEncoder = .veilProtocol,
        decoder: JSONDecoder = .veilProtocol
    ) {
        self.transport = transport
        self.encoder = encoder
        self.decoder = decoder
    }

    public func launchNotepad() async throws -> NotepadLaunchResult {
        let overview = try await loadOverview()

        guard overview.apps.contains(where: { $0.id == "winapp_notepad" }) else {
            throw VeilHostError.notepadMissing
        }

        let launchReplies = try await transport.send(
            encoder.encode(AppLaunchRequest(requestId: "req_launch_notepad", appId: "winapp_notepad")),
            expectedReplies: 2
        )

        guard launchReplies.count >= 2 else {
            throw VeilHostError.missingReply("app launch requires response and window event")
        }

        let launch = try decoder.decode(AppLaunchResponse.self, from: launchReplies[0])
        let window = try decoder.decode(WindowCreatedEvent.self, from: launchReplies[1])

        guard launch.accepted,
              launch.processId == window.processId,
              window.appId == "winapp_notepad" else {
            throw VeilHostError.notepadWindowMismatch
        }

        return NotepadLaunchResult(
            health: overview.health,
            apps: overview.apps,
            launch: launch,
            window: window
        )
    }

    public func closeWindow(windowId: String) async throws -> WindowCloseResponse {
        try await request(
            WindowCloseRequest(requestId: "req_close_notepad", windowId: windowId)
        )
    }

    public func sendMouseInput(_ input: InputMouseEvent) async throws {
        _ = try await transport.send(encoder.encode(input), expectedReplies: 0)
    }

    public func sendKeyInput(_ input: InputKeyEvent) async throws {
        _ = try await transport.send(encoder.encode(input), expectedReplies: 0)
    }

    public func sendClipboardText(_ clipboard: ClipboardTextSet) async throws {
        _ = try await transport.send(encoder.encode(clipboard), expectedReplies: 0)
    }

    public func loadOverview() async throws -> HostOverview {
        let health: AgentHealthResponse = try await request(
            AgentHealthRequest(requestId: "req_health")
        )

        let appList: AppListResponse = try await request(
            AppListRequest(requestId: "req_apps")
        )

        return HostOverview(health: health, apps: appList.apps)
    }

    private func request<Request: Encodable, Response: Decodable>(_ message: Request) async throws -> Response {
        let replies = try await transport.send(encoder.encode(message), expectedReplies: 1)
        guard let data = replies.first else {
            throw VeilHostError.missingReply("expected one response")
        }

        return try decoder.decode(Response.self, from: data)
    }
}
