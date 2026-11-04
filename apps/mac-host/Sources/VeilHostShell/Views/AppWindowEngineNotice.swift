import AppKit
import SwiftUI
import VeilHostCore

/// Whether the provider Veil booted with can open Windows apps as Mac windows.
///
/// Only the QEMU provider exposes the guest-agent network path that app windows need. The
/// provider is chosen once at launch, while snapshots re-probe on every refresh, so a QEMU
/// installed after launch shows up in the snapshot without changing how Windows will boot.
enum AppWindowEngineStatus: Equatable {
    case ready
    case needsInstall
    case needsRelaunch

    static let installCommand = "brew install qemu swtpm"

    static func resolve(
        bootProvider: AppRuntimeProviderSelection?,
        providers: [VMRuntimeProviderSummary],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        // An explicit provider override is a deliberate choice, not a missing dependency.
        if environment[AppRuntimeProviderSelection.environmentKey]?.isEmpty == false {
            return .ready
        }

        switch bootProvider {
        case .qemu, nil:
            return .ready
        case .appleVirtualization:
            let qemuIsActive = providers.contains { $0.kind == .qemuHypervisor && $0.status == .active }
            return qemuIsActive ? .needsRelaunch : .needsInstall
        }
    }
}

extension EnvironmentValues {
    @Entry var appRuntimeProvider: AppRuntimeProviderSelection?
}

struct AppWindowEngineNotice: View {
    var status: AppWindowEngineStatus
    var isWindowsRunning: Bool
    var checkAgainAction: () -> Void

    @State private var copied = false

    var body: some View {
        if status != .ready {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: status == .needsRelaunch ? "checkmark.seal.fill" : "macwindow.on.rectangle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    switch status {
                    case .needsInstall:
                        Text(AppWindowEngineStatus.installCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Button(copied ? "Copied" : "Copy", action: copyInstallCommand)
                            .help("Copy the Homebrew command that installs QEMU and the TPM emulator")

                        Button("Check Again", action: checkAgainAction)
                            .help("Look for QEMU again after installing it")

                        Link("Get Homebrew", destination: URL(string: "https://brew.sh")!)
                            .font(.caption)
                    case .needsRelaunch:
                        Button("Restart Veil", action: VeilRelauncher.relaunch)
                            .disabled(isWindowsRunning || !VeilRelauncher.canRelaunch)
                            .help(isWindowsRunning
                                ? "Stop Windows before restarting Veil"
                                : "Reopen Veil so Windows starts with QEMU")
                    case .ready:
                        EmptyView()
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: 620, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }

    private var title: String {
        switch status {
        case .needsRelaunch:
            return "QEMU is installed • restart Veil to open Windows apps as Mac windows"
        default:
            return "Windows apps open as Mac windows with QEMU"
        }
    }

    private var detail: String {
        switch status {
        case .needsRelaunch:
            return isWindowsRunning
                ? "Windows is still running with Apple Virtualization. Stop Windows, then restart Veil."
                : "Veil chose its Windows engine when it opened. Restarting switches it to QEMU."
        default:
            return "Without QEMU, Veil can install and run the full Windows desktop, but individual apps can't open as Mac windows. Install it with Homebrew, then check again."
        }
    }

    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppWindowEngineStatus.installCommand, forType: .string)
        copied = true
    }
}

enum VeilRelauncher {
    /// Relaunching only works from a real `.app` bundle; a `swift run` binary has nothing to reopen.
    static var canRelaunch: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    @MainActor
    static func relaunch() {
        guard canRelaunch else {
            return
        }

        // `open` waits for this process to exit first; otherwise LaunchServices would just
        // reactivate the instance that is about to quit.
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        // If the quit is cancelled the helper gives up after ~30 seconds instead of lingering.
        reopen.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done; kill -0 \"$1\" 2>/dev/null || /usr/bin/open \"$0\"",
            Bundle.main.bundlePath,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        do {
            try reopen.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }
}
