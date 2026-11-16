import AppKit
import SwiftUI
import VeilHostCore

/// The Parallels-style Control Center: the Windows machine with its live thumbnail and state, then
/// the Windows apps that open as Mac windows.
struct ControlCenterSidebar: View {
    var snapshot: VMRuntimeSnapshot?
    var status: MachineStatusPresentation
    var liveThumbnail: NSImage?
    var apps: [WindowsApp]
    @Binding var selectedAppId: String?
    var mirrorSessions: [WindowMirrorSession]
    var windowsInstalled: Bool
    var canOpenApps: Bool
    var isLaunching: Bool
    var openAppAction: (String) -> Void
    var configureAction: () -> Void
    /// False while the selected machine runs or an operation is in flight: Veil runs one machine at
    /// a time, so switching away from a live one is refused.
    var canChangeMachines: Bool = true
    /// Reloads the runtime snapshot after the selected machine changed; `true` also prepares its
    /// UEFI variables and TPM folder, which an imported disk arrives without.
    var machineDidChange: (Bool) -> Void = { _ in }

    @State private var library = VMLibraryController()
    @State private var renameTarget: VMLibraryMachine?
    @State private var deleteTarget: VMLibraryMachine?
    @State private var showsNewMachinePrompt = false
    @State private var nameDraft = ""

    var body: some View {
        List {
            Section {
                ForEach(listedMachines) { machine in
                    machineRow(machine)
                }
                if let errorMessage = library.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { library.errorMessage = nil }
                }
            } header: {
                HStack {
                    Text("Virtual Machines")
                    Spacer()
                    if library.isWorking {
                        ProgressView().controlSize(.mini)
                    }
                    Menu {
                        Button("New Windows Machine…", systemImage: "plus") {
                            nameDraft = String(localized: "Windows 11 Arm")
                            showsNewMachinePrompt = true
                        }
                        Divider()
                        Button("Import Machine Bundle…", systemImage: "square.and.arrow.down") {
                            library.importBundle(then: machineDidChange)
                        }
                        Button("Import Disk Image…", systemImage: "externaldrive.badge.plus") {
                            library.importDisk(then: machineDidChange)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!canChangeMachines || library.isWorking)
                    .help("Add a Windows machine")
                }
            }

            Section {
                if !windowsInstalled {
                    Label("Available after Windows setup", systemImage: "info.circle")
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
        .onAppear { library.reload() }
        .onChange(of: snapshot?.profileName) { _, _ in library.reload() }
        .onChange(of: snapshot?.state) { _, _ in library.reload() }
        .alert("New Windows Machine", isPresented: $showsNewMachinePrompt) {
            TextField("Name", text: $nameDraft)
            Button("Create") {
                library.createMachine(named: nameDraft, then: machineDidChange)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Installation Assistant sets up Windows on the new machine.")
        }
        .alert("Rename Machine", isPresented: isPresented($renameTarget)) {
            TextField("Name", text: $nameDraft)
            Button("Rename") {
                if let target = renameTarget {
                    library.rename(target.id, to: nameDraft, then: machineDidChange)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Move this machine to the Trash?",
            isPresented: isPresented($deleteTarget),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Move to Trash", role: .destructive) {
                library.delete(target.id, then: machineDidChange)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("\(target.profile.name)'s disk, UEFI variables, TPM state, and saved session go to the Trash. The shared folder and installer files are kept.")
        }
    }

    /// The library's list, or the single machine the snapshot shows before the library has loaded.
    private var listedMachines: [VMLibraryMachine] {
        library.machines
    }

    @ViewBuilder
    private func machineRow(_ machine: VMLibraryMachine) -> some View {
        let isActive = machine.id == library.activeMachineID
        let canChangeThis = canChangeMachines && !library.isWorking
        Button {
            library.select(machine.id, then: machineDidChange)
        } label: {
            if isActive {
                MachineSidebarRow(snapshot: snapshot, status: status, liveThumbnail: liveThumbnail)
            } else {
                LibraryMachineRow(machine: machine, isSuspended: library.suspendedMachineIDs.contains(machine.id))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isActive && !canChangeThis)
        .listRowBackground(isActive ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.22)) : nil)
        .help(isActive || canChangeThis ? "" : "Shut down the running machine to switch")
        .contextMenu {
            if isActive {
                Button("Configure…", systemImage: "gearshape", action: configureAction)
                Divider()
            }
            Button("Rename…", systemImage: "pencil") {
                nameDraft = machine.profile.name
                renameTarget = machine
            }
            .disabled(library.isWorking)
            Button("Clone", systemImage: "plus.square.on.square") {
                library.clone(machine.id, then: machineDidChange)
            }
            .disabled(!canChangeThis)
            Button("Export…", systemImage: "square.and.arrow.up") {
                library.export(machine)
            }
            .disabled(!canChangeThis)
            Divider()
            Button("Move to Trash…", systemImage: "trash", role: .destructive) {
                deleteTarget = machine
            }
            .disabled(!canChangeThis)
        }
    }

    private func isPresented(_ target: Binding<VMLibraryMachine?>) -> Binding<Bool> {
        Binding(
            get: { target.wrappedValue != nil },
            set: { if !$0 { target.wrappedValue = nil } }
        )
    }
}

/// A machine other than the selected one: its name and whether it is set up or suspended.
private struct LibraryMachineRow: View {
    var machine: VMLibraryMachine
    var isSuspended: Bool

    var body: some View {
        HStack(spacing: 10) {
            MachineThumbnail(snapshot: nil, liveImage: nil)
                .frame(width: 64, height: 40)
                .opacity(0.8)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.profile.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Label(LocalizedStringKey(statusTitle), systemImage: statusSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        if isSuspended {
            return "Suspended"
        }
        return machine.profile.virtualDiskPath == nil ? "Not set up" : "Stopped"
    }

    private var statusSymbol: String {
        if isSuspended {
            return "pause.circle"
        }
        return machine.profile.virtualDiskPath == nil ? "sparkles" : "stop.circle"
    }
}

private struct MachineSidebarRow: View {
    var snapshot: VMRuntimeSnapshot?
    var status: MachineStatusPresentation
    var liveThumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            MachineThumbnail(snapshot: snapshot, liveImage: liveThumbnail)
                .frame(width: 64, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot?.profileName ?? "Windows 11")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Label(LocalizedStringKey(status.title), systemImage: status.symbolName)
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
    /// A recent live frame, preferred over the boot-time console capture while Windows runs.
    var liveImage: NSImage?

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
        if isLive, let liveImage {
            return liveImage
        }
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
