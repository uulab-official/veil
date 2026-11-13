import Foundation

public enum MessageType: String, Codable, Sendable {
    case agentHealthRequest = "agent.health.request"
    case agentHealthResponse = "agent.health.response"
    case appListRequest = "app.list.request"
    case appListResponse = "app.list.response"
    case appLaunchRequest = "app.launch.request"
    case appLaunchResponse = "app.launch.response"
    case fileOpenRequest = "file.open.request"
    case sharedFileOpenRequest = "file.open.shared.request"
    case fileOpenResponse = "file.open.response"
    case windowCreated = "window.created"
    case windowListRequest = "window.list.request"
    case windowListResponse = "window.list.response"
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
    case displayResizeRequest = "display.resize.request"
    case displayResizeResponse = "display.resize.response"
    case displayScaleRequest = "display.scale.request"
    case displayScaleResponse = "display.scale.response"
    case systemShutdownRequest = "system.shutdown.request"
    case systemShutdownResponse = "system.shutdown.response"
    case windowLayout = "window.layout"
    case windowCropSet = "window.crop.set"
    case windowMoveRequest = "window.move.request"
    case clipboardTextSet = "clipboard.text.set"
    case clipboardImageSet = "clipboard.image.set"
    case clipboardFilesSet = "clipboard.files.set"
    case notificationListenerRequest = "notification.listener.request"
    case notificationListenerResponse = "notification.listener.response"
    case notificationReceived = "notification.received"
    case sharedFolderRequest = "shared.folder.request"
    case sharedFolderResponse = "shared.folder.response"
    case timeSyncRequest = "time.sync.request"
    case timeSyncResponse = "time.sync.response"
    case appearanceSetRequest = "appearance.set.request"
    case appearanceSetResponse = "appearance.set.response"
    case visualEffectsSetRequest = "visual.effects.set.request"
    case visualEffectsSetResponse = "visual.effects.set.response"
    case toolsUpdateRequest = "tools.update.request"
    case toolsUpdateResponse = "tools.update.response"
    case hostFolderMountRequest = "host.folder.mount.request"
    case hostFolderMountResponse = "host.folder.mount.response"
    case hostFolderUnmountRequest = "host.folder.unmount.request"
    case hostFolderUnmountResponse = "host.folder.unmount.response"
    case inputText = "input.text"
    case inputImeSet = "input.ime.set"
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
    /// True when the guest agent can ask Windows to change the active desktop display mode.
    /// Optional so older agents keep the RFB aspect-fit fallback.
    public var displayResize: Bool? = nil
    /// True when the agent accepts `display.scale.request`, so Windows can run at the Mac's backing scale.
    /// Optional so an older agent decodes as `nil` and the guest display stays at one pixel per point.
    public var displayScale: Bool? = nil
    /// True when Windows has the virtio-win VirtIO GPU display driver (`viogpudo`) installed, so the
    /// VM can boot on `virtio-gpu-pci` alone. Optional so an older agent decodes as `nil` and the VM keeps
    /// the `ramfb` display it boots with today.
    public var virtioGpuDisplay: Bool? = nil
    /// True when the agent accepts `system.shutdown.request`. Optional so an older agent decodes as
    /// `nil` and the host presses the ACPI power button instead.
    public var systemShutdown: Bool? = nil
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
    /// True when the agent acknowledges the fire-and-forget messages (`input.mouse`, `input.key`,
    /// `input.text`, `clipboard.text.set`, frame subscribe/unsubscribe) with an `operation.ack`
    /// reply, and reports their failures as `error` frames the host can read.
    ///
    /// Optional so an agent that predates acknowledgements decodes as `nil` and the host keeps the
    /// fire-and-forget semantics it was built on instead of waiting on a reply that never comes.
    public var operationAcks: Bool? = nil
    /// True when the agent accepts and broadcasts `clipboard.image.set`.
    ///
    /// Optional so an older agent decodes as `nil` and image clipboards stay on the Mac instead of being
    /// sent as a message the agent would answer with `unknown_message_type`.
    public var clipboardImage: Bool? = nil
    /// True when the agent can place shared-folder files on the Windows clipboard (`clipboard.files.set`).
    public var clipboardFiles: Bool? = nil
    /// True when the agent sends `window.layout`, so the host can crop windows out of the guest display.
    /// Optional so an older agent decodes as `nil` and every window keeps its `window.frame` stream.
    public var windowLayout: Bool? = nil
    /// True when the agent understands `time.sync.request`. Optional so an older agent decodes as `nil`
    /// and is never sent a message it would answer with `unknown_message_type`.
    public var timeSync: Bool? = nil
    /// True when the agent understands `appearance.set.request`. Optional for the same reason.
    public var appearanceSync: Bool? = nil
    /// The agent can turn Windows' transparency and animations down (`visual.effects.set.request`).
    public var visualEffects: Bool? = nil
    /// True when `input.text` accepts `replaceLength`, so an open IME composition can be shown in the guest.
    public var textComposition: Bool? = nil
    /// True when the agent understands `input.ime.set`, so the Windows IME can follow the macOS input source.
    public var imeMode: Bool? = nil
    /// True when the agent maps a Mac folder served over WebDAV (`host.folder.mount.request`).
    public var hostFolder: Bool? = nil
    /// True when the agent reports every app window on the Windows desktop, not only windows of apps Veil
    /// launched, and answers `window.list.request`.
    public var desktopWindows: Bool? = nil
    /// True when the agent starts the tools update from the tools disc itself (`tools.update.request`), so
    /// the host does not type a command into Windows.
    public var toolsUpdate: Bool? = nil
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

/// Why the host is asking the guest to check its clock. Diagnostic only: the guest applies one policy.
public enum GuestTimeSyncReason: String, Codable, Equatable, Sendable {
    case agentConnected = "agent-connected"
    case macWake = "mac-wake"
    case vmResume = "vm-resume"
    case manual
}

/// Tells the guest what time it is. Windows keeps its own clock after boot, so a resumed session or a
/// long Mac sleep otherwise leaves it stale.
public struct TimeSyncRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    /// ISO 8601 UTC with milliseconds and a `Z` suffix, which is the only shape the guest accepts.
    public var hostUtc: String
    public var reason: GuestTimeSyncReason

    public init(requestId: String, hostUtc: Date, reason: GuestTimeSyncReason, protocolVersion: Int = 1) {
        self.type = .timeSyncRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.hostUtc = Self.format(hostUtc)
        self.reason = reason
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

public enum GuestTimeSyncOutcome: String, Codable, Equatable, Sendable {
    case inSync = "in-sync"
    case corrected
    case resyncRequested = "resync-requested"
    case failed
    case unsupported
    case invalidRequest = "invalid-request"
}

public struct GuestTimeSyncStatus: Codable, Equatable, Sendable {
    public var isSupported: Bool
    public var guestUtcBefore: String?
    /// `hostUtc - guestUtcBefore`. Positive means Windows was behind.
    public var skewMilliseconds: Int?
    public var thresholdMilliseconds: Int
    public var outcome: GuestTimeSyncOutcome
    public var method: String
    public var requiresElevation: Bool
    public var recommendedAction: String
    public var message: String?

    public init(
        isSupported: Bool,
        guestUtcBefore: String? = nil,
        skewMilliseconds: Int? = nil,
        thresholdMilliseconds: Int = 2000,
        outcome: GuestTimeSyncOutcome,
        method: String,
        requiresElevation: Bool = false,
        recommendedAction: String = "none",
        message: String? = nil
    ) {
        self.isSupported = isSupported
        self.guestUtcBefore = guestUtcBefore
        self.skewMilliseconds = skewMilliseconds
        self.thresholdMilliseconds = thresholdMilliseconds
        self.outcome = outcome
        self.method = method
        self.requiresElevation = requiresElevation
        self.recommendedAction = recommendedAction
        self.message = message
    }
}

public struct TimeSyncResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var timeSync: GuestTimeSyncStatus

    public init(requestId: String, protocolVersion: Int = 1, timeSync: GuestTimeSyncStatus) {
        self.type = .timeSyncResponse
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.timeSync = timeSync
    }
}

/// The Windows IME state the host asks for: on (`native`), off (`alphanumeric`), or left to the user.
public enum GuestImeMode: String, Codable, Equatable, Sendable {
    case native
    case alphanumeric
    case unmanaged
}

/// Whether the macOS input source composes text (Korean, Japanese, Chinese) rather than being a plain layout.
public enum MacInputSourceKind {
    public static func isComposing(languages: [String], isInputMode: Bool) -> Bool {
        guard isInputMode, let primary = languages.first?.lowercased() else {
            return false
        }
        return primary.hasPrefix("ko") || primary.hasPrefix("ja") || primary.hasPrefix("zh")
    }
}

/// `input.ime.set`; see docs/protocol.md § Input IME Mode.
public struct InputImeSetRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var mode: GuestImeMode

    public init(requestId: String, mode: GuestImeMode) {
        self.type = .inputImeSet
        self.requestId = requestId
        self.mode = mode
    }
}

public enum GuestAppearanceTheme: String, Codable, Equatable, Sendable {
    case light
    case dark
}

/// Makes Windows follow the Mac's light or dark appearance.
public struct AppearanceSetRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var theme: GuestAppearanceTheme

    public init(requestId: String, theme: GuestAppearanceTheme, protocolVersion: Int = 1) {
        self.type = .appearanceSetRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.theme = theme
    }
}

public struct GuestAppearanceStatus: Codable, Equatable, Sendable {
    public var isSupported: Bool
    public var theme: GuestAppearanceTheme
    public var appsUseLightTheme: Bool
    public var systemUsesLightTheme: Bool
    public var changed: Bool
    public var broadcast: Bool
    public var message: String?

    public init(
        isSupported: Bool,
        theme: GuestAppearanceTheme,
        appsUseLightTheme: Bool,
        systemUsesLightTheme: Bool,
        changed: Bool,
        broadcast: Bool,
        message: String? = nil
    ) {
        self.isSupported = isSupported
        self.theme = theme
        self.appsUseLightTheme = appsUseLightTheme
        self.systemUsesLightTheme = systemUsesLightTheme
        self.changed = changed
        self.broadcast = broadcast
        self.message = message
    }
}

/// Maps the Mac folder Veil serves over WebDAV as a Windows drive; see docs/protocol.md § Mac Folder In Windows.
public struct HostFolderMountRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var port: Int
    public var token: String
    public var driveLetter: String
    public var label: String

    public init(requestId: String, port: Int, token: String, driveLetter: String, label: String, protocolVersion: Int = 1) {
        self.type = .hostFolderMountRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.port = port
        self.token = token
        self.driveLetter = driveLetter
        self.label = label
    }
}

public struct HostFolderUnmountRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var driveLetter: String

    public init(requestId: String, driveLetter: String, protocolVersion: Int = 1) {
        self.type = .hostFolderUnmountRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.driveLetter = driveLetter
    }
}

public struct HostFolderStatus: Codable, Equatable, Sendable {
    public var isMounted: Bool
    public var driveLetter: String
    public var uncPath: String?
    public var message: String?
}

/// Asks the agent to start the tools update from the disc in the removable drive. It names nothing to run:
/// the agent starts one fixed file from a disc with Veil's label.
public struct ToolsUpdateRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int

    public init(requestId: String = "req_tools_update", protocolVersion: Int = 1) {
        self.type = .toolsUpdateRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
    }
}

public struct ToolsUpdateResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int?
    public var accepted: Bool
    /// The file the agent started, for the log.
    public var entryPoint: String?

    public init(requestId: String, accepted: Bool, entryPoint: String? = nil, protocolVersion: Int? = 1) {
        self.type = .toolsUpdateResponse
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.accepted = accepted
        self.entryPoint = entryPoint
    }
}

public struct HostFolderMountResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var hostFolder: HostFolderStatus
}

public struct AppearanceSetResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var appearance: GuestAppearanceStatus

    public init(requestId: String, protocolVersion: Int = 1, appearance: GuestAppearanceStatus) {
        self.type = .appearanceSetResponse
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.appearance = appearance
    }
}

/// Turns Windows' transparency and animations down, or puts back what the user had.
public struct VisualEffectsSetRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var reduced: Bool

    public init(requestId: String, reduced: Bool, protocolVersion: Int = 1) {
        self.type = .visualEffectsSetRequest
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.reduced = reduced
    }
}

/// What the guest's visual effects are after a `visual.effects.set.request`.
public struct GuestVisualEffectsStatus: Codable, Equatable, Sendable {
    public var isSupported: Bool
    public var reduced: Bool
    public var transparency: Bool?
    public var windowAnimation: Bool?
    public var clientAnimation: Bool?
    public var changed: Bool
    public var message: String?

    public init(
        isSupported: Bool,
        reduced: Bool,
        transparency: Bool? = nil,
        windowAnimation: Bool? = nil,
        clientAnimation: Bool? = nil,
        changed: Bool,
        message: String? = nil
    ) {
        self.isSupported = isSupported
        self.reduced = reduced
        self.transparency = transparency
        self.windowAnimation = windowAnimation
        self.clientAnimation = clientAnimation
        self.changed = changed
        self.message = message
    }
}

public struct VisualEffectsSetResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var protocolVersion: Int
    public var visualEffects: GuestVisualEffectsStatus

    public init(requestId: String, protocolVersion: Int = 1, visualEffects: GuestVisualEffectsStatus) {
        self.type = .visualEffectsSetResponse
        self.requestId = requestId
        self.protocolVersion = protocolVersion
        self.visualEffects = visualEffects
    }
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
    /// The Start menu folder the app is in, such as `Windows Tools`; nil at the top of the Start menu.
    public var folder: String? = nil
    /// True for an app known only from an open window, such as File Explorer. It is not a Start menu entry.
    public var running: Bool? = nil

    /// Ids of apps known only from an open window start with this. The guest forgets them when its agent
    /// restarts, so they are not saved for reopening.
    public static let runningAppIdPrefix = "proc_"

    public var isStartMenuEntry: Bool { running != true }

    public init(
        id: String,
        name: String,
        exePath: String,
        publisher: String,
        iconId: String,
        iconPngBase64: String? = nil,
        folder: String? = nil,
        running: Bool? = nil
    ) {
        self.folder = folder
        self.running = running
        self.id = id
        self.name = name
        self.exePath = exePath
        self.publisher = publisher
        self.iconId = iconId
        self.iconPngBase64 = iconPngBase64
    }
}

extension WindowsApp {
    /// Decodes an app the guest described, keeping its icon only when it is a small PNG.
    ///
    /// The icon bytes go to AppKit's image decoding in the sidebar, the Dock, and the app launchers. The
    /// guest is not trusted: a "PNG" declaring tens of thousands of pixels a side decodes to gigabytes on
    /// the main thread, and bytes in another format reach whichever image parser recognizes them. An icon
    /// that fails the check is dropped and the app shows Veil's generic icon.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            exePath: try container.decode(String.self, forKey: .exePath),
            publisher: try container.decode(String.self, forKey: .publisher),
            iconId: try container.decode(String.self, forKey: .iconId),
            iconPngBase64: GuestAppIcon.validatedPNGBase64(
                try container.decodeIfPresent(String.self, forKey: .iconPngBase64)
            ),
            folder: try container.decodeIfPresent(String.self, forKey: .folder),
            running: try container.decodeIfPresent(Bool.self, forKey: .running)
        )
    }
}

/// The limits an app icon from the guest must meet before the host decodes it.
public enum GuestAppIcon {
    /// The agent sends icons of at most 256 pixels a side; this leaves room for larger ones.
    public static let maximumSide = 1_024
    public static let maximumByteCount = 1_048_576

    /// The icon as given when it is a PNG within the limits, otherwise nil.
    public static func validatedPNGBase64(_ base64: String?) -> String? {
        guard let base64,
              // Checked before decoding, so an oversized string is never expanded.
              base64.utf8.count <= maximumByteCount / 3 * 4 + 4,
              let data = Data(base64Encoded: base64),
              data.count <= maximumByteCount,
              let (width, height) = try? ClipboardImagePayload.headerDimensions(of: data),
              (1...maximumSide).contains(width),
              (1...maximumSide).contains(height) else {
            return nil
        }
        return base64
    }
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

/// Opens a file that already exists in the guest-served shared folder.
///
/// Unlike ``FileOpenRequest`` this carries no file bytes. The host copies the file into the mounted
/// shared folder, then sends the guest path. The guest still validates the path against its fixed
/// shared-folder root before launching, so a host cannot turn this convenience into arbitrary path
/// access.
public struct SharedFileOpenRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var appId: String
    public var fileName: String
    public var guestPath: String

    public init(
        requestId: String,
        appId: String,
        fileName: String,
        guestPath: String
    ) {
        self.type = .sharedFileOpenRequest
        self.requestId = requestId
        self.appId = appId
        self.fileName = fileName
        self.guestPath = guestPath
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
    /// A window without a title bar that Windows says another window owns, such as Paint's text formatting
    /// bar or a menu. Shown as a borderless overlay on its owner. Absent for ordinary windows.
    public var popup: Bool?
    /// The window that owns this one, when the guest reports it.
    public var ownerWindowId: String?
    /// False for a window Windows does not let the user resize, such as Character Map or most dialogs.
    /// Absent for resizable windows.
    public var resizable: Bool?

    public init(
        type: MessageType = .windowCreated,
        windowId: String,
        processId: Int,
        appId: String,
        title: String,
        bounds: WindowBounds,
        state: String,
        focused: Bool,
        popup: Bool? = nil,
        ownerWindowId: String? = nil,
        resizable: Bool? = nil
    ) {
        self.resizable = resizable
        self.type = type
        self.windowId = windowId
        self.processId = processId
        self.appId = appId
        self.title = title
        self.bounds = bounds
        self.state = state
        self.focused = focused
        self.popup = popup
        self.ownerWindowId = ownerWindowId
    }

    public var isPopup: Bool { popup == true }

    public var isResizable: Bool { resizable != false }

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
    /// The binary channel tile encoding this host can decode, such as `bgra-deflate`. Agents that do not know
    /// it, or hosts that omit it, use PNG.
    public var tileFormat: String?

    public init(
        type: MessageType = .windowFrameSubscribe,
        requestId: String,
        windowId: String,
        format: String = "png",
        tileFormat: String? = nil
    ) {
        self.type = type
        self.requestId = requestId
        self.windowId = windowId
        self.format = format
        self.tileFormat = tileFormat
    }
}

/// `window.move.request`: places a window's visible frame at a point on the guest display.
public struct WindowMoveRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowId: String
    public var x: Int
    public var y: Int

    public init(requestId: String, windowId: String, x: Int, y: Int) {
        self.type = .windowMoveRequest
        self.requestId = requestId
        self.windowId = windowId
        self.x = x
        self.y = y
    }
}

/// `window.crop.set`: the windows the host shows by cropping the guest framebuffer. See docs/protocol.md.
public struct WindowCropSetRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var windowIds: [String]
    /// True while the host shows apps as their own windows, so the agent hides the Windows taskbar.
    public var hidesDesktop: Bool?

    public init(requestId: String, windowIds: [String], hidesDesktop: Bool? = nil) {
        self.type = .windowCropSet
        self.requestId = requestId
        self.windowIds = windowIds
        self.hidesDesktop = hidesDesktop
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

/// Requests that the Windows agent change the active desktop display mode.
///
/// Unlike `WindowResizeRequest`, this targets the guest monitor rather than a tracked HWND. The host
/// sends this only after QEMU's RFB ExtendedDesktopSize path is explicitly rejected.
public struct DisplayResizeRequest: Codable, Equatable, Sendable {
    public static let minimumDimension = 640
    public static let maximumDimension = 3_840
    public static let maximumPixelCount = 8_294_400

    public var type: MessageType
    public var requestId: String
    public var width: Int
    public var height: Int

    public init(
        type: MessageType = .displayResizeRequest,
        requestId: String,
        width: Int,
        height: Int
    ) {
        self.type = type
        self.requestId = requestId
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

public struct DisplayResizeResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var accepted: Bool
    public var width: Int?
    public var height: Int?
    public var reason: String?

    public init(
        type: MessageType = .displayResizeResponse,
        requestId: String,
        accepted: Bool,
        width: Int? = nil,
        height: Int? = nil,
        reason: String? = nil
    ) {
        self.type = type
        self.requestId = requestId
        self.accepted = accepted
        self.width = width
        self.height = height
        self.reason = reason
    }
}

/// `display.scale.request`: sets Windows' display scale, or gives back the user's own. See docs/protocol.md.
public struct DisplayScaleRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var scalePercent: Int?
    public var restoresUserScale: Bool?

    public init(type: MessageType = .displayScaleRequest, requestId: String, scalePercent: Int?) {
        self.type = type
        self.requestId = requestId
        self.scalePercent = scalePercent
        self.restoresUserScale = scalePercent == nil ? true : nil
    }
}

public struct DisplayScaleResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var accepted: Bool
    /// The scale Windows reports after the request, which can differ from the one asked for.
    public var scalePercent: Int?
    public var reason: String?

    public init(
        type: MessageType = .displayScaleResponse,
        requestId: String,
        accepted: Bool,
        scalePercent: Int? = nil,
        reason: String? = nil
    ) {
        self.type = type
        self.requestId = requestId
        self.accepted = accepted
        self.scalePercent = scalePercent
        self.reason = reason
    }
}

/// Asks the Windows agent to shut Windows down normally. It carries no arguments on purpose.
public struct SystemShutdownRequest: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String

    public init(type: MessageType = .systemShutdownRequest, requestId: String) {
        self.type = type
        self.requestId = requestId
    }
}

public struct SystemShutdownResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var accepted: Bool
    public var reason: String?

    public init(
        type: MessageType = .systemShutdownResponse,
        requestId: String,
        accepted: Bool,
        reason: String? = nil
    ) {
        self.type = type
        self.requestId = requestId
        self.accepted = accepted
        self.reason = reason
    }
}

/// Where the Windows agent put the guest cursor for a mouse event, in the 0...32767 absolute range QEMU's USB
/// tablet uses on both axes. Carried on the `operation.ack` for `input.mouse`.
public struct GuestPointerPosition: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct InputMouseEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var event: String
    public var x: Int
    public var y: Int
    public var modifiers: [String]
    /// For `scroll`: wheel units, 120 per notch, positive scrolling right and up as Windows counts them.
    /// Omitted for every other event.
    public var deltaX: Int?
    public var deltaY: Int?

    public init(
        type: MessageType = .inputMouse,
        windowId: String,
        event: String,
        x: Int,
        y: Int,
        modifiers: [String] = [],
        deltaX: Int? = nil,
        deltaY: Int? = nil
    ) {
        self.type = type
        self.windowId = windowId
        self.event = event
        self.x = x
        self.y = y
        self.modifiers = modifiers
        self.deltaX = deltaX
        self.deltaY = deltaY
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
    /// Characters the guest deletes with Backspace before typing `text`, to correct an open IME composition.
    /// Nil, and left off the wire, for plain committed text so an agent without `textComposition` is unaffected.
    public var replaceLength: Int?

    public init(
        type: MessageType = .inputText,
        windowId: String,
        text: String,
        replaceLength: Int? = nil
    ) {
        self.type = type
        self.windowId = windowId
        self.text = text
        self.replaceLength = replaceLength
    }

    /// A composition correction: empty text is allowed when something is deleted.
    public static func isSendable(_ text: String, replaceLength: Int) -> Bool {
        guard replaceLength >= 0, replaceLength <= maximumUTF16Length else {
            return false
        }
        if text.isEmpty {
            return replaceLength > 0
        }
        return isSendable(text)
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

/// One PNG clipboard image. See `docs/protocol.md` "Clipboard Image"; ``ClipboardImagePayload`` builds and
/// verifies these, so code outside it should not read `pngBase64` directly.
public struct ClipboardImageSet: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var origin: String
    public var sequence: Int
    public var format: String
    public var width: Int
    public var height: Int
    public var byteLength: Int
    public var sha256: String
    public var pngBase64: String

    public init(
        type: MessageType = .clipboardImageSet,
        requestId: String,
        origin: String,
        sequence: Int,
        format: String = "png",
        width: Int,
        height: Int,
        byteLength: Int,
        sha256: String,
        pngBase64: String
    ) {
        self.type = type
        self.requestId = requestId
        self.origin = origin
        self.sequence = sequence
        self.format = format
        self.width = width
        self.height = height
        self.byteLength = byteLength
        self.sha256 = sha256
        self.pngBase64 = pngBase64
    }
}

/// Host-to-guest file paste. The files are already in the shared folder; this only names them, relative to
/// the share, so no host path ever crosses the protocol. See `docs/protocol.md` "Clipboard Files".
public struct ClipboardFilesSet: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var origin: String
    public var sequence: Int
    public var shareName: String
    public var relativePaths: [String]

    public init(
        type: MessageType = .clipboardFilesSet,
        requestId: String,
        origin: String = "host",
        sequence: Int,
        shareName: String,
        relativePaths: [String]
    ) {
        self.type = type
        self.requestId = requestId
        self.origin = origin
        self.sequence = sequence
        self.shareName = shareName
        self.relativePaths = relativePaths
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
