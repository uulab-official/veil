import Foundation

public protocol HostTransport: Sendable {
    func send(_ message: Data, expectedReplies: Int) async throws -> [Data]
}

public protocol HostEventSource: Sendable {
    func eventMessages() -> AsyncThrowingStream<Data, any Error>
}

public enum VeilHostError: Error, Equatable, LocalizedError, Sendable {
    case appMissing(String)
    case appWindowMismatch(String)
    case missingReply(String)

    public var errorDescription: String? {
        switch self {
        case .appMissing(let appId):
            "The Windows app \(appId) is not available from the Windows agent."
        case .appWindowMismatch(let appId):
            "The Windows agent launched \(appId), but the tracked HWND did not match the launch response."
        case .missingReply(let context):
            "The Windows agent did not return the expected reply: \(context)."
        }
    }
}

public struct WindowsAppLaunchResult: Codable, Equatable, Sendable {
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

public typealias NotepadLaunchResult = WindowsAppLaunchResult

public struct WindowFrameProofEvidence: Codable, Equatable, Sendable {
    public var windowId: String
    public var frameId: String
    public var sequence: Int
    public var format: String
    public var width: Int
    public var height: Int
    public var scale: Double
    public var encodedByteCount: Int

    public init(frame: WindowFrameEvent) {
        self.windowId = frame.windowId
        self.frameId = frame.frameId
        self.sequence = frame.sequence
        self.format = frame.format
        self.width = frame.width
        self.height = frame.height
        self.scale = frame.scale
        self.encodedByteCount = frame.encodedPayloadData?.count ?? 0
    }
}

public struct WindowsAppWindowProofReport: Codable, Equatable, Sendable {
    public var kind: String
    public var endpoint: String
    public var appId: String
    public var provedAt: Date
    public var launch: AppLaunchResponse
    public var window: WindowCreatedEvent
    public var frame: WindowFrameProofEvidence
    public var savedProofPath: String?
    public var nextActions: [String]

    public init(
        kind: String = "windowsAppWindowProof",
        endpoint: String,
        appId: String,
        provedAt: Date,
        launch: AppLaunchResponse,
        window: WindowCreatedEvent,
        frame: WindowFrameProofEvidence,
        savedProofPath: String? = nil,
        nextActions: [String]
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.appId = appId
        self.provedAt = provedAt
        self.launch = launch
        self.window = window
        self.frame = frame
        self.savedProofPath = savedProofPath
        self.nextActions = nextActions
    }
}

public struct WindowsAppInputProofEvidence: Codable, Equatable, Sendable {
    public var mouseEventsPosted: [String]
    public var keyEventsPosted: [String]
    public var typedTextCharacterCount: Int
    public var clipboardOrigin: String
    public var clipboardSequence: Int
    public var clipboardTextByteCount: Int

    public init(
        mouseEventsPosted: [String],
        keyEventsPosted: [String],
        typedTextCharacterCount: Int,
        clipboardOrigin: String,
        clipboardSequence: Int,
        clipboardTextByteCount: Int
    ) {
        self.mouseEventsPosted = mouseEventsPosted
        self.keyEventsPosted = keyEventsPosted
        self.typedTextCharacterCount = typedTextCharacterCount
        self.clipboardOrigin = clipboardOrigin
        self.clipboardSequence = clipboardSequence
        self.clipboardTextByteCount = clipboardTextByteCount
    }
}

public struct WindowsAppCoherenceProofReport: Codable, Equatable, Sendable {
    public var kind: String
    public var endpoint: String
    public var appId: String
    public var provedAt: Date
    public var launch: AppLaunchResponse
    public var window: WindowCreatedEvent
    public var initialFrame: WindowFrameProofEvidence
    public var postInputFrame: WindowFrameProofEvidence
    public var input: WindowsAppInputProofEvidence
    public var savedProofPath: String?
    public var nextActions: [String]

    public init(
        kind: String = "windowsAppCoherenceProof",
        endpoint: String,
        appId: String,
        provedAt: Date,
        launch: AppLaunchResponse,
        window: WindowCreatedEvent,
        initialFrame: WindowFrameProofEvidence,
        postInputFrame: WindowFrameProofEvidence,
        input: WindowsAppInputProofEvidence,
        savedProofPath: String? = nil,
        nextActions: [String]
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.appId = appId
        self.provedAt = provedAt
        self.launch = launch
        self.window = window
        self.initialFrame = initialFrame
        self.postInputFrame = postInputFrame
        self.input = input
        self.savedProofPath = savedProofPath
        self.nextActions = nextActions
    }
}

public enum WindowsMVPProofStatus: String, Codable, Equatable, Sendable {
    case proved
    case unavailable
}

public struct WindowsMVPProofReport: Codable, Equatable, Sendable {
    public var kind: String
    public var endpoint: String
    public var appId: String
    public var status: WindowsMVPProofStatus
    public var provedAt: Date
    public var wait: AgentConnectionWaitReport
    public var coherence: WindowsAppCoherenceProofReport?
    public var savedProofPath: String?
    public var nextActions: [String]

    public init(
        kind: String = "windowsMVPProof",
        endpoint: String,
        appId: String,
        status: WindowsMVPProofStatus,
        provedAt: Date,
        wait: AgentConnectionWaitReport,
        coherence: WindowsAppCoherenceProofReport? = nil,
        savedProofPath: String? = nil,
        nextActions: [String]
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.appId = appId
        self.status = status
        self.provedAt = provedAt
        self.wait = wait
        self.coherence = coherence
        self.savedProofPath = savedProofPath
        self.nextActions = nextActions
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

    public static func connected(endpoint: String, health: AgentHealthResponse) -> AgentConnectionDiagnostic {
        AgentConnectionDiagnostic(
            status: .connected,
            endpoint: endpoint,
            health: health,
            nextActions: [
                "Run veil-host-probe --overview to verify app metadata.",
                "Run veil-host-probe --launch-notepad-frame to verify HWND launch, tracking, and first frame capture."
            ]
        )
    }

    public static func unavailable(endpoint: String, errorMessage: String) -> AgentConnectionDiagnostic {
        AgentConnectionDiagnostic(
            status: .unavailable,
            endpoint: endpoint,
            errorMessage: errorMessage,
            nextActions: [
                "Confirm the Windows 11 Arm VM is running and has reached the desktop.",
                "Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd.",
                "If the agent still does not connect, run Veil Shared\\Veil Guest Agent\\Collect Veil Agent Diagnostics.cmd and inspect the desktop ZIP.",
                "Confirm the QEMU/HVF plan includes hostfwd=tcp::18444-:18444 and restart the VM after changing the launch plan."
            ]
        )
    }
}

public enum AgentConnectionWaitStatus: String, Codable, Equatable, Sendable {
    case connected
    case unavailable
}

public struct AgentConnectionWaitReport: Codable, Equatable, Sendable {
    public var kind: String
    public var endpoint: String
    public var status: AgentConnectionWaitStatus
    public var waitedSeconds: Int
    public var attempts: Int
    public var connectedAt: Date?
    public var diagnostic: AgentConnectionDiagnostic
    public var nextActions: [String]

    public init(
        kind: String = "guestAgentWait",
        endpoint: String,
        status: AgentConnectionWaitStatus,
        waitedSeconds: Int,
        attempts: Int,
        connectedAt: Date? = nil,
        diagnostic: AgentConnectionDiagnostic,
        nextActions: [String]
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.status = status
        self.waitedSeconds = waitedSeconds
        self.attempts = attempts
        self.connectedAt = connectedAt
        self.diagnostic = diagnostic
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

public enum WindowsAppWindowProofError: Error, Equatable, LocalizedError, Sendable {
    case frameTimeout(windowId: String)

    public var errorDescription: String? {
        switch self {
        case .frameTimeout(let windowId):
            "Timed out waiting for the first window.frame event for \(windowId)."
        }
    }
}

public enum WindowsAppCoherenceProofError: Error, Equatable, LocalizedError, Sendable {
    case capabilityUnavailable(String)
    case unsupportedProofText(String)

    public var errorDescription: String? {
        switch self {
        case .capabilityUnavailable(let capability):
            "The Windows agent does not report \(capability) support, so Veil cannot prove Coherence-style app input yet."
        case .unsupportedProofText(let text):
            "The Coherence proof text contains unsupported keyboard characters: \(text)"
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

    public func launchApp(appId: String) async throws -> WindowsAppLaunchResult {
        let overview = try await loadOverview()

        guard overview.apps.contains(where: { $0.id == appId }) else {
            throw VeilHostError.appMissing(appId)
        }

        let launchReplies = try await transport.send(
            encoder.encode(AppLaunchRequest(requestId: "req_launch_\(requestIdSuffix(for: appId))", appId: appId)),
            expectedReplies: 2
        )

        guard launchReplies.count >= 2 else {
            throw VeilHostError.missingReply("app launch requires response and window event")
        }

        let launch = try decoder.decode(AppLaunchResponse.self, from: launchReplies[0])
        let window = try decoder.decode(WindowCreatedEvent.self, from: launchReplies[1])

        guard launch.accepted,
              launch.processId == window.processId,
              window.appId == appId else {
            throw VeilHostError.appWindowMismatch(appId)
        }

        return WindowsAppLaunchResult(
            health: overview.health,
            apps: overview.apps,
            launch: launch,
            window: window
        )
    }

    public func launchNotepad() async throws -> NotepadLaunchResult {
        try await launchApp(appId: "winapp_notepad")
    }

    public func proveAppWindow(
        appId: String,
        endpoint: String,
        eventSource: any HostEventSource,
        timeoutNanoseconds: UInt64 = 10_000_000_000
    ) async throws -> WindowsAppWindowProofReport {
        let launchResult = try await launchApp(appId: appId)
        async let frame = firstFrame(
            from: eventSource,
            windowId: launchResult.window.windowId,
            timeoutNanoseconds: timeoutNanoseconds
        )
        try? await Task.sleep(nanoseconds: 200_000_000)
        try await subscribeWindowFrames(windowId: launchResult.window.windowId)
        let firstFrame = try await frame

        return WindowsAppWindowProofReport(
            endpoint: endpoint,
            appId: appId,
            provedAt: Date(),
            launch: launchResult.launch,
            window: launchResult.window,
            frame: WindowFrameProofEvidence(frame: firstFrame),
            nextActions: [
                "Open the mirrored HWND in the Veil host shell as a macOS window.",
                "Run `veil-vmctl app-runtime-status --json` to inspect active mirrored sessions and supported actions."
            ]
        )
    }

    public func proveCoherenceAppWindow(
        appId: String,
        endpoint: String,
        eventSource: any HostEventSource,
        timeoutNanoseconds: UInt64 = 10_000_000_000,
        typedText: String = "veil",
        clipboardText: String = "Veil coherence proof"
    ) async throws -> WindowsAppCoherenceProofReport {
        let launchResult = try await launchApp(appId: appId)
        guard launchResult.health.capabilities.input else {
            throw WindowsAppCoherenceProofError.capabilityUnavailable("input")
        }
        guard launchResult.health.capabilities.clipboardText else {
            throw WindowsAppCoherenceProofError.capabilityUnavailable("clipboardText")
        }

        async let frame = firstFrame(
            from: eventSource,
            windowId: launchResult.window.windowId,
            timeoutNanoseconds: timeoutNanoseconds
        )
        try? await Task.sleep(nanoseconds: 200_000_000)
        try await subscribeWindowFrames(windowId: launchResult.window.windowId)
        let initialFrame = try await frame

        async let postInputFrame = firstFrame(
            from: eventSource,
            windowId: launchResult.window.windowId,
            minimumSequenceExclusive: initialFrame.sequence,
            timeoutNanoseconds: timeoutNanoseconds
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        let click = Self.proofClickPoint(for: launchResult.window.bounds)
        let mouseInputs = [
            InputMouseEvent(windowId: launchResult.window.windowId, event: "leftDown", x: click.x, y: click.y),
            InputMouseEvent(windowId: launchResult.window.windowId, event: "leftUp", x: click.x, y: click.y)
        ]
        for input in mouseInputs {
            try await sendMouseInput(input)
        }

        let keyInputs = try Self.keyInputs(windowId: launchResult.window.windowId, text: typedText)
        for input in keyInputs {
            try await sendKeyInput(input)
        }

        let clipboard = ClipboardTextSet(
            requestId: "req_clipboard_coherence_proof",
            origin: "host",
            sequence: 1,
            text: clipboardText
        )
        try await sendClipboardText(clipboard)
        let frameAfterInput = try await postInputFrame

        return WindowsAppCoherenceProofReport(
            endpoint: endpoint,
            appId: appId,
            provedAt: Date(),
            launch: launchResult.launch,
            window: launchResult.window,
            initialFrame: WindowFrameProofEvidence(frame: initialFrame),
            postInputFrame: WindowFrameProofEvidence(frame: frameAfterInput),
            input: WindowsAppInputProofEvidence(
                mouseEventsPosted: mouseInputs.map(\.event),
                keyEventsPosted: keyInputs.map { "\($0.event):\($0.key)" },
                typedTextCharacterCount: typedText.count,
                clipboardOrigin: clipboard.origin,
                clipboardSequence: clipboard.sequence,
                clipboardTextByteCount: Data(clipboardText.utf8).count
            ),
            nextActions: [
                "Open the mirrored HWND in the Veil host shell as a macOS window.",
                "Use the saved proof artifact when filing app-runtime bugs or release gate evidence."
            ]
        )
    }

    public func proveMVPAppRuntime(
        appId: String,
        endpoint: String,
        eventSource: any HostEventSource,
        waitSeconds: Int = 30,
        proofTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) async throws -> WindowsMVPProofReport {
        let wait = await waitForAgentConnection(endpoint: endpoint, timeoutSeconds: waitSeconds)
        guard wait.status == .connected else {
            return WindowsMVPProofReport(
                endpoint: endpoint,
                appId: appId,
                status: .unavailable,
                provedAt: Date(),
                wait: wait,
                nextActions: wait.nextActions
            )
        }

        let coherence = try await proveCoherenceAppWindow(
            appId: appId,
            endpoint: endpoint,
            eventSource: eventSource,
            timeoutNanoseconds: proofTimeoutNanoseconds
        )

        return WindowsMVPProofReport(
            endpoint: endpoint,
            appId: appId,
            status: .proved,
            provedAt: Date(),
            wait: wait,
            coherence: coherence,
            nextActions: [
                "Open the mirrored HWND in the Veil host shell as a macOS window.",
                "Attach the saved MVP proof artifact to release gates and app-runtime bug reports."
            ]
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
            return .connected(endpoint: endpoint, health: health)
        } catch {
            return .unavailable(endpoint: endpoint, errorMessage: Self.errorMessage(for: error))
        }
    }

    public func waitForAgentConnection(
        endpoint: String,
        timeoutSeconds: Int = 30,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        perAttemptTimeoutNanoseconds: UInt64 = 2_000_000_000
    ) async -> AgentConnectionWaitReport {
        let boundedTimeoutSeconds = min(max(timeoutSeconds, 0), 300)
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(TimeInterval(boundedTimeoutSeconds))
        var attempts = 0
        var latestDiagnostic = AgentConnectionDiagnostic.unavailable(
            endpoint: endpoint,
            errorMessage: "Guest agent wait has not started."
        )

        while true {
            attempts += 1
            latestDiagnostic = await diagnoseAgentConnection(
                endpoint: endpoint,
                timeoutNanoseconds: perAttemptTimeoutNanoseconds
            )

            if latestDiagnostic.status == .connected {
                return AgentConnectionWaitReport(
                    endpoint: endpoint,
                    status: .connected,
                    waitedSeconds: Self.elapsedSeconds(since: startedAt),
                    attempts: attempts,
                    connectedAt: Date(),
                    diagnostic: latestDiagnostic,
                    nextActions: [
                        "Run `veil-vmctl app-runtime-status --json` to inspect app launch readiness.",
                        "Run `veil-vmctl app-window-proof --json --app-id winapp_notepad` to verify HWND launch, tracking, and first frame capture.",
                        "Run `veil-vmctl mvp-proof --json --app-id winapp_notepad` to verify the Notepad launch, frame, input, and clipboard MVP loop."
                    ]
                )
            }

            guard Date() < deadline else {
                return AgentConnectionWaitReport(
                    endpoint: endpoint,
                    status: .unavailable,
                    waitedSeconds: boundedTimeoutSeconds,
                    attempts: attempts,
                    diagnostic: latestDiagnostic,
                    nextActions: latestDiagnostic.nextActions
                )
            }

            let remainingNanoseconds = max(0, UInt64(deadline.timeIntervalSinceNow * 1_000_000_000))
            try? await Task.sleep(nanoseconds: min(pollIntervalNanoseconds, remainingNanoseconds))
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

    public func focusWindow(windowId: String) async throws -> WindowFocusResponse {
        try await request(
            WindowFocusRequest(requestId: "req_focus_\(requestIdSuffix(for: windowId))", windowId: windowId)
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

    private func firstFrame(
        from eventSource: any HostEventSource,
        windowId: String,
        minimumSequenceExclusive: Int? = nil,
        timeoutNanoseconds: UInt64
    ) async throws -> WindowFrameEvent {
        try await withThrowingTaskGroup(of: WindowFrameEvent.self) { group in
            group.addTask {
                for try await message in eventSource.eventMessages() {
                    let envelope = try decoder.decode(ProtocolMessageEnvelope.self, from: message)
                    guard envelope.type == .windowFrame else {
                        continue
                    }

                    let frame = try decoder.decode(WindowFrameEvent.self, from: message)
                    if frame.windowId == windowId,
                       minimumSequenceExclusive.map({ frame.sequence > $0 }) ?? true {
                        return frame
                    }
                }

                throw WindowsAppWindowProofError.frameTimeout(windowId: windowId)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw WindowsAppWindowProofError.frameTimeout(windowId: windowId)
            }

            guard let frame = try await group.next() else {
                throw WindowsAppWindowProofError.frameTimeout(windowId: windowId)
            }
            group.cancelAll()
            return frame
        }
    }

    private func requestIdSuffix(for windowId: String) -> String {
        windowId.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        .map(String.init)
        .joined()
    }

    private static func proofClickPoint(for bounds: WindowBounds) -> (x: Int, y: Int) {
        let maxX = max(bounds.width - 1, 1)
        let maxY = max(bounds.height - 1, 1)
        return (
            x: min(max(240, 1), maxX),
            y: min(max(130, 1), maxY)
        )
    }

    public static func keyInputs(windowId: String, text: String) throws -> [InputKeyEvent] {
        var inputs: [InputKeyEvent] = []
        for scalar in text.unicodeScalars {
            let value = scalar.value
            guard (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) else {
                throw WindowsAppCoherenceProofError.unsupportedProofText(text)
            }

            let key = String(scalar).lowercased()
            let virtualKey: Int
            if (97...122).contains(value) {
                virtualKey = Int(value - 32)
            } else {
                virtualKey = Int(value)
            }

            inputs.append(InputKeyEvent(windowId: windowId, event: "keyDown", key: key, windowsVirtualKey: virtualKey))
            inputs.append(InputKeyEvent(windowId: windowId, event: "keyUp", key: key, windowsVirtualKey: virtualKey))
        }

        return inputs
    }

    private static func errorMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    private static func elapsedSeconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date).rounded(.up)))
    }
}
