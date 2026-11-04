import AppKit
import SwiftUI
import VeilHostCore

/// The Parallels-style Control Center: the Windows machine with its live thumbnail and state, then
/// the Windows apps that open as Mac windows.
struct ControlCenterSidebar: View {
    var snapshot: VMRuntimeSnapshot?
    var status: MachineStatusPresentation
    var apps: [WindowsApp]
    @Binding var selectedAppId: String?
    var mirrorSessions: [WindowMirrorSession]
    var windowsInstalled: Bool
    var canOpenApps: Bool
    var isLaunching: Bool
    var openAppAction: (String) -> Void
    var configureAction: () -> Void

    var body: some View {
        List {
            Section("Virtual Machines") {
                MachineSidebarRow(snapshot: snapshot, status: status)
                    .contextMenu {
                        Button("Configure…", systemImage: "gearshape", action: configureAction)
                    }
            }

            Section {
                if !windowsInstalled {
                    Label("Apps appear here after Windows is installed", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(apps) { app in
                        WindowsAppSidebarRow(
                            app: app,
                            isSelected: selectedAppId == app.id,
                            openWindowCount: mirrorSessions.filter { $0.window.appId == app.id }.count,
                            canOpen: canOpenApps && !isLaunching
                        ) {
                            selectedAppId = app.id
                            openAppAction(app.id)
                        }
                    }
                }
            } header: {
                Text("Windows Applications")
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Control Center")
    }
}

private struct MachineSidebarRow: View {
    var snapshot: VMRuntimeSnapshot?
    var status: MachineStatusPresentation

    var body: some View {
        HStack(spacing: 10) {
            MachineThumbnail(snapshot: snapshot)
                .frame(width: 64, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot?.profileName ?? "Windows 11")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Label(status.title, systemImage: status.symbolName)
                    .font(.caption)
                    .foregroundStyle(status.tint)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The latest console capture, or the Windows mark when Windows has never shown a frame.
struct MachineThumbnail: View {
    var snapshot: VMRuntimeSnapshot?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.02, green: 0.32, blue: 0.62), Color(red: 0.08, green: 0.09, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(isLive ? 1 : 0.55)
            } else {
                WindowsLogoMark(size: 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var isLive: Bool {
        snapshot?.state == .running || snapshot?.state == .starting
    }

    private var image: NSImage? {
        guard let path = snapshot?.latestConsoleScreenshotPath else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }
}

private struct WindowsAppSidebarRow: View {
    var app: WindowsApp
    var isSelected: Bool
    var openWindowCount: Int
    var canOpen: Bool
    var openAction: () -> Void

    var body: some View {
        Button(action: openAction) {
            HStack(spacing: 8) {
                WindowsAppIcon(app: app, size: 24)

                Text(app.name)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if openWindowCount > 0 {
                    Text("\(openWindowCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.green, in: Circle())
                        .accessibilityLabel("\(openWindowCount) open")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .help(canOpen ? "Open \(app.name) as a Mac window" : "Start Windows to open \(app.name)")
        .accessibilityLabel("Open \(app.name)")
    }
}

/// A Windows app's own icon when the guest sent one, otherwise a tinted SF Symbol.
struct WindowsAppIcon: View {
    var app: WindowsApp
    var size: CGFloat

    var body: some View {
        Group {
            if let base64 = app.iconPngBase64,
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }

    private var symbolName: String {
        switch app.id {
        case "winapp_notepad": "note.text"
        case "winapp_calculator": "plus.forwardslash.minus"
        case "winapp_paint": "paintpalette"
        default: "app.window"
        }
    }

    private var tint: Color {
        switch app.id {
        case "winapp_notepad": .blue
        case "winapp_calculator": .green
        case "winapp_paint": .orange
        default: .indigo
        }
    }
}
