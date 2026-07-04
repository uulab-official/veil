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
    public var capabilities: AgentCapabilities?
    public var connectionDetail: String?

    public init(
        mode: HostConnectionMode,
        hasLiveAgentConnection: Bool,
        agentVersion: String?,
        os: String?,
        capabilities: AgentCapabilities? = nil,
        connectionDetail: String?
    ) {
        self.mode = mode
        self.hasLiveAgentConnection = hasLiveAgentConnection
        self.agentVersion = agentVersion
        self.os = os
        self.capabilities = capabilities
        self.connectionDetail = connectionDetail
    }
}

public struct WindowsAppRuntimeGuestAgentDiagnosticsStatus: Codable, Equatable, Sendable {
    public var endpoint: String
    public var isConnected: Bool
    public var diagnosticCommand: String
    public var waitCommand: String
    public var recommendedAction: String
    public var reason: String

    public init(
        endpoint: String,
        isConnected: Bool,
        diagnosticCommand: String,
        waitCommand: String,
        recommendedAction: String,
        reason: String
    ) {
        self.endpoint = endpoint
        self.isConnected = isConnected
        self.diagnosticCommand = diagnosticCommand
        self.waitCommand = waitCommand
        self.recommendedAction = recommendedAction
        self.reason = reason
    }
}

public struct WindowsAppRuntimeLocalRuntimeStatus: Codable, Equatable, Sendable {
    public var isKnown: Bool
    public var state: VMRuntimeState?
    public var bootReady: Bool
    public var canStart: Bool
    public var isRunning: Bool
    public var windowsInstalled: Bool
    public var recommendedAction: String
    public var recommendedInstallStatusCommand: String
    public var recommendedPrepareCommand: String?
    public var reason: String

    public init(
        isKnown: Bool,
        state: VMRuntimeState?,
        bootReady: Bool,
        canStart: Bool,
        isRunning: Bool,
        windowsInstalled: Bool,
        recommendedAction: String,
        recommendedInstallStatusCommand: String,
        recommendedPrepareCommand: String? = nil,
        reason: String
    ) {
        self.isKnown = isKnown
        self.state = state
        self.bootReady = bootReady
        self.canStart = canStart
        self.isRunning = isRunning
        self.windowsInstalled = windowsInstalled
        self.recommendedAction = recommendedAction
        self.recommendedInstallStatusCommand = recommendedInstallStatusCommand
        self.recommendedPrepareCommand = recommendedPrepareCommand
        self.reason = reason
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
    public var pendingLaunchCount: Int
    public var badgeLabel: String?
    public var canOpenMainWindow: Bool
    public var canBringWindowsAppsForward: Bool
    public var canRestorePreviousApps: Bool
    public var canLaunchSelectedApp: Bool

    public init(
        isEnabled: Bool,
        openWindowCount: Int,
        pendingLaunchCount: Int,
        badgeLabel: String?,
        canOpenMainWindow: Bool,
        canBringWindowsAppsForward: Bool,
        canRestorePreviousApps: Bool,
        canLaunchSelectedApp: Bool
    ) {
        self.isEnabled = isEnabled
        self.openWindowCount = openWindowCount
        self.pendingLaunchCount = pendingLaunchCount
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
    public var foregroundableWindowCount: Int
    public var foregroundWindowId: String?
    public var foregroundWindowTitle: String?
    public var pendingFrameWindowCount: Int
    public var streamingWindowCount: Int
    public var reason: String

    public init(
        isEnabled: Bool,
        acceptsGuestWindowEvents: Bool,
        opensMacWindowsAutomatically: Bool,
        hidesLauncherWhenMirroring: Bool,
        mirroredWindowCount: Int,
        foregroundableWindowCount: Int,
        foregroundWindowId: String? = nil,
        foregroundWindowTitle: String? = nil,
        pendingFrameWindowCount: Int,
        streamingWindowCount: Int,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.acceptsGuestWindowEvents = acceptsGuestWindowEvents
        self.opensMacWindowsAutomatically = opensMacWindowsAutomatically
        self.hidesLauncherWhenMirroring = hidesLauncherWhenMirroring
        self.mirroredWindowCount = mirroredWindowCount
        self.foregroundableWindowCount = foregroundableWindowCount
        self.foregroundWindowId = foregroundWindowId
        self.foregroundWindowTitle = foregroundWindowTitle
        self.pendingFrameWindowCount = pendingFrameWindowCount
        self.streamingWindowCount = streamingWindowCount
        self.reason = reason
    }
}

public struct WindowsAppRuntimeLauncherVisibilityStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var canOpenMainWindow: Bool
    public var shouldHideMainWindow: Bool
    public var keepsDockMenuAvailable: Bool
    public var recommendedAction: String
    public var reason: String

    public init(
        isEnabled: Bool,
        canOpenMainWindow: Bool,
        shouldHideMainWindow: Bool,
        keepsDockMenuAvailable: Bool,
        recommendedAction: String,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.canOpenMainWindow = canOpenMainWindow
        self.shouldHideMainWindow = shouldHideMainWindow
        self.keepsDockMenuAvailable = keepsDockMenuAvailable
        self.recommendedAction = recommendedAction
        self.reason = reason
    }
}

public struct WindowsAppRuntimeVisibleSurfacePolicyStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var primarySurface: String
    public var expectedVisibleSurfaceCount: Int
    public var shouldHideLauncher: Bool
    public var keepsRecoveryDisplayManual: Bool
    public var reason: String

    public init(
        isEnabled: Bool,
        primarySurface: String,
        expectedVisibleSurfaceCount: Int,
        shouldHideLauncher: Bool,
        keepsRecoveryDisplayManual: Bool,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.primarySurface = primarySurface
        self.expectedVisibleSurfaceCount = expectedVisibleSurfaceCount
        self.shouldHideLauncher = shouldHideLauncher
        self.keepsRecoveryDisplayManual = keepsRecoveryDisplayManual
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

public struct WindowsAppRuntimeProofPlanStatus: Codable, Equatable, Sendable {
    public var selectedAppId: String?
    public var canRunAppWindowProof: Bool
    public var canRunCoherenceProof: Bool
    public var canRunMVPProof: Bool
    public var recommendedProofKind: String?
    public var recommendedProofCommand: String?
    public var recommendedAppWindowProofCommand: String?
    public var recommendedCoherenceProofCommand: String?
    public var recommendedMVPProofCommand: String?
    public var reason: String

    public init(
        selectedAppId: String?,
        canRunAppWindowProof: Bool,
        canRunCoherenceProof: Bool,
        canRunMVPProof: Bool,
        recommendedProofKind: String? = nil,
        recommendedProofCommand: String? = nil,
        recommendedAppWindowProofCommand: String? = nil,
        recommendedCoherenceProofCommand: String? = nil,
        recommendedMVPProofCommand: String? = nil,
        reason: String
    ) {
        self.selectedAppId = selectedAppId
        self.canRunAppWindowProof = canRunAppWindowProof
        self.canRunCoherenceProof = canRunCoherenceProof
        self.canRunMVPProof = canRunMVPProof
        self.recommendedProofKind = recommendedProofKind
        self.recommendedProofCommand = recommendedProofCommand
        self.recommendedAppWindowProofCommand = recommendedAppWindowProofCommand
        self.recommendedCoherenceProofCommand = recommendedCoherenceProofCommand
        self.recommendedMVPProofCommand = recommendedMVPProofCommand
        self.reason = reason
    }
}

public struct WindowsAppRuntimeProofArtifactStatus: Codable, Equatable, Sendable {
    public var diagnosticsDirectory: String
    public var recommendedProofDirectory: String
    public var latestProofKind: String?
    public var latestProofPath: String?
    public var latestProofFileName: String?
    public var latestProofModifiedAt: Date?
    public var reason: String

    public init(
        diagnosticsDirectory: String,
        recommendedProofDirectory: String,
        latestProofKind: String? = nil,
        latestProofPath: String? = nil,
        latestProofFileName: String? = nil,
        latestProofModifiedAt: Date? = nil,
        reason: String
    ) {
        self.diagnosticsDirectory = diagnosticsDirectory
        self.recommendedProofDirectory = recommendedProofDirectory
        self.latestProofKind = latestProofKind
        self.latestProofPath = latestProofPath
        self.latestProofFileName = latestProofFileName
        self.latestProofModifiedAt = latestProofModifiedAt
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
    public var guestAgentDiagnostics: WindowsAppRuntimeGuestAgentDiagnosticsStatus
    public var localRuntime: WindowsAppRuntimeLocalRuntimeStatus
    public var apps: [WindowsAppRuntimeAppStatus]
    public var mirrorSessions: [WindowsAppRuntimeWindowStatus]
    public var restorableAppIds: [String]
    public var dockIntegration: WindowsAppRuntimeDockIntegrationStatus
    public var launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus
    public var visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus
    public var macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus
    public var quietRuntime: WindowsAppRuntimeQuietPolicyStatus
    public var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    public var proofPlan: WindowsAppRuntimeProofPlanStatus
    public var proofArtifacts: WindowsAppRuntimeProofArtifactStatus
    public var actions: [WindowsAppRuntimeActionStatus]

    public init(
        kind: String = "windowsAppRuntimeStatus",
        generatedAt: Date,
        phase: HostDashboardPhase,
        selectedAppId: String?,
        pendingLaunchAppId: String?,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        connection: WindowsAppRuntimeConnectionStatus,
        guestAgentDiagnostics: WindowsAppRuntimeGuestAgentDiagnosticsStatus,
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        apps: [WindowsAppRuntimeAppStatus],
        mirrorSessions: [WindowsAppRuntimeWindowStatus],
        restorableAppIds: [String],
        dockIntegration: WindowsAppRuntimeDockIntegrationStatus,
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus,
        visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        proofPlan: WindowsAppRuntimeProofPlanStatus,
        proofArtifacts: WindowsAppRuntimeProofArtifactStatus,
        actions: [WindowsAppRuntimeActionStatus]
    ) {
        self.kind = kind
        self.generatedAt = generatedAt
        self.phase = phase
        self.selectedAppId = selectedAppId
        self.pendingLaunchAppId = pendingLaunchAppId
        self.pendingLaunch = pendingLaunch
        self.connection = connection
        self.guestAgentDiagnostics = guestAgentDiagnostics
        self.localRuntime = localRuntime
        self.apps = apps
        self.mirrorSessions = mirrorSessions
        self.restorableAppIds = restorableAppIds
        self.dockIntegration = dockIntegration
        self.launcherVisibility = launcherVisibility
        self.visibleSurfacePolicy = visibleSurfacePolicy
        self.macWindowIntegration = macWindowIntegration
        self.quietRuntime = quietRuntime
        self.launchPlan = launchPlan
        self.proofPlan = proofPlan
        self.proofArtifacts = proofArtifacts
        self.actions = actions
    }
}

private struct ProofArtifactCandidate {
    var kind: String
    var url: URL
    var modifiedAt: Date
}

@MainActor
@Observable
public final class HostDashboardModel {
    public static var defaultAgentEndpoint: String {
        ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
    }

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

    public func runtimeStatusReport(
        generatedAt: Date = Date(),
        agentEndpoint: String = HostDashboardModel.defaultAgentEndpoint,
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil
    ) -> WindowsAppRuntimeStatusReport {
        let localRuntime = localRuntime ?? localRuntimeStatus(snapshot: nil)
        let quietRuntime = quietRuntimeStatus()
        let macWindowIntegration = macWindowIntegrationStatus()
        let launcherVisibility = launcherVisibilityStatus(
            macWindowIntegration: macWindowIntegration
        )
        let visibleSurfacePolicy = visibleSurfacePolicyStatus(
            launcherVisibility: launcherVisibility,
            macWindowIntegration: macWindowIntegration
        )
        let launchPlan = launchPlanStatus(localRuntime: localRuntime)
        let proofPlan = proofPlanStatus()
        let proofArtifacts = proofArtifactStatus()
        let pendingLaunch = pendingLaunchStatus()
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
                capabilities: hasLiveAgentConnection ? health?.capabilities : nil,
                connectionDetail: connectionDetail
            ),
            guestAgentDiagnostics: guestAgentDiagnosticsStatus(endpoint: agentEndpoint),
            localRuntime: localRuntime,
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
                pendingLaunchCount: pendingLaunch.isQueued ? 1 : 0,
                badgeLabel: dockBadgeLabel(pendingLaunch: pendingLaunch),
                canOpenMainWindow: true,
                canBringWindowsAppsForward: !mirrorSessions.isEmpty,
                canRestorePreviousApps: canRestoreMirrorSessions,
                canLaunchSelectedApp: canRequestSelectedAppLaunch
            ),
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            quietRuntime: quietRuntime,
            launchPlan: launchPlan,
            proofPlan: proofPlan,
            proofArtifacts: proofArtifacts,
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
                    isAvailable: launchPlan.recommendedStartCommand != nil
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
                    id: "runtime.stopWhenIdle",
                    title: "Stop Runtime When Idle",
                    isAvailable: quietRuntime.canQuietRuntime
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.appWindow",
                    title: "Run App Window Proof",
                    isAvailable: canRunAppWindowProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.coherence",
                    title: "Run Coherence Proof",
                    isAvailable: canRunCoherenceProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.mvp",
                    title: "Run MVP Proof",
                    isAvailable: canRunCoherenceProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.recommended",
                    title: "Run Recommended Proof",
                    isAvailable: proofPlan.recommendedProofCommand != nil
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

    private func dockBadgeLabel(pendingLaunch: WindowsAppRuntimePendingLaunchStatus) -> String? {
        if !mirrorSessions.isEmpty {
            return "\(mirrorSessions.count)"
        }

        if pendingLaunch.isQueued {
            return "..."
        }

        return nil
    }

    public func launchPlanStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil
    ) -> WindowsAppRuntimeLaunchPlanStatus {
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
        let localRuntime = localRuntime ?? localRuntimeStatus(snapshot: nil)

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
            let runtimeIsAlreadyRunning = localRuntime.isKnown && localRuntime.isRunning
            let requiresRuntimeStart = !hasLiveAgentConnection && !runtimeIsAlreadyRunning
            if requiresRuntimeStart && localRuntime.isKnown && !localRuntime.canStart {
                return WindowsAppRuntimeLaunchPlanStatus(
                    selectedAppId: selectedAppId,
                    pendingLaunchAppId: pendingLaunchAppId,
                    canRequestSelectedAppLaunch: true,
                    canLaunchSelectedAppNow: false,
                    requiresRuntimeStart: true,
                    requiresGuestAgent: true,
                    recommendedAction: "prepare-local-runtime",
                    recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                    reason: "The selected Windows app can be requested, but the local Windows runtime is not boot ready. \(localRuntime.reason)"
                )
            }

            let recommendedAction: String
            if runtimeIsAlreadyRunning {
                recommendedAction = "wait-for-guest-agent"
            } else {
                recommendedAction = hasPendingSelectedAppLaunch
                    ? "start-runtime-for-pending-launch"
                    : "start-runtime-and-wait-for-agent"
            }
            return WindowsAppRuntimeLaunchPlanStatus(
                selectedAppId: selectedAppId,
                pendingLaunchAppId: pendingLaunchAppId,
                canRequestSelectedAppLaunch: true,
                canLaunchSelectedAppNow: false,
                requiresRuntimeStart: requiresRuntimeStart,
                requiresGuestAgent: !hasLiveAgentConnection,
                recommendedAction: recommendedAction,
                recommendedStartCommand: requiresRuntimeStart ? "veil-vmctl qemu-start --json --wait-seconds 30" : nil,
                recommendedWaitCommand: hasLiveAgentConnection ? nil : "veil-vmctl guest-agent-wait --json --wait-seconds 30",
                recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                reason: hasPendingSelectedAppLaunch
                    ? "The selected app launch is queued until Windows starts and the guest agent connects."
                    : (runtimeIsAlreadyRunning
                        ? "Windows is running; wait for the guest agent, then launch the selected app."
                        : "Start Windows, wait for the guest agent, then launch the selected app.")
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

    public func proofPlanStatus() -> WindowsAppRuntimeProofPlanStatus {
        guard let selectedAppId else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: nil,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                reason: "Select a Windows app before running proof commands."
            )
        }

        guard hasLiveAgentConnection else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                reason: "Wait for the live Windows agent before running proof commands."
            )
        }

        guard canLaunchApp(appId: selectedAppId) else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                reason: "The selected Windows app is not available for proof launch."
            )
        }

        let appWindowCommand = "veil-vmctl app-window-proof --json --app-id \(selectedAppId)"
        let coherenceCommand = "veil-vmctl coherence-proof --json --app-id \(selectedAppId)"
        let mvpCommand = "veil-vmctl mvp-proof --json --app-id \(selectedAppId) --require-proved"

        guard health?.capabilities.windowCapture == true else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                reason: "The live Windows agent must report windowCapture before app-window proof can run."
            )
        }

        guard health?.capabilities.input == true,
              health?.capabilities.clipboardText == true else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: true,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                recommendedProofKind: "app-window",
                recommendedProofCommand: appWindowCommand,
                recommendedAppWindowProofCommand: appWindowCommand,
                reason: "The live Windows agent must report input and clipboardText before coherence and MVP proof can run."
            )
        }

        return WindowsAppRuntimeProofPlanStatus(
            selectedAppId: selectedAppId,
            canRunAppWindowProof: true,
            canRunCoherenceProof: true,
            canRunMVPProof: true,
            recommendedProofKind: "mvp",
            recommendedProofCommand: mvpCommand,
            recommendedAppWindowProofCommand: appWindowCommand,
            recommendedCoherenceProofCommand: coherenceCommand,
            recommendedMVPProofCommand: mvpCommand,
            reason: "The live Windows agent can run app-window, coherence, and MVP proof commands for the selected app."
        )
    }

    public func proofArtifactStatus(
        diagnosticsDirectory: URL = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    ) -> WindowsAppRuntimeProofArtifactStatus {
        let recommendedProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        let searchDirectories: [(kind: String, url: URL)] = [
            ("recommended", recommendedProofDirectory),
            ("mvp", diagnosticsDirectory.appendingPathComponent("MVP Proof", isDirectory: true)),
            ("coherence", diagnosticsDirectory.appendingPathComponent("Coherence Proof", isDirectory: true)),
            ("app-window", diagnosticsDirectory.appendingPathComponent("App Window Proof", isDirectory: true))
        ]

        let latestProof = searchDirectories
            .flatMap { proofArtifacts(in: $0.url, kind: $0.kind) }
            .max { lhs, rhs in
                lhs.modifiedAt < rhs.modifiedAt
            }

        guard let latestProof else {
            return WindowsAppRuntimeProofArtifactStatus(
                diagnosticsDirectory: diagnosticsDirectory.path,
                recommendedProofDirectory: recommendedProofDirectory.path,
                reason: "No proof artifact has been saved under Veil diagnostics yet."
            )
        }

        return WindowsAppRuntimeProofArtifactStatus(
            diagnosticsDirectory: diagnosticsDirectory.path,
            recommendedProofDirectory: recommendedProofDirectory.path,
            latestProofKind: latestProof.kind,
            latestProofPath: latestProof.url.path,
            latestProofFileName: latestProof.url.lastPathComponent,
            latestProofModifiedAt: latestProof.modifiedAt,
            reason: "Latest proof artifact is available in Veil diagnostics."
        )
    }

    private func proofArtifacts(in directory: URL, kind: String) -> [ProofArtifactCandidate] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate else {
                return nil
            }

            return ProofArtifactCandidate(kind: proofKind(for: url, fallback: kind), url: url, modifiedAt: modifiedAt)
        }
    }

    private func proofKind(for url: URL, fallback: String) -> String {
        let fileName = url.lastPathComponent.lowercased()
        if fileName.contains("mvp") {
            return "mvp"
        }
        if fileName.contains("coherence") {
            return "coherence"
        }
        if fileName.contains("app-window") || fileName.contains("appframe") || fileName.contains("app-frame") {
            return "app-window"
        }
        return fallback
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
            recommendedStopCommand: canQuietRuntimeWhenIdle ? "veil-vmctl app-runtime-action --json --action stop-runtime" : nil,
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
            foregroundableWindowCount: mirrorSessions.count,
            foregroundWindowId: mirrorSessions.last?.id,
            foregroundWindowTitle: mirrorSessions.last?.window.title,
            pendingFrameWindowCount: pendingFrameWindowCount,
            streamingWindowCount: streamingWindowCount,
            reason: reason
        )
    }

    public func launcherVisibilityStatus(
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus? = nil
    ) -> WindowsAppRuntimeLauncherVisibilityStatus {
        let macWindowIntegration = macWindowIntegration ?? macWindowIntegrationStatus()
        let shouldHideMainWindow = macWindowIntegration.hidesLauncherWhenMirroring
        let recommendedAction: String
        let reason: String

        if shouldHideMainWindow {
            recommendedAction = "hide-main-window-use-app-windows"
            reason = "A live Windows app window is mirrored, so the main launcher should stay hidden while Dock and menu controls remain available."
        } else if pendingLaunchAppId != nil {
            recommendedAction = "show-launcher-for-pending-launch"
            reason = "A Windows app launch is queued and may need the launcher to show start or reconnect recovery."
        } else if canRestoreMirrorSessions {
            recommendedAction = "show-launcher-or-restore-apps"
            reason = "No mirrored app window is open, but previous Windows app intent can be restored."
        } else {
            recommendedAction = "show-launcher"
            reason = "No live mirrored Windows app window needs the launcher hidden."
        }

        return WindowsAppRuntimeLauncherVisibilityStatus(
            isEnabled: true,
            canOpenMainWindow: true,
            shouldHideMainWindow: shouldHideMainWindow,
            keepsDockMenuAvailable: true,
            recommendedAction: recommendedAction,
            reason: reason
        )
    }

    public func visibleSurfacePolicyStatus(
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus? = nil,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus? = nil
    ) -> WindowsAppRuntimeVisibleSurfacePolicyStatus {
        let macWindowIntegration = macWindowIntegration ?? macWindowIntegrationStatus()
        let launcherVisibility = launcherVisibility ?? launcherVisibilityStatus(
            macWindowIntegration: macWindowIntegration
        )

        if launcherVisibility.shouldHideMainWindow && macWindowIntegration.mirroredWindowCount > 0 {
            return WindowsAppRuntimeVisibleSurfacePolicyStatus(
                isEnabled: true,
                primarySurface: "windows-app-windows",
                expectedVisibleSurfaceCount: macWindowIntegration.mirroredWindowCount,
                shouldHideLauncher: true,
                keepsRecoveryDisplayManual: true,
                reason: "Only mirrored Windows app windows should be visible during normal app runtime use; the main launcher and VM display stay out of the way unless recovery is requested."
            )
        }

        return WindowsAppRuntimeVisibleSurfacePolicyStatus(
            isEnabled: true,
            primarySurface: "launcher",
            expectedVisibleSurfaceCount: 1,
            shouldHideLauncher: false,
            keepsRecoveryDisplayManual: true,
            reason: "The main Veil launcher is the single normal surface until a live Windows app window is mirrored."
        )
    }

    public func guestAgentDiagnosticsStatus(
        endpoint: String = HostDashboardModel.defaultAgentEndpoint
    ) -> WindowsAppRuntimeGuestAgentDiagnosticsStatus {
        if hasLiveAgentConnection {
            return WindowsAppRuntimeGuestAgentDiagnosticsStatus(
                endpoint: endpoint,
                isConnected: true,
                diagnosticCommand: "veil-host-probe --diagnose-agent",
                waitCommand: "veil-vmctl guest-agent-wait --json --wait-seconds 30",
                recommendedAction: "run-app-window-proof",
                reason: "The live Windows guest agent is connected; proceed to app launch and HWND frame proof."
            )
        }

        return WindowsAppRuntimeGuestAgentDiagnosticsStatus(
            endpoint: endpoint,
            isConnected: false,
            diagnosticCommand: "veil-host-probe --diagnose-agent",
            waitCommand: "veil-vmctl guest-agent-wait --json --wait-seconds 30",
            recommendedAction: "diagnose-agent",
            reason: "Run the guest-agent diagnostic before and after installing the Windows agent so setup evidence is captured consistently."
        )
    }

    public func localRuntimeStatus(
        snapshot: VMRuntimeSnapshot?
    ) -> WindowsAppRuntimeLocalRuntimeStatus {
        guard let snapshot else {
            return WindowsAppRuntimeLocalRuntimeStatus(
                isKnown: false,
                state: nil,
                bootReady: false,
                canStart: true,
                isRunning: false,
                windowsInstalled: false,
                recommendedAction: "inspect-local-runtime",
                recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
                reason: "Local Windows runtime readiness has not been loaded for this status report."
            )
        }

        let isRunning = snapshot.state == .running || snapshot.state == .starting
        let canStart = snapshot.virtualizationAvailable
            && snapshot.minimumOSSupported
            && snapshot.profileName != nil
            && snapshot.bootReady
            && (snapshot.state == .stopped || snapshot.state == .suspended)
        let recommendedAction: String
        let recommendedPrepareCommand: String?
        let reason: String

        if isRunning {
            recommendedAction = "wait-for-guest-agent"
            recommendedPrepareCommand = nil
            reason = "The local Windows runtime is already running; wait for the guest agent before opening Windows apps."
        } else if canStart {
            recommendedAction = "start-runtime"
            recommendedPrepareCommand = nil
            reason = "The local Windows runtime is boot ready."
        } else {
            recommendedAction = "prepare-local-runtime"
            recommendedPrepareCommand = "veil-vmctl prepare --installer /path/to/Windows.iso"
            reason = snapshot.detail
        }

        return WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: snapshot.state,
            bootReady: snapshot.bootReady,
            canStart: canStart,
            isRunning: isRunning,
            windowsInstalled: snapshot.windowsInstalled,
            recommendedAction: recommendedAction,
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            recommendedPrepareCommand: recommendedPrepareCommand,
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
           canFulfillPendingLaunch {
            return await fulfillPendingLaunch()
        }

        if hasLiveAgentConnection {
            return nil
        }

        await load()

        if hasLiveAgentConnection,
           canFulfillPendingLaunch {
            return await fulfillPendingLaunch()
        }

        return nil
    }

    @discardableResult
    public func fulfillPendingLaunch() async -> WindowsAppLaunchResult? {
        guard canFulfillPendingLaunch,
              let pendingLaunchAppId else {
            return nil
        }

        return await launchApp(appId: pendingLaunchAppId)
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
