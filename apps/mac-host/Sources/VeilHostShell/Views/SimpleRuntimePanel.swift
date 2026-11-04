import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct SimpleRuntimePanel: View {
    var snapshot: VMRuntimeSnapshot
    var statusText: String
    var canStart: Bool
    var canStop: Bool
    var isLoading: Bool
    var errorMessage: String?
    var diagnosticsURL: URL?
    var displayMessage: String?
    var installSimulation: InstallSimulationState
    var primaryAction: () -> Void
    var chooseISOAction: () -> Void
    var displayAction: () -> Void
    var refreshAction: () -> Void
    var detailsAction: () -> Void
    var resetSimulationAction: () -> Void
    var runtimeTitle: String
    var runtimeSymbol: String
    var runtimeTint: Color

    var body: some View {
        ShellPanel(spacing: 20) {
            HStack(alignment: installSimulation.phase == .idle ? .center : .top, spacing: 22) {
                MachineBadge()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Windows 11 Arm")
                                .font(.largeTitle.weight(.semibold))
                                .lineLimit(1)
                            Text(summaryText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        StatusPill(title: runtimeTitle, symbolName: runtimeSymbol, tint: runtimeTint)
                    }

                    if installSimulation.phase == .idle {
                        setupStrip
                    } else {
                        InstallSimulationProgressView(
                            simulation: installSimulation,
                            resetAction: resetSimulationAction
                        )
                    }

                    if let displayMessage {
                        Label(displayMessage, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    HStack(spacing: 9) {
                        Button(action: primaryAction) {
                            Label(primaryTitle, systemImage: primarySymbol)
                                .frame(minWidth: 176)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(primaryDisabled)

                        if !canStart && !snapshot.windowsInstalled && installSimulation.phase == .idle {
                            Button(action: chooseISOAction) {
                                Label("Choose ISO", systemImage: "opticaldisc")
                            }
                            .disabled(isLoading)

                            Link(destination: Self.microsoftArmDownloadURL) {
                                Label("Get Windows", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(action: refreshAction) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(isLoading || installSimulation.phase == .running)
                        .help("Refresh")

                        Button(action: detailsAction) {
                            Label("Settings", systemImage: "gearshape")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(isLoading)
                        .help("Details")

                        Spacer()
                    }
                }
            }
        }
    }

    private static let microsoftArmDownloadURL = URL(string: "https://www.microsoft.com/en-us/software-download/windows11arm64")!

    private var setupStrip: some View {
        HStack(spacing: 18) {
            SetupStatusItem(
                title: "Windows ISO",
                detail: installerDetail,
                symbolName: "opticaldisc",
                state: installerState
            )
            SetupStatusItem(
                title: "Virtual Disk",
                detail: snapshot.virtualDiskPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not created",
                symbolName: "internaldrive",
                state: snapshot.virtualDiskPath == nil ? .pending : .complete
            )
            SetupStatusItem(
                title: "Auto Install",
                detail: answerFileDetail,
                symbolName: "text.document",
                state: snapshot.automaticInstallMediaPath == nil ? .pending : .complete
            )
            SetupStatusItem(
                title: "Install",
                detail: snapshot.bootReady ? "Can start" : "Needs setup",
                symbolName: "checkmark.seal",
                state: snapshot.bootReady ? .complete : .pending
            )
        }
    }

    private var installerDetail: String {
        if snapshot.windowsInstalled {
            return "Not required after install"
        }

        if let path = snapshot.installerMediaPath {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return "Not selected"
    }

    private var installerState: SetupStatusState {
        if snapshot.windowsInstalled {
            return .complete
        }

        if snapshot.installerMediaPath != nil {
            return .complete
        }

        return .pending
    }

    private var answerFileDetail: String {
        guard let path = snapshot.automaticInstallMediaPath else {
            return "Not prepared"
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var summaryText: String {
        switch snapshot.state {
        case .unsupported:
            return "This Mac cannot run the current Windows 11 Arm setup."
        case .notConfigured:
            return "Choose a Windows 11 Arm ISO, then prepare Windows."
        case .stopped:
            if installSimulation.phase == .complete {
                return "Windows start handoff finished. Start again if setup did not continue."
            }

            if snapshot.windowsInstalled {
                return "Start installed Windows from this main window."
            }

            return snapshot.bootReady ? "Start Windows setup from this main window." : statusText
        case .starting:
            return "Starting Windows and opening its desktop window."
        case .running:
            return "Windows is running locally. Open a Windows app once the app connection is ready."
        case .suspended:
            return "Windows is paused."
        case .failed:
            return "The last start attempt failed. Open details for diagnostics."
        }
    }

    var primaryTitle: String {
        if canStop {
            return "Stop"
        }

        if canStart {
            switch installSimulation.phase {
            case .idle:
                return "Start Windows"
            case .running:
                return "Starting..."
            case .complete:
                return "Start Again"
            }
        }

        if !snapshot.windowsInstalled && snapshot.installerMediaPath == nil {
            return "Choose Windows ISO"
        }

        return snapshot.profileName == nil ? "Prepare Windows" : "Continue Setup"
    }

    var primarySymbol: String {
        if canStop {
            return "stop.fill"
        }

        if canStart {
            return "play.fill"
        }

        if !snapshot.windowsInstalled && snapshot.installerMediaPath == nil {
            return "opticaldisc"
        }

        return "wand.and.stars"
    }

    var primaryDisabled: Bool {
        if canStop {
            return isLoading || snapshot.state == .unsupported
        }

        return isLoading || snapshot.state == .unsupported || installSimulation.phase == .running
    }

    private var canShowDisplay: Bool {
        snapshot.state == .running || snapshot.state == .starting
    }
}

struct InstallSimulationProgressView: View {
    var simulation: InstallSimulationState
    var resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer()

                Text("\(Int(simulation.progress * 100))%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: simulation.progress)
                .tint(tint)
                .controlSize(.large)

            stepTimeline

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(simulation.currentStep)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if simulation.phase == .complete {
                    Button(action: resetAction) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset progress")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private var stepTimeline: some View {
        HStack(spacing: 7) {
            ForEach(InstallSimulationState.steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= simulation.stepIndex || simulation.phase == .complete ? tint : Color.secondary.opacity(0.22))
                    .frame(height: 6)
            }
        }
    }

    private var title: String {
        switch simulation.phase {
        case .idle:
            return "Windows preview ready"
        case .running:
            return "Starting Windows preview"
        case .complete:
            return "Windows preview attached"
        }
    }

    private var symbolName: String {
        switch simulation.phase {
        case .idle:
            return "wand.and.stars"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .complete:
            return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch simulation.phase {
        case .idle:
            return .blue
        case .running:
            return .blue
        case .complete:
            return .green
        }
    }
}

struct MachineBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.blue.gradient)
            VStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 42, weight: .semibold))
                Text("11")
                    .font(.title.bold())
            }
            .foregroundStyle(.white)
        }
        .frame(width: 140, height: 140)
    }
}

struct RuntimeLandingPanel: View {
    var title: String
    var subtitle: String
    var primaryTitle: String
    var primarySymbol: String
    var secondaryTitle: String
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.32, blue: 0.62),
                            Color(red: 0.06, green: 0.10, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            WindowsDisplayGrid()
                .opacity(0.16)

            VStack(spacing: 18) {
                WindowsLogoMark(size: 86)
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 38, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primarySymbol)
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: secondaryAction) {
                        Label(secondaryTitle, systemImage: secondaryTitle == "Refresh" ? "arrow.clockwise" : "wand.and.stars")
                    }
                    .controlSize(.large)
                }
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}
