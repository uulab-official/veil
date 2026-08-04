import SwiftUI

struct WindowsSetupCanvas: View {
    let presentation: WindowsSetupCanvasPresentation
    let progress: Double
    let primaryAction: () -> Void
    let existingISOAction: () -> Void
    let settingsAction: () -> Void
    let diagnosticsAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 600 || proxy.size.width < 900

            ZStack(alignment: .topTrailing) {
                canvasBackground

                VStack(spacing: compact ? 14 : 22) {
                    Spacer(minLength: compact ? 12 : 30)

                    ZStack(alignment: .bottomTrailing) {
                        WindowsLogoMark(size: compact ? 58 : 76)
                            .shadow(color: .black.opacity(0.24), radius: 20, y: 10)

                        Image(systemName: presentation.symbolName)
                            .font(.system(size: compact ? 12 : 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                            .background(phaseTint, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                            .offset(x: 7, y: 6)
                    }

                    VStack(spacing: compact ? 6 : 9) {
                        Text(presentation.title)
                            .font(.system(size: compact ? 27 : 36, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.78)
                            .accessibilityAddTraits(.isHeader)

                        Text(presentation.detail)
                            .font(compact ? .callout : .title3)
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                            .frame(maxWidth: 560)
                            .help(presentation.detail)
                    }

                    primaryRegion

                    if presentation.showsExistingISOAction {
                        Button(action: existingISOAction) {
                            Label("Use Existing ISO", systemImage: "folder")
                                .frame(minWidth: 148)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Choose a Windows 11 Arm64 ISO already on this Mac")
                        .accessibilityLabel("Use Existing ISO")
                    }

                    Spacer(minLength: compact ? 12 : 30)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, compact ? 28 : 48)
                .padding(.vertical, compact ? 18 : 32)
                .contentTransition(.opacity)

                quietActions
                    .padding(compact ? 14 : 20)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
            value: presentation.phase
        )
    }

    private var primaryRegion: some View {
        Group {
            if presentation.showsProgress {
                VStack(spacing: 9) {
                    ProgressView(value: progress)
                        .tint(.white)
                        .frame(width: 250)
                        .accessibilityLabel("Windows setup progress")
                        .accessibilityValue("\(Int(progress * 100)) percent")

                    Text("Preparing Windows…")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }
            } else {
                Button {
                    switch presentation.primaryRoute {
                    case .effectiveAction:
                        primaryAction()
                    case .existingISO:
                        existingISOAction()
                    case .settings:
                        settingsAction()
                    }
                } label: {
                    Label(presentation.primaryTitle, systemImage: presentation.primarySymbolName)
                        .font(.headline)
                        .frame(minWidth: 224, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
                .disabled(presentation.primaryDisabled)
                .keyboardShortcut(.defaultAction)
                .help(presentation.primaryHelp)
                .accessibilityLabel(presentation.primaryTitle)
                .accessibilityHint(presentation.primaryHelp)
            }
        }
        .frame(width: 280, height: 62)
    }

    private var quietActions: some View {
        HStack(spacing: 8) {
            if presentation.showsDiagnosticsAction {
                Button(action: diagnosticsAction) {
                    Label("Diagnostics", systemImage: "stethoscope")
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .help("Open Windows diagnostics")
                .accessibilityLabel("Diagnostics")
            }

            if presentation.showsSettingsAction {
                Button(action: settingsAction) {
                    Label("Settings", systemImage: "gearshape.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .help("Open Windows settings")
                .accessibilityLabel("Settings")
            }
        }
        .controlSize(.small)
    }

    private var canvasBackground: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.09)

            LinearGradient(
                colors: [phaseTint.opacity(0.68), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            RadialGradient(
                colors: [.white.opacity(0.08), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }

    private var phaseTint: Color {
        switch presentation.phase {
        case .needsInstaller, .needsPreparation, .readyToInstall, .inProgress:
            return .blue
        case .needsIntegration:
            return .indigo
        case .ready:
            return .green
        case .failure:
            return .orange
        }
    }
}
