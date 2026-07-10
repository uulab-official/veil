import Foundation

public enum MessageType: String, Codable, Sendable {
    case agentHealthRequest = "agent.health.request"
    case agentHealthResponse = "agent.health.response"
    case appListRequest = "app.list.request"
    case appListResponse = "app.list.response"
    case appLaunchRequest = "app.launch.request"
    case appLaunchResponse = "app.launch.response"
    case fileOpenRequest = "file.open.request"
    case fileOpenResponse = "file.open.response"
    case windowCreated = "window.created"
    case windowUpdated = "window.updated"
    case windowClosed = "window.closed"
    case windowFrame = "window.frame"
    case windowFrameSubscribe = "window.frame.subscribe"
    case windowFrameUnsubscribe = "window.frame.unsubscribe"
    case windowFocusRequest = "window.focus.request"
    case windowFocusResponse = "window.focus.response"
    case windowCloseRequest = "window.close.request"
    case windowCloseResponse = "window.close.response"
    case clipboardTextSet = "clipboard.text.set"
    case notificationListenerRequest = "notification.listener.request"
    case notificationListenerResponse = "notification.listener.response"
    case notificationReceived = "notification.received"
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
    public var packageIdentityStatus: PackageIdentityStatus? = nil
    public var notificationListener: WindowsNotificationListenerStatus? = nil
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
    /// True when the Windows agent is running with package identity. Required before Veil can
    /// request package-gated Windows APIs such as borderless capture and notification listening.
    public var packageIdentity: Bool = false
}

public struct PackageIdentityStatus: Codable, Equatable, Sendable {
    public var statusPath: String
    public var stage: String
    public var succeeded: Bool
    public var message: String?
    public var updatedAt: String?
    public var packagePath: String?
    public var certificatePath: String?
}

public struct WindowsNotificationListenerStatus: Codable, Equatable, Sendable {
    public var isSupported: Bool
    public var canListen: Bool
    public var accessStatus: String
    public var recommendedAction: String
    public var requiresPackageIdentity: Bool
    public var message: String?
}

public struct WindowsNotificationListenerRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int

    public init(requestId: String, protocolVersion: Int = 1) {
        self.type = .notificationListenerRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
    }
}

public struct WindowsNotificationListenerResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var accepted: Bool
    public var notificationListener: WindowsNotificationListenerStatus
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
    /// Base64-encoded PNG of the app's real Windows icon, sent once per app.list.response since
    /// icons are static (`WindowsAppIconExtractor` on the guest). `nil` in demo mode or if the guest
    /// could not resolve/extract the icon -- callers should fall back to a generic icon in that case.
    public var iconPngBase64: String? = nil
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

public struct FileOpenRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var appId: String
    public var fileName: String
    public var contentBase64: String

    public init(requestId: String, appId: String, fileName: String, contentBase64: String) {
        self.type = .fileOpenRequest
        self.requestId = requestId
        self.appId = appId
        self.fileName = fileName
        self.contentBase64 = contentBase64
    }
}

public struct FileOpenResponse: Codable, Equatable, Sendable {
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

    public init(
        type: MessageType = .windowCreated,
        windowId: String,
        processId: Int,
        appId: String,
        title: String,
        bounds: WindowBounds,
        state: String,
        focused: Bool
    ) {
        self.type = type
        self.windowId = windowId
        self.processId = processId
        self.appId = appId
        self.title = title
        self.bounds = bounds
        self.state = state
        self.focused = focused
    }

    public init(updated event: WindowUpdatedEvent) {
        self.init(
            type: .windowCreated,
            windowId: event.windowId,
            processId: event.processId,
            appId: event.appId,
            title: event.title,
            bounds: event.bounds,
            state: event.state,
            focused: event.focused
        )
    }
}

public struct WindowUpdatedEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var processId: Int
    public var appId: String
    public var title: String
    public var bounds: WindowBounds
    public var state: String
    public var focused: Bool

    public init(
        type: MessageType = .windowUpdated,
        windowId: String,
        processId: Int,
        appId: String,
        title: String,
        bounds: WindowBounds,
        state: String,
        focused: Bool
    ) {
        self.type = type
        self.windowId = windowId
        self.processId = processId
        self.appId = appId
        self.title = title
        self.bounds = bounds
        self.state = state
        self.focused = focused
    }
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

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
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

public struct WindowFocusRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String

    public init(requestId: String, windowId: String) {
        self.type = .windowFocusRequest
        self.requestId = requestId
        self.windowId = windowId
    }
}

public struct WindowFocusResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String
    public var accepted: Bool

    public init(type: MessageType = .windowFocusResponse, requestId: String, windowId: String, accepted: Bool) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
        self.accepted = accepted
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

public struct WindowsNotificationReceivedEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var notificationId: String
    public var appId: String?
    public var appName: String?
    public var title: String
    public var body: String?
    public var receivedAt: String
    public var sourceAumid: String?

    public init(
        type: MessageType = .notificationReceived,
        notificationId: String,
        appId: String? = nil,
        appName: String? = nil,
        title: String,
        body: String? = nil,
        receivedAt: String,
        sourceAumid: String? = nil
    ) {
        self.type = type
        self.notificationId = notificationId
        self.appId = appId
        self.appName = appName
        self.title = title
        self.body = body
        self.receivedAt = receivedAt
        self.sourceAumid = sourceAumid
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
