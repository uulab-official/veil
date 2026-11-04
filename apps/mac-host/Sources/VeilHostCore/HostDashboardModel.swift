import CoreGraphics
import Foundation
import Observation

public extension HostDashboardService {
    /// Default for services that predate committed text input. Throwing rather than silently
    /// succeeding keeps this out of the "silent failure" class the agent audit already covered: a
    /// swallowed no-op would look like typed Korean simply vanishing.
    func sendTextInput(_ input: InputTextEvent) async throws {
        throw HostDashboardServiceError.textInputUnsupported
    }

    func restoreApp(appId: String) async throws -> WindowsAppLaunchResult {
        try await launchApp(appId: appId)
    }

    func resizeWindow(windowId: String, width: Int, height: Int) async throws -> WindowResizeResponse {
        WindowResizeResponse(
            requestId: "unsupported_resize",
            windowId: windowId,
            accepted: false
        )
    }
}

@MainActor
@Observable
public final class HostDashboardModel {
    nonisolated public static var defaultAgentEndpoint: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

    public internal(set) var phase: HostDashboardPhase = .idle
    public internal(set) var health: AgentHealthResponse?
    public internal(set) var apps: [WindowsApp] = []
    public internal(set) var lastLaunch: NotepadLaunchResult?
    public internal(set) var activeWindows: [WindowCreatedEvent] = []
    public internal(set) var mirrorSessions: [WindowMirrorSession] = []
    public internal(set) var errorMessage: String?
    /// The most recent refused drag-and-drop, so a surface can react to the kind of refusal without
    /// matching on the prose in ``errorMessage``.
    public internal(set) var lastFileDropRefusal: WindowsAppFileDropRefusal?
    /// Windows whose frame stream is paused because nothing on screen can show it, currently minimized ones.
    ///
    /// Held here rather than as a field on `WindowMirrorSession` because that type is `Codable`, and a
    /// non-optional property added to it would make previously encoded JSON fail to decode.
    var pausedFrameStreamWindowIds: Set<String> = []
    /// Guest events cross into things the user owns — the pasteboard and Notification Center — and the guest
    /// controls both their content and their timing. Bounding one message does nothing about a megabyte every
    /// ten milliseconds.
    var guestClipboardRateLimiter = GuestEventRateLimiter.guestClipboard
    var guestNotificationRateLimiter = GuestEventRateLimiter.guestNotifications
    public internal(set) var connectionMode: HostConnectionMode = .agent
    public internal(set) var connectionDetail: String?
    public internal(set) var agentDiagnostic: AgentConnectionDiagnostic?
    public internal(set) var latestAgentWait: AgentConnectionWaitReport?
    public internal(set) var pendingLaunchAppId: String?
    public internal(set) var clipboardSequence = 0
    public internal(set) var latestGuestClipboardText: String?
    public internal(set) var lastGuestClipboardSequence = 0
    public internal(set) var latestWindowsNotifications: [WindowsNotificationReceivedEvent] = []
    public internal(set) var restorableAppIds: [String] = []
    public internal(set) var restorableAppWindowCounts: [String: Int] = [:]
    public internal(set) var hasOpenedAppWindowThisSession = false
    public var selectedAppId: String?
    public var restorableWindowCount: Int {
        // The ordinary product path restores one macOS window per app. Counts from older
        // sessions are migration/diagnostic input, not a user-visible restore queue.
        restorableAppIds.count
    }

    let service: any HostDashboardService
    let restoreIntentStore: any WindowRestoreIntentStore
    let pendingLaunchIntentStore: any PendingLaunchIntentStore
    /// Holds the authoritative full-window image per mirrored window.
    ///
    /// `@ObservationIgnored` on purpose: the pixels must not be part of observable value-type state, or
    /// every frame would copy a full-resolution bitmap through the session array. Views observe
    /// `WindowMirrorSession.compositedFrameGeneration` instead and read the image through
    /// `compositedFrameImage(for:)`.
    @ObservationIgnored let frameCompositor: WindowFrameCompositor
    /// Optional throughput/efficiency instrumentation. Absent in normal app runs; supplied by the
    /// measurement command so a bounded diagnostic run can report what the pipeline actually did.
    @ObservationIgnored let framePipelineMetrics: FramePipelineMetrics?
    @ObservationIgnored var appLaunchTasks: [String: Task<WindowsAppLaunchResult?, Never>] = [:]
    let automaticQuietDelaySeconds = 8
    /// How many windows Veil will adopt for one app from the guest's discovery stream.
    ///
    /// Bounds guest-driven window creation rather than expressing a preference. See
    /// ``shouldAdoptAdditionalWindow(_:)`` for why a bound belongs here but not on the total.
    static let maximumAdoptedWindowsPerApp = 8

    public init(
        service: any HostDashboardService,
        initialApps: [WindowsApp] = [],
        restoreIntentStore: any WindowRestoreIntentStore = JSONWindowRestoreIntentStore(),
        pendingLaunchIntentStore: any PendingLaunchIntentStore = JSONPendingLaunchIntentStore(),
        frameCompositor: WindowFrameCompositor = WindowFrameCompositor(),
        framePipelineMetrics: FramePipelineMetrics? = nil
    ) {
        self.service = service
        self.apps = initialApps
        self.selectedAppId = initialApps.first?.id
        self.restoreIntentStore = restoreIntentStore
        self.pendingLaunchIntentStore = pendingLaunchIntentStore
        self.frameCompositor = frameCompositor
        self.framePipelineMetrics = framePipelineMetrics
    }

    public var statusText: String {
        switch phase {
        case .idle:
            "Ready to connect"
        case .loading:
            "Connecting to Windows agent"
        case .connected:
            if let lastLaunch {
                connectionMode == .demo
                    ? "Demo launched \(lastLaunch.window.title)"
                    : "Launched \(lastLaunch.window.title)"
            } else if let health {
                connectionMode == .demo
                    ? "Demo mode: Windows agent unavailable"
                    : "Connected to Windows agent \(health.agentVersion)"
            } else {
                "Connected"
            }
        case .launching:
            "Launching Notepad"
        case .failed:
            errorMessage ?? "Connection failed"
        case .reconnecting:
            "Reconnecting to Windows agent"
        }
    }

    public var selectedApp: WindowsApp? {
        guard let selectedAppId else {
            return nil
        }

        return apps.first { $0.id == selectedAppId }
    }

    public var canLaunchSelectedApp: Bool {
        guard let selectedAppId else {
            return false
        }

        return canLaunchApp(appId: selectedAppId)
    }

    public var canRequestSelectedAppLaunch: Bool {
        guard let selectedAppId else {
            return false
        }

        return canRequestAppLaunch(appId: selectedAppId)
    }

    public var canFulfillPendingLaunch: Bool {
        guard let pendingLaunchAppId else {
            return false
        }

        return canLaunchApp(appId: pendingLaunchAppId)
    }

    public var hasLiveAgentConnection: Bool {
        phase == .connected && connectionMode == .agent && health != nil
    }

    public var canCloseAllMirrorSessions: Bool {
        !mirrorSessions.isEmpty && phase != .loading
    }

    public var canSendHostClipboardText: Bool {
        hasLiveAgentConnection && health?.capabilities.clipboardText == true
    }

    public var canRunAppWindowProof: Bool {
        guard let selectedAppId else {
            return false
        }

        return canLaunchApp(appId: selectedAppId)
            && health?.capabilities.windowCapture == true
    }

    public var canRunCoherenceProof: Bool {
        canRunAppWindowProof
            && health?.capabilities.input == true
            && health?.capabilities.clipboardText == true
    }

    public var canRestoreMirrorSessions: Bool {
        hasLiveAgentConnection
            && !restorableAppIds.isEmpty
            && mirrorSessions.isEmpty
            && phase != .loading
            && phase != .launching
    }

    public var canReconnectRestoreMirrorSessions: Bool {
        !restorableAppIds.isEmpty
            && mirrorSessions.isEmpty
            && phase != .loading
            && phase != .launching
    }

    public var canQuietRuntimeWhenIdle: Bool {
        hasOpenedAppWindowThisSession
            && mirrorSessions.isEmpty
            && hasLiveAgentConnection
            && phase == .connected
    }

    public func canRequestAppLaunch(appId: String) -> Bool {
        apps.contains { $0.id == appId }
            && phase != .loading
            && phase != .launching
            && (!hasLiveAgentConnection || health?.capabilities.appLaunch == true)
    }

    public func canLaunchApp(appId: String) -> Bool {
        canRequestAppLaunch(appId: appId)
            && hasLiveAgentConnection
            && health?.capabilities.appLaunch == true
    }

    public func canFocusMirrorSession(windowId: String) -> Bool {
        phase != .loading
            && (
                mirrorSessions.contains { $0.id == windowId }
                    || activeWindows.contains { $0.windowId == windowId }
            )
    }

    public func canCloseMirrorSession(windowId: String) -> Bool {
        phase != .loading
            && (
                mirrorSessions.contains { $0.id == windowId }
                    || activeWindows.contains { $0.windowId == windowId }
            )
    }

    public func canSendInput(to windowId: String) -> Bool {
        mirrorSessions.contains { $0.id == windowId }
            && hasLiveAgentConnection
            && health?.capabilities.input == true
    }

    public func canResizeMirrorSession(windowId: String) -> Bool {
        mirrorSessions.contains { $0.id == windowId }
            && hasLiveAgentConnection
            && health?.capabilities.windowResize == true
    }

}
