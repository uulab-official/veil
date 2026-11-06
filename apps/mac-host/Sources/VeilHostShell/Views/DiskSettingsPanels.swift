import SwiftUI
import VeilHostCore

/// What the Disk tab allows in each Windows state. Size and format change only while Windows is
/// stopped; snapshots work while it runs (memory and disk) or is stopped (disk only).
struct DiskSettingsPolicy: Equatable {
    var canChangeDisk: Bool
    var canUseSnapshots: Bool
    var snapshotsIncludeMemory: Bool

    static func resolve(runtimeState: VMRuntimeState, isWorking: Bool) -> DiskSettingsPolicy {
        guard !isWorking else {
            return DiskSettingsPolicy(canChangeDisk: false, canUseSnapshots: false, snapshotsIncludeMemory: false)
        }

        switch runtimeState {
        case .running:
            return DiskSettingsPolicy(canChangeDisk: false, canUseSnapshots: true, snapshotsIncludeMemory: true)
        case .stopped, .failed, .notConfigured:
            return DiskSettingsPolicy(canChangeDisk: true, canUseSnapshots: true, snapshotsIncludeMemory: false)
        case .starting, .suspended, .unsupported:
            return DiskSettingsPolicy(canChangeDisk: false, canUseSnapshots: false, snapshotsIncludeMemory: false)
        }
    }

    /// Largest size offered, as UTM and Parallels cap their disk sliders well below APFS limits.
    static let maximumDiskGB = 2_048
}

/// The Disk tab: format, size, conversion to qcow2, and snapshots.
struct DiskSettingsView: View {
    var runtimeState: VMRuntimeState
    @State var model: VMDiskModel
    /// Called after the disk's size or file changes, so the rest of the window re-reads the profile.
    var diskDidChange: () -> Void

    private var policy: DiskSettingsPolicy {
        DiskSettingsPolicy.resolve(runtimeState: runtimeState, isWorking: model.isWorking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let status = model.status {
                DiskSizePanel(status: status, canChangeDisk: policy.canChangeDisk) { sizeGB in
                    Task {
                        await model.grow(toGB: sizeGB)
                        diskDidChange()
                    }
                }

                if status.format == .raw {
                    DiskConversionPanel(status: status, canChangeDisk: policy.canChangeDisk) {
                        Task {
                            await model.convertToQCOW2()
                            diskDidChange()
                        }
                    }
                } else {
                    SnapshotsPanel(status: status, policy: policy, model: model)
                }
            } else if model.isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(
                    "No Virtual Disk",
                    systemImage: "internaldrive",
                    description: Text("Create the Windows disk in Installation first.")
                )
            }

            if model.isWorking, model.status != nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working on the disk…")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: runtimeState) {
            await model.refresh()
        }
    }
}

private struct DiskSizePanel: View {
    var status: VMDiskStatus
    var canChangeDisk: Bool
    var growAction: (Int) -> Void

    @State private var requestedGB = 0

    private var currentGB: Int {
        Int((status.virtualSizeBytes ?? 0) / (1_024 * 1_024 * 1_024))
    }

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Virtual Disk",
                subtitle: "The Windows system disk on this Mac.",
                symbolName: "internaldrive"
            )

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ShellMetricRow(label: "Format", value: status.format.rawValue)
                ShellMetricRow(
                    label: "Size in Windows",
                    value: status.virtualSizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .binary) } ?? "—"
                )
                ShellMetricRow(
                    label: "Space Used on Mac",
                    value: status.allocatedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
                )
                ShellMetricRow(label: "Location", value: status.path, monospaced: true)
            }

            if status.isDiskToolAvailable, status.virtualSizeBytes != nil {
                Divider()
                HStack {
                    Stepper(value: $requestedGB, in: max(currentGB, 1)...DiskSettingsPolicy.maximumDiskGB, step: 16) {
                        Text("\(requestedGB) GB")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("New disk size")
                    .disabled(!canChangeDisk)
                    Spacer()
                    Button("Increase Size") {
                        growAction(requestedGB)
                    }
                    .disabled(!canChangeDisk || requestedGB <= currentGB)
                }
                Text("Shut down Windows to change the size. The disk can only grow; afterwards extend drive C: in Windows Disk Management.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !status.isDiskToolAvailable {
                Text("qemu-img is not available, so the disk size cannot be changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { requestedGB = currentGB }
        .onChange(of: status.virtualSizeBytes) { _, _ in requestedGB = currentGB }
    }
}

private struct DiskConversionPanel: View {
    var status: VMDiskStatus
    var canChangeDisk: Bool
    var convertAction: () -> Void

    @State private var confirmsConversion = false

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Snapshots",
                subtitle: "This disk is raw. Snapshots need a qcow2 disk.",
                symbolName: "camera.on.rectangle"
            )

            Text("Converting copies the disk into a qcow2 file next to it, which also takes less space as it only stores what Windows wrote. Veil switches to the copy and moves the raw file to the Trash.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let allocatedBytes = status.allocatedBytes {
                Text("Needs about \(ByteCountFormatter.string(fromByteCount: allocatedBytes, countStyle: .file)) of free space while converting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !canChangeDisk {
                    Text("Shut down Windows to convert the disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Convert to qcow2…") {
                    confirmsConversion = true
                }
                .disabled(!canChangeDisk || !status.isDiskToolAvailable)
            }
        }
        .confirmationDialog("Convert the Windows disk to qcow2?", isPresented: $confirmsConversion) {
            Button("Convert") {
                convertAction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can take several minutes. The raw disk goes to the Trash once the copy is in use; keep it there until Windows starts from the new disk.")
        }
    }
}

private struct SnapshotsPanel: View {
    var status: VMDiskStatus
    var policy: DiskSettingsPolicy
    var model: VMDiskModel

    @State private var newName = VMDiskModel.suggestedSnapshotName()
    @State private var pendingRestore: VMSnapshotSummary?
    @State private var pendingDelete: VMSnapshotSummary?

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Snapshots",
                subtitle: policy.snapshotsIncludeMemory
                    ? "Snapshots of a running Windows keep its open apps too."
                    : "Snapshots of a stopped Windows keep the disk only.",
                symbolName: "camera.on.rectangle"
            )

            if status.snapshots.isEmpty {
                Text("No snapshots yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(status.snapshots, id: \.id) { snapshot in
                        SnapshotRow(
                            snapshot: snapshot,
                            isEnabled: policy.canUseSnapshots,
                            restoreAction: { pendingRestore = snapshot },
                            deleteAction: { pendingDelete = snapshot }
                        )
                        if snapshot.id != status.snapshots.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if let listError = status.snapshotListError {
                Text(listError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            HStack {
                TextField("Snapshot name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button("Take Snapshot") {
                    let name = newName
                    Task {
                        await model.createSnapshot(named: name)
                        newName = VMDiskModel.suggestedSnapshotName()
                    }
                }
                .disabled(!policy.canUseSnapshots || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            Text("Use letters, numbers, dots, dashes, or underscores. Snapshots are not available while Windows starts or is suspended.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            "Restore this snapshot?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { snapshot in
            Button("Restore") {
                Task { await model.restoreSnapshot(named: snapshot.tag) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Windows returns to the moment of the snapshot. Changes since then are lost unless you take another snapshot first.")
        }
        .confirmationDialog(
            "Delete this snapshot?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { snapshot in
            Button("Delete", role: .destructive) {
                Task { await model.deleteSnapshot(named: snapshot.tag) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The snapshot is removed from the disk. Windows itself is not changed.")
        }
    }
}

private struct SnapshotRow: View {
    var snapshot: VMSnapshotSummary
    var isEnabled: Bool
    var restoreAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasMemoryState ? "camera.fill" : "internaldrive")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.tag)
                    .font(.body.weight(.medium))
                Text(snapshot.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(localized: hasMemoryState ? "With running Windows" : "Disk only")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Restore…", action: restoreAction)
                .disabled(!isEnabled)
            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete snapshot")
            .disabled(!isEnabled)
        }
        .padding(.vertical, 6)
    }

    private var hasMemoryState: Bool {
        !snapshot.vmStateSize.hasPrefix("0 ")
    }
}
