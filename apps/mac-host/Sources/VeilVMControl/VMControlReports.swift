import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

struct WindowsPrinterBridgePlan: Codable, Equatable {
    var kind: String = "windowsPrinterBridgePlan"
    var generatedAt: Date
    var mode: String
    var hostAddress: String
    var ippPort: Int
    var sharedPrinterName: String
    var windowsPrinterName: String
    var ippEndpoint: String
    var macOSSharingHint: String
    var windowsAddPrinterCommand: String
    var windowsVerifyPrinterCommand: String
    var manualTestPageInstruction: String
    var setupSteps: [String]
    var verificationSteps: [String]
    var limitations: [String]
    var nextActions: [String]
}

struct WindowsPrinterBridgeProofReport: Codable, Equatable {
    var kind: String = "windowsPrinterBridgeProof"
    var status: String
    var provedAt: Date
    var evidencePath: String
    var evidenceFileName: String
    var evidenceByteCount: Int
    var evidenceModifiedAt: Date?
    var plan: WindowsPrinterBridgePlan
    var savedProofPath: String?
    var nextActions: [String]
}

struct QEMUConsoleCaptureRecord: Codable, Equatable {
    var kind: String = "qemuConsoleCapture"
    var monitorSocketPath: String
    var consoleScreenshotPath: String
    var capturedAt: Date
}

struct QEMUGuestAgentInstallConsoleEvidence: Codable, Equatable {
    var kind: String = "qemuGuestAgentInstallConsoleEvidence"
    var capture: QEMUConsoleCaptureRecord?
    var visualObservation: QEMUConsoleVisualObservation?
    var reviewHint: String
    var expectedVisibleStates: [String]
}

enum QEMUConsoleReadinessStatus: String, Codable, Equatable {
    case ready
    case timedOut
    case unavailable
    case skipped
}

struct QEMUConsoleVisualObservation: Codable, Equatable {
    var phase: String
    var attempt: Int
    var capturedAt: Date
    var source: String
    var screenshotPath: String?
    var state: QEMUConsoleVisualState
    var recognizedText: [String]
    var metrics: QEMUConsoleFrameMetrics?
    var differenceFromReference: QEMUConsoleFrameDifference?
    var wakeKeySent: Bool
    var errorMessage: String?
}

struct QEMUConsoleReadinessReport: Codable, Equatable {
    var phase: String
    var status: QEMUConsoleReadinessStatus
    var expectedStates: [QEMUConsoleVisualState]
    var timeoutSeconds: Int
    var attempts: Int
    var observations: [QEMUConsoleVisualObservation]
}

struct QEMUKeySendResult: Codable, Equatable {
    var key: String
    var transport: String
    var socketPath: String
    var monitorCommand: String
    var terminationStatus: Int32?
    var didLaunchSender: Bool
}

struct QEMUKeySendRecord: Codable, Equatable {
    var kind: String = "qemuKeySend"
    var monitorSocketPath: String
    var keys: [String]
    var results: [QEMUKeySendResult]
    var sentAt: Date
}

struct QEMUGuestAgentInstallAttemptReport: Codable, Equatable {
    var kind: String = "qemuGuestAgentInstallAttempt"
    var commandText: String
    var activationTap: QEMUPointerTapRecord?
    var runConfirmationTap: QEMUPointerTapRecord?
    var uacApprovalTap: QEMUPointerTapRecord?
    var uacApprovalKeySend: QEMUKeySendRecord?
    var keySend: QEMUKeySendRecord
    var desktopReadiness: QEMUConsoleReadinessReport
    var runReadiness: QEMUConsoleReadinessReport
    var uacReadiness: QEMUConsoleReadinessReport
    var agentWait: AgentConnectionWaitReport
    var postAttemptConsole: QEMUGuestAgentInstallConsoleEvidence
    var status: AgentConnectionWaitStatus
    var nextActions: [String]
}

struct QEMUConsoleVisualSnapshot {
    var frame: RFBRenderedFrame
    var observation: QEMUConsoleVisualObservation
}

struct QEMUPointerClickRecord: Codable, Equatable {
    var kind: String = "qemuPointerClick"
    var monitorSocketPath: String
    var qmpSocketPath: String
    var x: Int
    var y: Int
    var results: [QEMUKeySendResult]
    var sentAt: Date
}

struct QEMUPowerDownRecord: Codable, Equatable {
    var kind: String = "qemuPowerDown"
    var pid: Int32?
    var monitorSocketPath: String
    var qmpSocketPath: String?
    var transport: String
    var socketPath: String
    var command: String
    var didLaunchSender: Bool
    var terminationStatus: Int32?
    var waitedSeconds: Int
    var didExitWithinWait: Bool
    var requestedAt: Date
}

struct QEMUForceStopRecord: Codable, Equatable {
    var kind: String = "qemuForceStop"
    var pid: Int32?
    var signal: String
    var didSignalProcess: Bool
    var waitedSeconds: Int
    var didExitWithinWait: Bool
    var requestedAt: Date
}

struct QEMUDisplaySmokeRecord: Codable, Equatable {
    var kind: String = "qemuDisplaySmoke"
    var pid: Int32?
    var endpoint: String
    var width: Int
    var height: Int
    var frameSequence: Int
    var pixelByteCount: Int
    var visualState: QEMUConsoleVisualState
    var frameMetrics: QEMUConsoleFrameMetrics
    var recognizedText: [String]
    var screenshotPath: String?
    var waitedSeconds: Int
    var capturedAt: Date
}

enum AppRuntimeRecommendedProofRunStatus: String, Codable, Equatable {
    case proved
    case unavailable
}

struct AppRuntimeRecommendedProofRun: Codable, Equatable {
    var kind: String = "windowsAppRuntimeRecommendedProofRun"
    var proofKind: String
    var command: String
    var appId: String
    var status: AppRuntimeRecommendedProofRunStatus
    var savedProofPath: String?
    var windowId: String?
    var windowTitle: String?
    var frameSequence: Int?
    var inputEventCount: Int?
    var clipboardTextByteCount: Int?
    var nextActions: [String]
}

struct AppRuntimeDisplayRecovery: Codable, Equatable {
    var kind: String = "windowsAppRuntimeDisplayRecovery"
    var command: String
    var beforePreviewStatus: VMConsolePreviewStatus?
    var afterPreviewStatus: VMConsolePreviewStatus?
    var beforeScreenshotPath: String?
    var afterScreenshotPath: String?
    var capture: QEMUConsoleCaptureRecord?
    var error: String?
}

struct AppRuntimeNotificationConsent: Codable, Equatable {
    var kind: String = "windowsNotificationConsentRequest"
    var command: String
    var response: WindowsNotificationListenerResponse?
    var error: String?
}

struct AppRuntimeActionReport: Codable, Equatable {
    var kind: String = "windowsAppRuntimeAction"
    var action: VMControlArguments.AppRuntimeAction
    var requestedAt: Date
    var endpoint: String
    var connectionMode: HostConnectionMode
    var accepted: Bool
    var appId: String?
    var windowId: String?
    var foregroundWindowId: String?
    var foregroundWindowTitle: String?
    var pendingLaunchAppId: String?
    var launchPlan: WindowsAppRuntimeLaunchPlanStatus?
    var proofPlan: WindowsAppRuntimeProofPlanStatus
    var launch: AppLaunchResponse?
    var window: WindowCreatedEvent?
    var focus: WindowFocusResponse?
    var close: WindowCloseResponse?
    var closedWindows: [WindowCloseResponse]
    var clipboard: ClipboardTextSet?
    var mouseInputs: [InputMouseEvent]
    var keyInputs: [InputKeyEvent]
    var typedTextCharacterCount: Int?
    var restoredWindows: [WindowCreatedEvent]
    var restoreRequestedAppIds: [String]
    var broughtForwardWindowIds: [String]
    var restartedFrameWindowIds: [String]
    var recoveredFrameWindowIds: [String]
    var reopenRequestedWindowIds: [String]
    var reopenedWindows: [WindowCreatedEvent]
    var proof: AppRuntimeRecommendedProofRun?
    var multiAppProof: WindowsMultiAppProofReport?
    var notificationProof: WindowsNotificationProofReport?
    var displayRecovery: AppRuntimeDisplayRecovery?
    var agentWait: AgentConnectionWaitReport?
    var agentRepair: QEMUGuestAgentInstallAttemptReport?
    var sparsePackagePreparation: QEMUGuestAgentInstallAttemptReport?
    var notificationConsent: AppRuntimeNotificationConsent?
    var quietRuntime: WindowsAppRuntimeQuietPolicyStatus?
    var runtimeStop: VMRuntimeSnapshot?
    /// Separate from `runtimeStop` on purpose: the stop-runtime contract pins `runtimeStop.state` to
    /// `stopped`, so a suspend has to report its own outcome rather than borrowing that field.
    var runtimeSuspend: VMRuntimeSnapshot?
    var status: WindowsAppRuntimeStatusReport
    var nextActions: [String]
}

struct AppRuntimeReviewStep: Codable, Equatable {
    var id: String
    var title: String
    var state: String
    var isPassing: Bool
    var evidence: String
    var nextActionCommand: String?
}

struct AppRuntimeReviewScreenshotSlot: Codable, Equatable {
    var id: String
    var title: String
    var expectedSurface: String
    var expectedFileName: String
    var attachmentState: String
    var attachmentPath: String?
    var attachmentIssueReason: String?
    var invalidAttachmentPath: String?
    var attachmentByteCount: Int?
    var attachmentWidth: Int?
    var attachmentHeight: Int?
    var invalidAttachmentByteCount: Int?
    var invalidAttachmentWidth: Int?
    var invalidAttachmentHeight: Int?
}

struct AppRuntimeReviewEvidence: Codable, Equatable {
    var latestAppCheckKind: String?
    var latestAppCheckPath: String?
    var latestAppCheckModifiedAt: Date?
    var multiAppProofTargetAppIds: [String]?
    var multiAppProofCoverageCount: Int?
    var multiAppProofCoverageHealth: String?
    var latestAppCheckLatencyHealth: String?
    var latestAppCheckSlowestLatencyMeasurement: String?
    var latestAppCheckSlowestLatencyMilliseconds: Int?
    var latestAppCheckLatencyBudgetMilliseconds: Int?
    var latestAppCheckStaleTimeoutMilliseconds: Int?
    var latestAppCheckLatencyRecommendedAction: String?
    var latestNotificationProofPath: String?
    var latestNotificationProofModifiedAt: Date?
    var latestNotificationProofStatus: String?
    var latestNotificationProofId: String?
    var latestNotificationProofTitle: String?
    var latestNotificationProofReceivedAt: Date?
    var latestPrinterBridgeProofPath: String?
    var latestPrinterBridgeProofModifiedAt: Date?
    var latestPrinterBridgeProofStatus: String?
    var latestPrinterBridgeProofEvidencePath: String?
    var latestPrinterBridgeProofEvidenceFileName: String?
    var latestPrinterBridgeProofEvidenceByteCount: Int?
    var latestPrinterBridgeProofEvidenceModifiedAt: Date?
    var latestPrinterBridgeProofIppEndpoint: String?
    var dailyUsePackageIdentityReady: Bool
    var dailyUseBorderlessCapturePreflightPassed: Bool
    var dailyUseNotificationBridgePreflightPassed: Bool
    var dailyUseRecommendedAction: String
    var dailyUseRecommendedCommand: String?
    var dailyUseReason: String
    var dailyUsePackageIdentityStage: String?
    var dailyUsePackageIdentitySucceeded: Bool?
    var dailyUsePackageIdentityEvidencePath: String?
    var diagnosticsDirectory: String
    var screenshotEvidenceDirectory: String?
    var recommendedAppCheckCommand: String?
    var hostAppBundle: AppRuntimeReviewHostAppBundleEvidence
}

struct AppRuntimeReviewHostAppBundleEvidence: Codable, Equatable {
    var verificationCommand: String
    var appBundlePath: String
    var isStagedBundlePresent: Bool
    var infoPlistExists: Bool
    var executableExists: Bool
    var appIconExists: Bool
    var bundleIdentifier: String?
    var expectedBundleIdentifier: String
    var latestLaunchReport: AppRuntimeReviewHostAppLaunchReportEvidence
    var latestFailedLaunchReportPath: String?
    var latestFailedLaunchReportModifiedAt: Date?
    var isVerificationReady: Bool
}

struct AppRuntimeReviewHostAppLaunchReportEvidence: Codable, Equatable {
    var reportPath: String?
    var modifiedAt: Date?
    var meetsLauncherContract: Bool
    var isCurrentForBundle: Bool
    var bundleIdentifier: String?
    var expectedBundleIdentifier: String
    var mainWindowCount: Int?
    var visibleMainWindowCount: Int?
    var duplicateMainWindowCount: Int?
    var frameWidth: Double?
    var frameHeight: Double?
    var minWidth: Double?
    var minHeight: Double?
    var titlebarAppearsTransparent: Bool?
    var hasFullSizeContentView: Bool?
    var appIconSource: String?
}

struct AppRuntimeReviewCard: Codable, Equatable {
    var kind: String = "windowsAppRuntimeReviewCard"
    var generatedAt: Date
    var isReadyForReview: Bool
    var areRequiredScreenshotsAttached: Bool
    var requiredScreenshotCount: Int
    var attachedScreenshotCount: Int
    var invalidScreenshotCount: Int
    var minimumScreenshotWidth: Int
    var minimumScreenshotHeight: Int
    var appFlowSummary: String
    var nextStepTitle: String
    var nextActionCommand: String?
    var launchOnboarding: WindowsAppRuntimeLaunchOnboardingStatus
    var detail: String
    var steps: [AppRuntimeReviewStep]
    var screenshotSlots: [AppRuntimeReviewScreenshotSlot]
    var evidence: AppRuntimeReviewEvidence
    var statusCommand: String
    var status: WindowsAppRuntimeStatusReport
}

struct AppRuntimeReviewEvidenceFile: Codable, Equatable {
    var slotId: String
    var title: String
    var expectedFileName: String
    var path: String
    var expectedSurface: String
}

struct AppRuntimeReviewAppCheckProofFile: Codable, Equatable {
    var expectedFileName: String
    var path: String
    var command: String
    var requiredKind: String
    var requiredStatus: String
}

struct AppRuntimeReviewCaptureStep: Codable, Equatable {
    var order: Int
    var slotId: String
    var title: String
    var expectedFileName: String
    var instruction: String
    var captureCommand: String
    var supportingCommand: String?

    init(
        order: Int,
        slotId: String,
        title: String,
        expectedFileName: String,
        instruction: String,
        captureCommand: String = "",
        supportingCommand: String? = nil
    ) {
        self.order = order
        self.slotId = slotId
        self.title = title
        self.expectedFileName = expectedFileName
        self.instruction = instruction
        self.captureCommand = captureCommand
        self.supportingCommand = supportingCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decode(Int.self, forKey: .order)
        slotId = try container.decode(String.self, forKey: .slotId)
        title = try container.decode(String.self, forKey: .title)
        expectedFileName = try container.decode(String.self, forKey: .expectedFileName)
        instruction = try container.decode(String.self, forKey: .instruction)
        captureCommand = try container.decodeIfPresent(String.self, forKey: .captureCommand) ?? ""
        supportingCommand = try container.decodeIfPresent(String.self, forKey: .supportingCommand)
    }
}

struct AppRuntimeReviewEvidenceManifest: Codable, Equatable {
    static let defaultMinimumScreenshotWidth = 640
    static let defaultMinimumScreenshotHeight = 360

    var kind: String = "windowsAppRuntimeReviewEvidenceManifest"
    var generatedAt: Date
    var evidenceDirectory: String
    var manifestPath: String
    var readmePath: String
    var requiredScreenshotCount: Int
    var minimumScreenshotWidth: Int
    var minimumScreenshotHeight: Int
    var screenshotFiles: [AppRuntimeReviewEvidenceFile]
    var appCheckProofFile: AppRuntimeReviewAppCheckProofFile
    var captureSteps: [AppRuntimeReviewCaptureStep]
    var reviewCommand: String
    var verifyCommand: String
    var openEvidenceDirectoryCommand: String
    var nextActions: [String]

    init(
        generatedAt: Date,
        evidenceDirectory: String,
        manifestPath: String,
        readmePath: String,
        requiredScreenshotCount: Int,
        minimumScreenshotWidth: Int = AppRuntimeReviewEvidenceManifest.defaultMinimumScreenshotWidth,
        minimumScreenshotHeight: Int = AppRuntimeReviewEvidenceManifest.defaultMinimumScreenshotHeight,
        screenshotFiles: [AppRuntimeReviewEvidenceFile],
        appCheckProofFile: AppRuntimeReviewAppCheckProofFile,
        captureSteps: [AppRuntimeReviewCaptureStep],
        reviewCommand: String,
        verifyCommand: String = "",
        openEvidenceDirectoryCommand: String = "",
        nextActions: [String]
    ) {
        self.generatedAt = generatedAt
        self.evidenceDirectory = evidenceDirectory
        self.manifestPath = manifestPath
        self.readmePath = readmePath
        self.requiredScreenshotCount = requiredScreenshotCount
        self.minimumScreenshotWidth = minimumScreenshotWidth
        self.minimumScreenshotHeight = minimumScreenshotHeight
        self.screenshotFiles = screenshotFiles
        self.appCheckProofFile = appCheckProofFile
        self.captureSteps = captureSteps
        self.reviewCommand = reviewCommand
        self.verifyCommand = verifyCommand
        self.openEvidenceDirectoryCommand = openEvidenceDirectoryCommand
        self.nextActions = nextActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "windowsAppRuntimeReviewEvidenceManifest"
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        evidenceDirectory = try container.decode(String.self, forKey: .evidenceDirectory)
        manifestPath = try container.decode(String.self, forKey: .manifestPath)
        readmePath = try container.decode(String.self, forKey: .readmePath)
        requiredScreenshotCount = try container.decode(Int.self, forKey: .requiredScreenshotCount)
        minimumScreenshotWidth = try container.decodeIfPresent(Int.self, forKey: .minimumScreenshotWidth) ?? Self.defaultMinimumScreenshotWidth
        minimumScreenshotHeight = try container.decodeIfPresent(Int.self, forKey: .minimumScreenshotHeight) ?? Self.defaultMinimumScreenshotHeight
        screenshotFiles = try container.decode([AppRuntimeReviewEvidenceFile].self, forKey: .screenshotFiles)
        appCheckProofFile = try container.decodeIfPresent(AppRuntimeReviewAppCheckProofFile.self, forKey: .appCheckProofFile)
            ?? AppRuntimeReviewAppCheckProofFile(
                expectedFileName: "mvp-proof.json",
                path: "\(evidenceDirectory)/mvp-proof.json",
                command: "",
                requiredKind: "windowsMVPProof",
                requiredStatus: "proved"
            )
        captureSteps = try container.decode([AppRuntimeReviewCaptureStep].self, forKey: .captureSteps)
        reviewCommand = try container.decode(String.self, forKey: .reviewCommand)
        verifyCommand = try container.decodeIfPresent(String.self, forKey: .verifyCommand) ?? ""
        openEvidenceDirectoryCommand = try container.decodeIfPresent(String.self, forKey: .openEvidenceDirectoryCommand) ?? ""
        nextActions = try container.decode([String].self, forKey: .nextActions)
    }
}

struct AppRuntimeReviewMissingCaptureStep: Codable, Equatable {
    var order: Int
    var slotId: String
    var title: String
    var expectedFileName: String
    var path: String
    var instruction: String
    var captureCommand: String
    var supportingCommand: String?
}

struct AppRuntimeReviewInvalidScreenshotFile: Codable, Equatable {
    var path: String
    var reason: String
    var byteCount: Int?
    var width: Int?
    var height: Int?
    var minimumWidth: Int
    var minimumHeight: Int
}

struct AppRuntimeReviewScreenshotEvidenceSummary: Codable, Equatable {
    var state: String
    var requiredScreenshotCount: Int
    var validScreenshotCount: Int
    var missingScreenshotCount: Int
    var invalidScreenshotCount: Int
    var pendingScreenshotCount: Int
    var minimumWidth: Int
    var minimumHeight: Int
    var isScreenshotEvidenceReady: Bool
    var nextStepKind: String
    var nextStepTitle: String
    var nextExpectedFileName: String?
    var nextCaptureCommand: String?
}

struct AppRuntimeReviewNextEvidenceAction: Codable, Equatable {
    var kind: String
    var title: String
    var command: String
    var isReadyToShare: Bool
    var expectedFileName: String?
    var path: String?
    var instruction: String?
    var supportingCommand: String?
}

struct AppRuntimeReviewAppCheckProofEvidence: Codable, Equatable {
    var expectedFileName: String
    var path: String
    var command: String
    var requiredKind: String
    var requiredStatus: String
    var exists: Bool
    var isValid: Bool
    var kind: String?
    var status: String?
    var appId: String?
    var issueReason: String?
}

struct AppRuntimeReviewPrinterBridgeProofEvidence: Codable, Equatable {
    var path: String
    var requiredKind: String
    var requiredStatus: String
    var exists: Bool
    var isValid: Bool
    var kind: String?
    var status: String?
    var evidencePath: String?
    var evidenceFileName: String?
    var evidenceByteCount: Int?
    var ippEndpoint: String?
    var issueReason: String?
}

struct AppRuntimeReviewNotificationProofEvidence: Codable, Equatable {
    var path: String
    var command: String
    var requiredKind: String
    var requiredStatus: String
    var exists: Bool
    var isValid: Bool
    var kind: String?
    var status: String?
    var notificationId: String?
    var title: String?
    var receivedAt: Date?
    var issueReason: String?
}

struct AppRuntimeReviewEvidenceVerification: Codable, Equatable {
    var kind: String = "windowsAppRuntimeReviewEvidenceVerification"
    var generatedAt: Date
    var evidenceDirectory: String
    var manifestPath: String
    var readmePath: String
    var manifestExists: Bool
    var readmeExists: Bool
    var requiredScreenshotCount: Int
    var attachedScreenshotCount: Int
    var minimumScreenshotWidth: Int
    var minimumScreenshotHeight: Int
    var isComplete: Bool
    var missingFiles: [String]
    var invalidScreenshotFiles: [AppRuntimeReviewInvalidScreenshotFile]
    var appCheckProof: AppRuntimeReviewAppCheckProofEvidence
    var notificationProof: AppRuntimeReviewNotificationProofEvidence?
    var printerBridgeProof: AppRuntimeReviewPrinterBridgeProofEvidence?
    var screenshotEvidenceSummary: AppRuntimeReviewScreenshotEvidenceSummary
    var nextEvidenceAction: AppRuntimeReviewNextEvidenceAction
    var invalidCaptureSteps: [AppRuntimeReviewMissingCaptureStep]
    var nextInvalidCaptureStep: AppRuntimeReviewMissingCaptureStep?
    var missingCaptureSteps: [AppRuntimeReviewMissingCaptureStep]
    var nextMissingCaptureStep: AppRuntimeReviewMissingCaptureStep?
    var review: AppRuntimeReviewCard
    var manifest: AppRuntimeReviewEvidenceManifest?
    var reviewCommand: String
    var verifyCommand: String
    var openEvidenceDirectoryCommand: String
    var nextActions: [String]
}

struct WindowsMultiAppProofReport: Codable, Equatable {
    var kind: String = "windowsMultiAppProof"
    var endpoint: String
    var provedAt: Date
    var proofDirectory: String
    var aggregateReportPath: String
    var appIds: [String]
    var targetAppIds: [String]
    var waitSeconds: Int
    var proofKind: String
    var provedAppCount: Int
    var failedAppCount: Int
    var coverageHealth: String
    var results: [WindowsMultiAppProofResult]
    var nextActions: [String]
}

struct WindowsMultiAppProofResult: Codable, Equatable {
    var appId: String
    var status: String
    var proofKind: String?
    var proofPath: String?
    var latencyHealth: String?
    var slowestLatencyMeasurement: String?
    var slowestLatencyMilliseconds: Int?
    var latencyBudgetMilliseconds: Int?
    var staleTimeoutMilliseconds: Int?
    var latencyRecommendedAction: String?
    var windowId: String?
    var windowTitle: String?
    var errorMessage: String?
}

struct WindowsMultiAppProofLatencySummary: Equatable {
    var health: String
    var slowestMeasurement: String
    var slowestElapsedMilliseconds: Int
    var freshFrameBudgetMilliseconds: Int
    var staleFrameTimeoutMilliseconds: Int
    var recommendedAction: String
}
