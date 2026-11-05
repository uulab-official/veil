import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore

/// The removable CD drive of a running Windows, like the CD/DVD menu of a UTM or Parallels VM.
struct RemovableMediaPanel: View {
    var snapshot: VMRuntimeSnapshot
    var status: VMRemovableMediaStatus?
    var refreshAction: () async -> Void
    var insertAction: (String) async -> String?
    var ejectAction: () async -> String?

    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "CD/DVD",
                subtitle: "Insert or eject an ISO while Windows runs.",
                symbolName: "opticaldisc"
            )

            HStack(spacing: 10) {
                Image(systemName: status?.insertedPath == nil ? "circle.dashed" : "opticaldisc.fill")
                    .foregroundStyle(.secondary)
                Text(localized: mediaTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status?.insertedPath ?? "")
                Spacer()
                Button("Choose ISO…", action: chooseISO)
                    .disabled(!canUseDrive || isWorking)
                Button("Eject") {
                    run { await ejectAction() }
                }
                .disabled(!canUseDrive || isWorking || status?.insertedPath == nil)
            }

            if let reason = status?.unavailableReason, isRunning {
                Text(localized: reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isRunning {
                Text("Start Windows to insert a disc. The drive starts empty each time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task(id: snapshot.state) {
            if isRunning {
                await refreshAction()
            }
        }
    }

    private var isRunning: Bool { snapshot.state == .running }
    private var canUseDrive: Bool { isRunning && status?.isDriveAvailable == true }

    private var mediaTitle: String {
        guard isRunning, let status, status.isDriveAvailable else {
            return "No drive"
        }
        guard let path = status.insertedPath else {
            return "No disc"
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseISO() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .diskImage]
        panel.prompt = String(localized: "Insert")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        run { await insertAction(url.path) }
    }

    private func run(_ operation: @escaping () async -> String?) {
        isWorking = true
        errorMessage = nil
        Task {
            errorMessage = await operation()
            isWorking = false
        }
    }
}

/// Port forwards on the guest's NAT network, like UTM's Port Forward list. Rules wait for Save and
/// reach QEMU at the next start; the host side listens only on this Mac unless a rule says otherwise.
struct PortForwardingPanel: View {
    var snapshot: VMRuntimeSnapshot
    var saveAction: ([VMPortForwardRule]) async -> String?

    @State private var rules: [VMPortForwardRule] = []
    @State private var errorMessage: String?

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Port Forwarding",
                subtitle: "Reach a port in Windows from a port on this Mac. Applies the next time Windows starts.",
                symbolName: "point.3.connected.trianglepath.dotted"
            )

            if rules.isEmpty {
                Text("No rules. Veil's own connection to Windows is always forwarded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Protocol")
                        Text("Listen On")
                        Text("Mac Port")
                        Text("Windows Port")
                        Text("")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach($rules) { $rule in
                        GridRow {
                            Picker("Protocol", selection: $rule.transport) {
                                Text("TCP").tag(VMPortForwardProtocol.tcp)
                                Text("UDP").tag(VMPortForwardProtocol.udp)
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            Picker("Listen On", selection: $rule.hostBinding) {
                                Text("This Mac only").tag(VMPortForwardHostBinding.loopback)
                                Text("All networks").tag(VMPortForwardHostBinding.allInterfaces)
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            TextField("Mac Port", value: $rule.hostPort, format: .number.grouping(.never))
                                .frame(width: 80)
                            TextField("Windows Port", value: $rule.guestPort, format: .number.grouping(.never))
                                .frame(width: 80)
                            Button {
                                rules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove Rule")
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            }

            if rules.contains(where: { $0.hostBinding == .allInterfaces }) {
                Label(
                    "A rule on all networks lets other devices on your network reach that Windows port. Use it only for services you trust on that network.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Add Rule", systemImage: "plus") {
                    rules.append(VMPortForwardRule(hostPort: nextFreeHostPort, guestPort: 80))
                }
                .disabled(rules.count >= VMPortForwardRuleValidator.maximumRuleCount)
                Spacer()
                Button("Revert", action: loadFromSnapshot)
                    .disabled(!isChanged)
                Button("Save") {
                    Task {
                        errorMessage = await saveAction(rules)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isChanged)
            }
        }
        .onAppear(perform: loadFromSnapshot)
        .onChange(of: snapshot.portForwards) { _, _ in loadFromSnapshot() }
    }

    private var isChanged: Bool { rules != (snapshot.portForwards ?? []) }

    private var nextFreeHostPort: Int {
        let used = Set(rules.map(\.hostPort))
        return (8_080...65_535).first { !used.contains($0) } ?? 8_080
    }

    private func loadFromSnapshot() {
        rules = snapshot.portForwards ?? []
        errorMessage = nil
    }
}

/// What the Command key does in the Windows desktop, like UTM's modifier key options.
struct KeyboardMappingPanel: View {
    var snapshot: VMRuntimeSnapshot
    var applyAction: (VMCommandKeyMapping) -> Void

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Keyboard",
                subtitle: "How Mac modifier keys reach the Windows desktop.",
                symbolName: "keyboard"
            )

            Picker("Command key", selection: Binding(
                get: { snapshot.commandKeyMapping ?? .default },
                set: applyAction
            )) {
                Text("Control (Command-C copies)").tag(VMCommandKeyMapping.control)
                Text("Windows key (Command-E opens File Explorer)").tag(VMCommandKeyMapping.windows)
            }
            .pickerStyle(.radioGroup)

            Text("Control is always Control and Option is Alt. Windows app windows on the Mac always use Command as Control.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
