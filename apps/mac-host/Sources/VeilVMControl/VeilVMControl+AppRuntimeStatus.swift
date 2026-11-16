import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    @MainActor
    static func printAppRuntimeStatus(
        json: Bool,
        demo: Bool,
        hostBackingScale: Double? = nil
    ) async throws {
        let report = try await appRuntimeStatusReport(demo: demo, hostBackingScale: hostBackingScale)
        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows app runtime: \(report.connection.mode.rawValue)")
        print("Live agent: \(report.connection.hasLiveAgentConnection ? "yes" : "no")")
        if let agentVersion = report.connection.agentVersion {
            print("Agent: \(agentVersion)")
        }
        if let detail = report.connection.connectionDetail {
            print("Detail: \(detail)")
        }
        print("Guest agent diagnostics: \(report.guestAgentDiagnostics.recommendedAction)")
        print("Guest agent endpoint: \(report.guestAgentDiagnostics.endpoint)")
        print("Guest agent diagnostic command: \(report.guestAgentDiagnostics.diagnosticCommand)")
        print("Guest agent wait command: \(report.guestAgentDiagnostics.waitCommand)")
        print("Local runtime: \(report.localRuntime.recommendedAction)")
        print("Local runtime boot ready: \(report.localRuntime.bootReady ? "yes" : "no")")
        if let installEvidence = report.localRuntime.installEvidence {
            print("Local runtime install evidence: \(installEvidence.kind.rawValue)")
            print("Local runtime installed: \(installEvidence.isInstalled ? "yes" : "no")")
            print("Local runtime install evidence detail: \(installEvidence.detail)")
        }
        print("Local runtime reason: \(report.localRuntime.reason)")
        print("Local runtime install status command: \(report.localRuntime.recommendedInstallStatusCommand)")
        if let previewStatus = report.localRuntime.consolePreviewStatus {
            print("Local runtime console preview: \(previewStatus.rawValue)")
        }
        if let prepareCommand = report.localRuntime.recommendedPrepareCommand {
            print("Local runtime prepare command: \(prepareCommand)")
        }
        if let displayCommand = report.localRuntime.recommendedDisplayCommand {
            print("Local runtime display command: \(displayCommand)")
        }
        if let recoveryCommand = report.localRuntime.recommendedRecoveryCommand {
            print("Local runtime recovery command: \(recoveryCommand)")
        }
        print("Pending launch queued: \(report.pendingLaunch.isQueued ? "yes" : "no")")
        if let pendingLaunchAppId = report.pendingLaunch.appId {
            print("Pending launch app: \(pendingLaunchAppId)")
        }
        print("Pending launch auto-reconnect: \(report.pendingLaunch.willLaunchOnAgentReconnect ? "yes" : "no")")
        print("Pending launch action: \(report.pendingLaunch.recommendedAction)")
        print("Apps: \(report.apps.count)")
        print("Open Windows app windows: \(report.mirrorSessions.count)")
        for session in report.mirrorSessions {
            let age = session.latestFrameAgeMilliseconds.map { "\($0)ms old" }
                ?? session.frameStreamWaitingAgeMilliseconds.map { "\($0)ms waiting" }
                ?? "no frame yet"
            let interval = session.latestFrameIntervalMilliseconds.map { ", \($0)ms interval" } ?? ""
            let restarts = session.frameStreamRestartCount > 0 ? ", \(session.frameStreamRestartCount) restarts" : ""
            let escalation = session.frameStreamRecoveryEscalated ? ", recovery needed" : ""
            let reopen = session.frameStreamReopenEscalated ? ", reopen needed" : ""
            print("Window frame stream \(session.windowId): \(session.frameStreamStatus.rawValue) (\(age)\(interval), \(session.receivedFrameCount) frames\(restarts)\(escalation)\(reopen))")
        }
        print("Dock integration: \(report.dockIntegration.isEnabled ? "enabled" : "disabled")")
        print("Dock pending launches: \(report.dockIntegration.pendingLaunchCount)")
        print("Dock runtime badge: \(report.dockIntegration.badgeLabel ?? "none")")
        print("Dock can bring apps forward: \(report.dockIntegration.canBringWindowsAppsForward ? "yes" : "no")")
        print("Menu bar status: \(report.menuBarIntegration.statusTitle)")
        print("Menu bar symbol: \(report.menuBarIntegration.symbolName)")
        print("Menu bar primary action: \(report.menuBarIntegration.primaryActionTitle)")
        print("Launcher action: \(report.launcherVisibility.recommendedAction)")
        print("Launcher hidden for apps: \(report.launcherVisibility.shouldHideMainWindow ? "yes" : "no")")
        print("Visible surface: \(report.visibleSurfacePolicy.primarySurface)")
        print("Expected visible surfaces: \(report.visibleSurfacePolicy.expectedVisibleSurfaceCount)")
        print("Recovery display: \(report.visibleSurfacePolicy.keepsRecoveryDisplayManual ? "manual" : "automatic")")
        print("One-screen UX: \(oneScreenUXSummary(report.oneScreenUX))")
        print("One-screen controls: \(oneScreenUXControls(report.oneScreenUX))")
        print("Launch onboarding: \(report.launchOnboarding.state)")
        print("Launch onboarding step: \(report.launchOnboarding.currentStepTitle)")
        print("Launch onboarding continues in app: \(report.launchOnboarding.canContinueInApp ? "yes" : "no")")
        if let primaryActionId = report.launchOnboarding.primaryActionId {
            print("Launch onboarding action: \(primaryActionId)")
        }
        print("App flow: \(appFlowSummary(report.releaseGate))")
        print("Next app step: \(appFlowNextStepTitle(report.releaseGate))")
        print("App flow detail: \(appFlowDetail(report.releaseGate))")
        if let nextAppCommand = appFlowNextCommand(report.releaseGate) {
            print("Next app command: \(nextAppCommand)")
        }
        print("Primary next action: \(report.primaryNextAction.title)")
        print("Primary next action available: \(report.primaryNextAction.isAvailable ? "yes" : "no")")
        print("Primary next action runs in app: \(report.primaryNextAction.runsInApp ? "yes" : "no")")
        if let primaryCommand = report.primaryNextAction.command {
            print("Primary next command: \(primaryCommand)")
        }
        print("Screenshot slots: \(report.releaseGate.screenshotSlots.map(\.title).joined(separator: ", "))")
        print("Mac window integration: \(report.macWindowIntegration.isEnabled ? "enabled" : "disabled")")
        print("Mac windows auto-open: \(report.macWindowIntegration.acceptsGuestWindowEvents ? "ready" : "waiting")")
        print("Mac mirrored windows: \(report.macWindowIntegration.mirroredWindowCount)")
        print("Mac frame streams: \(report.macWindowIntegration.freshFrameWindowCount) fresh, \(report.macWindowIntegration.delayedFrameWindowCount) delayed, \(report.macWindowIntegration.staleFrameWindowCount) stale")
        print("Mac frame latency: \(report.macWindowIntegration.frameLatencyHealth) (\(report.macWindowIntegration.frameLatencyBudgetMilliseconds)ms budget, \(report.macWindowIntegration.frameStaleTimeoutMilliseconds)ms stale timeout)")
        print("Mac frame latency action: \(report.macWindowIntegration.frameLatencyRecommendedAction)")
        if let slowestFrameWindowId = report.macWindowIntegration.slowestFrameWindowId,
           let slowestFrameAgeMilliseconds = report.macWindowIntegration.slowestFrameAgeMilliseconds {
            print("Mac slowest app screen: \(slowestFrameWindowId) at \(slowestFrameAgeMilliseconds)ms")
        }
        print("Mac foregroundable windows: \(report.macWindowIntegration.foregroundableWindowCount)")
        if let foregroundWindowId = report.macWindowIntegration.foregroundWindowId {
            print("Mac foreground window: \(foregroundWindowId)")
        }
        if let foregroundWindowTitle = report.macWindowIntegration.foregroundWindowTitle {
            print("Mac foreground title: \(foregroundWindowTitle)")
        }
        print("Launch plan: \(report.launchPlan.recommendedAction)")
        print("Launch automatic app open: \(report.launchPlan.willOpenAppAutomatically ? "yes" : "no")")
        print("Launch plan reason: \(report.launchPlan.reason)")
        if let startCommand = report.launchPlan.recommendedStartCommand {
            print("Launch start command: \(startCommand)")
        }
        if let waitCommand = report.launchPlan.recommendedWaitCommand {
            print("Launch wait command: \(waitCommand)")
        }
        if let repairCommand = report.launchPlan.recommendedRepairCommand {
            print("Launch repair command: \(repairCommand)")
        }
        if let launchCommand = report.launchPlan.recommendedLaunchCommand {
            print("Launch app command: \(launchCommand)")
        }
        print("App check reason: \(report.proofPlan.reason)")
        print("App window check ready: \(report.proofPlan.canRunAppWindowProof ? "yes" : "no")")
        print("App input check ready: \(report.proofPlan.canRunCoherenceProof ? "yes" : "no")")
        print("Full app check ready: \(report.proofPlan.canRunMVPProof ? "yes" : "no")")
        print("Daily Use app coverage check ready: \(report.proofPlan.canRunMultiAppProof ? "yes" : "no")")
        if let proofCommand = report.proofPlan.recommendedAppWindowProofCommand {
            print("App window check command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedCoherenceProofCommand {
            print("App input check command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedMVPProofCommand {
            print("Full app check command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedMultiAppProofCommand {
            print("Daily Use app coverage command: \(proofCommand)")
        }
        print("App check artifacts: \(report.proofArtifacts.reason)")
        print("App check coverage: \(report.proofArtifacts.multiAppProofCoverageHealth) (\(report.proofArtifacts.multiAppProofCoverageCount)/\(report.proofArtifacts.multiAppProofTargetAppIds.count))")
        if !report.proofArtifacts.latestProofsByApp.isEmpty {
            print("App check coverage apps:")
            for appProof in report.proofArtifacts.latestProofsByApp {
                let latency = appProof.latestProofLatencyHealth.map { " \($0)" } ?? ""
                print("  - \(appProof.appId): \(appProof.latestProofKind)\(latency)")
            }
        }
        if let latestProofKind = report.proofArtifacts.latestProofKind {
            print("Latest app check kind: \(latestProofKind)")
        }
        if let latestProofPath = report.proofArtifacts.latestProofPath {
            print("Latest app check artifact: \(latestProofPath)")
        }
        if let notificationProofPath = report.proofArtifacts.latestNotificationProofPath {
            print("Latest notification proof artifact: \(notificationProofPath)")
        }
        if let notificationProofStatus = report.proofArtifacts.latestNotificationProofStatus {
            print("Latest notification proof status: \(notificationProofStatus)")
        }
        if let notificationProofTitle = report.proofArtifacts.latestNotificationProofTitle {
            print("Latest notification proof title: \(notificationProofTitle)")
        }
        if let printerProofPath = report.proofArtifacts.latestPrinterBridgeProofPath {
            print("Latest printer proof artifact: \(printerProofPath)")
        }
        if let printerProofEvidence = report.proofArtifacts.latestPrinterBridgeProofEvidenceFileName {
            print("Latest printer proof evidence: \(printerProofEvidence)")
        }
        if let latestLatencyHealth = report.proofArtifacts.latestProofLatencyHealth {
            print("Latest app check latency: \(latestLatencyHealth)")
        }
        if let latestLatencyMilliseconds = report.proofArtifacts.latestProofSlowestLatencyMilliseconds,
           let latestLatencyMeasurement = report.proofArtifacts.latestProofSlowestLatencyMeasurement {
            print("Slowest app check latency: \(latestLatencyMeasurement) \(latestLatencyMilliseconds)ms")
        }
        print("Daily Use package identity: \(report.dailyUseReadiness.packageIdentityReady ? "ready" : "needed")")
        print("Daily Use borderless capture preflight: \(report.dailyUseReadiness.borderlessCapturePreflightPassed ? "ready" : "blocked")")
        print("Daily Use borderless action: \(report.dailyUseReadiness.borderlessCaptureRecommendedAction)")
        print("Daily Use borderless requirement: \(report.dailyUseReadiness.borderlessCaptureRequirement)")
        print("Daily Use notifications preflight: \(report.dailyUseReadiness.notificationBridgePreflightPassed ? "ready" : "blocked")")
        print("Daily Use notifications action: \(report.dailyUseReadiness.notificationBridgeRecommendedAction)")
        print("Daily Use notifications requirement: \(report.dailyUseReadiness.notificationBridgeRequirement)")
        print("Windows notification bridge: \(report.notificationBridge.canReceiveNotifications ? "ready" : "blocked")")
        print("Windows notification action: \(report.notificationBridge.recommendedAction)")
        print("Windows notifications delivered: \(report.notificationBridge.deliveredNotificationCount)")
        if let latestNotification = report.notificationBridge.latestNotification {
            print("Latest Windows notification: \(latestNotification.title)")
        }
        print("Daily Use printer mode: \(report.dailyUseReadiness.printerBridgeMode)")
        print("Daily Use printer action: \(report.dailyUseReadiness.printerBridgeRecommendedAction)")
        print("Daily Use printer endpoint: \(report.dailyUseReadiness.printerBridgeEndpointTemplate)")
        print("Daily Use printer plan: \(report.dailyUseReadiness.printerBridgePlanCommand)")
        print("Daily Use printer setup: \(report.dailyUseReadiness.printerBridgeSetupHint)")
        if let packageIdentityStage = report.dailyUseReadiness.packageIdentityStage {
            print("Daily Use package identity stage: \(packageIdentityStage)")
        }
        if let packageIdentitySucceeded = report.dailyUseReadiness.packageIdentitySucceeded {
            print("Daily Use package identity status: \(packageIdentitySucceeded ? "succeeded" : "not complete")")
        }
        if let packageIdentityMessage = report.dailyUseReadiness.packageIdentityMessage {
            print("Daily Use package identity message: \(packageIdentityMessage)")
        }
        if let packageIdentityEvidencePath = report.dailyUseReadiness.packageIdentityEvidencePath {
            print("Daily Use package identity evidence: \(packageIdentityEvidencePath)")
        }
        print("Daily Use recommendation: \(report.dailyUseReadiness.recommendedAction)")
        if let dailyUseCommand = report.dailyUseReadiness.recommendedCommand {
            print("Daily Use command: \(dailyUseCommand)")
        }
        print("Daily Use reason: \(report.dailyUseReadiness.reason)")
        print("Quiet Windows ready: \(report.quietRuntime.canQuietRuntime ? "yes" : "no")")
        print("Quiet Windows auto: \(report.quietRuntime.willQuietAutomatically ? "yes" : "no")")
        print("Quiet Windows delay: \(report.quietRuntime.automaticQuietDelaySeconds)s")
        print("Quiet Windows recommendation: \(report.quietRuntime.recommendedAction)")
        if let stopCommand = report.quietRuntime.recommendedStopCommand {
            print("Quiet Windows stop command: \(stopCommand)")
        }
        print("Quiet Windows reason: \(report.quietRuntime.reason)")
        print("Restorable apps: \(report.restorableAppIds.joined(separator: ", "))")
        print("Dock restorable apps: \(report.dockIntegration.restorableAppCount)")
        print("Dock reconnect previous apps: \(report.dockIntegration.canReconnectPreviousApps ? "yes" : "no")")
        print("Actions:")
        for action in report.actions {
            print("  - \(action.id): \(action.isAvailable ? "available" : "unavailable")")
        }
    }

    static func latestLaunchVerificationReport(
        in distURL: URL,
        expectedBundleIdentifier: String,
        latestBundleModifiedAt: Date?
    ) -> AppRuntimeReviewHostAppLaunchReportEvidence {
        let reportURL = distURL.appendingPathComponent("veil-launch-report-latest.plist")
        let modifiedAt = modificationDate(for: reportURL)

        guard FileManager.default.fileExists(atPath: reportURL.path),
              let dictionary = propertyListDictionary(in: reportURL) else {
            return AppRuntimeReviewHostAppLaunchReportEvidence(
                reportPath: nil,
                modifiedAt: nil,
                meetsLauncherContract: false,
                isCurrentForBundle: false,
                bundleIdentifier: nil,
                expectedBundleIdentifier: expectedBundleIdentifier,
                mainWindowCount: nil,
                visibleMainWindowCount: nil,
                duplicateMainWindowCount: nil,
                frameWidth: nil,
                frameHeight: nil,
                minWidth: nil,
                minHeight: nil,
                titlebarAppearsTransparent: nil,
                hasFullSizeContentView: nil,
                appIconSource: nil
            )
        }

        let frame = dictionary["frame"] as? [String: Any]
        let isCurrentForBundle: Bool
        if let modifiedAt, let latestBundleModifiedAt {
            isCurrentForBundle = modifiedAt >= latestBundleModifiedAt
        } else {
            isCurrentForBundle = false
        }

        return AppRuntimeReviewHostAppLaunchReportEvidence(
            reportPath: reportURL.path,
            modifiedAt: modifiedAt,
            meetsLauncherContract: boolValue(dictionary["meetsLauncherContract"]) ?? false,
            isCurrentForBundle: isCurrentForBundle,
            bundleIdentifier: dictionary["bundleIdentifier"] as? String,
            expectedBundleIdentifier: expectedBundleIdentifier,
            mainWindowCount: intValue(dictionary["mainWindowCount"]),
            visibleMainWindowCount: intValue(dictionary["visibleMainWindowCount"]),
            duplicateMainWindowCount: intValue(dictionary["duplicateMainWindowCount"]),
            frameWidth: doubleValue(frame?["width"]),
            frameHeight: doubleValue(frame?["height"]),
            minWidth: doubleValue(dictionary["minWidth"]),
            minHeight: doubleValue(dictionary["minHeight"]),
            titlebarAppearsTransparent: boolValue(dictionary["titlebarAppearsTransparent"]),
            hasFullSizeContentView: boolValue(dictionary["hasFullSizeContentView"]),
            appIconSource: dictionary["appIconSource"] as? String
        )
    }

    private static func propertyListDictionary(in url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }

        return plist as? [String: Any]
    }

    static func latestModificationDate(for urls: [URL]) -> Date? {
        urls.compactMap(modificationDate(for:)).max()
    }

    private static func modificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    static func latestLaunchVerificationFailureReport(in distURL: URL) -> (url: URL, modifiedAt: Date)? {
        guard let reportURLs = try? FileManager.default.contentsOfDirectory(
            at: distURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return reportURLs.compactMap { url -> (url: URL, modifiedAt: Date)? in
            guard url.lastPathComponent.hasPrefix("veil-launch-report-failed-"),
                  url.pathExtension == "plist" else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate else {
                return nil
            }
            return (url, modifiedAt)
        }
        .max { lhs, rhs in lhs.modifiedAt < rhs.modifiedAt }
    }

    static func appFlowSummary(
        _ releaseGate: WindowsAppRuntimeReleaseGateStatus
    ) -> String {
        if releaseGate.isPassing {
            return "ready (\(releaseGate.passingStepCount)/\(releaseGate.requiredStepCount))"
        }

        return "\(releaseGate.passingStepCount)/\(releaseGate.requiredStepCount) ready"
    }

    private static func oneScreenUXSummary(
        _ oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    ) -> String {
        let surface = oneScreenUX.mode == "windows-app-windows"
            ? "Windows app windows"
            : "launcher"
        let family = oneScreenUX.usesSinglePrimarySurfaceFamily
            ? "single surface family"
            : "needs attention"
        return "\(surface), \(oneScreenUX.expectedVisibleSurfaceCount) visible, \(family)"
    }

    private static func oneScreenUXControls(
        _ oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    ) -> String {
        let menu = oneScreenUX.keepsMenuBarControlAvailable ? "menu ready" : "menu missing"
        let dock = oneScreenUX.keepsDockControlAvailable ? "Dock ready" : "Dock missing"
        let recovery = oneScreenUX.keepsDisplayRecoveryManual
            ? "manual display recovery"
            : "automatic display recovery"
        let appRecovery = oneScreenUX.canRecoverFromMenuOrDock
            ? "app recovery ready"
            : "app recovery missing"
        let launcherFallback = oneScreenUX.returnsToLauncherWhenNoAppWindows
            ? "launcher fallback ready"
            : "launcher fallback missing"
        let hero = oneScreenUX.heroRunsPrimaryAction
            ? "hero action ready"
            : "hero action not needed"
        let action = oneScreenUX.primaryActionId ?? "no primary action"
        return "\(menu), \(dock), \(appRecovery), \(launcherFallback), \(hero), \(recovery), \(action)"
    }

    static func appFlowNextStepTitle(
        _ releaseGate: WindowsAppRuntimeReleaseGateStatus
    ) -> String {
        if releaseGate.isPassing {
            return "Ready For App Review"
        }

        return releaseGate.steps.first { $0.id == releaseGate.recommendedAction }?.title
            ?? "Continue App Setup"
    }

    static func appFlowNextCommand(
        _ releaseGate: WindowsAppRuntimeReleaseGateStatus
    ) -> String? {
        releaseGate.steps.first { $0.id == releaseGate.recommendedAction }?.nextActionCommand
    }

    static func appFlowDetail(
        _ releaseGate: WindowsAppRuntimeReleaseGateStatus
    ) -> String {
        if releaseGate.isPassing {
            return "Setup, launch, app checks, and close controls are covered."
        }

        switch releaseGate.recommendedAction {
        case "windowsSetup":
            return "Finish Windows setup before opening apps."
        case "oneScreenPath":
            return "Keep setup, launch, and recovery in one clean app flow."
        case "openWindowsApp":
            return "Open or queue a Windows app from this status."
        case "appCheckEvidence":
            return "Run the app check and save current evidence."
        case "closeOrRestore":
            return "Close, restore, or quiet Windows from app controls."
        default:
            return "Continue the next app setup step."
        }
    }

    static func appRuntimeStatusService(demo: Bool) -> any HostDashboardService {
        if demo {
            return DemoHostDashboardService()
        }

        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        return FallbackHostDashboardService(
            primary: VeilHostClient(
                transport: URLSessionWebSocketTransport(url: url)
            ),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: endpoint
        )
    }
}
