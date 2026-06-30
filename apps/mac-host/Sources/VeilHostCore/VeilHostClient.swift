import Foundation

public protocol HostTransport: Sendable {
    func send(_ message: Data, expectedReplies: Int) async throws -> [Data]
}

public enum VeilHostError: Error, Equatable, Sendable {
    case notepadMissing
    case missingReply(String)
}

public struct NotepadLaunchResult: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]
    public var launch: AppLaunchResponse
    public var window: WindowCreatedEvent
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

        return try NotepadLaunchResult(
            health: overview.health,
            apps: overview.apps,
            launch: decoder.decode(AppLaunchResponse.self, from: launchReplies[0]),
            window: decoder.decode(WindowCreatedEvent.self, from: launchReplies[1])
        )
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
