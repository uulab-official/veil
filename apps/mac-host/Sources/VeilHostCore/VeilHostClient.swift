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

public enum AgentConnectionDiagnosticStatus: String, Codable, Equatable, Sendable {
    case connected
    case unavailable
}

public struct AgentConnectionDiagnostic: Codable, Equatable, Sendable {
    public var status: AgentConnectionDiagnosticStatus
    public var endpoint: String
    public var health: AgentHealthResponse?
    public var errorMessage: String?
    public var nextActions: [String]

    public init(
        status: AgentConnectionDiagnosticStatus,
        endpoint: String,
        health: AgentHealthResponse? = nil,
        errorMessage: String? = nil,
        nextActions: [String]
    ) {
        self.status = status
        self.endpoint = endpoint
        self.health = health
        self.errorMessage = errorMessage
        self.nextActions = nextActions
    }
}

private enum AgentConnectionProbeError: Error, LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Timed out waiting for Windows agent health."
        }
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

    public func loadHealth() async throws -> AgentHealthResponse {
        try await request(
            AgentHealthRequest(requestId: "req_health")
        )
    }

    public func diagnoseAgentConnection(
        endpoint: String,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async -> AgentConnectionDiagnostic {
        do {
            let health = try await loadHealth(timeoutNanoseconds: timeoutNanoseconds)
            return AgentConnectionDiagnostic(
                status: .connected,
                endpoint: endpoint,
                health: health,
                nextActions: [
                    "Run veil-host-probe --overview to verify app metadata.",
                    "Run veil-host-probe --launch-notepad to verify HWND launch and tracking."
                ]
            )
        } catch {
            return AgentConnectionDiagnostic(
                status: .unavailable,
                endpoint: endpoint,
                errorMessage: Self.errorMessage(for: error),
                nextActions: [
                    "Confirm the Windows 11 Arm VM is running and has reached the desktop.",
                    "Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd.",
                    "If the agent still does not connect, run Veil Shared\\Veil Guest Agent\\Collect Veil Agent Diagnostics.cmd and inspect the desktop ZIP.",
                    "Confirm the QEMU/HVF plan includes hostfwd=tcp::18444-:18444 and restart the VM after changing the launch plan."
                ]
            )
        }
    }

    private func loadHealth(timeoutNanoseconds: UInt64) async throws -> AgentHealthResponse {
        try await withThrowingTaskGroup(of: AgentHealthResponse.self) { group in
            group.addTask {
                try await loadHealth()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw AgentConnectionProbeError.timeout
            }

            guard let health = try await group.next() else {
                throw AgentConnectionProbeError.timeout
            }
            group.cancelAll()
            return health
        }
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

    public func subscribeWindowFrames(windowId: String) async throws {
        _ = try await transport.send(
            encoder.encode(
                WindowFrameSubscribeRequest(
                    requestId: "req_frame_subscribe_\(requestIdSuffix(for: windowId))",
                    windowId: windowId
                )
            ),
            expectedReplies: 0
        )
    }

    public func unsubscribeWindowFrames(windowId: String) async throws {
        _ = try await transport.send(
            encoder.encode(
                WindowFrameUnsubscribeRequest(
                    requestId: "req_frame_unsubscribe_\(requestIdSuffix(for: windowId))",
                    windowId: windowId
                )
            ),
            expectedReplies: 0
        )
    }

    public func loadOverview() async throws -> HostOverview {
        let health = try await loadHealth()

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

    private func requestIdSuffix(for windowId: String) -> String {
        windowId.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        .map(String.init)
        .joined()
    }

    private static func errorMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
