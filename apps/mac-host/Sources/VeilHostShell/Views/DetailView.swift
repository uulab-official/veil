import SwiftUI
import VeilHostCore

struct DetailView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var prepareSparsePackageAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var displayMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VMRuntimeView(
                model: vmModel,
                guestAgentInstallEvidence: model.guestAgentInstallEvidence,
                agentDiagnostic: model.agentDiagnostic,
                canLaunchWindowsApp: model.canLaunchSelectedApp,
                canRequestWindowsAppLaunch: model.canRequestSelectedAppLaunch,
                selectedWindowsAppName: model.selectedApp?.name,
                pendingLaunch: model.pendingLaunchStatus(),
                canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                pendingWindowsAppName: pendingWindowsAppName,
                activeMirrorSession: activeMirrorSession,
                launchPlan: runtimeStatusReport.launchPlan,
                primaryNextAction: runtimeStatusReport.primaryNextAction,
                oneScreenUX: runtimeStatusReport.oneScreenUX,
                launchOnboarding: runtimeStatusReport.launchOnboarding,
                recommendedProofKind: proofPlan.recommendedProofKind,
                recommendedProofCommand: proofPlan.recommendedProofCommand,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction,
                markWindowsInstalledAction: markWindowsInstalledAction,
                installGuestAgentAction: installGuestAgentAction,
                prepareSparsePackageAction: prepareSparsePackageAction,
                waitForGuestAgentAction: waitForGuestAgentAction,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                launchWindowsAppAction: launchWindowsAppAction,
                fulfillPendingLaunchAction: fulfillPendingLaunchAction,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
                restartStaleFrameStreamsAction: restartStaleFrameStreamsAction,
                requestNotificationConsentAction: requestNotificationConsentAction,
                runNotificationProofAction: runNotificationProofAction,
                runRecommendedProofAction: runRecommendedProofAction,
                runMultiAppProofAction: runMultiAppProofAction,
                quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
                displayMessage: displayMessage
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)

            if shouldShowAppLauncher {
                WindowsQuickLaunchPanel(
                    apps: model.apps,
                    mirrorSessions: model.mirrorSessions,
                    selectedAppId: $model.selectedAppId,
                    canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                    canLaunchSelectedApp: model.canLaunchSelectedApp,
                    canRequestSelectedAppLaunch: model.canRequestSelectedAppLaunch,
                    hasLiveAgentConnection: model.hasLiveAgentConnection,
                    phase: model.phase,
                    proofPlan: proofPlan,
                    proofArtifacts: runtimeStatusReport.proofArtifacts,
                    dailyUseReadiness: runtimeStatusReport.dailyUseReadiness,
                    releaseGate: runtimeStatusReport.releaseGate,
                    launchPlan: runtimeStatusReport.launchPlan,
                    primaryNextAction: runtimeStatusReport.primaryNextAction,
                    oneScreenUX: runtimeStatusReport.oneScreenUX,
                    launchOnboarding: runtimeStatusReport.launchOnboarding,
                    launchWindowsAppAction: launchWindowsAppAction,
                    runPrimaryNextAction: runPrimaryNextAction,
                    requestNotificationConsentAction: requestNotificationConsentAction,
                    runNotificationProofAction: runNotificationProofAction,
                    runRecommendedProofAction: runRecommendedProofAction,
                    runMultiAppProofAction: runMultiAppProofAction
                )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    private var activeMirrorSession: WindowMirrorSession? {
        model.mirrorSessions.first { $0.latestFrame != nil }
            ?? model.mirrorSessions.first
    }

    /// Demo or stale app catalogs must not make first-run setup look complete. The
    /// launcher appears only after a local VM profile has real installation evidence.
    private var shouldShowAppLauncher: Bool {
        guard !model.apps.isEmpty,
              let snapshot = vmModel.snapshot else {
            return false
        }

        if snapshot.installEvidence.isInstalled {
            return true
        }

        return snapshot.profileName != nil && model.guestAgentInstallEvidence?.isInstalled == true
    }

    private var pendingWindowsAppName: String? {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return nil
        }

        return model.apps.first { $0.id == pendingAppId }?.name
    }

    private var proofPlan: WindowsAppRuntimeProofPlanStatus {
        runtimeStatusReport.proofPlan
    }

    private var runtimeStatusReport: WindowsAppRuntimeStatusReport {
        model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: vmModel.snapshot)
        )
    }

    private func runPrimaryNextAction(_ route: LauncherPrimaryNextActionRoute) {
        switch route {
        case .launchSelectedApp:
            launchWindowsAppAction()
        case .fulfillPendingLaunch:
            fulfillPendingLaunchAction()
        case .recoverDisplay:
            recoverRuntimeDisplayAction()
        case .waitForAgent:
            waitForGuestAgentAction()
        case .repairAppConnection:
            repairGuestAgentForAppLaunchAction()
        case .startWindows:
            startVMAction()
        case .startWindowsForApp:
            launchWindowsAppAction()
        case .prepareWindows:
            Task {
                await vmModel.prepareDefaultVM()
            }
        case .preparePackageIdentity:
            prepareSparsePackageAction()
        case .refreshRuntimeStatus:
            Task {
                await vmModel.load()
            }
        case .reconnectPreviousApps:
            restoreWindowsAppWindowsAction()
        case .closeAllWindowsApps:
            closeAllWindowsAppWindowsAction()
        case .restartFrameStream:
            restartStaleFrameStreamsAction()
        case .recoverWindowCapture:
            restartStaleFrameStreamsAction()
        case .reopenWindow:
            restartStaleFrameStreamsAction()
        case .quietWindows:
            quietWindowsWhenIdleAction()
        case .requestNotificationConsent:
            requestNotificationConsentAction()
        case .runNotificationProof:
            runNotificationProofAction()
        case .showPrinterBridgePlan:
            Task {
                await vmModel.load()
            }
        case .runRecommendedProof:
            runRecommendedProofAction()
        case .runMultiAppProof:
            runMultiAppProofAction()
        }
    }
}

private struct WindowsQuickLaunchPanel: View {
    var apps: [WindowsApp]
    var mirrorSessions: [WindowMirrorSession]
    @Binding var selectedAppId: String?
    var canFulfillPendingLaunch: Bool
    var canLaunchSelectedApp: Bool
    var canRequestSelectedAppLaunch: Bool
    var hasLiveAgentConnection: Bool
    var phase: HostDashboardPhase
    var proofPlan: WindowsAppRuntimeProofPlanStatus
    var proofArtifacts: WindowsAppRuntimeProofArtifactStatus
    var dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    var releaseGate: WindowsAppRuntimeReleaseGateStatus
    var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    var primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
    var oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    var launchOnboarding: WindowsAppRuntimeLaunchOnboardingStatus
    var launchWindowsAppAction: () -> Void
    var runPrimaryNextAction: (LauncherPrimaryNextActionRoute) -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void

    var body: some View {
        ShellPanel(spacing: 12) {
            HStack(spacing: 12) {
                ShellPanelHeader(
                    title: "Windows Apps",
                    subtitle: "Pick an app and open it as a native macOS window.",
                    symbolName: "macwindow.on.rectangle"
                )

                Spacer()

                StatusPill(
                    title: runningAppStateTitle,
                    symbolName: runningAppStateSymbol,
                    tint: mirrorSessions.isEmpty ? .secondary : .green
                )
            }

            if apps.isEmpty {
                ContentUnavailableView(
                    "No Windows Apps",
                    systemImage: "square.grid.2x2",
                    description: Text("Start Windows to load the installed app list.")
                )
                .frame(maxWidth: .infinity, minHeight: 118)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(apps) { app in
                            WindowsQuickLaunchTile(
                                app: app,
                                isSelected: selectedAppId == app.id,
                                openWindowCount: mirrorSessions.filter { $0.window.appId == app.id }.count,
                                isDisabled: phase == .loading || phase == .launching
                            ) {
                                selectedAppId = app.id
                                launchWindowsAppAction()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 8) {
                Label(
                    hasLiveAgentConnection ? "Windows is ready" : "Windows starts when an app opens",
                    systemImage: hasLiveAgentConnection ? "checkmark.circle.fill" : "power"
                )
                .foregroundStyle(hasLiveAgentConnection ? Color.green : Color.secondary)

                Spacer()

                Text("Setup and recovery are in More.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var runningAppStateTitle: String {
        if !mirrorSessions.isEmpty {
            let count = mirrorSessions.count
            return count == 1 ? "1 App Window" : "\(count) App Windows"
        }

        if canFulfillPendingLaunch {
            return "Queued App"
        }

        return "No App Window"
    }

    private var runningAppStateSymbol: String {
        if mirrorSessions.isEmpty {
            return "macwindow"
        }

        return "macwindow.badge.plus"
    }

    private var appCheckStatusTitle: String {
        WindowsShellCopy.appCheckStatusTitle(
            recommendedProofKind: proofPlan.recommendedProofKind,
            latestProofFileName: proofArtifacts.latestProofFileName
        )
    }

    private var appCheckDetail: String {
        WindowsShellCopy.appCheckDetail(
            canRunMVPProof: proofPlan.canRunMVPProof,
            canRunCoherenceProof: proofPlan.canRunCoherenceProof,
            canRunAppWindowProof: proofPlan.canRunAppWindowProof,
            recommendedProofCommand: proofPlan.recommendedProofCommand,
            latestProofFileName: proofArtifacts.latestProofFileName,
            reason: proofPlan.reason
        )
    }

    private var appCheckSymbolName: String {
        switch proofPlan.recommendedProofKind {
        case "mvp":
            return "checkmark.seal.fill"
        case "coherence":
            return "keyboard.badge.ellipsis"
        case "app-window":
            return "macwindow"
        default:
            return proofArtifacts.latestProofFileName == nil ? "clock" : "doc.text"
        }
    }

    private var appCheckTint: Color {
        if proofPlan.canRunMVPProof {
            return .green
        }

        if proofPlan.recommendedProofCommand != nil {
            return .blue
        }

        return proofArtifacts.latestProofFileName == nil ? .secondary : .green
    }

    private var printerBridgeDetail: String {
        if let evidenceFileName = proofArtifacts.latestPrinterBridgeProofEvidenceFileName {
            return "Latest test page proof: \(evidenceFileName)"
        }

        return "Manual IPP setup at \(dailyUseReadiness.printerBridgeEndpointTemplate)"
    }

    private var printerBridgeHelp: String {
        var details = [
            dailyUseReadiness.printerBridgeSetupHint,
            "Command: \(dailyUseReadiness.printerBridgePlanCommand)"
        ]

        if let proofPath = proofArtifacts.latestPrinterBridgeProofPath {
            details.append("Latest proof: \(proofPath)")
        }

        if let evidencePath = proofArtifacts.latestPrinterBridgeProofEvidencePath {
            details.append("Evidence: \(evidencePath)")
        }

        return details.joined(separator: "\n")
    }

    private var printerBridgeStatusTitle: String {
        proofArtifacts.latestPrinterBridgeProofPath == nil ? "Printer Setup" : "Printer Proof"
    }

    private var printerBridgeTint: Color {
        proofArtifacts.latestPrinterBridgeProofPath == nil ? .blue : .green
    }

    private var appFlowStatusTitle: String {
        WindowsShellCopy.appFlowStatusTitle(
            isPassing: releaseGate.isPassing,
            passingStepCount: releaseGate.passingStepCount,
            requiredStepCount: releaseGate.requiredStepCount
        )
    }

    private var launchOnboardingTitle: String {
        WindowsShellCopy.launchOnboardingTitle(
            state: launchOnboarding.state,
            canContinueInApp: launchOnboarding.canContinueInApp
        )
    }

    private var launchOnboardingDetail: String {
        WindowsShellCopy.launchOnboardingDetail(
            currentStepTitle: launchOnboarding.currentStepTitle,
            pendingLiveProof: launchOnboarding.pendingLiveProof
        )
    }

    private var launchOnboardingSymbolName: String {
        WindowsShellCopy.launchOnboardingSymbolName(
            state: launchOnboarding.state,
            canContinueInApp: launchOnboarding.canContinueInApp
        )
    }

    private var launchOnboardingTint: Color {
        if launchOnboarding.state == "ready-for-review" {
            return .green
        }

        return launchOnboarding.canContinueInApp ? .blue : .orange
    }

    private var oneScreenUXTitle: String {
        if primaryNextAction.runsInApp && !oneScreenUX.heroRunsPrimaryAction {
            return "Hero action needs attention"
        }

        if !oneScreenUX.canRecoverFromMenuOrDock {
            return "Recovery needs attention"
        }

        if !oneScreenUX.returnsToLauncherWhenNoAppWindows {
            return "Launcher fallback needs attention"
        }

        if oneScreenUX.mode == "windows-app-windows" {
            let count = oneScreenUX.expectedVisibleSurfaceCount
            return count == 1 ? "One Windows app surface" : "\(count) Windows app surfaces"
        }

        return "One launcher surface"
    }

    private var oneScreenUXSymbolName: String {
        oneScreenUX.usesSinglePrimarySurfaceFamily
            && oneScreenUX.canRecoverFromMenuOrDock
            && oneScreenUX.returnsToLauncherWhenNoAppWindows
            && (!primaryNextAction.runsInApp || oneScreenUX.heroRunsPrimaryAction)
            ? "rectangle.on.rectangle"
            : "exclamationmark.triangle"
    }

    private var appAutomationTitle: String {
        if launchPlan.willOpenAppAutomatically {
            return launchPlan.canLaunchSelectedAppNow ? "App opens now" : "App opens automatically"
        }

        if launchPlan.recommendedAction == "prepare-local-runtime" {
            return "Setup needed before app opens"
        }

        return "App open needs attention"
    }

    private var appAutomationSymbolName: String {
        launchPlan.willOpenAppAutomatically ? "bolt.circle" : "exclamationmark.triangle"
    }

    private var primaryNextActionHelp: String {
        [
            primaryNextAction.reason,
            WindowsShellCopy.primaryActionHandoffDetail(runsInApp: primaryNextAction.runsInApp),
            primaryNextAction.command.map { "Command: \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var launchOnboardingHelp: String {
        [
            launchOnboarding.currentStepDetail,
            launchOnboarding.reason,
            WindowsShellCopy.launchOnboardingHandoffDetail(
                state: launchOnboarding.state,
                canContinueInApp: launchOnboarding.canContinueInApp
            ),
            launchOnboarding.primaryCommand.map { "Command: \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var primaryNextActionRoute: LauncherPrimaryNextActionRoute? {
        LauncherPrimaryNextActionRoute.resolve(
            actionId: launchOnboarding.primaryActionId ?? launchOnboarding.currentStepId,
            command: launchOnboarding.primaryCommand,
            runsInApp: launchOnboarding.canContinueInApp
        )
    }

    private var appFlowSymbolName: String {
        releaseGate.isPassing ? "checkmark.circle.fill" : "list.bullet.circle"
    }

    private var appFlowTint: Color {
        releaseGate.isPassing ? .green : .blue
    }
}

private struct WindowsQuickLaunchTile: View {
    var app: WindowsApp
    var isSelected: Bool
    var openWindowCount: Int
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbolName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if openWindowCount > 0 {
                        Text("\(openWindowCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(.green, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }

                Text(app.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(openWindowCount > 0 ? "Open" : "Launch")
                    .font(.caption2)
                    .foregroundStyle(openWindowCount > 0 ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 124, height: 118)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help("Open \(app.name) as a macOS window")
        .accessibilityLabel("Open \(app.name)")
    }

    private var symbolName: String {
        switch app.id {
        case "winapp_notepad":
            return "note.text"
        case "winapp_calculator":
            return "plus.forwardslash.minus"
        case "winapp_paint":
            return "paintpalette"
        default:
            return "app.window"
        }
    }

    private var tint: Color {
        switch app.id {
        case "winapp_notepad":
            return .blue
        case "winapp_calculator":
            return .green
        case "winapp_paint":
            return .orange
        default:
            return .teal
        }
    }
}
