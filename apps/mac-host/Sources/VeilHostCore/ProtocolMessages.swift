import Foundation

public enum MessageType: String, Codable, Sendable {
    case agentHealthRequest = "agent.health.request"
    case agentHealthResponse = "agent.health.response"
    case appListRequest = "app.list.request"
    case appListResponse = "app.list.response"
    case appLaunchRequest = "app.launch.request"
    case appLaunchResponse = "app.launch.response"
    case windowCreated = "window.created"
    case clipboardTextSet = "clipboard.text.set"
    case inputMouse = "input.mouse"
    case inputKey = "input.key"
    case error
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

public struct WindowsApp: Codable, Equatable, Sendable {
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

public struct WindowBounds: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
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
