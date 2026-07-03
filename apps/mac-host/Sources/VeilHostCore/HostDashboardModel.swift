import Foundation
import Observation

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchApp(appId: String) async throws -> WindowsAppLaunchResult
    func launchNotepad() async throws -> NotepadLaunchResult
    func focusWindow(windowId: String) async throws -> WindowFocusResponse
    func closeWindow(windowId: String) async throws -> WindowCloseResponse
    func sendMouseInput(_ input: InputMouseEvent) async throws
    func sendKeyInput(_ input: InputKeyEvent) async throws
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws
    func subscribeWindowFrames(windowId: String) async throws
    func unsubscribeWindowFrames(windowId: String) async throws
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

public enum WindowCaptureState: String, Codable, Equatable, Sendable {
    case unavailable
    case pending
    case streaming
}

public struct WindowFrameTiming: Codable, Equatable, Sendable {
    public var firstFrameReceivedAt: Date
    public var latestFrameReceivedAt: Date
    public var latestFrameIntervalMilliseconds: Int?
    public var receivedFrameCount: Int

    public init(
        firstFrameReceivedAt: Date,
        latestFrameReceivedAt: Date,
        latestFrameIntervalMilliseconds: Int? = nil,
        receivedFrameCount: Int = 1
    ) {
        self.firstFrameReceivedAt = firstFrameReceivedAt
        self.latestFrameReceivedAt = latestFrameReceivedAt
        self.latestFrameIntervalMilliseconds = latestFrameIntervalMilliseconds
        self.receivedFrameCount = receivedFrameCount
    }
}

public struct WindowMirrorSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String { window.windowId }
    public var window: WindowCreatedEvent
    public var connectionMode: HostConnectionMode
    public var captureState: WindowCaptureState
    public var latestFrame: WindowFrameEvent?
    public var frameTiming: WindowFrameTiming?

    public init(
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        captureState: WindowCaptureState,
        latestFrame: WindowFrameEvent? = nil,
        frameTiming: WindowFrameTiming? = nil
    ) {
        self.window = window
        self.connectionMode = connectionMode
        self.captureState = captureState
        self.latestFrame = latestFrame
        self.frameTiming = frameTiming
    }
}

public enum HostDashboardPhase: String, Codable, Equatable, Sendable {
    case idle
    case loading
    case connected
    case launching
    case failed
}

public enum HostProtocolMessageResult: Equatable, Sendable {
    case handledWindowCreated(windowId: String)
    case handledWindowUpdated(windowId: String)
    case handledWindowFrame(windowId: String)
    case handledWindowClosed(windowId: String)
    case handledClipboardText(sequence: Int)
    case ignored
}

public struct WindowsAppRuntimeConnectionStatus: Codable, Equatable, Sendable {
    public var mode: HostConnectionMode
    public var hasLiveAgentConnection: Bool
    public var agentVersion: String?
    public var os: String?
    public var connectionDetail: String?

    public init(
        mode: HostConnectionMode,
        hasLiveAgentConnection: Bool,
        agentVersion: String?,
        os: String?,
        connectionDetail: String?
    ) {
        self.mode = mode
        self.hasLiveAgentConnection = hasLiveAgentConnection
        self.agentVersion = agentVersion
        self.os = os
        self.connectionDetail = connectionDetail
    }
}

public struct WindowsAppRuntimeAppStatus: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var canRequestLaunch: Bool
    public var canLaunchNow: Bool

    public init(id: String, name: String, canRequestLaunch: Bool, canLaunchNow: Bool) {
        self.id = id
        self.name = name
        self.canRequestLaunch = canRequestLaunch
        self.canLaunchNow = canLaunchNow
    }
}

public struct WindowsAppRuntimeWindowStatus: Codable, Equatable, Sendable {
    public var windowId: String
    public var appId: String
    public var title: String
    public var captureState: WindowCaptureState
    public var canFocus: Bool
    public var canClose: Bool
    public var canSendInput: Bool

    public init(
        windowId: String,
        appId: String,
        title: String,
        captureState: WindowCaptureState,
        canFocus: Bool,
        canClose: Bool,
        canSendInput: Bool
    ) {
        self.windowId = windowId
        self.appId = appId
        self.title = title
        self.captureState = captureState
        self.canFocus = canFocus
        self.canClose = canClose
        self.canSendInput = canSendInput
    }
}

public struct WindowsAppRuntimeActionStatus: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var isAvailable: Bool

    public init(id: String, title: String, isAvailable: Bool) {
        self.id = id
        self.title = title
        self.isAvailable = isAvailable
    }
}

public struct WindowsAppRuntimeDockIntegrationStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var openWindowCount: Int
    public var badgeLabel: String?
    public var canOpenMainWindow: Bool
    public var canBringWindowsAppsForward: Bool
    public var canRestorePreviousApps: Bool
    public var canLaunchSelectedApp: Bool

    public init(
        isEnabled: Bool,
        openWindowCount: Int,
        badgeLabel: String?,
        canOpenMainWindow: Bool,
        canBringWindowsAppsForward: Bool,
        canRestorePreviousApps: Bool,
        canLaunchSelectedApp: Bool
    ) {
        self.isEnabled = isEnabled
        self.openWindowCount = openWindowCount
        self.badgeLabel = badgeLabel
        self.canOpenMainWindow = canOpenMainWindow
        self.canBringWindowsAppsForward = canBringWindowsAppsForward
        self.canRestorePreviousApps = canRestorePreviousApps
        self.canLaunchSelectedApp = canLaunchSelectedApp
    }
}

public struct WindowsAppRuntimeMacWindowIntegrationStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var acceptsGuestWindowEvents: Bool
    public var opensMacWindowsAutomatically: Bool
    public var hidesLauncherWhenMirroring: Bool
    public var mirroredWindowCount: Int
    public var pendingFrameWindowCount: Int
    public var streamingWindowCount: Int
    public var reason: String

    public init(
        isEnabled: Bool,
        acceptsGuestWindowEvents: Bool,
        opensMacWindowsAutomatically: Bool,
        hidesLauncherWhenMirroring: Bool,
        mirroredWindowCount: Int,
        pendingFrameWindowCount: Int,
        streamingWindowCount: Int,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.acceptsGuestWindowEvents = acceptsGuestWindowEvents
        self.opensMacWindowsAutomatically = opensMacWindowsAutomatically
        self.hidesLauncherWhenMirroring = hidesLauncherWhenMirroring
        self.mirroredWindowCount = mirroredWindowCount
        self.pendingFrameWindowCount = pendingFrameWindowCount
        self.streamingWindowCount = streamingWindowCount
        self.reason = reason
    }
}

public struct WindowsAppRuntimeQuietPolicyStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var hasOpenedAppWindowThisSession: Bool
    public var openWindowCount: Int
    public var canQuietRuntime: Bool
    public var willQuietAutomatically: Bool
    public var automaticQuietDelaySeconds: Int
    public var recommendedAction: String
    public var recommendedStopCommand: String?
    public var reason: String

    public init(
        isEnabled: Bool,
        hasOpenedAppWindowThisSession: Bool,
        openWindowCount: Int,
        canQuietRuntime: Bool,
        willQuietAutomatically: Bool,
        automaticQuietDelaySeconds: Int,
        recommendedAction: String,
        recommendedStopCommand: String? = nil,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.hasOpenedAppWindowThisSession = hasOpenedAppWindowThisSession
        self.openWindowCount = openWindowCount
        self.canQuietRuntime = canQuietRuntime
        self.willQuietAutomatically = willQuietAutomatically
        self.automaticQuietDelaySeconds = automaticQuietDelaySeconds
        self.recommendedAction = recommendedAction
        self.recommendedStopCommand = recommendedStopCommand
        self.reason = reason
    }
}

public struct WindowsAppRuntimeLaunchPlanStatus: Codable, Equatable, Sendable {
    public var selectedAppId: String?
    public var pendingLaunchAppId: String?
    public var canRequestSelectedAppLaunch: Bool
    public var canLaunchSelectedAppNow: Bool
    public var requiresRuntimeStart: Bool
    public var requiresGuestAgent: Bool
    public var recommendedAction: String
    public var recommendedStartCommand: String?
    public var recommendedWaitCommand: String?
    public var recommendedLaunchCommand: String?
    public var reason: String

    public init(
        selectedAppId: String?,
        pendingLaunchAppId: String?,
        canRequestSelectedAppLaunch: Bool,
        canLaunchSelectedAppNow: Bool,
        requiresRuntimeStart: Bool,
        requiresGuestAgent: Bool,
        recommendedAction: String,
        recommendedStartCommand: String? = nil,
        recommendedWaitCommand: String? = nil,
        recommendedLaunchCommand: String? = nil,
        reason: String
    ) {
        self.selectedAppId = selectedAppId
        self.pendingLaunchAppId = pendingLaunchAppId
        self.canRequestSelectedAppLaunch = canRequestSelectedAppLaunch
        self.canLaunchSelectedAppNow = canLaunchSelectedAppNow
        self.requiresRuntimeStart = requiresRuntimeStart
        self.requiresGuestAgent = requiresGuestAgent
        self.recommendedAction = recommendedAction
        self.recommendedStartCommand = recommendedStartCommand
        self.recommendedWaitCommand = recommendedWaitCommand
        self.recommendedLaunchCommand = recommendedLaunchCommand
        self.reason = reason
    }
}

public struct WindowsAppRuntimePendingLaunchStatus: Codable, Equatable, Sendable {
    public var isQueued: Bool
    public var appId: String?
    public var willLaunchOnAgentReconnect: Bool
    public var recommendedAction: String
    public var reason: String

    public init(
        isQueued: Bool,
        appId: String?,
        willLaunchOnAgentReconnect: Bool,
        recommendedAction: String,
        reason: String
    ) {
        self.isQueued = isQueued
        self.appId = appId
        self.willLaunchOnAgentReconnect = willLaunchOnAgentReconnect
        self.recommendedAction = recommendedAction
        self.reason = reason
    }
}

public struct WindowsAppRuntimeStatusReport: Codable, Equatable, Sendable {
    public var kind: String
    public var generatedAt: Date
    public var phase: HostDashboardPhase
    public var selectedAppId: String?
    public var pendingLaunchAppId: String?
    public var pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    public var connection: WindowsAppRuntimeConnectionStatus
    public var apps: [WindowsAppRuntimeAppStatus]
    public var mirrorSessions: [WindowsAppRuntimeWindowStatus]
    public var restorableAppIds: [String]
    public var dockIntegration: WindowsAppRuntimeDockIntegrationStatus
    public var macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus
    public var quietRuntime: WindowsAppRuntimeQuietPolicyStatus
    public var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    public var actions: [WindowsAppRuntimeActionStatus]

    public init(
        kind: String = "windowsAppRuntimeStatus",
        generatedAt: Date,
        phase: HostDashboardPhase,
        selectedAppId: String?,
        pendingLaunchAppId: String?,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        connection: WindowsAppRuntimeConnectionStatus,
        apps: [WindowsAppRuntimeAppStatus],
        mirrorSessions: [WindowsAppRuntimeWindowStatus],
        restorableAppIds: [String],
        dockIntegration: WindowsAppRuntimeDockIntegrationStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        actions: [WindowsAppRuntimeActionStatus]
    ) {
        self.kind = kind
        self.generatedAt = generatedAt
        self.phase = phase
        self.selectedAppId = selectedAppId
        self.pendingLaunchAppId = pendingLaunchAppId
        self.pendingLaunch = pendingLaunch
        self.connection = connection
        self.apps = apps
        self.mirrorSessions = mirrorSessions
        self.restorableAppIds = restorableAppIds
        self.dockIntegration = dockIntegration
        self.macWindowIntegration = macWindowIntegration
        self.quietRuntime = quietRuntime
        self.launchPlan = launchPlan
        self.actions = actions
    }
}

@MainActor
@Observable
public final class HostDashboardModel {
    public private(set) var phase: HostDashboardPhase = .idle
    public private(set) var health: AgentHealthResponse?
    public private(set) var apps: [WindowsApp] = []
    public private(set) var lastLaunch: NotepadLaunchResult?
    public private(set) var activeWindows: [WindowCreatedEvent] = []
    public private(set) var mirrorSessions: [WindowMirrorSession] = []
    public private(set) var errorMessage: String?
    public private(set) var connectionMode: HostConnectionMode = .agent
    public private(set) var connectionDetail: String?
    public private(set) var agentDiagnostic: AgentConnectionDiagnostic?
    public private(set) var pendingLaunchAppId: String?
    public private(set) var clipboardSequence = 0
    public private(set) var latestGuestClipboardText: String?
    public private(set) var lastGuestClipboardSequence = 0
    public private(set) var restorableAppIds: [String] = []
    public private(set) var hasOpenedAppWindowThisSession = false
    public var selectedAppId: String?

    private let service: any HostDashboardService
    private let restoreIntentStore: any WindowRestoreIntentStore
    private let pendingLaunchIntentStore: any PendingLaunchIntentStore
    private let automaticQuietDelaySeconds = 8

    public init(
        service: any HostDashboardService,
        restoreIntentStore: any WindowRestoreIntentStore = JSONWindowRestoreIntentStore(),
        pendingLaunchIntentStore: any PendingLaunchIntentStore = JSONPendingLaunchIntentStore()
    ) {
        self.service = service
        self.restoreIntentStore = restoreIntentStore
        self.pendingLaunchIntentStore = pendingLaunchIntentStore
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

    public var hasLiveAgentConnection: Bool {
        phase == .connected && connectionMode == .agent && health != nil
    }

    public var canCloseAllMirrorSessions: Bool {
        !mirrorSessions.isEmpty && phase != .loading
    }

    public var canSendHostClipboardText: Bool {
        hasLiveAgentConnection && health?.capabilities.clipboardText == true
    }

    public var canRestoreMirrorSessions: Bool {
        hasLiveAgentConnection
            && !restorableAppIds.isEmpty
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

    public func runtimeStatusReport(generatedAt: Date = Date()) -> WindowsAppRuntimeStatusReport {
        let quietRuntime = quietRuntimeStatus()
        let macWindowIntegration = macWindowIntegrationStatus()
        let launchPlan = launchPlanStatus()
        let pendingLaunch = pendingLaunchStatus()
        let canFulfillPendingLaunch = pendingLaunch.appId.map { canLaunchApp(appId: $0) } ?? false
        return WindowsAppRuntimeStatusReport(
            generatedAt: generatedAt,
            phase: phase,
            selectedAppId: selectedAppId,
            pendingLaunchAppId: pendingLaunchAppId,
            pendingLaunch: pendingLaunch,
            connection: WindowsAppRuntimeConnectionStatus(
                mode: connectionMode,
                hasLiveAgentConnection: hasLiveAgentConnection,
                agentVersion: health?.agentVersion,
                os: health?.os,
                connectionDetail: connectionDetail
            ),
            apps: apps.map { app in
                WindowsAppRuntimeAppStatus(
                    id: app.id,
                    name: app.name,
                    canRequestLaunch: canRequestAppLaunch(appId: app.id),
                    canLaunchNow: canLaunchApp(appId: app.id)
                )
            },
            mirrorSessions: mirrorSessions.map { session in
                WindowsAppRuntimeWindowStatus(
                    windowId: session.id,
                    appId: session.window.appId,
                    title: session.window.title,
                    captureState: session.captureState,
                    canFocus: canFocusMirrorSession(windowId: session.id),
                    canClose: canCloseMirrorSession(windowId: session.id),
                    canSendInput: canSendInput(to: session.id)
                )
            },
            restorableAppIds: restorableAppIds,
            dockIntegration: WindowsAppRuntimeDockIntegrationStatus(
                isEnabled: true,
                openWindowCount: mirrorSessions.count,
                badgeLabel: mirrorSessions.isEmpty ? nil : "\(mirrorSessions.count)",
                canOpenMainWindow: true,
                canBringWindowsAppsForward: !mirrorSessions.isEmpty,
                canRestorePreviousApps: canRestoreMirrorSessions,
                canLaunchSelectedApp: canRequestSelectedAppLaunch
            ),
            macWindowIntegration: macWindowIntegration,
            quietRuntime: quietRuntime,
            launchPlan: launchPlan,
            actions: [
                WindowsAppRuntimeActionStatus(
                    id: "dock.openMainWindow",
                    title: "Open Veil From Dock",
                    isAvailable: true
                ),
                WindowsAppRuntimeActionStatus(
                    id: "dock.bringWindowsAppsForward",
                    title: "Bring Windows Apps Forward",
                    isAvailable: !mirrorSessions.isEmpty
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.restorePrevious",
                    title: "Restore Previous Apps",
                    isAvailable: canRestoreMirrorSessions
                ),
                WindowsAppRuntimeActionStatus(
                    id: "windowsApps.closeAll",
                    title: "Close All Windows Apps",
                    isAvailable: canCloseAllMirrorSessions
                ),
                WindowsAppRuntimeActionStatus(
                    id: "macWindows.autoOpen",
                    title: "Auto Open Windows App Windows",
                    isAvailable: macWindowIntegration.acceptsGuestWindowEvents
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.startWindowsForApp",
                    title: "Start Windows For App Launch",
                    isAvailable: launchPlan.requiresRuntimeStart
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.fulfillPendingLaunch",
                    title: "Open Queued Windows App",
                    isAvailable: pendingLaunch.isQueued && canFulfillPendingLaunch
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.quietWhenIdle",
                    title: "Quiet Runtime When Idle",
                    isAvailable: quietRuntime.canQuietRuntime
                ),
                WindowsAppRuntimeActionStatus(
                    id: "clipboard.setText",
                    title: "Set Windows Clipboard Text",
                    isAvailable: canSendHostClipboardText
                )
            ]
        )
    }

    public func pendingLaunchStatus() -> WindowsAppRuntimePendingLaunchStatus {
        guard let pendingLaunchAppId else {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: false,
                appId: nil,
                willLaunchOnAgentReconnect: false,
                recommendedAction: "none",
                reason: "No Windows app launch is queued."
            )
        }

        let appCanBeRequested = canRequestAppLaunch(appId: pendingLaunchAppId)
        if hasLiveAgentConnection && canLaunchApp(appId: pendingLaunchAppId) {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: true,
                appId: pendingLaunchAppId,
                willLaunchOnAgentReconnect: false,
                recommendedAction: "launch-pending-now",
                reason: "The live Windows agent is connected; retry the queued app launch now."
            )
        }

        if appCanBeRequested && !hasLiveAgentConnection {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: true,
                appId: pendingLaunchAppId,
                willLaunchOnAgentReconnect: true,
                recommendedAction: "auto-launch-on-agent-reconnect",
                reason: "Veil will launch the queued Windows app after the guest agent reconnects."
            )
        }

        return WindowsAppRuntimePendingLaunchStatus(
            isQueued: true,
            appId: pendingLaunchAppId,
            willLaunchOnAgentReconnect: false,
            recommendedAction: "select-supported-app",
            reason: "The queued Windows app is not available in the current app catalog."
        )
    }

    public func launchPlanStatus() -> WindowsAppRuntimeLaunchPlanStatus {
        guard let selectedAppId else {
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: nil,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: false,
                canLaunchSelectedAppNow: false,
                requiresRuntimeStart: false,
                requiresGuestAgent: false,
                recommendedAction: "select-app",
                reason: "Select a Windows app before opening the app runtime."
            )
        }

        let canRequest = canRequestAppLaunch(appId: selectedAppId)
        let canLaunchNow = canLaunchApp(appId: selectedAppId)
        let launchCommand = "veil-vmctl app-runtime-action --json --action launch --app-id \(selectedAppId)"
        let fulfillPendingCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending"
        let hasPendingSelectedAppLaunch = pendingLaunchAppId == selectedAppId

        if canLaunchNow {
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: selectedAppId,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: canRequest,
                canLaunchSelectedAppNow: true,
                requiresRuntimeStart: false,
                requiresGuestAgent: false,
                recommendedAction: hasPendingSelectedAppLaunch ? "fulfill-pending-now" : "launch-now",
                recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                reason: hasPendingSelectedAppLaunch
                    ? "The live Windows agent can fulfill the queued app launch now."
                    : "The live Windows agent can launch the selected app now."
            )
        }

        if canRequest {
            let recommendedAction = hasPendingSelectedAppLaunch
                ? "start-runtime-for-pending-launch"
                : "start-runtime-and-wait-for-agent"
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: selectedAppId,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: true,
                canLaunchSelectedAppNow: false,
                requiresRuntimeStart: !hasLiveAgentConnection,
                requiresGuestAgent: !hasLiveAgentConnection,
                recommendedAction: recommendedAction,
                recommendedStartCommand: hasLiveAgentConnection ? nil : "veil-vmctl qemu-start --json --wait-seconds 30",
                recommendedWaitCommand: hasLiveAgentConnection ? nil : "veil-vmctl guest-agent-wait --json --wait-seconds 30",
                recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                reason: hasPendingSelectedAppLaunch
                    ? "The selected app launch is queued until Windows starts and the guest agent connects."
                    : "Start Windows, wait for the guest agent, then launch the selected app."
            )
        }

        return WindowsAppRuntimeLaunchPlanStatus(
            selectedAppId: selectedAppId,
            pendingLaunchAppId: pendingLaunchAppId,
            canRequestSelectedAppLaunch: false,
            canLaunchSelectedAppNow: false,
            requiresRuntimeStart: false,
            requiresGuestAgent: !hasLiveAgentConnection,
            recommendedAction: "unavailable",
            recommendedWaitCommand: hasLiveAgentConnection ? nil : "veil-vmctl guest-agent-wait --json --wait-seconds 30",
            reason: "The selected Windows app is not available for launch."
        )
    }

    public func quietRuntimeStatus() -> WindowsAppRuntimeQuietPolicyStatus {
        let recommendedAction: String
        let reason: String

        if !hasOpenedAppWindowThisSession {
            recommendedAction = "none"
            reason = "No Windows app window has opened in this host session."
        } else if !mirrorSessions.isEmpty {
            recommendedAction = "keep-running"
            reason = "Windows app windows are still open."
        } else if canQuietRuntimeWhenIdle {
            recommendedAction = "stop-or-suspend-runtime"
            reason = "All Windows app windows are closed and the live agent is connected."
        } else {
            recommendedAction = "wait-for-agent"
            reason = "Wait for a live Windows agent before quieting the runtime."
        }

        return WindowsAppRuntimeQuietPolicyStatus(
            isEnabled: true,
            hasOpenedAppWindowThisSession: hasOpenedAppWindowThisSession,
            openWindowCount: mirrorSessions.count,
            canQuietRuntime: canQuietRuntimeWhenIdle,
            willQuietAutomatically: canQuietRuntimeWhenIdle,
            automaticQuietDelaySeconds: automaticQuietDelaySeconds,
            recommendedAction: recommendedAction,
            recommendedStopCommand: canQuietRuntimeWhenIdle ? "veil-vmctl qemu-powerdown --json --wait-seconds 30" : nil,
            reason: reason
        )
    }

    public func macWindowIntegrationStatus() -> WindowsAppRuntimeMacWindowIntegrationStatus {
        let pendingFrameWindowCount = mirrorSessions.filter { $0.captureState == .pending }.count
        let streamingWindowCount = mirrorSessions.filter { $0.captureState == .streaming }.count
        let reason: String

        if !hasLiveAgentConnection {
            reason = "Waiting for the live Windows agent before guest HWND events can open macOS windows automatically."
        } else if mirrorSessions.isEmpty {
            reason = "Ready to open the next guest HWND as a macOS window."
        } else {
            reason = "Guest HWND sessions are mirrored as macOS windows."
        }

        return WindowsAppRuntimeMacWindowIntegrationStatus(
            isEnabled: true,
            acceptsGuestWindowEvents: hasLiveAgentConnection,
            opensMacWindowsAutomatically: true,
            hidesLauncherWhenMirroring: hasLiveAgentConnection && !mirrorSessions.isEmpty,
            mirroredWindowCount: mirrorSessions.count,
            pendingFrameWindowCount: pendingFrameWindowCount,
            streamingWindowCount: streamingWindowCount,
            reason: reason
        )
    }

    public var guestAgentInstallEvidence: VMInstallEvidenceSummary? {
        guard hasLiveAgentConnection, let health else {
            return nil
        }

        return VMInstallEvidenceSummary(
            kind: .guestAgent,
            isInstalled: true,
            title: "Guest agent connected",
            detail: "Windows is running the Veil guest agent \(health.agentVersion) over the local runtime channel."
        )
    }

    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            let overview = try await service.loadOverview()
            health = overview.health
            apps = overview.apps
            connectionMode = overview.connectionMode
            connectionDetail = overview.connectionDetail
            agentDiagnostic = overview.agentDiagnostic
            selectDefaultAppIfNeeded()
            phase = .connected
        } catch {
            errorMessage = userMessage(for: error)
            agentDiagnostic = AgentConnectionDiagnostic.unavailable(
                endpoint: "configured Windows agent",
                errorMessage: userMessage(for: error)
            )
            phase = .failed
        }
    }

    public func refreshLiveAgentIfNeeded() async -> NotepadLaunchResult? {
        if hasLiveAgentConnection,
           let pendingAppId = pendingLaunchAppId {
            return await launchApp(appId: pendingAppId)
        }

        if hasLiveAgentConnection {
            return nil
        }

        await load()

        if hasLiveAgentConnection,
           let pendingAppId = pendingLaunchAppId {
            return await launchApp(appId: pendingAppId)
        }

        return nil
    }

    public func loadRestoreIntent() async {
        do {
            restorableAppIds = try await restoreIntentStore.load()?.appIds ?? []
            pendingLaunchAppId = try await pendingLaunchIntentStore.load()?.appId
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func restoreMirroredWindowsAfterReconnect() async -> [NotepadLaunchResult] {
        guard !restorableAppIds.isEmpty else {
            return []
        }

        if !hasLiveAgentConnection {
            await load()
        }

        guard hasLiveAgentConnection else {
            return []
        }

        var restored: [NotepadLaunchResult] = []
        for appId in restorableAppIds {
            if let result = await launchApp(appId: appId) {
                restored.append(result)
            }
        }

        return restored
    }

    public func launchSelectedApp() async {
        guard selectedApp != nil else {
            errorMessage = "Select an app before launching."
            phase = .failed
            return
        }

        guard hasLiveAgentConnection else {
            await queuePendingLaunchIntent(appId: selectedAppId)
            errorMessage = nil
            return
        }

        guard let selectedAppId, canLaunchSelectedApp else {
            errorMessage = "The selected Windows app is not available."
            phase = .failed
            return
        }

        _ = await launchApp(appId: selectedAppId)
    }

    @discardableResult
    public func launchNotepad() async -> NotepadLaunchResult? {
        await launchApp(appId: "winapp_notepad")
    }

    @discardableResult
    public func launchApp(appId: String) async -> WindowsAppLaunchResult? {
        phase = .launching
        errorMessage = nil

        do {
            let result = try await service.launchApp(appId: appId)
            health = result.health
            apps = result.apps
            connectionMode = result.connectionMode
            connectionDetail = result.connectionDetail
            agentDiagnostic = result.connectionMode == .agent
                ? AgentConnectionDiagnostic.connected(endpoint: "configured Windows agent", health: result.health)
                : agentDiagnostic
            selectedAppId = result.window.appId
            lastLaunch = result
            if pendingLaunchAppId == result.window.appId {
                await clearPendingLaunchIntent()
            }
            await rememberRestorableAppId(result.window.appId)
            storeActiveWindow(result.window)
            storeMirrorSession(
                window: result.window,
                connectionMode: result.connectionMode,
                supportsCapture: result.health.capabilities.windowCapture
            )
            if result.connectionMode == .agent,
               result.health.capabilities.windowCapture {
                try await service.subscribeWindowFrames(windowId: result.window.windowId)
            }
            phase = .connected
            return result
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    public func receiveWindowFrame(_ frame: WindowFrameEvent, receivedAt: Date = Date()) {
        guard let index = mirrorSessions.firstIndex(where: { $0.id == frame.windowId }) else {
            return
        }

        let priorTiming = mirrorSessions[index].frameTiming
        mirrorSessions[index].latestFrame = frame
        mirrorSessions[index].captureState = .streaming
        mirrorSessions[index].frameTiming = WindowFrameTiming(
            firstFrameReceivedAt: priorTiming?.firstFrameReceivedAt ?? receivedAt,
            latestFrameReceivedAt: receivedAt,
            latestFrameIntervalMilliseconds: priorTiming.map {
                max(0, Int((receivedAt.timeIntervalSince($0.latestFrameReceivedAt) * 1000).rounded()))
            },
            receivedFrameCount: (priorTiming?.receivedFrameCount ?? 0) + 1
        )
    }

    @discardableResult
    public func focusMirrorSession(windowId: String) async -> WindowFocusResponse? {
        guard canFocusMirrorSession(windowId: windowId) else {
            return nil
        }

        do {
            let response: WindowFocusResponse
            if hasLiveAgentConnection {
                response = try await service.focusWindow(windowId: windowId)
            } else {
                response = WindowFocusResponse(
                    requestId: "local_focus_window",
                    windowId: windowId,
                    accepted: true
                )
            }

            if response.accepted {
                markFocusedWindow(windowId: windowId)
            }
            return response
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    @discardableResult
    public func closeMirrorSession(windowId: String) async -> WindowCloseResponse? {
        guard canCloseMirrorSession(windowId: windowId) else {
            return nil
        }

        do {
            if let session = mirrorSessions.first(where: { $0.id == windowId }),
               session.captureState != .unavailable,
               hasLiveAgentConnection {
                try await service.unsubscribeWindowFrames(windowId: windowId)
            }
            let response = try await service.closeWindow(windowId: windowId)
            if response.accepted {
                await removeWindowState(windowId: windowId)
            }
            return response
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    @discardableResult
    public func closeAllMirrorSessions() async -> [WindowCloseResponse] {
        let windowIds = mirrorSessions.map(\.id)
        var responses: [WindowCloseResponse] = []

        for windowId in windowIds {
            guard let response = await closeMirrorSession(windowId: windowId) else {
                continue
            }

            responses.append(response)
        }

        return responses
    }

    public func sendMouseInput(
        windowId: String,
        event: String,
        x: Int,
        y: Int,
        modifiers: [String] = []
    ) async {
        guard canSendInput(to: windowId) else {
            return
        }

        do {
            try await service.sendMouseInput(
                InputMouseEvent(windowId: windowId, event: event, x: x, y: y, modifiers: modifiers)
            )
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func sendKeyInput(
        windowId: String,
        event: String,
        key: String,
        windowsVirtualKey: Int,
        modifiers: [String] = []
    ) async {
        guard canSendInput(to: windowId) else {
            return
        }

        do {
            try await service.sendKeyInput(
                InputKeyEvent(
                    windowId: windowId,
                    event: event,
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            )
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func sendHostClipboardText(_ text: String) async {
        guard canSendHostClipboardText else {
            return
        }

        let nextSequence = clipboardSequence + 1
        do {
            try await service.sendClipboardText(
                ClipboardTextSet(
                    requestId: "req_clipboard_\(nextSequence)",
                    origin: "host",
                    sequence: nextSequence,
                    text: text
                )
            )
            clipboardSequence = nextSequence
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func receiveClipboardText(_ clipboard: ClipboardTextSet) -> Bool {
        guard clipboard.origin == "guest",
              clipboard.sequence > lastGuestClipboardSequence else {
            return false
        }

        latestGuestClipboardText = clipboard.text
        lastGuestClipboardSequence = clipboard.sequence
        return true
    }

    public func receiveProtocolMessage(
        _ message: Data,
        decoder: JSONDecoder = .veilProtocol
    ) async throws -> HostProtocolMessageResult {
        let envelope = try decoder.decode(ProtocolMessageEnvelope.self, from: message)

        switch envelope.type {
        case .windowCreated:
            let event = try decoder.decode(WindowCreatedEvent.self, from: message)
            storeActiveWindow(event)
            storeMirrorSession(
                window: event,
                connectionMode: connectionMode,
                supportsCapture: hasLiveAgentConnection && health?.capabilities.windowCapture == true
            )
            await rememberRestorableAppId(event.appId)
            if hasLiveAgentConnection, health?.capabilities.windowCapture == true {
                do {
                    try await service.subscribeWindowFrames(windowId: event.windowId)
                } catch {
                    errorMessage = userMessage(for: error)
                    phase = .failed
                }
            }
            return .handledWindowCreated(windowId: event.windowId)
        case .windowUpdated:
            let event = try decoder.decode(WindowUpdatedEvent.self, from: message)
            let window = WindowCreatedEvent(updated: event)
            guard updateWindowState(window) else {
                return .ignored
            }

            return .handledWindowUpdated(windowId: event.windowId)
        case .windowFrame:
            let frame = try decoder.decode(WindowFrameEvent.self, from: message)
            receiveWindowFrame(frame)
            return mirrorSessions.contains(where: { $0.id == frame.windowId && $0.latestFrame == frame })
                ? .handledWindowFrame(windowId: frame.windowId)
                : .ignored
        case .windowClosed:
            let event = try decoder.decode(WindowClosedEvent.self, from: message)
            guard activeWindows.contains(where: { $0.windowId == event.windowId })
                    || mirrorSessions.contains(where: { $0.id == event.windowId }) else {
                return .ignored
            }

            await removeWindowState(windowId: event.windowId)
            return .handledWindowClosed(windowId: event.windowId)
        case .clipboardTextSet:
            let clipboard = try decoder.decode(ClipboardTextSet.self, from: message)
            return receiveClipboardText(clipboard)
                ? .handledClipboardText(sequence: clipboard.sequence)
                : .ignored
        default:
            return .ignored
        }
    }

    public func consumeProtocolMessages(
        from source: any HostEventSource,
        onMessageHandled: @MainActor (HostProtocolMessageResult) -> Void = { _ in }
    ) async {
        do {
            for try await message in source.eventMessages() {
                let result = try await receiveProtocolMessage(message)
                onMessageHandled(result)
            }
        } catch {
            return
        }
    }

    private func storeActiveWindow(_ window: WindowCreatedEvent) {
        if let index = activeWindows.firstIndex(where: { $0.windowId == window.windowId }) {
            activeWindows[index] = window
            return
        }

        activeWindows.append(window)
    }

    private func storeMirrorSession(
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        supportsCapture: Bool
    ) {
        let captureState: WindowCaptureState = connectionMode == .agent && supportsCapture ? .pending : .unavailable
        hasOpenedAppWindowThisSession = true
        let session = WindowMirrorSession(
            window: window,
            connectionMode: connectionMode,
            captureState: captureState
        )

        if let index = mirrorSessions.firstIndex(where: { $0.id == session.id }) {
            mirrorSessions[index] = session
            return
        }

        mirrorSessions.append(session)
    }

    private func updateWindowState(_ window: WindowCreatedEvent) -> Bool {
        let isTracked = activeWindows.contains { $0.windowId == window.windowId }
            || mirrorSessions.contains { $0.id == window.windowId }
        guard isTracked else {
            return false
        }

        storeActiveWindow(window)

        guard let index = mirrorSessions.firstIndex(where: { $0.id == window.windowId }) else {
            return true
        }

        mirrorSessions[index].window = window
        return true
    }

    private func markFocusedWindow(windowId: String) {
        activeWindows = activeWindows.map { window in
            var focusedWindow = window
            focusedWindow.focused = window.windowId == windowId
            return focusedWindow
        }

        mirrorSessions = mirrorSessions.map { session in
            var focusedSession = session
            focusedSession.window.focused = session.id == windowId
            return focusedSession
        }
    }

    private func removeWindowState(windowId: String) async {
        let removedAppIds = Set(
            activeWindows
                .filter { $0.windowId == windowId }
                .map(\.appId)
            + mirrorSessions
                .filter { $0.id == windowId }
                .map(\.window.appId)
        )
        activeWindows.removeAll { $0.windowId == windowId }
        mirrorSessions.removeAll { $0.id == windowId }

        if lastLaunch?.window.windowId == windowId {
            lastLaunch = nil
        }

        for appId in removedAppIds {
            await forgetRestorableAppId(appId)
        }
    }

    private func rememberRestorableAppId(_ appId: String) async {
        if !restorableAppIds.contains(appId) {
            restorableAppIds.append(appId)
        }

        await persistRestoreIntent()
    }

    private func forgetRestorableAppId(_ appId: String) async {
        restorableAppIds.removeAll { $0 == appId }
        await persistRestoreIntent()
    }

    private func persistRestoreIntent() async {
        do {
            try await restoreIntentStore.save(WindowRestoreIntent(appIds: restorableAppIds))
        } catch {
            errorMessage = userMessage(for: error)
            return
        }
    }

    private func queuePendingLaunchIntent(appId: String?) async {
        pendingLaunchAppId = appId
        await persistPendingLaunchIntent()
    }

    private func clearPendingLaunchIntent() async {
        pendingLaunchAppId = nil
        await persistPendingLaunchIntent()
    }

    private func persistPendingLaunchIntent() async {
        do {
            try await pendingLaunchIntentStore.save(PendingLaunchIntent(appId: pendingLaunchAppId))
        } catch {
            errorMessage = userMessage(for: error)
            return
        }
    }

    private func selectDefaultAppIfNeeded() {
        if let selectedAppId, apps.contains(where: { $0.id == selectedAppId }) {
            return
        }

        selectedAppId = apps.first?.id
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
