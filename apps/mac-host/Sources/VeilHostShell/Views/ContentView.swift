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
    var launchWindowsAppAction: () -> Void
    var openNewWindowsAppAction: (String) -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var optimizationStatus: WindowsOptimizationStatus
    var optimizeWindowsAction: () -> Void
    var retryWindowsOptimizationAction: () -> Void
    var cancelWindowsOptimizationAction: () -> Void
    var windowsDisplaySizeChangedAction: (Int, Int) -> Void
    var displayMessage: String?
    @State private var isMainWindowFullScreen = false

    var body: some View {
        ZStack {
            VeilWindowBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VeilWindowHeader(
                    title: headerTitle,
                    subtitle: headerSubtitle,
                    statusTitle: headerStatus.title,
                    statusSymbol: headerStatus.symbolName,
                    statusTint: headerStatus.tone.color,
                    isRefreshing: isRefreshing,
                    isFullScreen: isMainWindowFullScreen,
                    refreshAction: refreshAll
                )

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
                    launchWindowsAppAction: launchWindowsAppAction,
                    openNewWindowsAppAction: openNewWindowsAppAction,
                    fulfillPendingLaunchAction: fulfillPendingLaunchAction,
                    restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
                    closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
                    restartStaleFrameStreamsAction: restartStaleFrameStreamsAction,
                    requestNotificationConsentAction: requestNotificationConsentAction,
                    runNotificationProofAction: runNotificationProofAction,
                    runRecommendedProofAction: runRecommendedProofAction,
                    runMultiAppProofAction: runMultiAppProofAction,
                    quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
                    optimizationStatus: optimizationStatus,
                    optimizeWindowsAction: optimizeWindowsAction,
                    retryWindowsOptimizationAction: retryWindowsOptimizationAction,
                    cancelWindowsOptimizationAction: cancelWindowsOptimizationAction,
                    windowsDisplaySizeChangedAction: windowsDisplaySizeChangedAction,
                    displayMessage: displayMessage
                )
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear(perform: refreshMainWindowFullScreenState)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
            updateMainWindowFullScreenState(from: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
            updateMainWindowFullScreenState(from: $0)
        }
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
            windowsInstalled: vmModel.snapshot?.windowsInstalled == true
        )
    }

    private var headerStatus: WindowsHeaderStatus {
        .resolve(
            isRefreshing: isRefreshing,
            hasLiveAppConnection: model.hasLiveAgentConnection,
            runtimeState: vmModel.snapshot?.state,
            windowsInstalled: vmModel.snapshot?.windowsInstalled == true
        )
    }

    private func refreshAll() {
        Task {
            async let hostLoad: Void = model.load()
            async let vmLoad: Void = vmModel.load()
            _ = await (hostLoad, vmLoad)
        }
    }

    private func updateMainWindowFullScreenState(from notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "main" else {
            return
        }

        isMainWindowFullScreen = window.styleMask.contains(.fullScreen)
    }

    private func refreshMainWindowFullScreenState() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else {
                return
            }
            isMainWindowFullScreen = window.styleMask.contains(.fullScreen)
        }
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
    var isFullScreen: Bool
    var refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: MainWindowHeaderLayout.leadingInset(
                    isFullScreen: isFullScreen,
                    contentInset: MainWindowContentLayout.expandedHorizontalInset
                ))

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
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: statusTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(action: refreshAction) {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(isRefreshing ? 0 : 1)

                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(TitlebarIconButtonStyle())
            .disabled(isRefreshing)
            .help(isRefreshing ? "Refreshing Windows status" : "Refresh Windows status")
            .accessibilityLabel(isRefreshing ? "Refreshing Windows status" : "Refresh Windows status")
            .accessibilityValue(isRefreshing ? "In progress" : "Ready")
            .animation(.easeInOut(duration: 0.16), value: isRefreshing)
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

enum MainWindowContentLayout {
    static let compactHorizontalInset: CGFloat = 22
    static let expandedHorizontalInset: CGFloat = 42
}

enum MainWindowHeaderLayout {
    private static let windowControlsClearance: CGFloat = 74

    static func leadingInset(isFullScreen: Bool, contentInset: CGFloat) -> CGFloat {
        isFullScreen ? contentInset : max(windowControlsClearance, contentInset)
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

private extension WindowsShellStatusTone {
    var color: Color {
        switch self {
        case .green:
            return .green
        case .blue:
            return .blue
        case .orange:
            return .orange
        case .secondary:
            return .secondary
        }
    }
}
