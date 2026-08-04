import Foundation
import VeilHostCore

enum WindowsSetupCanvasPhase: Equatable {
    case needsInstaller
    case needsPreparation
    case readyToInstall
    case inProgress
    case needsIntegration
    case ready
    case failure
}

enum WindowsSetupCanvasPrimaryRoute: Equatable {
    case effectiveAction
    case existingISO
    case settings
}

struct WindowsSetupCanvasPresentation: Equatable {
    let phase: WindowsSetupCanvasPhase
    let title: String
    let detail: String
    let symbolName: String
    let primaryTitle: String
    let primarySymbolName: String
    let primaryHelp: String
    let primaryDisabled: Bool
    let primaryRoute: WindowsSetupCanvasPrimaryRoute
    let showsProgress: Bool
    let showsExistingISOAction: Bool
    let showsSettingsAction: Bool
    let showsDiagnosticsAction: Bool

    static func resolve(
        runtimeState: VMRuntimeState,
        windowsInstalled: Bool,
        hasInstaller: Bool,
        requiresInstallerAccess: Bool,
        installerName: String?,
        bootReady: Bool,
        isBusy: Bool,
        integrationReady: Bool,
        errorMessage: String?,
        primaryTitle: String,
        primarySymbolName: String,
        primaryHelp: String,
        primaryDisabled: Bool,
        hasDiagnostics: Bool
    ) -> Self {
        if errorMessage != nil || runtimeState == .failed || runtimeState == .unsupported {
            let usesSettings = primaryDisabled || runtimeState == .unsupported
            return Self(
                phase: .failure,
                title: "Windows needs attention",
                detail: "Veil couldn't continue Windows setup. Open settings or diagnostics for details.",
                symbolName: "exclamationmark.triangle.fill",
                primaryTitle: usesSettings ? "Open Settings" : primaryTitle,
                primarySymbolName: usesSettings ? "gearshape.fill" : primarySymbolName,
                primaryHelp: usesSettings ? "Open Windows settings" : primaryHelp,
                primaryDisabled: false,
                primaryRoute: usesSettings ? .settings : .effectiveAction,
                showsProgress: false,
                showsExistingISOAction: false,
                showsSettingsAction: !usesSettings,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        if isBusy || runtimeState == .starting {
            return Self(
                phase: .inProgress,
                title: "Getting Windows ready",
                detail: "Keep Veil open while setup continues.",
                symbolName: "arrow.triangle.2.circlepath",
                primaryTitle: primaryTitle,
                primarySymbolName: primarySymbolName,
                primaryHelp: primaryHelp,
                primaryDisabled: true,
                primaryRoute: .effectiveAction,
                showsProgress: true,
                showsExistingISOAction: false,
                showsSettingsAction: true,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        if requiresInstallerAccess {
            let displayName = installerName.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "the selected ISO"
            return Self(
                phase: .needsInstaller,
                title: "Allow access to Windows ISO",
                detail: "Re-select \(displayName) so Veil can use it.",
                symbolName: "folder.badge.questionmark",
                primaryTitle: "Use Existing ISO",
                primarySymbolName: "folder",
                primaryHelp: "Choose the Windows 11 Arm64 ISO again",
                primaryDisabled: false,
                primaryRoute: .existingISO,
                showsProgress: false,
                showsExistingISOAction: false,
                showsSettingsAction: true,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        if !windowsInstalled, !hasInstaller {
            return Self(
                phase: .needsInstaller,
                title: "Get Windows 11",
                detail: "Download Windows 11 Arm64 from Microsoft to continue.",
                symbolName: "arrow.down.circle.fill",
                primaryTitle: primaryTitle,
                primarySymbolName: primarySymbolName,
                primaryHelp: primaryHelp,
                primaryDisabled: primaryDisabled,
                primaryRoute: .effectiveAction,
                showsProgress: false,
                showsExistingISOAction: true,
                showsSettingsAction: true,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        if !windowsInstalled, !bootReady {
            let displayName = installerName.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Windows 11 Arm64"
            return Self(
                phase: .needsPreparation,
                title: "Prepare Windows",
                detail: "\(displayName) is ready. Veil will create local Windows storage.",
                symbolName: "internaldrive.fill",
                primaryTitle: primaryTitle,
                primarySymbolName: primarySymbolName,
                primaryHelp: primaryHelp,
                primaryDisabled: primaryDisabled,
                primaryRoute: .effectiveAction,
                showsProgress: false,
                showsExistingISOAction: false,
                showsSettingsAction: true,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        if !windowsInstalled {
            return Self(
                phase: .readyToInstall,
                title: "Install Windows 11",
                detail: "Windows Setup will open here in Veil.",
                symbolName: "display",
                primaryTitle: primaryTitle,
                primarySymbolName: primarySymbolName,
                primaryHelp: primaryHelp,
                primaryDisabled: primaryDisabled,
                primaryRoute: .effectiveAction,
                showsProgress: false,
                showsExistingISOAction: false,
                showsSettingsAction: true,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        if !integrationReady {
            return Self(
                phase: .needsIntegration,
                title: "Connect Windows apps",
                detail: "Finish Veil integration to open Windows apps as Mac windows.",
                symbolName: "macwindow.badge.plus",
                primaryTitle: primaryTitle,
                primarySymbolName: primarySymbolName,
                primaryHelp: primaryHelp,
                primaryDisabled: primaryDisabled,
                primaryRoute: .effectiveAction,
                showsProgress: false,
                showsExistingISOAction: false,
                showsSettingsAction: true,
                showsDiagnosticsAction: hasDiagnostics
            )
        }

        return Self(
            phase: .ready,
            title: "Windows apps are ready",
            detail: "Open a Windows app in its own Mac window.",
            symbolName: "checkmark.circle.fill",
            primaryTitle: primaryTitle,
            primarySymbolName: primarySymbolName,
            primaryHelp: primaryHelp,
            primaryDisabled: primaryDisabled,
            primaryRoute: .effectiveAction,
            showsProgress: false,
            showsExistingISOAction: false,
            showsSettingsAction: true,
            showsDiagnosticsAction: hasDiagnostics
        )
    }
}
