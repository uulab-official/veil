import Foundation

public enum MessageType: String, Codable, Sendable {
    case agentHealthRequest = "agent.health.request"
    case agentHealthResponse = "agent.health.response"
    case appListRequest = "app.list.request"
    case appListResponse = "app.list.response"
    case appLaunchRequest = "app.launch.request"
    case appLaunchResponse = "app.launch.response"
    case windowCreated = "window.created"
    case windowClosed = "window.closed"
    case windowFrame = "window.frame"
    case windowFrameSubscribe = "window.frame.subscribe"
    case windowFrameUnsubscribe = "window.frame.unsubscribe"
    case windowCloseRequest = "window.close.request"
    case windowCloseResponse = "window.close.response"
    case clipboardTextSet = "clipboard.text.set"
    case inputMouse = "input.mouse"
    case inputKey = "input.key"
    case error
}

public struct ProtocolMessageEnvelope: Codable, Equatable, Sendable {
    public var type: MessageType
}

public struct AgentHealthRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int

    public init(requestId: String, protocolVersion: Int = 1) {
        self.type = .agentHealthRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
    }
}

public struct AgentHealthResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var agentVersion: String
    public var os: String
    public var session: AgentSession
    public var capabilities: AgentCapabilities
}

public struct AgentSession: Codable, Equatable, Sendable {
    public var interactive: Bool
    public var user: String
}

public struct AgentCapabilities: Codable, Equatable, Sendable {
    public var appList: Bool
    public var appLaunch: Bool
    public var windowTracking: Bool
    public var windowCapture: Bool
    public var input: Bool
    public var clipboardText: Bool
}

public struct AppListRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int

    public init(requestId: String, protocolVersion: Int = 1) {
        self.type = .appListRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
    }
}

public struct AppListResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var apps: [WindowsApp]
}

public struct WindowsApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var exePath: String
    public var publisher: String
    public var iconId: String
}

public struct AppLaunchRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var appId: String
    public var args: [String]

    public init(requestId: String, appId: String, args: [String] = []) {
        self.type = .appLaunchRequest
        self.requestId = requestId
        self.appId = appId
        self.args = args
    }
}

public struct AppLaunchResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var accepted: Bool
    public var processId: Int
}

public struct WindowCreatedEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var processId: Int
    public var appId: String
    public var title: String
    public var bounds: WindowBounds
    public var state: String
    public var focused: Bool
}

public struct WindowClosedEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String

    public init(type: MessageType = .windowClosed, windowId: String) {
        self.type = type
        self.windowId = windowId
    }
}

public struct WindowBounds: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
}

public struct WindowFrameEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var frameId: String
    public var sequence: Int
    public var format: String
    public var width: Int
    public var height: Int
    public var scale: Double
    public var encodedData: String
}

public extension WindowFrameEvent {
    var encodedPayloadData: Data? {
        Data(base64Encoded: encodedData)
    }
}

public struct WindowFrameSubscribeRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String
    public var format: String

    public init(
        type: MessageType = .windowFrameSubscribe,
        requestId: String,
        windowId: String,
        format: String = "png"
    ) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
        self.format = format
    }
}

public struct WindowFrameUnsubscribeRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String

    public init(
        type: MessageType = .windowFrameUnsubscribe,
        requestId: String,
        windowId: String
    ) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
    }
}

public struct WindowCloseRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String

    public init(requestId: String, windowId: String) {
        self.type = .windowCloseRequest
        self.requestId = requestId
        self.windowId = windowId
    }
}

public struct WindowCloseResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String
    public var accepted: Bool

    public init(type: MessageType = .windowCloseResponse, requestId: String, windowId: String, accepted: Bool) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
        self.accepted = accepted
    }
}

public struct InputMouseEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var event: String
    public var x: Int
    public var y: Int
    public var modifiers: [String]

    public init(
        type: MessageType = .inputMouse,
        windowId: String,
        event: String,
        x: Int,
        y: Int,
        modifiers: [String] = []
    ) {
        self.type = type
        self.windowId = windowId
        self.event = event
        self.x = x
        self.y = y
        self.modifiers = modifiers
    }
}

public struct InputKeyEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var event: String
    public var key: String
    public var windowsVirtualKey: Int
    public var modifiers: [String]

    public init(
        type: MessageType = .inputKey,
        windowId: String,
        event: String,
        key: String,
        windowsVirtualKey: Int,
        modifiers: [String] = []
    ) {
        self.type = type
        self.windowId = windowId
        self.event = event
        self.key = key
        self.windowsVirtualKey = windowsVirtualKey
        self.modifiers = modifiers
    }
}

public struct ClipboardTextSet: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var origin: String
    public var sequence: Int
    public var text: String

    public init(
        type: MessageType = .clipboardTextSet,
        requestId: String,
        origin: String,
        sequence: Int,
        text: String
    ) {
        self.type = type
        self.requestId = requestId
        self.origin = origin
        self.sequence = sequence
        self.text = text
    }
}

public struct ErrorResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String?
    public var code: String
    public var message: String
}

public extension JSONDecoder {
    static var veilProtocol: JSONDecoder {
        JSONDecoder()
    }
}

public extension JSONEncoder {
    static var veilProtocol: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
