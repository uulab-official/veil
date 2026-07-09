import Foundation
import Observation

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchApp(appId: String) async throws -> WindowsAppLaunchResult
    func launchNotepad() async throws -> NotepadLaunchResult
    func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult
    func focusWindow(windowId: String) async throws -> WindowFocusResponse
    func closeWindow(windowId: String) async throws -> WindowCloseResponse
    func sendMouseInput(_ input: InputMouseEvent) async throws
    func sendKeyInput(_ input: InputKeyEvent) async throws
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws
    func subscribeWindowFrames(windowId: String) async throws
    func unsubscribeWindowFrames(windowId: String) async throws
    func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport
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
    /// Distinct from `.failed`: the guest-agent connection just dropped and the background retry
    /// loop (`consumeProtocolMessages`'s caller) is actively attempting to recover, not stuck.
    /// `.failed` remains reserved for a user-triggered action that failed outright.
    case reconnecting
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
    public var recommendedDisplayCommand: String?
    public var recommendedRecoveryCommand: String?
    public var consolePreviewStatus: VMConsolePreviewStatus?
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
        recommendedDisplayCommand: String? = nil,
        recommendedRecoveryCommand: String? = nil,
        consolePreviewStatus: VMConsolePreviewStatus? = nil,
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
        self.recommendedDisplayCommand = recommendedDisplayCommand
        self.recommendedRecoveryCommand = recommendedRecoveryCommand
        self.consolePreviewStatus = consolePreviewStatus
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
    public var restorableAppCount: Int
    public var badgeLabel: String?
    public var canOpenMainWindow: Bool
    public var canBringWindowsAppsForward: Bool
    public var canRestorePreviousApps: Bool
    public var canReconnectPreviousApps: Bool
    public var canLaunchSelectedApp: Bool

    public init(
        isEnabled: Bool,
        openWindowCount: Int,
        pendingLaunchCount: Int,
        restorableAppCount: Int,
        badgeLabel: String?,
        canOpenMainWindow: Bool,
        canBringWindowsAppsForward: Bool,
        canRestorePreviousApps: Bool,
        canReconnectPreviousApps: Bool,
        canLaunchSelectedApp: Bool
    ) {
        self.isEnabled = isEnabled
        self.openWindowCount = openWindowCount
        self.pendingLaunchCount = pendingLaunchCount
        self.restorableAppCount = restorableAppCount
        self.badgeLabel = badgeLabel
        self.canOpenMainWindow = canOpenMainWindow
        self.canBringWindowsAppsForward = canBringWindowsAppsForward
        self.canRestorePreviousApps = canRestorePreviousApps
        self.canReconnectPreviousApps = canReconnectPreviousApps
        self.canLaunchSelectedApp = canLaunchSelectedApp
    }
}

public struct WindowsAppRuntimeMenuBarIntegrationStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var statusTitle: String
    public var symbolName: String
    public var primaryActionId: String
    public var primaryActionTitle: String
    public var primaryActionAvailable: Bool
    public var canOpenMainWindow: Bool
    public var canBringWindowsAppsForward: Bool
    public var canRestorePreviousApps: Bool
    public var canReconnectPreviousApps: Bool
    public var canLaunchSelectedApp: Bool
    public var canFulfillPendingLaunch: Bool

    public init(
        isEnabled: Bool,
        statusTitle: String,
        symbolName: String,
        primaryActionId: String,
        primaryActionTitle: String,
        primaryActionAvailable: Bool,
        canOpenMainWindow: Bool,
        canBringWindowsAppsForward: Bool,
        canRestorePreviousApps: Bool,
        canReconnectPreviousApps: Bool,
        canLaunchSelectedApp: Bool,
        canFulfillPendingLaunch: Bool
    ) {
        self.isEnabled = isEnabled
        self.statusTitle = statusTitle
        self.symbolName = symbolName
        self.primaryActionId = primaryActionId
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionAvailable = primaryActionAvailable
        self.canOpenMainWindow = canOpenMainWindow
        self.canBringWindowsAppsForward = canBringWindowsAppsForward
        self.canRestorePreviousApps = canRestorePreviousApps
        self.canReconnectPreviousApps = canReconnectPreviousApps
        self.canLaunchSelectedApp = canLaunchSelectedApp
        self.canFulfillPendingLaunch = canFulfillPendingLaunch
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
    public var recommendedRepairCommand: String?
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
        recommendedRepairCommand: String? = nil,
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
        self.recommendedRepairCommand = recommendedRepairCommand
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

public struct WindowsAppRuntimeReleaseGateStepStatus: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var state: String
    public var isRequired: Bool
    public var isPassing: Bool
    public var evidence: String
    public var nextActionCommand: String?

    public init(
        id: String,
        title: String,
        state: String,
        isRequired: Bool = true,
        isPassing: Bool,
        evidence: String,
        nextActionCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.isRequired = isRequired
        self.isPassing = isPassing
        self.evidence = evidence
        self.nextActionCommand = nextActionCommand
    }
}

public struct WindowsAppRuntimeReleaseGateScreenshotSlotStatus: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var expectedSurface: String
    public var isRequired: Bool

    public init(
        id: String,
        title: String,
        expectedSurface: String,
        isRequired: Bool = true
    ) {
        self.id = id
        self.title = title
        self.expectedSurface = expectedSurface
        self.isRequired = isRequired
    }
}

public struct WindowsAppRuntimeReleaseGateStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var requiredStepCount: Int
    public var passingStepCount: Int
    public var isPassing: Bool
    public var recommendedAction: String
    public var steps: [WindowsAppRuntimeReleaseGateStepStatus]
    public var screenshotSlots: [WindowsAppRuntimeReleaseGateScreenshotSlotStatus]
    public var reason: String

    public init(
        isEnabled: Bool = true,
        requiredStepCount: Int,
        passingStepCount: Int,
        isPassing: Bool,
        recommendedAction: String,
        steps: [WindowsAppRuntimeReleaseGateStepStatus],
        screenshotSlots: [WindowsAppRuntimeReleaseGateScreenshotSlotStatus],
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.requiredStepCount = requiredStepCount
        self.passingStepCount = passingStepCount
        self.isPassing = isPassing
        self.recommendedAction = recommendedAction
        self.steps = steps
        self.screenshotSlots = screenshotSlots
        self.reason = reason
    }
}

public struct WindowsAppRuntimePrimaryNextActionStatus: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var source: String
    public var isAvailable: Bool
    public var actionId: String?
    public var command: String?
    public var reason: String

    public init(
        id: String,
        title: String,
        source: String,
        isAvailable: Bool,
        actionId: String? = nil,
        command: String? = nil,
        reason: String
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.isAvailable = isAvailable
        self.actionId = actionId
        self.command = command
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
    public var menuBarIntegration: WindowsAppRuntimeMenuBarIntegrationStatus
    public var launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus
    public var visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus
    public var macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus
    public var quietRuntime: WindowsAppRuntimeQuietPolicyStatus
    public var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    public var proofPlan: WindowsAppRuntimeProofPlanStatus
    public var proofArtifacts: WindowsAppRuntimeProofArtifactStatus
    public var releaseGate: WindowsAppRuntimeReleaseGateStatus
    public var primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
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
        menuBarIntegration: WindowsAppRuntimeMenuBarIntegrationStatus,
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus,
        visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        proofPlan: WindowsAppRuntimeProofPlanStatus,
        proofArtifacts: WindowsAppRuntimeProofArtifactStatus,
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus,
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
        self.menuBarIntegration = menuBarIntegration
        self.launcherVisibility = launcherVisibility
        self.visibleSurfacePolicy = visibleSurfacePolicy
        self.macWindowIntegration = macWindowIntegration
        self.quietRuntime = quietRuntime
        self.launchPlan = launchPlan
        self.proofPlan = proofPlan
        self.proofArtifacts = proofArtifacts
        self.releaseGate = releaseGate
        self.primaryNextAction = primaryNextAction
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
    public private(set) var latestAgentWait: AgentConnectionWaitReport?
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

    public func runtimeStatusReport(
        generatedAt: Date = Date(),
        agentEndpoint: String = HostDashboardModel.defaultAgentEndpoint,
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil
    ) -> WindowsAppRuntimeStatusReport {
        let localRuntime = localRuntime ?? localRuntimeStatus(snapshot: nil)
        let quietRuntime = quietRuntimeStatus(localRuntime: localRuntime)
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
        let releaseGate = releaseGateStatus(
            localRuntime: localRuntime,
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            quietRuntime: quietRuntime,
            launchPlan: launchPlan,
            proofPlan: proofPlan,
            proofArtifacts: proofArtifacts
        )
        let primaryNextAction = primaryNextActionStatus(releaseGate: releaseGate)
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
                restorableAppCount: restorableAppIds.count,
                badgeLabel: dockBadgeLabel(pendingLaunch: pendingLaunch),
                canOpenMainWindow: true,
                canBringWindowsAppsForward: !mirrorSessions.isEmpty,
                canRestorePreviousApps: canRestoreMirrorSessions,
                canReconnectPreviousApps: canReconnectRestoreMirrorSessions,
                canLaunchSelectedApp: canRequestSelectedAppLaunch
            ),
            menuBarIntegration: menuBarIntegrationStatus(
                localRuntime: localRuntime,
                launchPlan: launchPlan,
                pendingLaunch: pendingLaunch
            ),
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            quietRuntime: quietRuntime,
            launchPlan: launchPlan,
            proofPlan: proofPlan,
            proofArtifacts: proofArtifacts,
            releaseGate: releaseGate,
            primaryNextAction: primaryNextAction,
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
                    id: "windowsApps.reconnectRestore",
                    title: "Reconnect Previous Apps",
                    isAvailable: canReconnectRestoreMirrorSessions
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
                    id: "windowsApps.launchSelected",
                    title: "Open Selected Windows App",
                    isAvailable: canRequestSelectedAppLaunch
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.prepareWindows",
                    title: "Prepare Windows",
                    isAvailable: localRuntime.recommendedPrepareCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.refreshStatus",
                    title: "Refresh Windows Status",
                    isAvailable: true
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.startWindowsForApp",
                    title: "Start Windows To Open App",
                    isAvailable: launchPlan.recommendedStartCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.repairGuestAgentForApp",
                    title: "Repair App Connection",
                    isAvailable: launchPlan.recommendedRepairCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.recoverDisplay",
                    title: "Refresh Windows Display",
                    isAvailable: localRuntime.recommendedRecoveryCommand != nil
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.fulfillPendingLaunch",
                    title: "Open Queued Windows App",
                    isAvailable: pendingLaunch.isQueued && canFulfillPendingLaunch
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.waitAgent",
                    title: "Check App Connection",
                    isAvailable: !hasLiveAgentConnection
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.quietWhenIdle",
                    title: "Quiet Windows When Idle",
                    isAvailable: quietRuntime.canQuietRuntime
                ),
                WindowsAppRuntimeActionStatus(
                    id: "runtime.stopWhenIdle",
                    title: "Stop Windows When Idle",
                    isAvailable: quietRuntime.canQuietRuntime
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.appWindow",
                    title: "Check App Window",
                    isAvailable: canRunAppWindowProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.coherence",
                    title: "Check App Input",
                    isAvailable: canRunCoherenceProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.mvp",
                    title: "Check Full App Flow",
                    isAvailable: canRunCoherenceProof
                ),
                WindowsAppRuntimeActionStatus(
                    id: "proof.recommended",
                    title: "Check Windows App",
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
                reason: "The Windows app connection is active; retry the queued app launch now."
            )
        }

        if appCanBeRequested && !hasLiveAgentConnection {
            return WindowsAppRuntimePendingLaunchStatus(
                isQueued: true,
                appId: pendingLaunchAppId,
                willLaunchOnAgentReconnect: true,
                recommendedAction: "auto-launch-on-agent-reconnect",
                reason: "Veil will launch the queued Windows app after the app connection returns."
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

        if !restorableAppIds.isEmpty {
            return restorableAppIds.count == 1 ? "R" : "R\(restorableAppIds.count)"
        }

        return nil
    }

    private func menuBarIntegrationStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    ) -> WindowsAppRuntimeMenuBarIntegrationStatus {
        let primaryAction = menuBarPrimaryAction(
            localRuntime: localRuntime,
            launchPlan: launchPlan,
            pendingLaunch: pendingLaunch
        )

        return WindowsAppRuntimeMenuBarIntegrationStatus(
            isEnabled: true,
            statusTitle: menuBarStatusTitle(
                localRuntime: localRuntime,
                pendingLaunch: pendingLaunch
            ),
            symbolName: menuBarSymbolName(
                localRuntime: localRuntime,
                pendingLaunch: pendingLaunch
            ),
            primaryActionId: primaryAction.id,
            primaryActionTitle: primaryAction.title,
            primaryActionAvailable: primaryAction.isAvailable,
            canOpenMainWindow: true,
            canBringWindowsAppsForward: !mirrorSessions.isEmpty,
            canRestorePreviousApps: canRestoreMirrorSessions,
            canReconnectPreviousApps: canReconnectRestoreMirrorSessions,
            canLaunchSelectedApp: canRequestSelectedAppLaunch,
            canFulfillPendingLaunch: pendingLaunch.isQueued && canFulfillPendingLaunch
        )
    }

    private func menuBarStatusTitle(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    ) -> String {
        if !mirrorSessions.isEmpty {
            return mirrorSessions.count == 1 ? "1 Windows App Open" : "\(mirrorSessions.count) Windows Apps Open"
        }

        if pendingLaunch.isQueued {
            guard let appName = appName(for: pendingLaunch.appId) else {
                return "App Waiting to Open"
            }

            return suffixedMenuItemTitle(prefix: "", title: appName, suffix: "Waiting")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if canRestoreMirrorSessions || canReconnectRestoreMirrorSessions {
            return previousAppsStatusTitle()
        }

        if hasLiveAgentConnection {
            return "Apps Ready"
        }

        switch localRuntime.state {
        case .running:
            return "Preparing Apps"
        case .starting:
            return "Opening Windows"
        case .suspended:
            return "Windows Paused"
        case .failed, .unsupported:
            return "Needs Attention"
        case .notConfigured:
            return "Set Up Windows"
        case .stopped, nil:
            return localRuntime.windowsInstalled ? "Ready to Open Apps" : "Set Up Windows"
        }
    }

    private func menuBarSymbolName(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    ) -> String {
        if !mirrorSessions.isEmpty {
            return "rectangle.stack.fill"
        }

        if pendingLaunch.isQueued {
            return "clock.fill"
        }

        if canRestoreMirrorSessions || canReconnectRestoreMirrorSessions {
            return "arrow.counterclockwise.circle.fill"
        }

        switch localRuntime.state {
        case .running:
            return "display"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .failed, .unsupported:
            return "exclamationmark.triangle"
        default:
            return "play.rectangle"
        }
    }

    private func menuBarPrimaryAction(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    ) -> (id: String, title: String, isAvailable: Bool) {
        if !mirrorSessions.isEmpty {
            return (
                "dock.bringWindowsAppsForward",
                bringWindowsAppsForwardTitle(),
                true
            )
        }

        if canRestoreMirrorSessions || canReconnectRestoreMirrorSessions {
            return (
                canRestoreMirrorSessions ? "windowsApps.restorePrevious" : "windowsApps.reconnectRestore",
                previousAppsRestoreTitle(),
                canReconnectRestoreMirrorSessions
            )
        }

        if pendingLaunch.isQueued {
            let appName = appName(for: pendingLaunch.appId) ?? "Windows App"
            if localRuntime.recommendedRecoveryCommand != nil {
                return ("runtime.recoverDisplay", "Refresh Display", true)
            }
            if canFulfillPendingLaunch {
                return ("runtime.fulfillPendingLaunch", prefixedMenuItemTitle(prefix: "Open Queued", title: appName), true)
            }
            if launchPlan.recommendedRepairCommand != nil {
                return ("runtime.repairGuestAgentForApp", prefixedMenuItemTitle(prefix: "Continue", title: appName), true)
            }
            if launchPlan.recommendedStartCommand != nil {
                return (
                    "runtime.startWindowsForApp",
                    prefixedMenuItemTitle(prefix: "Open Windows for", title: appName),
                    true
                )
            }

            return ("runtime.waitAgent", "Check App Connection", !hasLiveAgentConnection)
        }

        if canRequestSelectedAppLaunch {
            return (
                "windowsApps.launchSelected",
                prefixedMenuItemTitle(prefix: "Open", title: selectedAppDisplayName()),
                true
            )
        }

        if !hasLiveAgentConnection {
            return ("runtime.waitAgent", "Check App Connection", true)
        }

        return ("dock.openMainWindow", "Open Veil", true)
    }

    private func bringWindowsAppsForwardTitle() -> String {
        guard mirrorSessions.count == 1,
              let session = mirrorSessions.first else {
            return "Bring Windows Apps Forward"
        }

        return suffixedMenuItemTitle(
            prefix: "Bring",
            title: appName(for: session.window.appId) ?? session.window.title,
            suffix: "Forward"
        )
    }

    private func previousAppsStatusTitle() -> String {
        guard let appName = singleRestorableAppName() else {
            return canRestoreMirrorSessions ? "Previous Apps Ready" : "Previous Apps Can Reconnect"
        }

        return suffixedMenuItemTitle(
            prefix: "",
            title: appName,
            suffix: canRestoreMirrorSessions ? "Ready" : "Can Reconnect"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func previousAppsRestoreTitle() -> String {
        let prefix = canRestoreMirrorSessions ? "Restore" : "Reconnect"
        guard let appName = singleRestorableAppName() else {
            return canRestoreMirrorSessions ? "Restore Previous Apps" : "Reconnect Previous Apps"
        }

        return prefixedMenuItemTitle(prefix: prefix, title: appName)
    }

    private func selectedAppDisplayName() -> String {
        appName(for: selectedAppId) ?? "Windows App"
    }

    private func singleRestorableAppName() -> String? {
        guard restorableAppIds.count == 1,
              let appId = restorableAppIds.first else {
            return nil
        }

        return appName(for: appId)
    }

    private func appName(for appId: String?) -> String? {
        guard let appId else {
            return nil
        }

        return apps.first { $0.id == appId }?.name
    }

    private func menuItemTitle(_ title: String, maxCount: Int = 30) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "Windows App"
        }

        guard trimmedTitle.count > maxCount else {
            return trimmedTitle
        }

        let prefixCount = max(1, maxCount - 3)
        let prefix = String(trimmedTitle.prefix(prefixCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    private func prefixedMenuItemTitle(prefix: String, title: String, maxCount: Int = 30) -> String {
        let itemTitleLimit = max(1, maxCount - prefix.count - 1)
        return "\(prefix) \(menuItemTitle(title, maxCount: itemTitleLimit))"
    }

    private func suffixedMenuItemTitle(
        prefix: String,
        title: String,
        suffix: String,
        maxCount: Int = 30
    ) -> String {
        let itemTitleLimit = max(1, maxCount - prefix.count - suffix.count - 2)
        return "\(prefix) \(menuItemTitle(title, maxCount: itemTitleLimit)) \(suffix)"
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
        let repairCommand = "veil-vmctl qemu-install-agent --json --wait-seconds 120"
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
                recommendedAction = hasPendingSelectedAppLaunch
                    ? "repair-guest-agent-for-pending-launch"
                    : "repair-guest-agent-for-app-launch"
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
                recommendedRepairCommand: runtimeIsAlreadyRunning ? repairCommand : nil,
                recommendedLaunchCommand: hasPendingSelectedAppLaunch ? fulfillPendingCommand : launchCommand,
                reason: hasPendingSelectedAppLaunch
                    ? (runtimeIsAlreadyRunning
                        ? "Windows is running and the selected app launch is queued; repair or start the guest agent, then open the app automatically."
                        : "The selected app launch is queued until Windows starts and the guest agent connects.")
                    : (runtimeIsAlreadyRunning
                        ? "Windows is running; repair or start the guest agent, then launch the selected app."
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
                reason: "Select a Windows app before running app checks."
            )
        }

        guard hasLiveAgentConnection else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                reason: "Wait for the Windows app connection before running app checks."
            )
        }

        guard canLaunchApp(appId: selectedAppId) else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                reason: "The selected Windows app is not available for app checks."
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
                reason: "The Windows app connection must support window capture before the window check can run."
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
                reason: "The Windows app connection must support input and clipboard before full app checks can run."
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
            reason: "The Windows app connection can run window, input, and full app checks for the selected app."
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
                reason: "No app check artifact has been saved under Veil diagnostics yet."
            )
        }

        return WindowsAppRuntimeProofArtifactStatus(
            diagnosticsDirectory: diagnosticsDirectory.path,
            recommendedProofDirectory: recommendedProofDirectory.path,
            latestProofKind: latestProof.kind,
            latestProofPath: latestProof.url.path,
            latestProofFileName: latestProof.url.lastPathComponent,
            latestProofModifiedAt: latestProof.modifiedAt,
            reason: "Latest app check artifact is available in Veil diagnostics."
        )
    }

    public func releaseGateStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        launcherVisibility: WindowsAppRuntimeLauncherVisibilityStatus,
        visibleSurfacePolicy: WindowsAppRuntimeVisibleSurfacePolicyStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        proofPlan: WindowsAppRuntimeProofPlanStatus,
        proofArtifacts: WindowsAppRuntimeProofArtifactStatus
    ) -> WindowsAppRuntimeReleaseGateStatus {
        let setupPassing = localRuntime.bootReady && localRuntime.windowsInstalled
        let setupCommand = setupPassing
            ? localRuntime.recommendedInstallStatusCommand
            : (localRuntime.recommendedPrepareCommand ?? localRuntime.recommendedInstallStatusCommand)
        let surfacePassing = launcherVisibility.isEnabled
            && visibleSurfacePolicy.isEnabled
            && visibleSurfacePolicy.keepsRecoveryDisplayManual
            && (visibleSurfacePolicy.primarySurface == "launcher" || macWindowIntegration.hidesLauncherWhenMirroring)
        let launchPassing = launchPlan.canRequestSelectedAppLaunch
            && launchPlan.recommendedLaunchCommand != nil
        let checkPassing = proofArtifacts.latestProofPath != nil
            && proofArtifacts.latestProofKind != nil
        let quietOrRestorePassing = quietRuntime.canQuietRuntime
            || macWindowIntegration.mirroredWindowCount > 0
            || canReconnectRestoreMirrorSessions
            || canRestoreMirrorSessions

        let steps = [
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "windowsSetup",
                title: "Windows Setup Ready",
                state: setupPassing ? "passed" : "blocked",
                isPassing: setupPassing,
                evidence: localRuntime.reason,
                nextActionCommand: setupCommand
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "oneScreenPath",
                title: "One-Screen App Path",
                state: surfacePassing ? "passed" : "blocked",
                isPassing: surfacePassing,
                evidence: visibleSurfacePolicy.reason,
                nextActionCommand: "veil-vmctl app-runtime-status --json"
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "openWindowsApp",
                title: "Open Windows App",
                state: launchPassing ? "ready" : "blocked",
                isPassing: launchPassing,
                evidence: launchPlan.reason,
                nextActionCommand: nextLaunchGateCommand(launchPlan: launchPlan)
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "appCheckEvidence",
                title: "App Check Evidence",
                state: checkPassing ? "passed" : (proofPlan.recommendedProofCommand == nil ? "blocked" : "ready"),
                isPassing: checkPassing,
                evidence: proofArtifacts.reason,
                nextActionCommand: proofPlan.recommendedProofCommand
            ),
            WindowsAppRuntimeReleaseGateStepStatus(
                id: "closeOrRestore",
                title: "Close Or Restore Apps",
                state: quietOrRestorePassing ? "ready" : "pending",
                isPassing: quietOrRestorePassing,
                evidence: quietRuntime.reason,
                nextActionCommand: closeOrRestoreGateCommand(
                    macWindowIntegration: macWindowIntegration,
                    quietRuntime: quietRuntime
                )
            )
        ]

        let requiredSteps = steps.filter(\.isRequired)
        let passingStepCount = requiredSteps.filter(\.isPassing).count
        let isPassing = passingStepCount == requiredSteps.count
        let firstUnmetStep = requiredSteps.first { !$0.isPassing }

        return WindowsAppRuntimeReleaseGateStatus(
            requiredStepCount: requiredSteps.count,
            passingStepCount: passingStepCount,
            isPassing: isPassing,
            recommendedAction: firstUnmetStep?.id ?? "ready-for-release-card",
            steps: steps,
            screenshotSlots: [
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "preBootLauncher",
                    title: "Pre-Boot Launcher",
                    expectedSurface: "One Veil launcher window with setup or start action visible."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "firstAppLaunch",
                    title: "First App Launch",
                    expectedSurface: "A selected Windows app is opening, queued, or ready with one concrete next action."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "appWindowOnly",
                    title: "App Window Only",
                    expectedSurface: "The mirrored Windows app window is visible while the launcher is hidden unless recovery is needed."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "menuRestore",
                    title: "Menu Restore",
                    expectedSurface: "Menu or Dock controls can bring forward, restore, reconnect, or close Windows app windows."
                ),
                WindowsAppRuntimeReleaseGateScreenshotSlotStatus(
                    id: "closeQuiet",
                    title: "Close And Quiet",
                    expectedSurface: "After the final Windows app window closes, the launcher returns or quiet Windows action is available."
                )
            ],
            reason: isPassing
                ? "The one-screen Windows app release gate has current setup, launch, app check, and close or restore evidence."
                : "Continue the first unmet release gate step before promoting the one-screen Windows app flow."
        )
    }

    private func nextLaunchGateCommand(
        launchPlan: WindowsAppRuntimeLaunchPlanStatus
    ) -> String? {
        launchPlan.recommendedLaunchCommand
            ?? launchPlan.recommendedStartCommand
            ?? launchPlan.recommendedRepairCommand
            ?? launchPlan.recommendedWaitCommand
    }

    private func closeOrRestoreGateCommand(
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus
    ) -> String? {
        if macWindowIntegration.mirroredWindowCount > 0 {
            return "veil-vmctl app-runtime-action --json --action close-all"
        }

        if let recommendedStopCommand = quietRuntime.recommendedStopCommand {
            return recommendedStopCommand
        }

        if canReconnectRestoreMirrorSessions || canRestoreMirrorSessions {
            return "veil-vmctl app-runtime-action --json --action reconnect-restore"
        }

        return nil
    }

    private func primaryNextActionStatus(
        releaseGate: WindowsAppRuntimeReleaseGateStatus
    ) -> WindowsAppRuntimePrimaryNextActionStatus {
        if releaseGate.isPassing {
            return WindowsAppRuntimePrimaryNextActionStatus(
                id: "ready-for-release-card",
                title: "Review App Flow",
                source: "releaseGate",
                isAvailable: true,
                command: "veil-vmctl app-runtime-review --json",
                reason: releaseGate.reason
            )
        }

        guard let step = releaseGate.steps.first(where: { $0.id == releaseGate.recommendedAction }) else {
            return WindowsAppRuntimePrimaryNextActionStatus(
                id: releaseGate.recommendedAction,
                title: "Review App Flow",
                source: "releaseGate",
                isAvailable: false,
                reason: releaseGate.reason
            )
        }

        return WindowsAppRuntimePrimaryNextActionStatus(
            id: step.id,
            title: step.title,
            source: "releaseGate",
            isAvailable: step.nextActionCommand != nil,
            actionId: primaryNextActionId(stepId: step.id, command: step.nextActionCommand),
            command: step.nextActionCommand,
            reason: step.evidence
        )
    }

    private func primaryNextActionId(stepId: String, command: String?) -> String? {
        guard let command else {
            return nil
        }

        switch stepId {
        case "windowsSetup":
            if command == "veil-vmctl qemu-install-status --json"
                || command == "veil-vmctl app-runtime-status --json" {
                return "runtime.refreshStatus"
            }
            if command.hasPrefix("veil-vmctl prepare") {
                return "runtime.prepareWindows"
            }
            if command.contains("qemu-start") {
                return "runtime.startWindowsForApp"
            }
        case "oneScreenPath":
            return "runtime.refreshStatus"
        case "openWindowsApp":
            if command.contains("--action fulfill-pending") {
                return "runtime.fulfillPendingLaunch"
            }
            if command.contains("--action launch") {
                return "windowsApps.launchSelected"
            }
            if command.contains("--action recover-display") {
                return "runtime.recoverDisplay"
            }
            if command.contains("--action wait-agent") {
                return "runtime.waitAgent"
            }
            if command.contains("qemu-install-agent") {
                return "runtime.repairGuestAgentForApp"
            }
            if command.contains("qemu-start") {
                return "runtime.startWindowsForApp"
            }
        case "appCheckEvidence":
            return "proof.recommended"
        case "closeOrRestore":
            if command.contains("--action close-all") {
                return "windowsApps.closeAll"
            }
            if command.contains("--action reconnect-restore")
                || command.contains("--action restore") {
                return "windowsApps.reconnectRestore"
            }
            if command.contains("--action stop-runtime")
                || command.contains("--action quiet-when-idle") {
                return "runtime.quietWhenIdle"
            }
        default:
            break
        }

        return nil
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

    public func quietRuntimeStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus? = nil
    ) -> WindowsAppRuntimeQuietPolicyStatus {
        let recommendedAction: String
        let reason: String
        let canStopLocalRuntime = canStopLocalRuntime(localRuntime)
        let canQuietRuntime = canQuietRuntimeWhenIdle && canStopLocalRuntime

        if !hasOpenedAppWindowThisSession {
            recommendedAction = "none"
            reason = "No Windows app window has opened in this host session."
        } else if !mirrorSessions.isEmpty {
            recommendedAction = "keep-running"
            reason = "Windows app windows are still open."
        } else if canQuietRuntime {
            recommendedAction = "stop-or-suspend-runtime"
            reason = "All Windows app windows are closed and the Windows app connection is ready to stop cleanly."
        } else if localRuntime?.isKnown == true && !canStopLocalRuntime {
            recommendedAction = "already-quiet"
            reason = "All Windows app windows are closed and Windows is already quiet."
        } else {
            recommendedAction = "wait-for-agent"
            reason = "Wait for the Windows app connection before stopping Windows cleanly."
        }

        return WindowsAppRuntimeQuietPolicyStatus(
            isEnabled: true,
            hasOpenedAppWindowThisSession: hasOpenedAppWindowThisSession,
            openWindowCount: mirrorSessions.count,
            canQuietRuntime: canQuietRuntime,
            willQuietAutomatically: canQuietRuntime,
            automaticQuietDelaySeconds: automaticQuietDelaySeconds,
            recommendedAction: recommendedAction,
            recommendedStopCommand: canQuietRuntime ? "veil-vmctl app-runtime-action --json --action stop-runtime" : nil,
            reason: reason
        )
    }

    private func canStopLocalRuntime(_ localRuntime: WindowsAppRuntimeLocalRuntimeStatus?) -> Bool {
        guard let localRuntime, localRuntime.isKnown else {
            return true
        }

        return localRuntime.state == .running || localRuntime.state == .suspended
    }

    public func macWindowIntegrationStatus() -> WindowsAppRuntimeMacWindowIntegrationStatus {
        let pendingFrameWindowCount = mirrorSessions.filter { $0.captureState == .pending }.count
        let streamingWindowCount = mirrorSessions.filter { $0.captureState == .streaming }.count
        let reason: String

        if !hasLiveAgentConnection {
            reason = "Waiting for the Windows app connection before opening app windows on macOS automatically."
        } else if mirrorSessions.isEmpty {
            reason = "Ready to open the next Windows app as a macOS window."
        } else {
            reason = "Windows app windows are mirrored as macOS windows."
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
        let recommendedDisplayCommand: String?
        let recommendedRecoveryCommand: String?
        let reason: String
        let consolePreviewStatus = snapshot.latestConsoleLaunch?.previewStatus

        if isRunning {
            let displayNeedsRecovery = consolePreviewStatus == .stale
                || consolePreviewStatus == .unavailable
            recommendedAction = displayNeedsRecovery ? "recover-runtime-display" : "wait-for-guest-agent"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = snapshot.latestConsoleLaunch?.displaySurface.isLiveCapable == true
                ? "veil-vmctl qemu-display-smoke --json"
                : nil
            recommendedRecoveryCommand = displayNeedsRecovery ? "veil-vmctl qemu-capture --json" : nil
            reason = displayNeedsRecovery
                ? "The local Windows runtime is running, but the embedded console preview is \(consolePreviewStatus?.rawValue ?? "unavailable"); refresh or validate display evidence before relying on app launch recovery."
                : "The local Windows runtime is already running; wait for the guest agent before opening Windows apps."
        } else if canStart {
            recommendedAction = "start-runtime"
            recommendedPrepareCommand = nil
            recommendedDisplayCommand = nil
            recommendedRecoveryCommand = nil
            reason = "The local Windows runtime is boot ready."
        } else {
            recommendedAction = "prepare-local-runtime"
            recommendedPrepareCommand = prepareCommand(for: snapshot)
            recommendedDisplayCommand = nil
            recommendedRecoveryCommand = nil
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
            recommendedDisplayCommand: recommendedDisplayCommand,
            recommendedRecoveryCommand: recommendedRecoveryCommand,
            consolePreviewStatus: consolePreviewStatus,
            reason: reason
        )
    }

    private func prepareCommand(for snapshot: VMRuntimeSnapshot) -> String {
        let installerPath = snapshot.installerMediaPath ?? "/path/to/Windows.iso"
        var command = "veil-vmctl prepare --installer \(shellQuotedArgument(installerPath))"

        if let driverPath = snapshot.driverMediaPath, !driverPath.isEmpty {
            command += " --drivers \(shellQuotedArgument(driverPath))"
        }

        return command
    }

    private func shellQuotedArgument(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
    public func waitForLiveAgentConnection(
        endpoint: String = HostDashboardModel.defaultAgentEndpoint,
        timeoutSeconds: Int = 5
    ) async -> AgentConnectionWaitReport {
        phase = .loading
        errorMessage = nil

        let report = await service.waitForAgentConnection(
            endpoint: endpoint,
            timeoutSeconds: timeoutSeconds
        )
        latestAgentWait = report
        agentDiagnostic = report.diagnostic

        if report.status == .connected {
            await load()
        } else {
            phase = .failed
            errorMessage = report.diagnostic.errorMessage
        }

        return report
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
        // Cleared unconditionally, including on the early-return paths below, so a stale
        // errorMessage from some earlier unrelated failure can never be mistaken by a caller for a
        // failure of *this* call (callers like VeilHostShellApp.restoreWindowsAppWindows() read
        // errorMessage after an empty result to distinguish "nothing to restore" from "restore
        // failed").
        errorMessage = nil

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
            return try await applyWindowsAppLaunchResult(result)
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    /// Opens a host file in the given app on the Windows guest -- the drag-and-drop entry point.
    /// Applies the exact same side effects as `launchApp` since the wire response has the same
    /// launch-acceptance-plus-`window.created` shape; the only difference is what triggered it.
    @discardableResult
    public func openFile(appId: String, fileName: String, contentBase64: String) async -> WindowsAppLaunchResult? {
        phase = .launching
        errorMessage = nil

        do {
            let result = try await service.openFile(appId: appId, fileName: fileName, contentBase64: contentBase64)
            return try await applyWindowsAppLaunchResult(result)
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    private func applyWindowsAppLaunchResult(_ result: WindowsAppLaunchResult) async throws -> WindowsAppLaunchResult {
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
                // Only ever transitions .reconnecting -> .connected here, never touching .loading/
                // .launching/.idle/.failed -- those are driven by unrelated user-triggered flows
                // sharing this same `phase` property, and this background pump must not clobber them.
                if phase == .reconnecting {
                    phase = .connected
                }
                let result = try await receiveProtocolMessage(message)
                onMessageHandled(result)
            }
        } catch {
            // Callers run this in a `while !Task.isCancelled` retry loop, so a dropped connection
            // recovers on its own -- but a silent `return` here leaves zero trace of *why* window
            // updates or clipboard sync briefly stopped, which is exactly the failure class that
            // masked a real crash on the guest-agent side earlier the same day this was written.
            // Not `.public`: this error can originate from a disk-backed transport/decoding path and
            // os.Logger's default `.private` redaction is the same protection `exportDiagnostics`
            // applies to on-disk paths elsewhere in this codebase -- a log line is not the place to
            // reintroduce an unredacted host path into Console.app/sysdiagnose output.
            VeilLog.agent.notice("consumeProtocolMessages stopped: \(String(describing: error))")
        }

        // The event stream just ended, whether via the catch above or by completing normally --
        // either way the live pump is no longer running. Only flip .connected -> .reconnecting (see
        // the guard at loop entry above for why other phases are left alone); the caller's retry loop
        // will call this again, which flips back to .connected once a message actually arrives.
        if phase == .connected {
            phase = .reconnecting
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
