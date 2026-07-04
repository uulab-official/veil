import SwiftUI
import VeilHostCore

struct DetailView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var selectedSection: ShellSection
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var displayMessage: String?

    var body: some View {
        if selectedSection == .vm {
            VMRuntimeView(
                model: vmModel,
                guestAgentInstallEvidence: model.guestAgentInstallEvidence,
                canLaunchWindowsApp: model.canLaunchSelectedApp,
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
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                launchWindowsAppAction: launchWindowsAppAction,
                runRecommendedProofAction: runRecommendedProofAction,
                displayMessage: displayMessage
            )
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(model: model, selectedSection: selectedSection)

                switch selectedSection {
                case .apps:
                    AppsView(apps: model.apps, selectedAppId: $model.selectedAppId)
                case .agent:
                    AgentView(
                        health: model.health,
                        connectionMode: model.connectionMode,
                        connectionDetail: model.connectionDetail,
                        agentDiagnostic: model.agentDiagnostic,
                        errorMessage: model.errorMessage
                    )
                case .vm:
                    EmptyView()
                case .launch:
                    LaunchView(result: model.lastLaunch)
                }
            }
            .frame(maxWidth: 1280, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
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

private struct HeaderView: View {
    @Bindable var model: HostDashboardModel
    var selectedSection: ShellSection

    var body: some View {
        ShellPanel(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: selectedSection.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSection.title)
                        .font(.title2.weight(.semibold))
                    Text(selectedSection.subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                StatusPill(
                    title: model.phase.displayTitle,
                    symbolName: model.phase.symbolName,
                    tint: model.phase.tint
                )
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(model.connectionMode == .demo ? "Demo Mode" : "Agent Mode", systemImage: model.connectionMode == .demo ? "play.rectangle" : "bolt.horizontal.circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(model.connectionMode == .demo ? .orange : .green)
                    .frame(width: 116, alignment: .leading)

                Text(model.connectionDetail ?? model.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
    }
}
