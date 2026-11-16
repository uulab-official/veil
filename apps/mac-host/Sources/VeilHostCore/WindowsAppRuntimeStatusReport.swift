import CoreGraphics
import Foundation
import Observation

public struct WindowsAppRuntimeConnectionStatus: Codable, Equatable, Sendable {
    public var mode: HostConnectionMode
    public var hasLiveAgentConnection: Bool
    public var agentVersion: String?
    public var os: String?
    public var capabilities: AgentCapabilities?
    public var packageIdentityStatus: PackageIdentityStatus?
    public var notificationListener: WindowsNotificationListenerStatus?
    public var connectionDetail: String?

    public init(
        mode: HostConnectionMode,
        hasLiveAgentConnection: Bool,
        agentVersion: String?,
        os: String?,
        capabilities: AgentCapabilities? = nil,
        packageIdentityStatus: PackageIdentityStatus? = nil,
        notificationListener: WindowsNotificationListenerStatus? = nil,
        connectionDetail: String?
    ) {
        self.mode = mode
        self.hasLiveAgentConnection = hasLiveAgentConnection
        self.agentVersion = agentVersion
        self.os = os
        self.capabilities = capabilities
        self.packageIdentityStatus = packageIdentityStatus
        self.notificationListener = notificationListener
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
    /// Whether this VM can persist a running Windows session, so going idle can suspend instead of
    /// shutting Windows down and losing every open app. Defaults to `false` so a caller that has no
    /// snapshot reports the conservative answer rather than promising a session it cannot keep.
    public var canSuspendSession: Bool
    public var windowsInstalled: Bool
    public var installEvidence: VMInstallEvidenceSummary?
    public var automaticInstallMediaStatus: VMAutomaticInstallMediaStatus?
    public var requiresGuestToolsMediaRebuild: Bool
    public var recommendedAction: String
    public var recommendedInstallStatusCommand: String
    public var recommendedPrepareCommand: String?
    public var recommendedDisplayCommand: String?
    public var recommendedRecoveryCommand: String?
    public var recommendedMediaRebuildCommand: String?
    public var recommendedPowerDownCommand: String?
    public var consolePreviewStatus: VMConsolePreviewStatus?
    public var reason: String

    public init(
        isKnown: Bool,
        state: VMRuntimeState?,
        bootReady: Bool,
        canStart: Bool,
        isRunning: Bool,
        canSuspendSession: Bool = false,
        windowsInstalled: Bool,
        installEvidence: VMInstallEvidenceSummary? = nil,
        automaticInstallMediaStatus: VMAutomaticInstallMediaStatus? = nil,
        requiresGuestToolsMediaRebuild: Bool = false,
        recommendedAction: String,
        recommendedInstallStatusCommand: String,
        recommendedPrepareCommand: String? = nil,
        recommendedDisplayCommand: String? = nil,
        recommendedRecoveryCommand: String? = nil,
        recommendedMediaRebuildCommand: String? = nil,
        recommendedPowerDownCommand: String? = nil,
        consolePreviewStatus: VMConsolePreviewStatus? = nil,
        reason: String
    ) {
        self.isKnown = isKnown
        self.state = state
        self.bootReady = bootReady
        self.canStart = canStart
        self.isRunning = isRunning
        self.canSuspendSession = canSuspendSession
        self.windowsInstalled = windowsInstalled
        self.installEvidence = installEvidence
        self.automaticInstallMediaStatus = automaticInstallMediaStatus
        self.requiresGuestToolsMediaRebuild = requiresGuestToolsMediaRebuild
        self.recommendedAction = recommendedAction
        self.recommendedInstallStatusCommand = recommendedInstallStatusCommand
        self.recommendedPrepareCommand = recommendedPrepareCommand
        self.recommendedDisplayCommand = recommendedDisplayCommand
        self.recommendedRecoveryCommand = recommendedRecoveryCommand
        self.recommendedMediaRebuildCommand = recommendedMediaRebuildCommand
        self.recommendedPowerDownCommand = recommendedPowerDownCommand
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
    public var frameStreamStatus: WindowFrameStreamStatus
    public var frameStreamRequestedAt: Date?
    public var latestFrameReceivedAt: Date?
    public var latestFrameAgeMilliseconds: Int?
    /// Age of the last liveness signal, frame or unchanged-frame heartbeat. `frameStreamStatus` is
    /// derived from this, not from `latestFrameAgeMilliseconds`, so an idle window reads as healthy
    /// with an old picture instead of being escalated into recovery.
    public var latestActivityAgeMilliseconds: Int?
    public var latestFrameIntervalMilliseconds: Int?
    public var frameStreamWaitingAgeMilliseconds: Int?
    public var receivedFrameCount: Int
    /// Heartbeats received on this stream. A high count beside a low `receivedFrameCount` means the
    /// guest is skipping redundant encodes for a static window, which is the healthy case.
    public var unchangedHeartbeatCount: Int
    public var frameStreamRecommendedAction: String
    public var frameStreamRestartCount: Int
    public var latestFrameStreamRestartedAt: Date?
    public var frameStreamRecoveryEscalated: Bool
    public var frameStreamReopenEscalated: Bool
    public var canFocus: Bool
    public var canClose: Bool
    public var canSendInput: Bool

    public init(
        windowId: String,
        appId: String,
        title: String,
        captureState: WindowCaptureState,
        frameStreamStatus: WindowFrameStreamStatus,
        frameStreamRequestedAt: Date? = nil,
        latestFrameReceivedAt: Date? = nil,
        latestFrameAgeMilliseconds: Int? = nil,
        latestActivityAgeMilliseconds: Int? = nil,
        latestFrameIntervalMilliseconds: Int? = nil,
        frameStreamWaitingAgeMilliseconds: Int? = nil,
        receivedFrameCount: Int = 0,
        unchangedHeartbeatCount: Int = 0,
        frameStreamRecommendedAction: String,
        frameStreamRestartCount: Int = 0,
        latestFrameStreamRestartedAt: Date? = nil,
        frameStreamRecoveryEscalated: Bool = false,
        frameStreamReopenEscalated: Bool = false,
        canFocus: Bool,
        canClose: Bool,
        canSendInput: Bool
    ) {
        self.windowId = windowId
        self.appId = appId
        self.title = title
        self.captureState = captureState
        self.frameStreamStatus = frameStreamStatus
        self.frameStreamRequestedAt = frameStreamRequestedAt
        self.latestFrameReceivedAt = latestFrameReceivedAt
        self.latestFrameAgeMilliseconds = latestFrameAgeMilliseconds
        self.latestActivityAgeMilliseconds = latestActivityAgeMilliseconds ?? latestFrameAgeMilliseconds
        self.latestFrameIntervalMilliseconds = latestFrameIntervalMilliseconds
        self.frameStreamWaitingAgeMilliseconds = frameStreamWaitingAgeMilliseconds
        self.receivedFrameCount = receivedFrameCount
        self.unchangedHeartbeatCount = unchangedHeartbeatCount
        self.frameStreamRecommendedAction = frameStreamRecommendedAction
        self.frameStreamRestartCount = frameStreamRestartCount
        self.latestFrameStreamRestartedAt = latestFrameStreamRestartedAt
        self.frameStreamRecoveryEscalated = frameStreamRecoveryEscalated
        self.frameStreamReopenEscalated = frameStreamReopenEscalated
        self.canFocus = canFocus
        self.canClose = canClose
        self.canSendInput = canSendInput
    }
}

public struct WindowsAppReopenResult: Equatable, Sendable {
    public var requestedWindowId: String
    public var close: WindowCloseResponse
    public var launch: WindowsAppLaunchResult

    public init(
        requestedWindowId: String,
        close: WindowCloseResponse,
        launch: WindowsAppLaunchResult
    ) {
        self.requestedWindowId = requestedWindowId
        self.close = close
        self.launch = launch
    }
}

public struct WindowsAppFrameStreamMaintenanceResult: Equatable, Sendable {
    public var reopenedWindows: [WindowsAppReopenResult]
    public var recoveredFrameWindowIds: [String]
    public var restartedFrameWindowIds: [String]

    public init(
        reopenedWindows: [WindowsAppReopenResult] = [],
        recoveredFrameWindowIds: [String] = [],
        restartedFrameWindowIds: [String] = []
    ) {
        self.reopenedWindows = reopenedWindows
        self.recoveredFrameWindowIds = recoveredFrameWindowIds
        self.restartedFrameWindowIds = restartedFrameWindowIds
    }

    public var didPerformMaintenance: Bool {
        !reopenedWindows.isEmpty
            || !recoveredFrameWindowIds.isEmpty
            || !restartedFrameWindowIds.isEmpty
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
    public var restorableWindowCount: Int
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
        restorableWindowCount: Int? = nil,
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
        self.restorableWindowCount = restorableWindowCount ?? restorableAppCount
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
    public var freshFrameWindowCount: Int
    public var delayedFrameWindowCount: Int
    public var staleFrameWindowCount: Int
    public var frameLatencyHealth: String
    public var frameLatencyBudgetMilliseconds: Int
    public var frameStaleTimeoutMilliseconds: Int
    public var slowestFrameWindowId: String?
    public var slowestFrameWindowTitle: String?
    public var slowestFrameAgeMilliseconds: Int?
    public var frameLatencyRecommendedAction: String
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
        freshFrameWindowCount: Int,
        delayedFrameWindowCount: Int,
        staleFrameWindowCount: Int,
        frameLatencyHealth: String = "idle",
        frameLatencyBudgetMilliseconds: Int = WindowFrameStreamAssessment.freshFrameAgeThresholdMilliseconds,
        frameStaleTimeoutMilliseconds: Int = WindowFrameStreamAssessment.delayedFrameAgeThresholdMilliseconds,
        slowestFrameWindowId: String? = nil,
        slowestFrameWindowTitle: String? = nil,
        slowestFrameAgeMilliseconds: Int? = nil,
        frameLatencyRecommendedAction: String = "none",
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
        self.freshFrameWindowCount = freshFrameWindowCount
        self.delayedFrameWindowCount = delayedFrameWindowCount
        self.staleFrameWindowCount = staleFrameWindowCount
        self.frameLatencyHealth = frameLatencyHealth
        self.frameLatencyBudgetMilliseconds = frameLatencyBudgetMilliseconds
        self.frameStaleTimeoutMilliseconds = frameStaleTimeoutMilliseconds
        self.slowestFrameWindowId = slowestFrameWindowId
        self.slowestFrameWindowTitle = slowestFrameWindowTitle
        self.slowestFrameAgeMilliseconds = slowestFrameAgeMilliseconds
        self.frameLatencyRecommendedAction = frameLatencyRecommendedAction
        self.reason = reason
    }
}

/// Whether the guest is rendering mirrored windows at the resolution this Mac can actually show.
///
/// Two units already travel on the wire and both ends agree on them: window bounds are logical
/// ~96-DPI-equivalent units so a macOS window is sized in points, and frame dimensions are real physical
/// pixels so the Mac gets the sharpest bitmap available. That part is correct and needs no host
/// arithmetic. What the host *cannot* fix by calculation is a resolution mismatch:
///
/// - Guest below host: a 100% Windows guest on a 2x Mac supplies half the pixels the display will draw,
///   so macOS upscales and text looks soft. Those pixels do not exist; only raising the guest's own
///   display scaling creates them.
/// - Guest above host: a 200% guest on a 1x Mac renders four times the pixels the display can show. They
///   are encoded, sent, and composited before being thrown away, which is wasted bandwidth and CPU on
///   every frame.
///
/// Veil cannot set Windows' display scaling from outside, so this reports the mismatch and the exact
/// percentage to choose instead of silently living with it.
public struct WindowsAppRuntimeDisplayScalingStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// This Mac's backing scale factor. `nil` when the caller did not supply it, in which case no
    /// mismatch is claimed rather than assuming 1.
    public var hostBackingScale: Double?
    /// The DPI scale the guest is rendering at, taken from the foreground window's most recent frame.
    /// Guest display scaling is a single Windows setting, so one window is representative.
    public var guestRenderScale: Double?
    /// `hostBackingScale / guestRenderScale`. Above 1 means macOS is upscaling; below 1 means the guest
    /// is rendering pixels the display cannot show.
    public var scaleRatio: Double?
    public var isUpscaling: Bool
    public var isOverRendering: Bool
    /// The Windows display-scaling percentage that would match this Mac.
    public var recommendedGuestScalePercent: Int?
    public var recommendedAction: String
    public var reason: String

    public init(
        isEnabled: Bool = true,
        hostBackingScale: Double? = nil,
        guestRenderScale: Double? = nil,
        scaleRatio: Double? = nil,
        isUpscaling: Bool = false,
        isOverRendering: Bool = false,
        recommendedGuestScalePercent: Int? = nil,
        recommendedAction: String,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.hostBackingScale = hostBackingScale
        self.guestRenderScale = guestRenderScale
        self.scaleRatio = scaleRatio
        self.isUpscaling = isUpscaling
        self.isOverRendering = isOverRendering
        self.recommendedGuestScalePercent = recommendedGuestScalePercent
        self.recommendedAction = recommendedAction
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

public struct WindowsAppRuntimeOneScreenUXStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var mode: String
    public var expectedVisibleSurfaceCount: Int
    public var usesSinglePrimarySurfaceFamily: Bool
    public var hidesLauncherDuringAppMirroring: Bool
    public var keepsMenuBarControlAvailable: Bool
    public var keepsDockControlAvailable: Bool
    public var canRecoverFromMenuOrDock: Bool
    public var returnsToLauncherWhenNoAppWindows: Bool
    public var keepsDisplayRecoveryManual: Bool
    public var primaryActionId: String?
    public var heroRunsPrimaryAction: Bool
    public var reason: String

    public init(
        isEnabled: Bool,
        mode: String,
        expectedVisibleSurfaceCount: Int,
        usesSinglePrimarySurfaceFamily: Bool,
        hidesLauncherDuringAppMirroring: Bool,
        keepsMenuBarControlAvailable: Bool,
        keepsDockControlAvailable: Bool,
        canRecoverFromMenuOrDock: Bool,
        returnsToLauncherWhenNoAppWindows: Bool,
        keepsDisplayRecoveryManual: Bool,
        primaryActionId: String? = nil,
        heroRunsPrimaryAction: Bool,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.expectedVisibleSurfaceCount = expectedVisibleSurfaceCount
        self.usesSinglePrimarySurfaceFamily = usesSinglePrimarySurfaceFamily
        self.hidesLauncherDuringAppMirroring = hidesLauncherDuringAppMirroring
        self.keepsMenuBarControlAvailable = keepsMenuBarControlAvailable
        self.keepsDockControlAvailable = keepsDockControlAvailable
        self.canRecoverFromMenuOrDock = canRecoverFromMenuOrDock
        self.returnsToLauncherWhenNoAppWindows = returnsToLauncherWhenNoAppWindows
        self.keepsDisplayRecoveryManual = keepsDisplayRecoveryManual
        self.primaryActionId = primaryActionId
        self.heroRunsPrimaryAction = heroRunsPrimaryAction
        self.reason = reason
    }
}

/// What Veil will do when every mirrored Windows app window is closed.
///
/// `quietMode` exists because "quiet" covers two outcomes a user experiences very differently:
/// suspending keeps their open apps and unsaved work, stopping shuts Windows down and loses them.
/// A single boolean could not express that, and the previous `stop-or-suspend-runtime` recommendation
/// named both without committing to either, so nobody could tell which was about to happen.
public struct WindowsAppRuntimeQuietPolicyStatus: Codable, Equatable, Sendable {
    /// Windows is suspended and its apps survive.
    public static let suspendMode = "suspend"
    /// Windows shuts down. Open apps and unsaved work are lost.
    public static let stopMode = "stop"
    /// Nothing will happen, because the runtime cannot be quieted right now.
    public static let noneMode = "none"

    public var isEnabled: Bool
    public var hasOpenedAppWindowThisSession: Bool
    public var openWindowCount: Int
    public var canQuietRuntime: Bool
    public var willQuietAutomatically: Bool
    public var automaticQuietDelaySeconds: Int
    /// Which of ``suspendMode``, ``stopMode``, or ``noneMode`` will actually run.
    public var quietMode: String
    /// Whether this VM can persist a running session at all. Derived from the same persistence summary
    /// `vm-session-status` uses, so the app and the CLI cannot disagree.
    public var canSuspendSession: Bool
    public var recommendedAction: String
    public var recommendedSuspendCommand: String?
    public var recommendedStopCommand: String?
    public var reason: String

    public init(
        isEnabled: Bool,
        hasOpenedAppWindowThisSession: Bool,
        openWindowCount: Int,
        canQuietRuntime: Bool,
        willQuietAutomatically: Bool,
        automaticQuietDelaySeconds: Int,
        quietMode: String = WindowsAppRuntimeQuietPolicyStatus.noneMode,
        canSuspendSession: Bool = false,
        recommendedAction: String,
        recommendedSuspendCommand: String? = nil,
        recommendedStopCommand: String? = nil,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.hasOpenedAppWindowThisSession = hasOpenedAppWindowThisSession
        self.openWindowCount = openWindowCount
        self.canQuietRuntime = canQuietRuntime
        self.willQuietAutomatically = willQuietAutomatically
        self.automaticQuietDelaySeconds = automaticQuietDelaySeconds
        self.quietMode = quietMode
        self.canSuspendSession = canSuspendSession
        self.recommendedAction = recommendedAction
        self.recommendedSuspendCommand = recommendedSuspendCommand
        self.recommendedStopCommand = recommendedStopCommand
        self.reason = reason
    }
}

public struct WindowsAppRuntimeLaunchPlanStatus: Codable, Equatable, Sendable {
    public var selectedAppId: String?
    public var pendingLaunchAppId: String?
    public var canRequestSelectedAppLaunch: Bool
    public var canLaunchSelectedAppNow: Bool
    public var willOpenAppAutomatically: Bool
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
        willOpenAppAutomatically: Bool,
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
        self.willOpenAppAutomatically = willOpenAppAutomatically
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
    public var canRunMultiAppProof: Bool
    public var recommendedProofKind: String?
    public var recommendedProofCommand: String?
    public var recommendedAppWindowProofCommand: String?
    public var recommendedCoherenceProofCommand: String?
    public var recommendedMVPProofCommand: String?
    public var recommendedMultiAppProofCommand: String?
    public var reason: String

    public init(
        selectedAppId: String?,
        canRunAppWindowProof: Bool,
        canRunCoherenceProof: Bool,
        canRunMVPProof: Bool,
        canRunMultiAppProof: Bool = false,
        recommendedProofKind: String? = nil,
        recommendedProofCommand: String? = nil,
        recommendedAppWindowProofCommand: String? = nil,
        recommendedCoherenceProofCommand: String? = nil,
        recommendedMVPProofCommand: String? = nil,
        recommendedMultiAppProofCommand: String? = nil,
        reason: String
    ) {
        self.selectedAppId = selectedAppId
        self.canRunAppWindowProof = canRunAppWindowProof
        self.canRunCoherenceProof = canRunCoherenceProof
        self.canRunMVPProof = canRunMVPProof
        self.canRunMultiAppProof = canRunMultiAppProof
        self.recommendedProofKind = recommendedProofKind
        self.recommendedProofCommand = recommendedProofCommand
        self.recommendedAppWindowProofCommand = recommendedAppWindowProofCommand
        self.recommendedCoherenceProofCommand = recommendedCoherenceProofCommand
        self.recommendedMVPProofCommand = recommendedMVPProofCommand
        self.recommendedMultiAppProofCommand = recommendedMultiAppProofCommand
        self.reason = reason
    }
}

public struct WindowsAppRuntimeProofArtifactStatus: Codable, Equatable, Sendable {
    public var diagnosticsDirectory: String
    public var recommendedProofDirectory: String
    public var notificationProofDirectory: String
    public var printerProofDirectory: String
    public var multiAppProofTargetAppIds: [String]
    public var multiAppProofCoverageCount: Int
    public var multiAppProofCoverageHealth: String
    public var latestProofsByApp: [WindowsAppRuntimeProofArtifactAppSummary]
    public var latestProofKind: String?
    public var latestProofPath: String?
    public var latestProofFileName: String?
    public var latestProofModifiedAt: Date?
    public var latestProofLatencyHealth: String?
    public var latestProofSlowestLatencyMeasurement: String?
    public var latestProofSlowestLatencyMilliseconds: Int?
    public var latestProofLatencyBudgetMilliseconds: Int?
    public var latestProofStaleTimeoutMilliseconds: Int?
    public var latestProofLatencyRecommendedAction: String?
    public var latestNotificationProofPath: String?
    public var latestNotificationProofFileName: String?
    public var latestNotificationProofModifiedAt: Date?
    public var latestNotificationProofStatus: String?
    public var latestNotificationProofId: String?
    public var latestNotificationProofTitle: String?
    public var latestNotificationProofReceivedAt: Date?
    public var latestPrinterBridgeProofPath: String?
    public var latestPrinterBridgeProofFileName: String?
    public var latestPrinterBridgeProofModifiedAt: Date?
    public var latestPrinterBridgeProofStatus: String?
    public var latestPrinterBridgeProofEvidencePath: String?
    public var latestPrinterBridgeProofEvidenceFileName: String?
    public var latestPrinterBridgeProofEvidenceByteCount: Int?
    public var latestPrinterBridgeProofEvidenceModifiedAt: Date?
    public var latestPrinterBridgeProofSharedPrinterName: String?
    public var latestPrinterBridgeProofWindowsPrinterName: String?
    public var latestPrinterBridgeProofIppEndpoint: String?
    public var reason: String

    public init(
        diagnosticsDirectory: String,
        recommendedProofDirectory: String,
        notificationProofDirectory: String,
        printerProofDirectory: String,
        multiAppProofTargetAppIds: [String] = WindowsAppRuntimeProofCoverageDefaults.targetAppIds,
        multiAppProofCoverageCount: Int = 0,
        multiAppProofCoverageHealth: String = "missing",
        latestProofsByApp: [WindowsAppRuntimeProofArtifactAppSummary] = [],
        latestProofKind: String? = nil,
        latestProofPath: String? = nil,
        latestProofFileName: String? = nil,
        latestProofModifiedAt: Date? = nil,
        latestProofLatencyHealth: String? = nil,
        latestProofSlowestLatencyMeasurement: String? = nil,
        latestProofSlowestLatencyMilliseconds: Int? = nil,
        latestProofLatencyBudgetMilliseconds: Int? = nil,
        latestProofStaleTimeoutMilliseconds: Int? = nil,
        latestProofLatencyRecommendedAction: String? = nil,
        latestNotificationProofPath: String? = nil,
        latestNotificationProofFileName: String? = nil,
        latestNotificationProofModifiedAt: Date? = nil,
        latestNotificationProofStatus: String? = nil,
        latestNotificationProofId: String? = nil,
        latestNotificationProofTitle: String? = nil,
        latestNotificationProofReceivedAt: Date? = nil,
        latestPrinterBridgeProofPath: String? = nil,
        latestPrinterBridgeProofFileName: String? = nil,
        latestPrinterBridgeProofModifiedAt: Date? = nil,
        latestPrinterBridgeProofStatus: String? = nil,
        latestPrinterBridgeProofEvidencePath: String? = nil,
        latestPrinterBridgeProofEvidenceFileName: String? = nil,
        latestPrinterBridgeProofEvidenceByteCount: Int? = nil,
        latestPrinterBridgeProofEvidenceModifiedAt: Date? = nil,
        latestPrinterBridgeProofSharedPrinterName: String? = nil,
        latestPrinterBridgeProofWindowsPrinterName: String? = nil,
        latestPrinterBridgeProofIppEndpoint: String? = nil,
        reason: String
    ) {
        self.diagnosticsDirectory = diagnosticsDirectory
        self.recommendedProofDirectory = recommendedProofDirectory
        self.notificationProofDirectory = notificationProofDirectory
        self.printerProofDirectory = printerProofDirectory
        self.multiAppProofTargetAppIds = multiAppProofTargetAppIds
        self.multiAppProofCoverageCount = multiAppProofCoverageCount
        self.multiAppProofCoverageHealth = multiAppProofCoverageHealth
        self.latestProofsByApp = latestProofsByApp
        self.latestProofKind = latestProofKind
        self.latestProofPath = latestProofPath
        self.latestProofFileName = latestProofFileName
        self.latestProofModifiedAt = latestProofModifiedAt
        self.latestProofLatencyHealth = latestProofLatencyHealth
        self.latestProofSlowestLatencyMeasurement = latestProofSlowestLatencyMeasurement
        self.latestProofSlowestLatencyMilliseconds = latestProofSlowestLatencyMilliseconds
        self.latestProofLatencyBudgetMilliseconds = latestProofLatencyBudgetMilliseconds
        self.latestProofStaleTimeoutMilliseconds = latestProofStaleTimeoutMilliseconds
        self.latestProofLatencyRecommendedAction = latestProofLatencyRecommendedAction
        self.latestNotificationProofPath = latestNotificationProofPath
        self.latestNotificationProofFileName = latestNotificationProofFileName
        self.latestNotificationProofModifiedAt = latestNotificationProofModifiedAt
        self.latestNotificationProofStatus = latestNotificationProofStatus
        self.latestNotificationProofId = latestNotificationProofId
        self.latestNotificationProofTitle = latestNotificationProofTitle
        self.latestNotificationProofReceivedAt = latestNotificationProofReceivedAt
        self.latestPrinterBridgeProofPath = latestPrinterBridgeProofPath
        self.latestPrinterBridgeProofFileName = latestPrinterBridgeProofFileName
        self.latestPrinterBridgeProofModifiedAt = latestPrinterBridgeProofModifiedAt
        self.latestPrinterBridgeProofStatus = latestPrinterBridgeProofStatus
        self.latestPrinterBridgeProofEvidencePath = latestPrinterBridgeProofEvidencePath
        self.latestPrinterBridgeProofEvidenceFileName = latestPrinterBridgeProofEvidenceFileName
        self.latestPrinterBridgeProofEvidenceByteCount = latestPrinterBridgeProofEvidenceByteCount
        self.latestPrinterBridgeProofEvidenceModifiedAt = latestPrinterBridgeProofEvidenceModifiedAt
        self.latestPrinterBridgeProofSharedPrinterName = latestPrinterBridgeProofSharedPrinterName
        self.latestPrinterBridgeProofWindowsPrinterName = latestPrinterBridgeProofWindowsPrinterName
        self.latestPrinterBridgeProofIppEndpoint = latestPrinterBridgeProofIppEndpoint
        self.reason = reason
    }
}

public enum WindowsAppRuntimeProofCoverageDefaults {
    public static let targetAppIds = ["winapp_notepad", "winapp_calculator", "winapp_paint"]
}

public struct WindowsAppRuntimeProofArtifactAppSummary: Codable, Equatable, Sendable {
    public var appId: String
    public var latestProofKind: String
    public var latestProofPath: String
    public var latestProofFileName: String
    public var latestProofModifiedAt: Date
    public var latestProofLatencyHealth: String?
    public var latestProofSlowestLatencyMeasurement: String?
    public var latestProofSlowestLatencyMilliseconds: Int?
    public var latestProofLatencyBudgetMilliseconds: Int?
    public var latestProofStaleTimeoutMilliseconds: Int?
    public var latestProofLatencyRecommendedAction: String?

    public init(
        appId: String,
        latestProofKind: String,
        latestProofPath: String,
        latestProofFileName: String,
        latestProofModifiedAt: Date,
        latestProofLatencyHealth: String? = nil,
        latestProofSlowestLatencyMeasurement: String? = nil,
        latestProofSlowestLatencyMilliseconds: Int? = nil,
        latestProofLatencyBudgetMilliseconds: Int? = nil,
        latestProofStaleTimeoutMilliseconds: Int? = nil,
        latestProofLatencyRecommendedAction: String? = nil
    ) {
        self.appId = appId
        self.latestProofKind = latestProofKind
        self.latestProofPath = latestProofPath
        self.latestProofFileName = latestProofFileName
        self.latestProofModifiedAt = latestProofModifiedAt
        self.latestProofLatencyHealth = latestProofLatencyHealth
        self.latestProofSlowestLatencyMeasurement = latestProofSlowestLatencyMeasurement
        self.latestProofSlowestLatencyMilliseconds = latestProofSlowestLatencyMilliseconds
        self.latestProofLatencyBudgetMilliseconds = latestProofLatencyBudgetMilliseconds
        self.latestProofStaleTimeoutMilliseconds = latestProofStaleTimeoutMilliseconds
        self.latestProofLatencyRecommendedAction = latestProofLatencyRecommendedAction
    }
}

public enum WindowsAppRuntimePrinterBridgeDefaults {
    public static let recommendedAction = "manual-ipp-experiment"
    public static let endpointTemplate = "http://10.0.2.2:631/printers/<shared-printer-name>"
    public static let planCommand = "veil-vmctl printer-bridge-plan --json --shared-printer <shared-printer-name>"
    public static let setupHint =
        "Share the Mac printer, then add it in Windows as an IPP network printer at http://10.0.2.2:631/printers/<shared-printer-name>."
}

public enum WindowsAppRuntimeDailyUseIntegrationDefaults {
    public static let borderlessCaptureRequirement =
        "Requires signed sparse package identity plus windowCapture capability before borderless Windows Graphics Capture consent can be requested."
    public static let notificationBridgeRequirement =
        "Requires signed sparse package identity and Windows UserNotificationListener consent before Windows notifications can be mirrored."
}

public struct WindowsAppRuntimeDailyUseReadinessStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var packageIdentityReady: Bool
    public var borderlessCapturePreflightPassed: Bool
    public var borderlessCaptureRecommendedAction: String
    public var borderlessCaptureRequirement: String
    public var notificationBridgePreflightPassed: Bool
    public var notificationBridgeRecommendedAction: String
    public var notificationBridgeRequirement: String
    public var printerBridgeMode: String
    public var printerBridgeRecommendedAction: String
    public var printerBridgeEndpointTemplate: String
    public var printerBridgePlanCommand: String
    public var printerBridgeSetupHint: String
    public var packageIdentityStatus: PackageIdentityStatus?
    public var packageIdentityStage: String?
    public var packageIdentitySucceeded: Bool?
    public var packageIdentityMessage: String?
    public var packageIdentityEvidencePath: String?
    public var recommendedAction: String
    public var recommendedCommand: String?
    public var reason: String

    public init(
        isEnabled: Bool = true,
        packageIdentityReady: Bool,
        borderlessCapturePreflightPassed: Bool,
        borderlessCaptureRecommendedAction: String,
        borderlessCaptureRequirement: String = WindowsAppRuntimeDailyUseIntegrationDefaults.borderlessCaptureRequirement,
        notificationBridgePreflightPassed: Bool,
        notificationBridgeRecommendedAction: String,
        notificationBridgeRequirement: String = WindowsAppRuntimeDailyUseIntegrationDefaults.notificationBridgeRequirement,
        printerBridgeMode: String,
        printerBridgeRecommendedAction: String = WindowsAppRuntimePrinterBridgeDefaults.recommendedAction,
        printerBridgeEndpointTemplate: String = WindowsAppRuntimePrinterBridgeDefaults.endpointTemplate,
        printerBridgePlanCommand: String = WindowsAppRuntimePrinterBridgeDefaults.planCommand,
        printerBridgeSetupHint: String = WindowsAppRuntimePrinterBridgeDefaults.setupHint,
        packageIdentityStatus: PackageIdentityStatus? = nil,
        packageIdentityStage: String? = nil,
        packageIdentitySucceeded: Bool? = nil,
        packageIdentityMessage: String? = nil,
        packageIdentityEvidencePath: String? = nil,
        recommendedAction: String,
        recommendedCommand: String? = nil,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.packageIdentityReady = packageIdentityReady
        self.borderlessCapturePreflightPassed = borderlessCapturePreflightPassed
        self.borderlessCaptureRecommendedAction = borderlessCaptureRecommendedAction
        self.borderlessCaptureRequirement = borderlessCaptureRequirement
        self.notificationBridgePreflightPassed = notificationBridgePreflightPassed
        self.notificationBridgeRecommendedAction = notificationBridgeRecommendedAction
        self.notificationBridgeRequirement = notificationBridgeRequirement
        self.printerBridgeMode = printerBridgeMode
        self.printerBridgeRecommendedAction = printerBridgeRecommendedAction
        self.printerBridgeEndpointTemplate = printerBridgeEndpointTemplate
        self.printerBridgePlanCommand = printerBridgePlanCommand
        self.printerBridgeSetupHint = printerBridgeSetupHint
        self.packageIdentityStatus = packageIdentityStatus
        self.packageIdentityStage = packageIdentityStage
        self.packageIdentitySucceeded = packageIdentitySucceeded
        self.packageIdentityMessage = packageIdentityMessage
        self.packageIdentityEvidencePath = packageIdentityEvidencePath
        self.recommendedAction = recommendedAction
        self.recommendedCommand = recommendedCommand
        self.reason = reason
    }
}

public struct WindowsAppRuntimeNotificationBridgeStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var canReceiveNotifications: Bool
    public var deliveredNotificationCount: Int
    public var latestNotification: WindowsNotificationReceivedEvent?
    public var recommendedAction: String
    public var reason: String

    public init(
        isEnabled: Bool = true,
        canReceiveNotifications: Bool,
        deliveredNotificationCount: Int,
        latestNotification: WindowsNotificationReceivedEvent? = nil,
        recommendedAction: String,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.canReceiveNotifications = canReceiveNotifications
        self.deliveredNotificationCount = deliveredNotificationCount
        self.latestNotification = latestNotification
        self.recommendedAction = recommendedAction
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
    public var runsInApp: Bool
    public var actionId: String?
    public var command: String?
    public var reason: String

    public init(
        id: String,
        title: String,
        source: String,
        isAvailable: Bool,
        runsInApp: Bool,
        actionId: String? = nil,
        command: String? = nil,
        reason: String
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.isAvailable = isAvailable
        self.runsInApp = runsInApp
        self.actionId = actionId
        self.command = command
        self.reason = reason
    }
}

public struct WindowsAppRuntimeLaunchOnboardingStatus: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var state: String
    public var currentStepId: String
    public var currentStepTitle: String
    public var currentStepDetail: String
    public var usesSinglePrimarySurface: Bool
    public var expectedVisibleSurfaceCount: Int
    public var canContinueInApp: Bool
    public var heroRunsPrimaryAction: Bool
    public var keepsRecoveryInMenuOrDock: Bool
    public var keepsVMDisplayManual: Bool
    public var pendingLiveProof: Bool
    public var completedStepCount: Int
    public var totalStepCount: Int
    public var currentStepNumber: Int
    public var progressLabel: String
    public var primaryActionId: String?
    public var primaryCommand: String?
    public var reason: String

    public init(
        isEnabled: Bool = true,
        state: String,
        currentStepId: String,
        currentStepTitle: String,
        currentStepDetail: String,
        usesSinglePrimarySurface: Bool,
        expectedVisibleSurfaceCount: Int,
        canContinueInApp: Bool,
        heroRunsPrimaryAction: Bool,
        keepsRecoveryInMenuOrDock: Bool,
        keepsVMDisplayManual: Bool,
        pendingLiveProof: Bool,
        completedStepCount: Int = 0,
        totalStepCount: Int = 0,
        currentStepNumber: Int = 0,
        progressLabel: String = "Step 0 of 0",
        primaryActionId: String? = nil,
        primaryCommand: String? = nil,
        reason: String
    ) {
        self.isEnabled = isEnabled
        self.state = state
        self.currentStepId = currentStepId
        self.currentStepTitle = currentStepTitle
        self.currentStepDetail = currentStepDetail
        self.usesSinglePrimarySurface = usesSinglePrimarySurface
        self.expectedVisibleSurfaceCount = expectedVisibleSurfaceCount
        self.canContinueInApp = canContinueInApp
        self.heroRunsPrimaryAction = heroRunsPrimaryAction
        self.keepsRecoveryInMenuOrDock = keepsRecoveryInMenuOrDock
        self.keepsVMDisplayManual = keepsVMDisplayManual
        self.pendingLiveProof = pendingLiveProof
        self.completedStepCount = completedStepCount
        self.totalStepCount = totalStepCount
        self.currentStepNumber = currentStepNumber
        self.progressLabel = progressLabel
        self.primaryActionId = primaryActionId
        self.primaryCommand = primaryCommand
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
    public var oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    public var launchOnboarding: WindowsAppRuntimeLaunchOnboardingStatus
    public var macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus
    /// Optional so reports written before this section existed still decode and validate. Absent means
    /// the report predates the check, which is different from a matched scale.
    public var displayScaling: WindowsAppRuntimeDisplayScalingStatus?
    public var quietRuntime: WindowsAppRuntimeQuietPolicyStatus
    public var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    public var proofPlan: WindowsAppRuntimeProofPlanStatus
    public var proofArtifacts: WindowsAppRuntimeProofArtifactStatus
    public var dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    public var notificationBridge: WindowsAppRuntimeNotificationBridgeStatus
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
        oneScreenUX: WindowsAppRuntimeOneScreenUXStatus,
        launchOnboarding: WindowsAppRuntimeLaunchOnboardingStatus,
        macWindowIntegration: WindowsAppRuntimeMacWindowIntegrationStatus,
        displayScaling: WindowsAppRuntimeDisplayScalingStatus? = nil,
        quietRuntime: WindowsAppRuntimeQuietPolicyStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        proofPlan: WindowsAppRuntimeProofPlanStatus,
        proofArtifacts: WindowsAppRuntimeProofArtifactStatus,
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus,
        notificationBridge: WindowsAppRuntimeNotificationBridgeStatus,
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
        self.oneScreenUX = oneScreenUX
        self.launchOnboarding = launchOnboarding
        self.macWindowIntegration = macWindowIntegration
        self.displayScaling = displayScaling
        self.quietRuntime = quietRuntime
        self.launchPlan = launchPlan
        self.proofPlan = proofPlan
        self.proofArtifacts = proofArtifacts
        self.dailyUseReadiness = dailyUseReadiness
        self.notificationBridge = notificationBridge
        self.releaseGate = releaseGate
        self.primaryNextAction = primaryNextAction
        self.actions = actions
    }
}
