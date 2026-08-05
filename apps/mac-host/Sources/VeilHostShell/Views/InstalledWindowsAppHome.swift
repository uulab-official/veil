import AppKit
import SwiftUI
import VeilHostCore

struct InstalledWindowsAppHome: View {
    let presentation: InstalledAppHomePresentation
    let optimizationPresentation: InstalledWindowsOptimizationPresentation?
    let apps: [WindowsApp]
    @Binding var selectedAppId: String?
    let pendingAppId: String?
    let openWindowCounts: [String: Int]
    let canShowDesktop: Bool
    let launchAction: () -> Void
    let showDesktopAction: () -> Void
    let settingsAction: () -> Void
    let effectiveRecoveryAction: () -> Void
    let optimizationPrimaryAction: () -> Void
    let cancelOptimizationAction: () -> Void
    let refreshAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 900 || proxy.size.height < 600

            ZStack {
                canvasBackground

                VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                    topRow(compact: compact)

                    if let optimizationPresentation {
                        optimizationCard(optimizationPresentation, compact: compact)
                    }

                    ScrollView {
                        appRegion(compact: compact)
                            .frame(maxWidth: 920)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, compact ? 18 : 30)
                    }
                }
                .padding(.horizontal, compact ? 22 : 42)
                .padding(.vertical, compact ? 18 : 30)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
            value: presentation.phase
        )
    }

    private func topRow(compact: Bool) -> some View {
        let heading = InstalledWindowsAppHomeHeadingPresentation.resolve(
            base: presentation,
            optimization: optimizationPresentation
        )

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading.title)
                    .font(.system(size: compact ? 26 : 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(heading.detail)
                    .font(compact ? .callout : .title3)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(compact ? 2 : 1)
                    .minimumScaleFactor(0.84)
            }

            Spacer(minLength: 12)

            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if canShowDesktop {
                Button(action: showDesktopAction) {
                    Label("Windows Desktop", systemImage: "display")
                }
                .buttonStyle(.bordered)
                .help("Open the Windows desktop")
            }

            if optimizationPresentation == nil,
               let recoveryTitle = presentation.recoveryTitle,
               let recoverySymbolName = presentation.recoverySymbolName,
               let recoveryRoute = presentation.recoveryRoute {
                Button {
                    switch recoveryRoute {
                    case .effectiveAction:
                        effectiveRecoveryAction()
                    case .refresh:
                        refreshAction()
                    }
                } label: {
                    Label(recoveryTitle, systemImage: recoverySymbolName)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(action: settingsAction) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .help("Open Windows settings")
            .accessibilityLabel("Settings")
        }
        .controlSize(.small)
    }

    private func optimizationCard(
        _ optimization: InstalledWindowsOptimizationPresentation,
        compact: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: compact ? 14 : 20) {
            Image(systemName: optimization.isRunning ? "gearshape.2.fill" : "wand.and.stars")
                .font(.system(size: compact ? 24 : 30, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: compact ? 42 : 50, height: compact ? 42 : 50)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(optimization.title)
                    .font(.headline)

                Text(optimization.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 1)

                if optimization.isRunning {
                    ProgressView(value: optimization.progress)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Windows optimization progress")
                        .accessibilityValue("\(Int(optimization.progress * 100)) percent")
                }
            }

            Spacer(minLength: 8)

            if optimization.showsCancel {
                Button("Cancel", role: .cancel, action: cancelOptimizationAction)
                    .buttonStyle(.bordered)
            } else if !optimization.isRunning, optimization.showsPrimaryAction {
                Button(action: optimizationPrimaryAction) {
                    Label(optimization.primaryButtonTitle, systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(compact ? 14 : 18)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func appRegion(compact: Bool) -> some View {
        if apps.isEmpty {
            ContentUnavailableView(
                presentation.phase == .loading ? "Loading Windows Apps" : "No Windows Apps Available",
                systemImage: presentation.phase == .loading ? "arrow.triangle.2.circlepath" : "square.grid.2x2"
            )
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: compact ? 240 : 340)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: compact ? 112 : 148, maximum: compact ? 150 : 188),
                        spacing: compact ? 12 : 18
                    )
                ],
                spacing: compact ? 12 : 18
            ) {
                ForEach(apps) { app in
                    InstalledWindowsAppTile(
                        app: app,
                        isSelected: selectedAppId == app.id,
                        pendingAppId: pendingAppId,
                        openWindowCount: openWindowCounts[app.id, default: 0],
                        dashboardPhase: tileDashboardPhase,
                        isGridEnabled: presentation.isGridEnabled,
                        selectedAppId: $selectedAppId,
                        launchAction: launchAction
                    )
                }
            }
        }
    }

    private var tileDashboardPhase: HostDashboardPhase {
        switch presentation.phase {
        case .ready, .stopped:
            .connected
        case .starting:
            .launching
        case .reconnecting:
            .reconnecting
        case .loading:
            .loading
        case .catalogUnavailable, .failure:
            .failed
        }
    }

    private var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.26, blue: 0.58),
                Color(red: 0.03, green: 0.06, blue: 0.12),
                Color(red: 0.015, green: 0.02, blue: 0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct InstalledWindowsAppTile: View {
    let app: WindowsApp
    let isSelected: Bool
    let pendingAppId: String?
    let openWindowCount: Int
    let dashboardPhase: HostDashboardPhase
    let isGridEnabled: Bool
    @Binding var selectedAppId: String?
    let launchAction: () -> Void

    var body: some View {
        let tilePresentation = InstalledAppTilePresentation.resolve(
            appId: app.id,
            pendingAppId: pendingAppId,
            openWindowCount: openWindowCount,
            dashboardPhase: dashboardPhase
        )

        Button {
            selectedAppId = app.id
            launchAction()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                appIcon

                Text(app.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if tilePresentation.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let statusText = tilePresentation.statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(height: 14, alignment: .leading)
            }
            .padding(compactTilePadding)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .foregroundStyle(.primary)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? .white.opacity(0.8) : .white.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isGridEnabled)
        .help("Open \(app.name) as a Mac window")
        .accessibilityLabel("Open \(app.name)")
        .accessibilityValue(tilePresentation.accessibilityValue)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: fallbackSymbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(fallbackColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var icon: NSImage? {
        guard let base64 = app.iconPngBase64,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return NSImage(data: data)
    }

    private var fallbackSymbolName: String {
        switch app.id {
        case "winapp_notepad":
            "note.text"
        case "winapp_calculator":
            "plus.forwardslash.minus"
        case "winapp_paint":
            "paintpalette"
        default:
            "app.window"
        }
    }

    private var fallbackColor: Color {
        switch app.id {
        case "winapp_notepad":
            .blue
        case "winapp_calculator":
            .green
        case "winapp_paint":
            .orange
        default:
            .teal
        }
    }

    private var compactTilePadding: CGFloat {
        14
    }

    private var tileBackground: Color {
        isSelected ? .white.opacity(0.22) : .white.opacity(0.12)
    }
}
