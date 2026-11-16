import AppKit
import SwiftUI
import VeilHostCore

/// File > New Virtual Machine…: opens the window that creates and boots non-Windows guests.
struct NewGuestVMCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Virtual Machine…") {
                openWindow(id: NewGuestVMView.windowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
    }
}

/// Creates a Linux Arm64 or emulated x86_64 VM from an installer ISO and boots it in QEMU's own
/// window, the way UTM runs a generic VM. Windows keeps its own setup flow; this window never
/// touches the Windows profile.
struct NewGuestVMView: View {
    static let windowID = "new-guest-vm"
    private static let creatableKinds: [VMGuestOS] = [.linuxArm64, .x86_64]

    private let store = GuestVMStore()
    @State private var guestOS: VMGuestOS = .linuxArm64
    @State private var name = VMGuestOS.linuxArm64.displayName
    @State private var installerPath = ""
    @State private var tpm = false
    @State private var secureBoot = false
    @State private var guests: [GuestVM] = []
    @State private var status: Status?

    private enum Status {
        case started(name: String, pid: Int32)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Picker("Operating System", selection: $guestOS) {
                    ForEach(Self.creatableKinds, id: \.self) { kind in
                        Text(localized: kind.displayName).tag(kind)
                    }
                }
                TextField("Name", text: $name)
                HStack {
                    TextField("Installer ISO", text: $installerPath)
                    Button("Choose…", action: chooseInstaller)
                }
                Toggle("TPM 2.0", isOn: $tpm)
                Toggle("Secure Boot", isOn: $secureBoot)
                    .disabled(guestOS != .linuxArm64)
                if guestOS == .x86_64 {
                    Label("x86_64 runs under emulation and is much slower than an Arm guest.", systemImage: "tortoise")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: guestOS) { oldValue, newValue in
                if name.isEmpty || name == oldValue.displayName {
                    name = newValue.displayName
                }
                if newValue != .linuxArm64 {
                    secureBoot = false
                }
            }

            HStack {
                Group {
                    switch status {
                    case .started(let name, let pid):
                        Text("Started \(name) (QEMU PID \(pid)).")
                    case .failed(let detail):
                        Text(detail)
                    case nil:
                        EmptyView()
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                Spacer()
                Button("Create and Start", action: createAndStart)
                    .keyboardShortcut(.defaultAction)
                    .disabled(installerPath.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !guests.isEmpty {
                Divider()
                Text("Other Virtual Machines")
                    .font(.headline)
                List(guests) { guest in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(guest.profile.name)
                            Text(localized: guest.profile.guestOS.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Start") { start(guest) }
                    }
                }
                .frame(minHeight: 120)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
        .onAppear(perform: reload)
    }

    private func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "iso") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            installerPath = url.path
        }
    }

    private func createAndStart() {
        let guest = store.makeGuest(
            guestOS,
            name: name.trimmingCharacters(in: .whitespaces),
            installerMediaPath: installerPath,
            options: QEMUGuestBootOptions(tpm: tpm, secureBoot: secureBoot)
        )
        do {
            try store.save(guest)
            reload()
            start(guest)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func start(_ guest: GuestVM) {
        do {
            let plan = try LocalQEMUGuestBootPlanFactory.makePlan(for: guest.profile, options: guest.options)
            let record = try GuestVMLauncher.launch(guest, plan: plan)
            status = .started(name: guest.profile.name, pid: record.pid)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func reload() {
        guests = store.list()
    }
}
