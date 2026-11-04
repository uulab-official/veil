import AppKit
import SwiftUI
import VeilHostCore

/// The app-first surface of Veil. VM controls stay in the runtime view below, while this
/// launcher remains stable as apps move from queued -> starting -> mirrored.
struct WindowsAppLauncherBar: View {
    var apps: [WindowsApp]
    @Binding var selectedAppId: String?
    var mirrorSessions: [WindowMirrorSession]
    var phase: HostDashboardPhase
    var runtimeState: VMRuntimeState?
    var windowsInstalled: Bool
    var hasLiveAgentConnection: Bool
    var appConnectionUnavailable: Bool
    var canRequestLaunch: Bool
    var canFulfillPendingLaunch: Bool
    var pendingAppName: String?
    var launchAction: () -> Void
    var repairConnectionAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            launcherIdentity

            Divider()
                .frame(height: 54)
                .opacity(0.55)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(apps) { app in
                        LauncherAppTile(
                            app: app,
                            selected: selectedAppId == app.id,
                            openWindowCount: mirrorSessions.filter { $0.window.appId == app.id }.count
                        ) {
                            selectedAppId = app.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                // Before Windows is installed the setup flow below owns the only real
                // action; a permanently disabled "Set up Windows" button here was a dead end.
                if showsPrimaryButton {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primarySymbol)
                            .frame(minWidth: 142)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!primaryEnabled)
                    .help(primaryHelp)
                }

                Text(statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 78)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Windows app launcher")
    }

    private var launcherIdentity: some View {
        HStack(spacing: 10) {
            WindowsLogoMark(size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Windows apps")
                    .font(.callout.weight(.semibold))
                Text(identitySubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 134, alignment: .leading)
        }
    }

    private var selectedApp: WindowsApp? {
        apps.first { $0.id == selectedAppId }
    }

    private var canLaunch: Bool {
        // A queued launch is only meaningful after the local Windows profile has been
        // installed. Before that point the runtime panel owns the ISO/profile setup flow;
        // keeping this button disabled prevents a misleading "Open" request from being
        // sent into an unconfigured VM.
        windowsInstalled
            && !apps.isEmpty
            && canRequestLaunch
            && phase != .loading
            && phase != .launching
    }

    private var primaryTitle: String {
        if phase == .launching {
            return "Opening…"
        }

        if appConnectionUnavailable {
            return "Repair connection"
        }

        if canFulfillPendingLaunch, let pendingAppName {
            return "Open " + pendingAppName
        }

        if !windowsInstalled {
            return "Set up Windows"
        }

        if let selectedApp {
            return "Open " + selectedApp.name
        }

        return "Open app"
    }

    private var primarySymbol: String {
        if phase == .launching {
            return "arrow.triangle.2.circlepath"
        }

        if appConnectionUnavailable {
            return "wrench.and.screwdriver"
        }

        return windowsInstalled ? "macwindow.badge.plus" : "arrow.right.circle"
    }

    private var identitySubtitle: String {
        if hasLiveAgentConnection {
            return "Ready on this Mac"
        }

        if appConnectionUnavailable {
            return "App connection needs repair"
        }

        if runtimeState == .starting {
            return "Starting in background"
        }

        if let pendingAppName {
            return pendingAppName + " queued"
        }

        if windowsInstalled {
            return "Connecting to Windows"
        }

        return "One click after setup"
    }

    private var statusText: String {
        if phase == .launching {
            return "Preparing the Windows window…"
        }

        if appConnectionUnavailable {
            return "Run the Veil Agent repair in Windows"
        }

        if !windowsInstalled {
            return "Install Windows once to unlock app launch"
        }

        if !hasLiveAgentConnection {
            return "Windows starts automatically when needed"
        }

        let count = mirrorSessions.count
        guard count > 0 else {
            return "No mirrored windows"
        }

        return String(count) + " app window" + (count == 1 ? "" : "s") + " open"
    }

    private var statusTint: Color {
        if phase == .launching || runtimeState == .starting {
            return .blue
        }

        if hasLiveAgentConnection {
            return .green
        }

        return windowsInstalled ? .secondary : .orange
    }

    // Repair is the primary action whenever it is offered; disabling it while the
    // same repair button below is enabled left the launcher contradicting the page.
    private var showsPrimaryButton: Bool {
        windowsInstalled || appConnectionUnavailable || canFulfillPendingLaunch
    }

    private var primaryEnabled: Bool {
        appConnectionUnavailable ? phase != .launching : canLaunch
    }

    private var primaryHelp: String {
        if appConnectionUnavailable {
            return "Repair the Veil Agent connection inside Windows"
        }

        return canLaunch ? "Open the selected Windows app as a Mac window" : "Finish Windows setup below to enable app launch"
    }

    private var primaryAction: () -> Void {
        appConnectionUnavailable ? repairConnectionAction : launchAction
    }
}

private struct LauncherAppTile: View {
    var app: WindowsApp
    var selected: Bool
    var openWindowCount: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                appIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(app.publisher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if openWindowCount > 0 {
                    Text("\(openWindowCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.green, in: Circle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 128, minHeight: 48, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.17) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.72) : Color.white.opacity(0.09), lineWidth: selected ? 1.2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select (app.name)")
    }

    private var appIcon: some View {
        Group {
            if let base64 = app.iconPngBase64,
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbolName: String {
        switch app.id {
        case "winapp_notepad": return "note.text"
        case "winapp_calculator": return "plus.forwardslash.minus"
        case "winapp_paint": return "paintpalette"
        default: return "app.window"
        }
    }

    private var tint: Color {
        switch app.id {
        case "winapp_notepad": return .blue
        case "winapp_calculator": return .green
        case "winapp_paint": return .orange
        default: return .teal
        }
    }
}
