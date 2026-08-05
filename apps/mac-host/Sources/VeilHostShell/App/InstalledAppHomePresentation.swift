import Foundation
import VeilHostCore

enum WindowsOptimizationConsentPolicy {
    static let title = "Optimize Windows Automatically?"
    static let message = "Veil will install official UTM Guest Tools and the Veil guest agent, then restart once. Review both terms before continuing. Your Windows disk and files are preserved."
    static let reviewButtonTitle = "Review Both Terms"
    static let acceptButtonTitle = "I Agree and Optimize"
    static let microsoftTermsURL = WindowsLicenseConsentPolicy.termsURL
    static let guestToolsInformationURL = WindowsLicenseConsentPolicy.guestToolsInformationURL
}

struct InstalledWindowsAppHomeHeadingPresentation: Equatable {
    let title: String
    let detail: String

    static func resolve(
        base: InstalledAppHomePresentation,
        optimization: InstalledWindowsOptimizationPresentation?
    ) -> Self {
        guard optimization != nil else {
            return Self(title: base.title, detail: base.detail)
        }

        return Self(
            title: "Windows Apps",
            detail: "Complete integration once, then open Windows apps here."
        )
    }
}

struct InstalledWindowsOptimizationPresentation: Equatable {
    let title: String
    let detail: String
    let progress: Double
    let isRunning: Bool
    let primaryButtonTitle: String
    let showsPrimaryAction: Bool
    let showsCancel: Bool

    static func resolve(
        windowsInstalled: Bool,
        provider: VMRuntimeProviderKind?,
        installEvidenceKind: VMInstallEvidenceKind,
        status: WindowsOptimizationStatus
    ) -> Self? {
        guard windowsInstalled,
              provider == .qemuHypervisor,
              status.showsOptimizationCard else {
            return nil
        }

        let isPartialCompletion: Bool
        if case .complete(displayOptimized: false) = status.phase {
            isPartialCompletion = true
        } else {
            isPartialCompletion = false
        }

        guard installEvidenceKind != .guestAgent || isPartialCompletion else {
            return nil
        }

        return Self(
            title: status.title,
            detail: status.detail,
            progress: status.progress,
            isRunning: status.isRunning,
            primaryButtonTitle: status.primaryButtonTitle,
            showsPrimaryAction: !isPartialCompletion,
            showsCancel: status.canCancel
        )
    }
}

enum InstalledAppHomePhase: Equatable {
    case ready
    case stopped
    case starting
    case reconnecting
    case loading
    case catalogUnavailable
    case failure
}

enum InstalledAppHomeTone: Equatable {
    case neutral
    case progress
    case warning
}

enum InstalledAppHomeRecoveryRoute: Equatable {
    case effectiveAction
    case refresh
}

struct InstalledAppHomePresentation: Equatable {
    let phase: InstalledAppHomePhase
    let title: String
    let detail: String
    let tone: InstalledAppHomeTone
    let isGridEnabled: Bool
    let recoveryTitle: String?
    let recoverySymbolName: String?
    let recoveryRoute: InstalledAppHomeRecoveryRoute?

    static func resolve(
        runtimeState: VMRuntimeState,
        dashboardPhase: HostDashboardPhase,
        hasLiveAgentConnection: Bool,
        appCount: Int,
        pendingAppId: String?,
        errorMessage: String?
    ) -> Self {
        if errorMessage != nil
            || dashboardPhase == .failed
            || runtimeState == .failed
            || runtimeState == .unsupported
            || runtimeState == .notConfigured {
            return .init(
                phase: .failure,
                title: "Windows needs attention",
                detail: "Veil could not make Windows apps available. Try the recovery action or open Settings for details.",
                tone: .warning,
                isGridEnabled: false,
                recoveryTitle: "Try Again",
                recoverySymbolName: "arrow.clockwise",
                recoveryRoute: .effectiveAction
            )
        }

        if appCount == 0 {
            if dashboardPhase == .loading || runtimeState == .starting {
                return .init(
                    phase: .loading,
                    title: "Windows Apps",
                    detail: "Loading your Windows apps…",
                    tone: .progress,
                    isGridEnabled: false,
                    recoveryTitle: nil,
                    recoverySymbolName: nil,
                    recoveryRoute: nil
                )
            }

            return .init(
                phase: .catalogUnavailable,
                title: "Windows Apps",
                detail: "Veil could not load the Windows app list.",
                tone: .warning,
                isGridEnabled: false,
                recoveryTitle: "Check Again",
                recoverySymbolName: "arrow.clockwise",
                recoveryRoute: .refresh
            )
        }

        if dashboardPhase == .reconnecting
            || (runtimeState == .running && !hasLiveAgentConnection) {
            return .init(
                phase: .reconnecting,
                title: "Windows Apps",
                detail: pendingAppId == nil
                    ? "Reconnecting to Windows apps…"
                    : "Reconnecting so your selected app can open…",
                tone: .progress,
                isGridEnabled: false,
                recoveryTitle: "Reconnect",
                recoverySymbolName: "bolt.horizontal.circle",
                recoveryRoute: .effectiveAction
            )
        }

        if dashboardPhase == .loading {
            return .init(
                phase: .loading,
                title: "Windows Apps",
                detail: "Checking Windows apps…",
                tone: .progress,
                isGridEnabled: false,
                recoveryTitle: nil,
                recoverySymbolName: nil,
                recoveryRoute: nil
            )
        }

        if runtimeState == .starting || dashboardPhase == .launching {
            return .init(
                phase: .starting,
                title: "Windows Apps",
                detail: pendingAppId == nil ? "Starting Windows…" : "Opening your selected app…",
                tone: .progress,
                isGridEnabled: false,
                recoveryTitle: nil,
                recoverySymbolName: nil,
                recoveryRoute: nil
            )
        }

        if runtimeState == .stopped || runtimeState == .suspended {
            return .init(
                phase: .stopped,
                title: "Windows Apps",
                detail: "Windows starts automatically when you open an app.",
                tone: .neutral,
                isGridEnabled: true,
                recoveryTitle: nil,
                recoverySymbolName: nil,
                recoveryRoute: nil
            )
        }

        return .init(
            phase: .ready,
            title: "Windows Apps",
            detail: "Choose an app to open it in its own Mac window.",
            tone: .neutral,
            isGridEnabled: true,
            recoveryTitle: nil,
            recoverySymbolName: nil,
            recoveryRoute: nil
        )
    }
}

struct InstalledAppTilePresentation: Equatable {
    let statusText: String?
    let showsProgress: Bool
    let accessibilityValue: String

    static func resolve(
        appId: String,
        pendingAppId: String?,
        openWindowCount: Int,
        dashboardPhase: HostDashboardPhase
    ) -> Self {
        if appId == pendingAppId {
            return .init(
                statusText: "Opening…",
                showsProgress: true,
                accessibilityValue: "Opening"
            )
        }

        guard openWindowCount > 0 else {
            return .init(
                statusText: nil,
                showsProgress: false,
                accessibilityValue: "Ready"
            )
        }

        let windowLabel = openWindowCount == 1 ? "window" : "windows"
        return .init(
            statusText: "\(openWindowCount) \(windowLabel)",
            showsProgress: false,
            accessibilityValue: "\(openWindowCount) \(windowLabel)"
        )
    }
}
