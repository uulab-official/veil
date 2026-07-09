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
    var runRecommendedProofAction: () -> Void
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
                    launchWindowsAppAction: launchWindowsAppAction
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
        model.runtimeStatusReport().proofPlan
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
    var launchWindowsAppAction: () -> Void

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
            return "Preparing Runtime"
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
}
