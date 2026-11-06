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
    @Environment(ShellNavigation.self) private var navigation
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
    /// Saves the local Windows account name before the answer file is built.
    var saveAccountName: (String) async -> Void = { _ in }
    @State private var isDownloading = false
    @State private var accountName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                assistantHeader

                VStack(alignment: .leading, spacing: 20) {
                    page
                }
                .frame(maxWidth: 640, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Text("Windows comes from Microsoft and needs your own license. Veil never ships Windows.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 14)
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

    /// The assistant's name and a horizontal stepper, centered above the page like a macOS setup
    /// assistant, so the window keeps a single sidebar.
    private var assistantHeader: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                WindowsLogoMark(size: 16)
                Text("Installation Assistant")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(InstallationAssistantStep.allCases) { step in
                    if step != .getWindows {
                        Capsule()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor.opacity(0.7) : .white.opacity(0.12))
                            .frame(height: 2)
                            .frame(minWidth: 24, maxWidth: 72)
                            .padding(.horizontal, 10)
                    }

                    AssistantStepRow(
                        step: step,
                        state: step.rawValue < currentStep.rawValue
                            ? .complete
                            : (step == currentStep ? .current : .pending)
                    )
                }
            }
            .frame(maxWidth: 640)
        }
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

            accountField

            AssistantChoiceCard(
                title: "Download and Install Windows 11",
                detail: "From microsoft.com, checked against Microsoft's published SHA-256. Setup starts automatically when the download finishes.",
                symbolName: "arrow.down.circle.fill",
                isPrimary: true,
                isDisabled: isLoading,
                action: {
                    Task {
                        await saveAccountName(accountName)
                        isDownloading = true
                    }
                }
            )
            .keyboardShortcut(.defaultAction)

            Button("Use an ISO file I already have…") {
                Task {
                    await saveAccountName(accountName)
                    chooseInstallerAction()
                }
            }
            .buttonStyle(.link)
            .disabled(isLoading)
        }
        .onAppear {
            accountName = snapshot.windowsAccountName ?? ""
        }
    }

    /// Setup creates this local account and signs in to it, so Windows never stops to ask who
    /// will use the device. Leaving it empty uses this Mac's user name.
    private var accountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Windows account")
                .font(.subheadline.weight(.medium))
            TextField(WindowsAccountName.resolve(preferred: nil), text: $accountName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .disabled(isLoading)
                .onSubmit {
                    Task { await saveAccountName(accountName) }
                }
            Text("Windows signs in to this local account automatically. Add a password later in Windows Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var downloadPage: some View {
        // The download stage carries its own title, so the page adds no header above it.
        VStack(alignment: .leading, spacing: 12) {
            WindowsDownloadSheet(
                prepareDownloadedISO: prepareDownloadedISO,
                useExistingISO: chooseInstallerAction,
                presentation: .embedded(cancelAction: { isDownloading = false }),
                prefetchesDriverMedia: snapshot.driverMediaPath == nil
            )
            .frame(minHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }

            Label("Keep Veil open. Windows Setup starts in this window as soon as the ISO is verified.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .disabled(isLoading || snapshot.state == .unsupported || !engineStatus.canRunWindows)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(engineStatus.canRunWindows
                    ? "Starts Windows Setup in this window"
                    : "Install QEMU first; Apple Virtualization can't run Windows")

                Button("Configure…") {
                    configureAction(.hardware)
                }
                .controlSize(.large)
                .help("Change CPU, memory, and disk before installing")
            }

            if RestartInstallationAvailability.hasPreviousAttempt(snapshot: snapshot) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .foregroundStyle(.orange)
                    Text("An earlier installation didn't finish.")
                        .foregroundStyle(.secondary)
                    Button("Start Over…") {
                        navigation.requestRestartInstallation()
                    }
                    .buttonStyle(.link)
                    .disabled(isLoading)
                }
                .font(.callout)
            }
        }
    }

    private var engineStatus: AppWindowEngineStatus {
        AppWindowEngineStatus.resolve(
            bootProvider: appRuntimeProvider,
            providers: snapshot.runtimeProviders
        )
    }

    private var engineNotice: some View {
        AppWindowEngineNotice(
            status: engineStatus,
            isWindowsRunning: false,
            checkAgainAction: refreshAction
        )
    }

    private func pageHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized: title)
                .font(.system(size: 26, weight: .semibold))
            Text(localized: detail)
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
                    .frame(width: 24, height: 24)
                    .overlay {
                        if state == .current {
                            Circle()
                                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3)
                                .padding(-4)
                        }
                    }
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
                Text(localized: step.title)
                    .font(.callout.weight(state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                Text(localized: step.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
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
                    Text(localized: title)
                        .font(.headline)
                    Text(localized: detail)
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
