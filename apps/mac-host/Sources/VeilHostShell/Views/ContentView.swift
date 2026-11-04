import AppKit
import SwiftUI
import VeilHostCore

struct ContentView: View {
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
    var showWindowsDisplayAction: () -> Void
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
        ZStack {
            VeilWindowBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VeilWindowHeader(
                    title: headerTitle,
                    subtitle: headerSubtitle,
                    statusTitle: headerStatusTitle,
                    statusSymbol: headerStatusSymbol,
                    statusTint: headerStatusTint,
                    isRefreshing: isRefreshing,
                    refreshAction: refreshAll
                )

                WindowsAppLauncherBar(
                    apps: model.apps,
                    selectedAppId: $model.selectedAppId,
                    mirrorSessions: model.mirrorSessions,
                    phase: model.phase,
                    runtimeState: vmModel.snapshot?.state,
                    windowsInstalled: windowsInstalled,
                    hasLiveAgentConnection: model.hasLiveAgentConnection,
                    appConnectionUnavailable: appConnectionUnavailable,
                    canRequestLaunch: model.canRequestSelectedAppLaunch,
                    canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                    pendingAppName: pendingAppName,
                    launchAction: launchWindowsAppAction,
                    repairConnectionAction: repairGuestAgentForAppLaunchAction
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(height: 104)

                DetailView(
                    model: model,
                    vmModel: vmModel,
                    startVMAction: startVMAction,
                    stopVMAction: stopVMAction,
                    markWindowsInstalledAction: markWindowsInstalledAction,
                    installGuestAgentAction: installGuestAgentAction,
                    prepareSparsePackageAction: prepareSparsePackageAction,
                    waitForGuestAgentAction: waitForGuestAgentAction,
                    repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                    recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                    showWindowsDisplayAction: showWindowsDisplayAction,
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
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private var isRefreshing: Bool {
        model.phase == .loading || model.phase == .launching || vmModel.phase == .loading
    }

    private var headerTitle: String {
        "Windows 11"
    }

    private var headerSubtitle: String {
        WindowsShellCopy.headerSubtitle(
            hasLiveAppConnection: model.hasLiveAgentConnection,
            runtimeState: vmModel.snapshot?.state,
            windowsInstalled: windowsInstalled,
            appConnectionUnavailable: appConnectionUnavailable
        )
    }

    private var headerStatusTitle: String {
        WindowsShellCopy.headerStatusTitle(
            runtimeState: vmModel.snapshot?.state,
            windowsInstalled: windowsInstalled,
            appConnectionUnavailable: appConnectionUnavailable
        )
    }

    private var headerStatusSymbol: String {
        WindowsShellCopy.headerStatusSymbol(
            runtimeState: vmModel.snapshot?.state,
            windowsInstalled: windowsInstalled,
            appConnectionUnavailable: appConnectionUnavailable
        )
    }

    private var headerStatusTint: Color {
        if vmModel.snapshot?.state == .failed || appConnectionUnavailable {
            return .orange
        }

        switch vmModel.snapshot?.state {
        case .running:
            return .green
        case .starting:
            return .blue
        default:
            return windowsInstalled ? .green : .secondary
        }
    }

    private var appConnectionUnavailable: Bool {
        WindowsShellCopy.appConnectionNeedsRepair(
            hasLiveAppConnection: model.hasLiveAgentConnection,
            agentUnavailable: model.agentDiagnostic?.status == .unavailable,
            windowsInstalled: windowsInstalled,
            runtimeState: vmModel.snapshot?.state
        )
    }

    private var windowsInstalled: Bool {
        vmModel.snapshot?.installEvidence.isInstalled == true
    }

    private func refreshAll() {
        Task {
            async let hostLoad: Void = model.load()
            async let vmLoad: Void = vmModel.load()
            _ = await (hostLoad, vmLoad)
        }
    }

    private var pendingAppName: String? {
        guard let pendingAppId = model.pendingLaunchAppId else {
            return nil
        }

        return model.apps.first { $0.id == pendingAppId }?.name
    }

}

private struct VeilWindowBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.061, blue: 0.071)

            LinearGradient(
                colors: [
                    Color(red: 0.024, green: 0.130, blue: 0.240).opacity(0.52),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
    }
}

private struct VeilWindowHeader: View {
    var title: String
    var subtitle: String
    var statusTitle: String
    var statusSymbol: String
    var statusTint: Color
    var isRefreshing: Bool
    var refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 74)

            HStack(spacing: 10) {
                VeilAppMark(size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                StatusPill(
                    title: statusTitle,
                    symbolName: statusSymbol,
                    tint: statusTint
                )
                .padding(.leading, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(TitlebarIconButtonStyle())
            .disabled(isRefreshing)
            .help("Refresh")
        }
        .padding(.trailing, 14)
        .frame(height: 58)
        .background(
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.045, green: 0.050, blue: 0.060).opacity(0.98))
                LinearGradient(
                    colors: [
                        Color(red: 0.030, green: 0.185, blue: 0.315).opacity(0.72),
                        Color(red: 0.080, green: 0.085, blue: 0.100).opacity(0.88)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.075))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .allowsWindowActivationEvents()
        .simultaneousGesture(WindowDragGesture())
    }
}

private struct TitlebarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
