import SwiftUI
import VeilHostCore

struct DetailView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var runRecommendedProofAction: () -> Void
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
                recommendedProofKind: proofPlan.recommendedProofKind,
                recommendedProofCommand: proofPlan.recommendedProofCommand,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction,
                markWindowsInstalledAction: markWindowsInstalledAction,
                installGuestAgentAction: installGuestAgentAction,
                waitForGuestAgentAction: waitForGuestAgentAction,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                launchWindowsAppAction: launchWindowsAppAction,
                runRecommendedProofAction: runRecommendedProofAction,
                displayMessage: displayMessage
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)

            if !model.apps.isEmpty {
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
                    releaseGate: runtimeStatusReport.releaseGate,
                    launchPlan: runtimeStatusReport.launchPlan,
                    primaryNextAction: runtimeStatusReport.primaryNextAction,
                    oneScreenUX: runtimeStatusReport.oneScreenUX,
                    launchWindowsAppAction: launchWindowsAppAction,
                    runPrimaryNextAction: runPrimaryNextAction,
                    runRecommendedProofAction: runRecommendedProofAction
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
        case .prepareWindows:
            Task {
                await vmModel.prepareDefaultVM()
            }
        case .refreshRuntimeStatus:
            Task {
                await vmModel.load()
            }
        case .reconnectPreviousApps:
            restoreWindowsAppWindowsAction()
        case .closeAllWindowsApps:
            closeAllWindowsAppWindowsAction()
        case .quietWindows:
            quietWindowsWhenIdleAction()
        case .runRecommendedProof:
            runRecommendedProofAction()
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
    var releaseGate: WindowsAppRuntimeReleaseGateStatus
    var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    var primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
    var oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    var launchWindowsAppAction: () -> Void
    var runPrimaryNextAction: (LauncherPrimaryNextActionRoute) -> Void
    var runRecommendedProofAction: () -> Void

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

            HStack(spacing: 12) {
                Picker("Windows App", selection: $selectedAppId) {
                    ForEach(apps) { app in
                        Text(app.name).tag(Optional(app.id))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 220, maxWidth: 320)
                .disabled(apps.isEmpty || phase == .loading || phase == .launching)

                Button {
                    launchWindowsAppAction()
                } label: {
                    Text(launchButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(launchDisabled)
                .help("Open selected Windows app")

                if let selected = apps.first(where: { $0.id == selectedAppId }) {
                    Label(selected.publisher, systemImage: "person")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                StatusPill(
                    title: appCheckStatusTitle,
                    symbolName: appCheckSymbolName,
                    tint: appCheckTint
                )
                .frame(minWidth: 118, alignment: .leading)

                Text(appCheckDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let latestProofFileName = proofArtifacts.latestProofFileName {
                    Label(
                        "Latest Check",
                        systemImage: "doc.text"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(latestProofFileName)
                }

                Spacer()

                Button {
                    runRecommendedProofAction()
                } label: {
                    Label("Check App", systemImage: "checkmark.seal")
                }
                .disabled(proofPlan.recommendedProofCommand == nil)
                .help("Check selected Windows app")
            }

            Divider()

            HStack(spacing: 12) {
                StatusPill(
                    title: appFlowStatusTitle,
                    symbolName: appFlowSymbolName,
                    tint: appFlowTint
                )
                .frame(minWidth: 118, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appFlowDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Label(primaryNextAction.title, systemImage: "arrow.forward.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryNextAction.isAvailable ? .primary : .secondary)
                        .lineLimit(1)
                        .help(primaryNextActionHelp)

                    Label(oneScreenUXTitle, systemImage: oneScreenUXSymbolName)
                        .font(.caption)
                        .foregroundStyle(oneScreenUX.usesSinglePrimarySurfaceFamily
                            && oneScreenUX.canRecoverFromMenuOrDock
                            && oneScreenUX.returnsToLauncherWhenNoAppWindows ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .help(oneScreenUX.reason)

                    Label(appAutomationTitle, systemImage: appAutomationSymbolName)
                        .font(.caption)
                        .foregroundStyle(launchPlan.willOpenAppAutomatically ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .help(launchPlan.reason)
                }

                Spacer()

                HStack(spacing: 5) {
                    ForEach(releaseGate.steps, id: \.id) { step in
                        Circle()
                            .fill(step.isPassing ? Color.green : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .help(step.title)
                    }
                }
                .accessibilityLabel("App flow progress")

                if let primaryNextActionRoute {
                    Button {
                        runPrimaryNextAction(primaryNextActionRoute)
                    } label: {
                        Label(primaryNextActionRoute.buttonTitle, systemImage: primaryNextActionRoute.symbolName)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!primaryNextAction.isAvailable)
                    .help(primaryNextActionHelp)
                }
            }
        }
    }

    private var launchButtonTitle: String {
        if canFulfillPendingLaunch {
            return "Open Queued App"
        }

        if !hasLiveAgentConnection {
            return "Open When Ready"
        }

        if canRequestSelectedAppLaunch {
            return "Open Selected App"
        }

        if !canLaunchSelectedApp {
            return "Preparing Windows"
        }

        return "Open App"
    }

    private var launchDisabled: Bool {
        phase == .loading || phase == .launching || (!canRequestSelectedAppLaunch && !canFulfillPendingLaunch)
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

    private var appFlowStatusTitle: String {
        WindowsShellCopy.appFlowStatusTitle(
            isPassing: releaseGate.isPassing,
            passingStepCount: releaseGate.passingStepCount,
            requiredStepCount: releaseGate.requiredStepCount
        )
    }

    private var appFlowDetail: String {
        WindowsShellCopy.appFlowDetail(
            recommendedAction: releaseGate.recommendedAction,
            isPassing: releaseGate.isPassing
        )
    }

    private var oneScreenUXTitle: String {
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
            primaryNextAction.runsInApp ? "Runs inside Veil." : "Review from the command line.",
            primaryNextAction.command.map { "Command: \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var primaryNextActionRoute: LauncherPrimaryNextActionRoute? {
        LauncherPrimaryNextActionRoute.resolve(
            actionId: primaryNextAction.actionId ?? primaryNextAction.id,
            command: primaryNextAction.command
        )
    }

    private var appFlowSymbolName: String {
        releaseGate.isPassing ? "checkmark.circle.fill" : "list.bullet.circle"
    }

    private var appFlowTint: Color {
        releaseGate.isPassing ? .green : .blue
    }
}
