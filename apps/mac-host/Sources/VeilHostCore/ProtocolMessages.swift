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
    case windowFrameUnchanged = "window.frame.unchanged"
    case windowFrameSubscribe = "window.frame.subscribe"
    case windowFrameUnsubscribe = "window.frame.unsubscribe"
    case windowFocusRequest = "window.focus.request"
    case windowFocusResponse = "window.focus.response"
    case windowCloseRequest = "window.close.request"
    case windowCloseResponse = "window.close.response"
    case windowResizeRequest = "window.resize.request"
    case windowResizeResponse = "window.resize.response"
    case clipboardTextSet = "clipboard.text.set"
    case notificationListenerRequest = "notification.listener.request"
    case notificationListenerResponse = "notification.listener.response"
    case notificationReceived = "notification.received"
    case sharedFolderRequest = "shared.folder.request"
    case sharedFolderResponse = "shared.folder.response"
    case inputText = "input.text"
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
    public var sharedFolder: WindowsSharedFolderStatus? = nil
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
    /// True when the agent can apply a host-requested logical size to a tracked Windows HWND.
    ///
    /// Optional so a host connected to an older agent keeps the resize affordance disabled instead of
    /// sending a message that the agent cannot route.
    public var windowResize: Bool? = nil
    /// True when the agent can serve window frames as raw binary on a dedicated connection.
    ///
    /// Optional rather than defaulted, so an agent that predates the frame channel decodes as `nil` and
    /// the host keeps using the JSON frame path instead of opening an endpoint that does not exist.
    public var binaryFrameChannel: Bool? = nil
    /// True when the agent can report and prepare the guest-hosted shared folder.
    ///
    /// Optional for the same reason as `binaryFrameChannel`: an older agent decodes as `nil`, and the
    /// host then says the share cannot be confirmed rather than reporting a share that is missing.
    public var sharedFolder: Bool? = nil
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

/// What the Windows guest reports about the folder it shares back to macOS.
///
/// Deliberately carries no credentials. An SMB share needs a Windows account with a password, but the
/// password never travels over this protocol -- `requiresCredentials` says one is needed and the user
/// supplies it to macOS at mount time.
public struct WindowsSharedFolderStatus: Codable, Equatable, Sendable {
    public var isSupported: Bool
    public var shareName: String
    public var guestDirectoryPath: String
    public var directoryExists: Bool
    public var isShared: Bool
    public var isWritable: Bool
    /// Whether the guest is accepting SMB connections. Separate from `isShared` because a share can
    /// exist while the firewall drops every connection to it, which looks identical from the Mac.
    public var serverListening: Bool
    /// Whether publishing the share still needs an administrator. Describes the remaining work, not the
    /// agent's current token, so it stays true until the share exists.
    public var requiresElevation: Bool
    /// Whether an account password is needed to mount the share.
    ///
    /// A standing requirement rather than a detection: SMB refuses a network sign-in for a
    /// blank-password account, and the guest does not inspect password state. The password is given to
    /// macOS at mount time and never crosses this protocol.
    public var requiresCredentials: Bool
    /// Exact elevated command that creates the share, so the report never makes the user invent it.
    public var shareCommand: String?
    public var recommendedAction: String
    public var message: String?

    public init(
        isSupported: Bool,
        shareName: String,
        guestDirectoryPath: String,
        directoryExists: Bool,
        isShared: Bool,
        isWritable: Bool,
        serverListening: Bool,
        requiresElevation: Bool,
        requiresCredentials: Bool,
        shareCommand: String? = nil,
        recommendedAction: String,
        message: String? = nil
    ) {
        self.isSupported = isSupported
        self.shareName = shareName
        self.guestDirectoryPath = guestDirectoryPath
        self.directoryExists = directoryExists
        self.isShared = isShared
        self.isWritable = isWritable
        self.serverListening = serverListening
        self.requiresElevation = requiresElevation
        self.requiresCredentials = requiresCredentials
        self.shareCommand = shareCommand
        self.recommendedAction = recommendedAction
        self.message = message
    }
}

/// Asks the guest to prepare the shared folder as far as it can without elevation, then report.
public struct WindowsSharedFolderRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    /// Share name and guest directory the host expects. Sent rather than assumed so the two sides
    /// cannot silently disagree about which folder is shared.
    public var shareName: String
    public var guestDirectoryPath: String

    public init(
        requestId: String,
        protocolVersion: Int = 1,
        shareName: String = QEMUWindowsSharedFolderTransport.shareName,
        guestDirectoryPath: String = QEMUWindowsSharedFolderTransport.guestDirectoryPath
    ) {
        self.type = .sharedFolderRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.shareName = shareName
        self.guestDirectoryPath = guestDirectoryPath
    }
}

public struct WindowsSharedFolderResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var sharedFolder: WindowsSharedFolderStatus
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
    /// Set only by reconnect/restore flows. The guest reuses an existing HWND
    /// when possible instead of opening a second Windows app instance.
    public var reuseExistingWindow: Bool

    public init(
        requestId: String,
        appId: String,
        args: [String] = [],
        reuseExistingWindow: Bool = false
    ) {
        self.type = .appLaunchRequest
        self.requestId = requestId
        self.appId = appId
        self.args = args
        self.reuseExistingWindow = reuseExistingWindow
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

/// Proof that a frame stream is alive with nothing new to draw.
///
/// Carries no image payload on purpose. It advances liveness only, never the displayed frame, so the
/// frame-latency budget keeps measuring how old the picture actually is.
public struct WindowFrameUnchangedEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var sequence: Int
    public var capturedAt: String

    public init(
        type: MessageType = .windowFrameUnchanged,
        windowId: String,
        sequence: Int,
        capturedAt: String
    ) {
        self.type = type
        self.windowId = windowId
        self.sequence = sequence
        self.capturedAt = capturedAt
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

/// Requests that the guest resize the real HWND to the size of its macOS mirror.
///
/// The wire size is in the same logical units used by `window.created` and `window.updated`. The guest
/// converts those units to physical pixels using the HWND's current per-monitor DPI before calling
/// `SetWindowPos`, so a Retina macOS display does not accidentally double the Windows window size.
public struct WindowResizeRequest: Codable, Equatable, Sendable {
    public static let minimumDimension = 320
    public static let maximumDimension = 8_192
    public static let maximumPixelCount = 32_000_000

    public var type: MessageType
    public var requestId: String
    public var windowId: String
    public var width: Int
    public var height: Int

    public init(
        type: MessageType = .windowResizeRequest,
        requestId: String,
        windowId: String,
        width: Int,
        height: Int
    ) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
        self.width = width
        self.height = height
    }

    public var isPlausible: Bool {
        Self.isPlausible(width: width, height: height)
    }

    public static func isPlausible(width: Int, height: Int) -> Bool {
        width >= minimumDimension
            && width <= maximumDimension
            && height >= minimumDimension
            && height <= maximumDimension
            && width <= maximumPixelCount / max(height, 1)
    }
}

public struct WindowResizeResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String
    public var accepted: Bool
    public var bounds: WindowBounds?

    public init(
        type: MessageType = .windowResizeResponse,
        requestId: String,
        windowId: String,
        accepted: Bool,
        bounds: WindowBounds? = nil
    ) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
        self.accepted = accepted
        self.bounds = bounds
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

/// Committed Unicode text for a tracked HWND.
///
/// `InputKeyEvent` carries a Windows virtual key, and characters outside that map -- every Hangul
/// syllable, kana, and Han character -- cannot be expressed by it. macOS owns the IME here: the host
/// composes and sends only finished text, so the guest never renders a candidate window over a
/// mirrored bitmap. Navigation keys, shortcuts, Enter, and Tab stay on `InputKeyEvent`.
public struct InputTextEvent: Codable, Equatable, Sendable {
    /// One posted window message per UTF-16 code unit on the guest, so the payload is bounded to keep
    /// a single message from flooding the target HWND.
    public static let maximumUTF16Length = 4_096

    public var type: MessageType
    public var windowId: String
    public var text: String

    public init(
        type: MessageType = .inputText,
        windowId: String,
        text: String
    ) {
        self.type = type
        self.windowId = windowId
        self.text = text
    }

    /// Text that is safe to send as committed input.
    ///
    /// Rejects empty text, oversized payloads, and control characters. Newlines and tabs are excluded
    /// on purpose: they have virtual-key equivalents with distinct guest semantics (Enter submits, Tab
    /// moves focus), so routing them through committed text would quietly change behavior.
    public static func isSendable(_ text: String) -> Bool {
        guard !text.isEmpty,
              text.utf16.count <= maximumUTF16Length else {
            return false
        }

        return !text.unicodeScalars.contains { scalar in
            scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar.properties.generalCategory == .control
        }
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
