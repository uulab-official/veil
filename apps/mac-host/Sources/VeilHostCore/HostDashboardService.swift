import CoreGraphics
import Foundation
import Observation

public enum HostDashboardServiceError: Error, LocalizedError, Equatable, Sendable {
    case textInputUnsupported
    case clipboardFormatUnsupported
    case guestStateSyncUnsupported
    case agentEndpointUnavailable(endpoint: String, detail: String, nextActions: [String])

    public var errorDescription: String? {
        switch self {
        case .textInputUnsupported:
            "This Windows agent connection cannot accept committed text input."
        case .clipboardFormatUnsupported:
            "This Windows agent connection cannot accept images or files on the clipboard. Repair the app connection to update Veil's Windows tools."
        case .guestStateSyncUnsupported:
            "This Windows agent connection cannot sync the clock or appearance."
        case .agentEndpointUnavailable(_, let detail, _):
            detail
        }
    }
}

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchApp(appId: String) async throws -> WindowsAppLaunchResult
    func restoreApp(appId: String) async throws -> WindowsAppLaunchResult
    func launchNotepad() async throws -> NotepadLaunchResult
    func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult
    func openSharedFile(appId: String, fileName: String, guestPath: String) async throws -> WindowsAppLaunchResult
    func focusWindow(windowId: String) async throws -> WindowFocusResponse
    func closeWindow(windowId: String) async throws -> WindowCloseResponse
    func resizeWindow(windowId: String, width: Int, height: Int) async throws -> WindowResizeResponse
    func resizeDisplay(width: Int, height: Int) async throws -> DisplayResizeResponse
    /// Sets Windows' display scale to `scalePercent`, or gives back the user's own scale when it is nil.
    func setDisplayScale(scalePercent: Int?) async throws -> DisplayScaleResponse
    func requestSystemShutdown() async throws -> SystemShutdownResponse
    func sendMouseInput(_ input: InputMouseEvent) async throws
    /// Sends a mouse event and returns where the guest cursor ended up, when the agent reports it.
    func sendMouseInputReportingPointer(_ input: InputMouseEvent) async throws -> GuestPointerPosition?
    func sendKeyInput(_ input: InputKeyEvent) async throws
    func sendTextInput(_ input: InputTextEvent) async throws
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws
    func sendClipboardImage(_ clipboard: ClipboardImageSet) async throws
    func sendClipboardFiles(_ clipboard: ClipboardFilesSet) async throws
    func subscribeWindowFrames(windowId: String) async throws
    func unsubscribeWindowFrames(windowId: String) async throws
    /// Tells the agent which windows the host shows by cropping the guest framebuffer (`window.crop.set`).
    func setCroppedWindows(windowIds: [String], hidesDesktop: Bool) async throws
    /// Moves a guest window so its visible frame starts at (x, y) display pixels (`window.move.request`).
    func moveWindow(windowId: String, x: Int, y: Int) async throws
    func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport
    func syncGuestTime(hostUtc: Date, reason: GuestTimeSyncReason) async throws -> TimeSyncResponse
    func setGuestAppearance(theme: GuestAppearanceTheme) async throws -> AppearanceSetResponse
    func setGuestVisualEffects(reduced: Bool) async throws -> VisualEffectsSetResponse
    func setGuestImeMode(_ mode: GuestImeMode) async throws
    func mountHostFolder(_ request: HostFolderMountRequest) async throws -> HostFolderMountResponse
    func unmountHostFolder(_ request: HostFolderUnmountRequest) async throws -> HostFolderMountResponse
    /// Asks the agent to start the tools update from the disc in the removable drive.
    func startToolsUpdate(_ request: ToolsUpdateRequest) async throws -> ToolsUpdateResponse
}

public extension HostDashboardService {
    /// Default for services that predate committed text input. Throwing rather than silently
    /// succeeding keeps this out of the "silent failure" class the agent audit already covered: a
    /// swallowed no-op would look like typed Korean simply vanishing.
    func sendTextInput(_ input: InputTextEvent) async throws {
        throw HostDashboardServiceError.textInputUnsupported
    }

    /// Default for services that predate image and file clipboards. Throws for the same reason as
    /// `sendTextInput`: a paste shortcut after a silent no-op would paste stale Windows content.
    func sendClipboardImage(_ clipboard: ClipboardImageSet) async throws {
        throw HostDashboardServiceError.clipboardFormatUnsupported
    }

    func sendClipboardFiles(_ clipboard: ClipboardFilesSet) async throws {
        throw HostDashboardServiceError.clipboardFormatUnsupported
    }

    func restoreApp(appId: String) async throws -> WindowsAppLaunchResult {
        try await launchApp(appId: appId)
    }

    /// Default for services with no guest to sync, such as demo mode. Throwing keeps a missing
    /// implementation visible instead of looking like a guest that is already in sync.
    func syncGuestTime(hostUtc: Date, reason: GuestTimeSyncReason) async throws -> TimeSyncResponse {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func setGuestAppearance(theme: GuestAppearanceTheme) async throws -> AppearanceSetResponse {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func setGuestVisualEffects(reduced: Bool) async throws -> VisualEffectsSetResponse {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func setGuestImeMode(_ mode: GuestImeMode) async throws {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func mountHostFolder(_ request: HostFolderMountRequest) async throws -> HostFolderMountResponse {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func unmountHostFolder(_ request: HostFolderUnmountRequest) async throws -> HostFolderMountResponse {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func startToolsUpdate(_ request: ToolsUpdateRequest) async throws -> ToolsUpdateResponse {
        throw HostDashboardServiceError.guestStateSyncUnsupported
    }

    func sendMouseInputReportingPointer(_ input: InputMouseEvent) async throws -> GuestPointerPosition? {
        try await sendMouseInput(input)
        return nil
    }

    /// Default for services without a guest framebuffer. Nothing is cropped there, so nothing is lost;
    /// the list only lets the agent capture cropped windows less often.
    func setCroppedWindows(windowIds: [String], hidesDesktop: Bool) async throws {}

    /// Default for services without a guest layout to follow.
    func moveWindow(windowId: String, x: Int, y: Int) async throws {}

    func resizeWindow(windowId: String, width: Int, height: Int) async throws -> WindowResizeResponse {
        WindowResizeResponse(
            requestId: "unsupported_resize",
            windowId: windowId,
            accepted: false
        )
    }

    func resizeDisplay(width: Int, height: Int) async throws -> DisplayResizeResponse {
        DisplayResizeResponse(
            requestId: "unsupported_display_resize",
            accepted: false,
            reason: "display_resize_unsupported"
        )
    }

    func setDisplayScale(scalePercent: Int?) async throws -> DisplayScaleResponse {
        DisplayScaleResponse(
            requestId: "unsupported_display_scale",
            accepted: false,
            reason: "display_scale_unsupported"
        )
    }

    func requestSystemShutdown() async throws -> SystemShutdownResponse {
        SystemShutdownResponse(
            requestId: "unsupported_system_shutdown",
            accepted: false,
            reason: "system_shutdown_unsupported"
        )
    }
}

public struct HostOverview: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]
    public var connectionMode: HostConnectionMode
    public var connectionDetail: String?
    public var agentDiagnostic: AgentConnectionDiagnostic?

    public init(
        health: AgentHealthResponse,
        apps: [WindowsApp],
        connectionMode: HostConnectionMode = .agent,
        connectionDetail: String? = nil,
        agentDiagnostic: AgentConnectionDiagnostic? = nil
    ) {
        self.health = health
        self.apps = apps
        self.connectionMode = connectionMode
        self.connectionDetail = connectionDetail
        self.agentDiagnostic = agentDiagnostic
    }
}

public enum HostConnectionMode: String, Codable, Equatable, Sendable {
    case agent
    case demo
}
