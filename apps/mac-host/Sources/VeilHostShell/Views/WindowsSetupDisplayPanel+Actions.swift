import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

extension WindowsSetupDisplayPanel {
    var appConnectionRecoveryHero: some View {
        VStack(spacing: 18) {
            Image(systemName: "network.slash")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 76, height: 76)
                .background(.orange.opacity(0.14), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
                }

            VStack(spacing: 7) {
                Text("Windows apps need a connection")
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text("Windows is installed, but Veil Agent is not responding. Repair the connection in Windows and your apps will be ready to open as Mac windows.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            HStack(spacing: 10) {
                Button(action: repairGuestAgentForAppLaunchAction) {
                    Label("Repair connection", systemImage: "wrench.and.screwdriver")
                        .frame(minWidth: 176)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: detailsAction) {
                    Label("Connection details", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Label("Your Windows installation and app data are unchanged.", systemImage: "checkmark.shield")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.64))
        }
        .foregroundStyle(.white)
        .padding(36)
        .frame(maxWidth: 700)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
    }

    private var installPrimaryTitle: String {
        if effectiveInstallEvidence.isInstalled {
            if canFulfillPendingLaunch {
                return "Open \(pendingAppDisplayName)"
            }

            if pendingLaunch.willLaunchOnAgentReconnect {
                switch snapshot.state {
                case .running, .starting:
                    return "Repair App Connection"
                default:
                    return "Continue Opening \(pendingAppDisplayName)"
                }
            }

            if prefersOneClickAppLaunch {
                return selectedWindowsAppName.map { "Open \($0)" } ?? "Open Windows App"
            }

            if canRequestWindowsAppLaunch {
                return selectedWindowsAppName.map { "Open \($0)" } ?? "Open Windows App"
            }

            if canInstallGuestAgent {
                return "Repair App Connection"
            }
        }

        if canRecoverRuntimeDisplay {
            return "Refresh Display"
        }

        if canStop {
            return "Stop Windows"
        }

        if canStart {
            return installSimulation.phase == .running ? "Opening..." : installActionTitle
        }

        if snapshot.installerMediaPath == nil || installerNeedsFilePickerAccess {
            return "Download Windows 11"
        }

        return snapshot.profileName == nil ? "Prepare Windows" : "Continue Setup"
    }

    var horizontalActions: some View {
        HStack(spacing: 8) {
            if snapshot.state == .running, hasDesktopDisplay {
                Button(action: showWindowsDisplayAction) {
                    Label("Show Desktop", systemImage: "display")
                    .labelStyle(.iconOnly)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Open the live Windows desktop in its own window (⇧⌘A)")
                .accessibilityLabel("Show Windows desktop")
            }

            Button(action: detailsAction) {
                Label("Settings", systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
            }
            .disabled(isLoading)
            .help("Open Windows settings")

            if hasRuntimeMoreActions {
                runtimeMoreMenu
            }
        }
    }

    var runtimeSettingsButton: some View {
        Button(action: detailsAction) {
            Label("Settings", systemImage: "gearshape.fill")
        }
        .disabled(isLoading)
        .help("Open Windows settings")
    }

    @ViewBuilder
    private var runtimeActionButton: some View {
        if executablePrimaryNextActionRoute != nil {
            Button(action: runEffectivePrimaryAction) {
                Label(effectivePrimaryTitle, systemImage: effectivePrimarySymbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(effectivePrimaryDisabled)
            .help(effectivePrimaryHelp)
        } else if canOpenWindowsApp {
            Button(action: primaryAction) {
                Label(appDisplayName, systemImage: "macwindow.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)
            .help("Open Windows app")
        } else if canRepairGuestAgentForAppLaunch {
            Button(action: repairGuestAgentForAppLaunchAction) {
                Label("Continue \(pendingAppDisplayName)", systemImage: "bolt.horizontal.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)
            .help("Repair the Windows app connection and continue opening the queued app")
        } else if canRecoverRuntimeDisplay {
            Button(action: recoverRuntimeDisplayAction) {
                Label("Refresh Display", systemImage: "display")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isLoading)
            .help("Refresh embedded Windows display evidence")
        }
    }

    @ViewBuilder
    var runtimeMoreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            if canInstallGuestAgent {
                Button("Repair App Connection", systemImage: "app.badge") {
                    installGuestAgentAction()
                }
                .disabled(isLoading)
                .help("Repair the connection used to open Windows apps on your Mac")
            }

            if canWaitForGuestAgent {
                Button("Check App Connection", systemImage: "antenna.radiowaves.left.and.right") {
                    waitForGuestAgentAction()
                }
                .disabled(isLoading)
                .help("Wait for Windows app connection and refresh status")

                if let agentDiagnostic {
                    Button {
                        showsAgentDiagnosticPopover = true
                    } label: {
                        Label("Connection Details", systemImage: "info.circle")
                    }
                    .help("Show Windows app connection details")
                    .popover(isPresented: $showsAgentDiagnosticPopover, arrowEdge: .bottom) {
                        AgentDiagnosticPanel(diagnostic: agentDiagnostic)
                            .frame(width: 360)
                            .padding(14)
                    }
                }
            }

            if canMarkWindowsInstalled {
                Button("Mark Installed", systemImage: "checkmark.seal") {
                    markWindowsInstalledAction()
                }
                .disabled(isLoading)
            }

            if recommendedProofCommand != nil {
                Button("Check Windows App", systemImage: "checkmark.seal") {
                    runRecommendedProofAction()
                }
                .disabled(isLoading)
                .help("Run the strongest available Windows app check")
            }
        }
    }

    var hasRuntimeMoreActions: Bool {
        canInstallGuestAgent
            || canWaitForGuestAgent
            || canMarkWindowsInstalled
            || recommendedProofCommand != nil
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

    private var executablePrimaryNextActionRoute: LauncherPrimaryNextActionRoute? {
        guard effectiveInstallEvidence.isInstalled else {
            return nil
        }

        guard let route = LauncherPrimaryNextActionRoute.resolve(
            actionId: launchOnboarding.primaryActionId ?? launchOnboarding.currentStepId,
            command: launchOnboarding.primaryCommand,
            runsInApp: launchOnboarding.canContinueInApp
        ) else {
            return nil
        }

        return route
    }

    var effectivePrimaryTitle: String {
        if bootIsStalled {
            return primaryTitle
        }

        guard let route = executablePrimaryNextActionRoute else {
            return primaryTitle
        }

        switch route {
        case .launchSelectedApp:
            return selectedWindowsAppName.map { "Open \($0)" } ?? route.buttonTitle
        case .fulfillPendingLaunch:
            return "Open \(pendingAppDisplayName)"
        case .repairAppConnection:
            return "Open \(pendingWindowsAppName ?? selectedWindowsAppName ?? "Windows App")"
        case .startWindowsForApp:
            return selectedWindowsAppName.map { "Open \($0)" }
                ?? pendingWindowsAppName.map { "Open \($0)" }
                ?? route.buttonTitle
        default:
            return route.buttonTitle
        }
    }

    var effectivePrimarySymbol: String {
        if bootIsStalled {
            return primarySymbol
        }

        return executablePrimaryNextActionRoute?.symbolName ?? primarySymbol
    }

    var effectivePrimaryDisabled: Bool {
        if executablePrimaryNextActionRoute != nil {
            return primaryDisabled || !launchOnboarding.canContinueInApp
        }

        return primaryDisabled
    }

    var effectivePrimaryHelp: String {
        if bootIsStalled {
            return primaryHint
        }

        return executablePrimaryNextActionRoute == nil ? primaryTitle : launchOnboardingHelp
    }

    func runEffectivePrimaryAction() {
        if bootIsStalled {
            if canRecoverRuntimeDisplay {
                recoverRuntimeDisplayAction()
            } else {
                stopAction()
            }
            return
        }

        guard let route = executablePrimaryNextActionRoute else {
            primaryAction()
            return
        }

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
            launchWindowsAppAction()
        case .startWindows:
            primaryAction()
        case .startWindowsForApp:
            launchWindowsAppAction()
        case .prepareWindows:
            prepareAction()
        case .preparePackageIdentity:
            prepareSparsePackageAction()
        case .refreshRuntimeStatus:
            refreshAction()
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
            refreshAction()
        case .runRecommendedProof:
            runRecommendedProofAction()
        case .runMultiAppProof:
            runMultiAppProofAction()
        }
    }
}
