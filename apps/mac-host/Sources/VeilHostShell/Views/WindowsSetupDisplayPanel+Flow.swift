import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

extension WindowsSetupDisplayPanel {
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

    var launchOnboardingTitle: String {
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

    var launchOnboardingSymbolName: String {
        WindowsShellCopy.launchOnboardingSymbolName(
            state: launchOnboarding.state,
            canContinueInApp: launchOnboarding.canContinueInApp
        )
    }

    var launchOnboardingHelp: String {
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

    var installerNeedsFilePickerAccess: Bool {
        snapshot.preflightChecks.contains { check in
            check.id == "installer-media" && check.detail.contains("Re-select it with the file picker")
        }
    }

    var primaryDisabled: Bool {
        isLoading
            || snapshot.state == .unsupported
            || installSimulation.phase == .running
    }

    var progressFraction: Double {
        if installSimulation.phase == .running {
            return installSimulation.progress
        }

        if effectiveInstallEvidence.isInstalled {
            let completed = appOpenFlowItems.filter { $0.state == .complete }.count
            return Double(completed) / Double(appOpenFlowItems.count)
        }

        let completed = flowItems.filter { $0.state == .complete }.count
        return Double(completed) / Double(flowItems.count)
    }

    private var phaseTint: Color {
        switch snapshot.state {
        case .running:
            .green
        case .starting:
            .blue
        case .stopped:
            snapshot.bootReady ? .green : .orange
        case .failed, .unsupported:
            .orange
        case .notConfigured, .suspended:
            .secondary
        }
    }

    var progressTint: Color {
        installSimulation.phase == .running ? .blue : phaseTint
    }

    var canOpenWindowsApp: Bool {
        canRequestWindowsAppLaunch || canFulfillPendingLaunch
    }

    var prefersOneClickAppLaunch: Bool {
        WindowsAppLaunchCommandPolicy.prefersLaunchAsHero(
            windowsInstalled: effectiveInstallEvidence.isInstalled,
            hasSelectedApp: selectedWindowsAppName != nil
        )
    }

    var canRepairGuestAgentForAppLaunch: Bool {
        pendingLaunch.willLaunchOnAgentReconnect
            && !canFulfillPendingLaunch
            && (snapshot.state == .running || snapshot.state == .starting)
    }

    var canRecoverRuntimeDisplay: Bool {
        guard canShowDisplay else {
            return false
        }

        return snapshot.latestConsoleLaunch?.previewStatus == .stale
            || snapshot.latestConsoleLaunch?.previewStatus == .unavailable
    }

    var appOpenFlowItems: [InstallFlowItem] {
        [
            InstallFlowItem(
                title: "Windows",
                detail: snapshot.state == .running || snapshot.state == .starting
                    ? "Running locally"
                    : "Start Windows",
                symbolName: "play.rectangle",
                state: snapshot.state == .running || snapshot.state == .starting ? .complete : .current
            ),
            InstallFlowItem(
                title: "App Connection",
                detail: agentFlowDetail,
                symbolName: "bolt.horizontal.circle",
                state: agentFlowState
            ),
            InstallFlowItem(
                title: "App Window",
                detail: activeMirrorSession?.window.title
                    ?? (pendingLaunch.isQueued ? pendingAppDisplayName : appDisplayName),
                symbolName: "macwindow",
                state: appWindowFlowState
            ),
            InstallFlowItem(
                title: "App Check",
                detail: proofGateDetail,
                symbolName: "checkmark.seal",
                state: proofGateState
            )
        ]
    }

    private var agentFlowDetail: String {
        if canLaunchWindowsApp || canFulfillPendingLaunch {
            return "Connected"
        }

        if pendingLaunch.isQueued {
            return "Waiting for reconnect"
        }

        if canRequestWindowsAppLaunch {
            return snapshot.state == .running || snapshot.state == .starting
                ? "Repair before launch"
                : "Start before launch"
        }

        return "Waiting for app catalog"
    }

    private var agentFlowState: InstallFlowState {
        if canLaunchWindowsApp || canFulfillPendingLaunch {
            return .complete
        }

        if pendingLaunch.isQueued || canRequestWindowsAppLaunch {
            return snapshot.state == .running || snapshot.state == .starting ? .current : .pending
        }

        return .pending
    }

    private var appWindowFlowState: InstallFlowState {
        if activeMirrorSession != nil {
            return .complete
        }

        if canLaunchWindowsApp || canFulfillPendingLaunch {
            return .current
        }

        if pendingLaunch.isQueued || canRequestWindowsAppLaunch {
            return .pending
        }

        return .pending
    }

    private var proofGateState: InstallFlowState {
        guard recommendedProofCommand != nil else {
            return activeMirrorSession != nil ? .current : .pending
        }

        return recommendedProofKind == "mvp" ? .complete : .current
    }

    private var proofGateDetail: String {
        guard recommendedProofCommand != nil else {
            return activeMirrorSession != nil ? "Ready to check" : "Waiting for app"
        }

        switch recommendedProofKind {
        case "mvp":
            return "Full app check ready"
        case "coherence":
            return "Input check ready"
        case "app-window":
            return "Window check ready"
        default:
            return "App check ready"
        }
    }
}
