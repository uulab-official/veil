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
        ZStack(alignment: .bottom) {
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

            if shouldShowAppLauncher {
                WindowsQuickLaunchPanel(
                    apps: model.apps,
                    mirrorSessions: model.mirrorSessions,
                    selectedAppId: $model.selectedAppId,
                    canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                    hasLiveAgentConnection: model.hasLiveAgentConnection,
                    phase: model.phase,
                    launchWindowsAppAction: launchWindowsAppAction
                )
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

}

private struct WindowsQuickLaunchPanel: View {
    var apps: [WindowsApp]
    var mirrorSessions: [WindowMirrorSession]
    @Binding var selectedAppId: String?
    var canFulfillPendingLaunch: Bool
    var hasLiveAgentConnection: Bool
    var phase: HostDashboardPhase
    var launchWindowsAppAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            WindowsLogoMark(size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Windows Apps")
                    .font(.caption.weight(.semibold))
                Text(connectionTitle)
                    .font(.caption2)
                    .foregroundStyle(connectionTint)
            }
            .frame(width: 92, alignment: .leading)

            Divider()
                .frame(height: 40)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
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
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)

            if !mirrorSessions.isEmpty || canFulfillPendingLaunch {
                Divider()
                    .frame(height: 40)

                StatusPill(
                    title: runningAppStateTitle,
                    symbolName: runningAppStateSymbol,
                    tint: mirrorSessions.isEmpty ? .blue : .green
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 760)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Windows app dock")
    }

    private var connectionTitle: String {
        if hasLiveAgentConnection {
            return "Ready"
        }
        return canFulfillPendingLaunch ? "App queued" : "Starts on demand"
    }

    private var connectionTint: Color {
        hasLiveAgentConnection ? .green : (canFulfillPendingLaunch ? .blue : .secondary)
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

private struct WindowsQuickLaunchTile: View {
    var app: WindowsApp
    var isSelected: Bool
    var openWindowCount: Int
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    if openWindowCount > 0 {
                        Text("\(openWindowCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(.green, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }

                Text(app.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 66, minHeight: 56)
            .background(isSelected ? tint.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.80) : Color.clear, lineWidth: 1)
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
