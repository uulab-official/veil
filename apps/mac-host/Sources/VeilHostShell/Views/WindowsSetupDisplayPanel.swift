import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct WindowsSetupDisplayPanel: View {
    @Environment(\.appRuntimeProvider) private var appRuntimeProvider
    var snapshot: VMRuntimeSnapshot
    var runtimeStartAt: Date?
    var guestAgentInstallEvidence: VMInstallEvidenceSummary?
    var agentDiagnostic: AgentConnectionDiagnostic?
    var statusText: String
    var canStart: Bool
    var canStop: Bool
    var isLoading: Bool
    var errorMessage: String?
    var diagnosticsURL: URL?
    var displayMessage: String?
    var canShowDisplay: Bool
    var prepareAction: () -> Void
    var selectInstallerAction: () -> Void
    var selectDriverAction: () -> Void
    var primaryAction: () -> Void
    var stopAction: () -> Void
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
    var canLaunchWindowsApp: Bool
    var canRequestWindowsAppLaunch: Bool
    var selectedWindowsAppName: String?
    var pendingLaunch: WindowsAppRuntimePendingLaunchStatus
    var canFulfillPendingLaunch: Bool
    var pendingWindowsAppName: String?
    var activeMirrorSession: WindowMirrorSession?
    var launchPlan: WindowsAppRuntimeLaunchPlanStatus
    var primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus
    var oneScreenUX: WindowsAppRuntimeOneScreenUXStatus
    var launchOnboarding: WindowsAppRuntimeLaunchOnboardingStatus
    var recommendedProofKind: String?
    var recommendedProofCommand: String?
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var displayResizeAction: ((Int, Int) -> Void)?
    var refreshAction: () -> Void
    var consolePointerTapAction: (Double, Double) -> Void
    var consoleKeyAction: (String) -> Void
    var detailsAction: () -> Void
    var installSimulation: InstallSimulationState
    @Binding var showsFullDesktop: Bool
    @State var showsAgentDiagnosticPopover = false

    var body: some View {
        Group {
            if effectiveInstallEvidence.isInstalled {
                installedLauncherStage
            } else {
                installProcessStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Power, view mode, and configuration live in the window toolbar and the Actions menu, so the
    /// installed stage is only the Windows surface itself.
    private var installedLauncherStage: some View {
        launcherDisplaySurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installProcessStage: some View {
        ZStack(alignment: .bottom) {
            installDisplaySurface

            if showsInstallControlBar {
                installControlBar
                    .background(.black.opacity(0.18))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Like a Parallels VM window, a live Windows Setup gets the whole surface: power and
    /// configuration are in the toolbar and the bar's extra actions are in the Actions menu. The bar
    /// returns only when there is no live display or the boot stalled and needs a recovery action.
    private var showsInstallControlBar: Bool {
        !(isMachineLive && hasDesktopDisplay) || bootIsStalled
    }

    private var installDisplaySurface: some View {
        ZStack {
            if displaySelection == .appleVirtualMachine,
               let embeddedVirtualMachine {
                EmbeddedVirtualMachineView(virtualMachine: embeddedVirtualMachine)
            } else if let displaySurface {
                WindowsEmbeddedDisplayPreview(
                    image: displayScreenshotImage,
                    surface: displaySurface,
                    path: snapshot.latestConsoleScreenshotPath ?? "",
                    revisionID: displayScreenshotRevisionID,
                    displayResizeAction: displayResizeAction,
                    pointerTapAction: consolePointerTapAction,
                    keyAction: consoleKeyAction
                )
            } else {
                machineDisplay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var launcherDisplaySurface: some View {
        if showsFullDesktop,
           displaySelection == .appleVirtualMachine,
           let embeddedVirtualMachine {
            EmbeddedVirtualMachineView(virtualMachine: embeddedVirtualMachine)
        } else if showsFullDesktop, let displaySurface {
            WindowsEmbeddedDisplayPreview(
                image: displayScreenshotImage,
                surface: displaySurface,
                path: snapshot.latestConsoleScreenshotPath ?? "",
                revisionID: displayScreenshotRevisionID,
                displayResizeAction: displayResizeAction,
                pointerTapAction: consolePointerTapAction,
                keyAction: consoleKeyAction
            )
        } else {
            machineDisplay
        }
    }

    private var installControlBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controlBarTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(controlBarSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            runtimeSettingsButton

            if hasDesktopDisplay || canStop || snapshot.state == .starting {
                Button(action: runEffectivePrimaryAction) {
                    Label(effectivePrimaryTitle, systemImage: effectivePrimarySymbol)
                        .frame(minWidth: canStop ? 124 : 142)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(effectivePrimaryDisabled)
            }

            if hasRuntimeMoreActions {
                runtimeMoreMenu
                    .fixedSize()
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var displayScreenshotImage: NSImage? {
        guard let path = snapshot.latestConsoleScreenshotPath else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }

    private var displaySurface: VMConsoleDisplaySurface? {
        if let surface = snapshot.latestConsoleLaunch?.displaySurface,
           surface.kind != .unavailable {
            return surface
        }

        guard let path = snapshot.latestConsoleScreenshotPath else {
            return nil
        }

        return VMConsoleDisplaySurface(
            kind: .screenshot,
            endpoint: nil,
            screenshotPath: path,
            isLiveCapable: false
        )
    }

    @MainActor
    private var embeddedVirtualMachine: VZVirtualMachine? {
        guard snapshot.runtimeProvider?.kind == .appleVirtualization,
              snapshot.state == .running || snapshot.state == .starting else {
            return nil
        }

        return VirtualizationVMRuntimeBooter.shared.activeVirtualMachine
    }

    private var displaySelection: RuntimeDisplaySelection {
        RuntimeDisplaySelection.resolve(
            provider: snapshot.runtimeProvider?.kind,
            state: snapshot.state,
            hasAppleVirtualMachine: embeddedVirtualMachine != nil,
            hasCapturedSurface: displaySurface != nil
        )
    }

    private var isMachineLive: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }

    var hasDesktopDisplay: Bool {
        displaySelection != .placeholder
    }

    private var displayScreenshotRevisionID: String {
        let path = snapshot.latestConsoleScreenshotPath ?? "missing"
        let refreshedAt = snapshot.latestConsoleLaunch?.consoleScreenshotRefreshedAt?.timeIntervalSince1970 ?? 0
        return "\(path)#\(refreshedAt)"
    }

    @ViewBuilder
    private var machineDisplay: some View {
        ZStack {
            Rectangle()
                .fill(machineHeroGradient)

            // Like Parallels, a machine that is not live shows its last screen dimmed behind the
            // play button instead of an empty gradient.
            if effectiveInstallEvidence.isInstalled, !isMachineLive, let displayScreenshotImage {
                Image(nsImage: displayScreenshotImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .opacity(0.32)
                    .clipped()
                    .accessibilityHidden(true)
            }

            if showsUnavailableGuestAgentRoute {
                appConnectionRecoveryHero
            } else {
                VStack(spacing: 16) {
                Spacer(minLength: 8)

                WindowsLogoMark(size: 64)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                VStack(spacing: 4) {
                    Text(machineTitle)
                        .font(.system(size: 30, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(machineSubtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }

                if let displayMessage, !displayMessage.isEmpty {
                    Label(displayMessage, systemImage: "info.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                        .accessibilityLabel(displayMessage)
                }

                if let runtimeFailurePresentation {
                    RuntimeFailureBanner(
                        presentation: runtimeFailurePresentation,
                        refreshAction: refreshAction,
                        detailsAction: detailsAction,
                        diagnosticsURL: diagnosticsURL
                    )
                    .frame(maxWidth: 620)
                }

                Button(action: runEffectivePrimaryAction) {
                    ZStack {
                        Circle()
                            .fill(effectivePrimaryDisabled ? Color.white.opacity(0.20) : Color.accentColor)
                        Image(systemName: effectivePrimarySymbol)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 74, height: 74)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(effectivePrimaryDisabled ? 0.12 : 0.34), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(effectivePrimaryDisabled)
                .help(effectivePrimaryHelp)
                .accessibilityLabel(effectivePrimaryTitle)
                .accessibilityHint(effectivePrimaryHelp)

                Text(effectivePrimaryTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if showsUnavailableGuestAgentRoute {
                    Label("Windows setup is available • Connect Windows apps to open them as Mac windows", systemImage: "network.slash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                AppWindowEngineNotice(
                    status: AppWindowEngineStatus.resolve(
                        bootProvider: appRuntimeProvider,
                        providers: snapshot.runtimeProviders
                    ),
                    isWindowsRunning: snapshot.state == .running || snapshot.state == .starting,
                    checkAgainAction: refreshAction
                )

                if effectiveInstallEvidence.isInstalled {
                    Label(launchOnboardingTitle, systemImage: launchOnboardingSymbolName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(launchOnboarding.canContinueInApp ? 0.88 : 0.68))
                        .lineLimit(1)
                        .help(launchOnboardingHelp)

                }

                // Readiness only matters while Windows is coming up; a stopped machine just needs play.
                if isMachineLive {
                    RuntimeReadinessTimeline(steps: runtimeReadinessSteps)
                        .frame(maxWidth: 860)
                }

                if snapshot.state == .starting {
                    WindowsRuntimeWaitBanner(
                        context: WindowsRuntimeWaitContext(
                            attemptStartedAt: runtimeStartAt,
                            persistedLaunchStartedAt: snapshot.latestConsoleLaunch?.startedAt
                        ),
                        refreshAction: refreshAction
                    )
                    .frame(maxWidth: 620)
                }

                if installSimulation.phase != .idle {
                    AssistantProgressStrip(simulation: installSimulation)
                        .frame(maxWidth: 420)
                        .foregroundStyle(.primary)
                } else if effectiveInstallEvidence.isInstalled, isMachineLive {
                    AppRuntimeProgressStrip(items: appOpenFlowItems)
                        .frame(maxWidth: 760)
                } else if !effectiveInstallEvidence.isInstalled {
                    ProgressView(value: progressFraction)
                        .tint(progressTint)
                        .frame(maxWidth: 420)
                }

                    Spacer(minLength: 8)
                }
                .foregroundStyle(.white)
                .padding(24)
            }
        }
    }

}
