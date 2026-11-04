import SwiftUI
import VeilHostCore

/// The three pages of the Installation Assistant, resolved from the local runtime snapshot.
enum InstallationAssistantStep: Int, CaseIterable, Identifiable {
    case getWindows
    case prepare
    case install

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .getWindows: "Get Windows"
        case .prepare: "Prepare This Mac"
        case .install: "Install Windows"
        }
    }

    var subtitle: String {
        switch self {
        case .getWindows: "Windows 11 Arm installer"
        case .prepare: "Profile, disk, and shared folder"
        case .install: "Windows Setup"
        }
    }

    var symbolName: String {
        switch self {
        case .getWindows: "arrow.down.circle"
        case .prepare: "internaldrive"
        case .install: "play.circle"
        }
    }

    /// An installer the file picker can no longer read counts as missing: Veil has to ask for it again.
    static func resolve(
        hasInstaller: Bool,
        installerNeedsPickerAccess: Bool,
        bootReady: Bool
    ) -> InstallationAssistantStep {
        if !hasInstaller || installerNeedsPickerAccess {
            return .getWindows
        }

        return bootReady ? .install : .prepare
    }
}

/// Parallels-style Installation Assistant shown until Windows is installed.
///
/// Once Windows Setup starts, the runtime view switches to the live Windows display, so this view
/// only covers the steps before the first boot.
struct InstallationAssistantView: View {
    @Environment(\.appRuntimeProvider) private var appRuntimeProvider
    var snapshot: VMRuntimeSnapshot
    var isLoading: Bool
    var errorMessage: String?
    var diagnosticsURL: URL?
    var installerNeedsPickerAccess: Bool
    /// Prepares the VM from a verified, downloaded ISO and starts Windows Setup.
    var prepareDownloadedISO: (URL) async -> Bool
    var chooseInstallerAction: () -> Void
    var prepareAction: () -> Void
    var installAction: () -> Void
    var configureAction: (MachineConfigurationTab) -> Void
    var refreshAction: () -> Void
    @State private var isDownloading = false

    var body: some View {
        HStack(spacing: 0) {
            stepList
                .frame(width: 240)

            Divider()
                .opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    page
                }
                .padding(36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.13, blue: 0.24), Color(red: 0.06, green: 0.07, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Installation Assistant")
        .onChange(of: currentStep) { _, step in
            // Once the ISO is in place the download page is done; returning to this step later
            // (for example after file access is lost) must not silently restart a download.
            if step != .getWindows {
                isDownloading = false
            }
        }
    }

    private var currentStep: InstallationAssistantStep {
        InstallationAssistantStep.resolve(
            hasInstaller: snapshot.installerMediaPath != nil,
            installerNeedsPickerAccess: installerNeedsPickerAccess,
            bootReady: snapshot.bootReady
        )
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                WindowsLogoMark(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Installation Assistant")
                        .font(.headline)
                    Text("Windows 11 on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)

            ForEach(InstallationAssistantStep.allCases) { step in
                AssistantStepRow(
                    step: step,
                    state: step.rawValue < currentStep.rawValue
                        ? .complete
                        : (step == currentStep ? .current : .pending)
                )
            }

            Spacer()

            Text("Windows comes from Microsoft and needs your own license. Veil never ships Windows.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var page: some View {
        if let failure = WindowsRuntimeFailurePresentation.resolve(
            state: snapshot.state,
            errorMessage: errorMessage,
            snapshotDetail: snapshot.detail
        ) {
            RuntimeFailureBanner(
                presentation: failure,
                refreshAction: refreshAction,
                detailsAction: { configureAction(.diagnostics) },
                diagnosticsURL: diagnosticsURL
            )
        }

        switch currentStep {
        case .getWindows where isDownloading:
            downloadPage
        case .getWindows:
            getWindowsPage
        case .prepare:
            preparePage
        case .install:
            installPage
        }
    }

    /// One click gets Windows: Veil downloads the latest Arm64 ISO from Microsoft, verifies it,
    /// prepares the VM, and starts Windows Setup. Bringing an ISO is the fallback, not a peer choice.
    private var getWindowsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: installerNeedsPickerAccess ? "Get Windows 11 again" : "Get Windows 11",
                detail: installerNeedsPickerAccess
                    ? "macOS no longer lets Veil read the installer chosen earlier. Veil can download it again from Microsoft."
                    : "Veil downloads the latest Windows 11 for Arm from Microsoft, verifies it, and starts Windows Setup. You don't need an ISO file."
            )

            AssistantChoiceCard(
                title: "Download and Install Windows 11",
                detail: "From microsoft.com, checked against Microsoft's published SHA-256. Setup starts automatically when the download finishes.",
                symbolName: "arrow.down.circle.fill",
                isPrimary: true,
                isDisabled: isLoading,
                action: { isDownloading = true }
            )
            .keyboardShortcut(.defaultAction)

            Button("Use an ISO file I already have…", action: chooseInstallerAction)
                .buttonStyle(.link)
                .disabled(isLoading)
        }
    }

    private var downloadPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: "Getting Windows 11",
                detail: "Keep Veil open. Windows Setup starts in this window as soon as the download is verified."
            )

            WindowsDownloadSheet(
                prepareDownloadedISO: prepareDownloadedISO,
                useExistingISO: chooseInstallerAction,
                presentation: .embedded(cancelAction: { isDownloading = false })
            )
            .frame(minHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var preparePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: "Prepare this Mac",
                detail: "Veil creates the Windows profile, a sparse virtual disk sized for this Mac, and a shared folder."
            )

            if !snapshot.installationSteps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.installationSteps) { step in
                        InstallationStepRow(step: step)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            engineNotice

            HStack(spacing: 10) {
                Button(action: prepareAction) {
                    Label(isLoading ? "Preparing…" : "Continue", systemImage: "arrow.right.circle.fill")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading)

                Button("Change Installer…", action: chooseInstallerAction)
                    .controlSize(.large)
                    .disabled(isLoading)
            }
        }
    }

    private var installPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: "Ready to install Windows",
                detail: "Windows Setup opens in this window. Follow it like on a PC; Veil detaches the installer when setup is done."
            )

            if let installer = snapshot.installerMediaPath {
                Label(URL(fileURLWithPath: installer).lastPathComponent, systemImage: "opticaldisc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            engineNotice

            HStack(spacing: 10) {
                Button(action: installAction) {
                    Label("Install Windows", systemImage: "play.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading || snapshot.state == .unsupported)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Starts Windows Setup in this window")

                Button("Configure…") {
                    configureAction(.hardware)
                }
                .controlSize(.large)
                .help("Change CPU, memory, and disk before installing")
            }
        }
    }

    private var engineNotice: some View {
        AppWindowEngineNotice(
            status: AppWindowEngineStatus.resolve(
                bootProvider: appRuntimeProvider,
                providers: snapshot.runtimeProviders
            ),
            isWindowsRunning: false,
            checkAgainAction: refreshAction
        )
    }

    private func pageHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AssistantStepRow: View {
    enum RowState {
        case complete
        case current
        case pending
    }

    var step: InstallationAssistantStep
    var state: RowState

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 26, height: 26)
                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(state == .current ? .white : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.callout.weight(state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                Text(step.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            state == .current ? Color.white.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var fill: Color {
        switch state {
        case .complete: .green
        case .current: .accentColor
        case .pending: .white.opacity(0.10)
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .complete: "Done"
        case .current: "Current step"
        case .pending: "Not started"
        }
    }
}

private struct AssistantChoiceCard: View {
    var title: String
    var detail: String
    var symbolName: String
    var isPrimary: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.accentColor : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(isPrimary ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isPrimary ? Color.accentColor.opacity(0.6) : .white.opacity(0.10), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
