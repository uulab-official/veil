import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct DevicePlanPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Device Plan",
                subtitle: "The virtual hardware Windows starts with.",
                symbolName: "cpu"
            )

            if let deviceSummary = snapshot.deviceSummary {
                ResourcePlanRow(
                    title: "Boot",
                    value: "\(deviceSummary.platform), \(deviceSummary.bootLoader)",
                    symbolName: "power",
                    state: .ready
                )
                ResourcePlanRow(
                    title: "Storage",
                    value: storageValue(for: deviceSummary.storageDevices),
                    symbolName: "externaldrive.connected.to.line.below",
                    state: snapshot.virtualDiskPath == nil ? .blocked : .ready
                )
                ResourcePlanRow(
                    title: "Network",
                    value: deviceSummary.networkMode,
                    symbolName: "network",
                    state: .ready
                )
                ResourcePlanRow(
                    title: "Graphics",
                    value: "\(deviceSummary.graphics.widthInPixels) × \(deviceSummary.graphics.heightInPixels)",
                    symbolName: "display",
                    state: .ready
                )
                ResourcePlanRow(
                    title: "Input",
                    value: deviceSummary.inputDevices.joined(separator: ", "),
                    symbolName: "keyboard",
                    state: .ready
                )
            } else {
                ResourcePlanRow(
                    title: "Devices",
                    value: String(localized: "Shown once Windows is set up."),
                    symbolName: "rectangle.stack.badge.plus",
                    state: .blocked
                )
            }
        }
    }

    private func storageValue(for storageDevices: [VMRuntimeStorageDeviceSummary]) -> String {
        let readableDevices = storageDevices.map { device in
            "\(device.role): \(device.attachment)\(device.readOnly ? " read-only" : " writable")"
        }
        return readableDevices.joined(separator: "; ")
    }
}

struct ResourcePlanPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Resource Plan",
                subtitle: "The processors, memory, and storage Windows gets from this Mac.",
                symbolName: "gauge.with.dots.needle.50percent"
            )

            ResourcePlanRow(
                title: "CPU",
                value: cpuValue,
                symbolName: "cpu",
                state: snapshot.cpuCount == nil ? (snapshot.virtualizationAvailable ? .planned : .blocked) : .ready
            )
            ResourcePlanRow(
                title: "Memory",
                value: memoryValue,
                symbolName: "memorychip",
                state: snapshot.memoryMB == nil ? .planned : .ready
            )
            ResourcePlanRow(
                title: "Storage",
                value: storageValue,
                symbolName: "internaldrive",
                state: snapshot.virtualDiskPath == nil ? .blocked : .ready
            )
        }
    }

    private var cpuValue: String {
        guard snapshot.virtualizationAvailable else {
            return String(localized: "This Mac cannot run virtual machines.")
        }

        guard let cpuCount = snapshot.cpuCount else {
            return String(localized: "Chosen for this Mac when Veil prepares Windows.")
        }

        return String(localized: "\(cpuCount) cores")
    }

    private var memoryValue: String {
        guard let memoryMB = snapshot.memoryMB else {
            return String(localized: "Chosen for this Mac when Veil prepares Windows.")
        }

        return "\(formatGigabytes(memoryMB)) GB"
    }

    private var storageValue: String {
        guard let diskGB = snapshot.diskGB else {
            return String(localized: "Chosen for this Mac when Veil prepares Windows.")
        }

        if snapshot.virtualDiskPath == nil {
            return String(localized: "\(diskGB) GB. Create the disk in Installation before starting Windows.")
        }

        // A sparse file: it takes up on the Mac only what Windows has written.
        return String(localized: "\(diskGB) GB, using Mac storage only as Windows fills it")
    }

    private func formatGigabytes(_ memoryMB: Int) -> String {
        let gigabytes = Double(memoryMB) / 1_024
        if gigabytes.rounded() == gigabytes {
            return String(Int(gigabytes))
        }

        return String(format: "%.1f", gigabytes)
    }
}

struct SetupAssistantPanel: View {
    var snapshot: VMRuntimeSnapshot
    var createProfileAction: () -> Void
    var prepareAction: () -> Void
    var selectInstallerAction: () -> Void
    var selectDiskAction: () -> Void
    var createDiskAction: () -> Void
    var isLoading: Bool
    var canChangeResources: Bool

    private var items: [SetupItem] {
        [
            SetupItem(
                title: "VM Profile",
                detail: snapshot.profileName ?? "Create a default Windows 11 Arm profile.",
                symbolName: "rectangle.stack.badge.person.crop",
                isComplete: snapshot.profileName != nil
            ),
            SetupItem(
                title: "Installer Media",
                detail: installerMediaDetail,
                symbolName: "opticaldisc",
                isComplete: snapshot.windowsInstalled || snapshot.installerMediaPath != nil
            ),
            SetupItem(
                title: "Virtual Disk",
                detail: snapshot.virtualDiskPath ?? "Select or create the virtual disk path.",
                symbolName: "externaldrive",
                isComplete: snapshot.virtualDiskPath != nil
            ),
            SetupItem(
                title: "Preflight",
                detail: snapshot.bootReady ? "All local checks are passing." : snapshot.detail,
                symbolName: "checklist",
                isComplete: snapshot.bootReady
            )
        ]
    }

    private var completedCount: Int {
        items.filter(\.isComplete).count
    }

    private var installerMediaDetail: String {
        if snapshot.windowsInstalled {
            return "Windows is installed; installer media is no longer required."
        }

        if let path = snapshot.installerMediaPath {
            return path
        }

        return "Choose a Windows 11 Arm ISO. Veil will not scan Downloads automatically."
    }

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Install Assistant",
                subtitle: "The steps that get Windows 11 ready to start.",
                symbolName: "wand.and.stars"
            )

            SetupProgressBar(completed: completedCount, total: items.count)

            ForEach(items) { item in
                SetupItemRow(item: item)
            }

            HStack(spacing: 8) {
                if snapshot.profileName == nil {
                    Button(action: prepareAction) {
                        Label("Prepare", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || !canChangeResources)

                    Button(action: createProfileAction) {
                        Label("Profile Only", systemImage: "plus.circle")
                    }
                    .disabled(isLoading || !canChangeResources)
                }

                if !snapshot.windowsInstalled {
                    Button(action: selectInstallerAction) {
                        Label("Installer", systemImage: "opticaldisc")
                    }
                    .disabled(snapshot.profileName == nil || isLoading || !canChangeResources)
                }

                Button(action: selectDiskAction) {
                    Label("Disk", systemImage: "externaldrive")
                }
                .disabled(snapshot.profileName == nil || isLoading || !canChangeResources)

                if snapshot.profileName != nil && snapshot.virtualDiskPath == nil {
                    Button(action: createDiskAction) {
                        Label("Create Disk", systemImage: "internaldrive")
                    }
                    .disabled(isLoading || !canChangeResources)
                }

                Spacer()
            }
        }
    }
}

struct MachineSummaryPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            HStack(alignment: .center) {
                ShellPanelHeader(
                    title: "Machine Summary",
                    subtitle: "This Windows and what it uses on this Mac.",
                    symbolName: "rectangle.stack"
                )

                Spacer()

                StatusPill(
                    title: snapshot.profileName == nil ? "New" : "Managed",
                    symbolName: snapshot.profileName == nil ? "plus.circle" : "checkmark.circle.fill",
                    tint: snapshot.profileName == nil ? .secondary : .green
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ShellMetricRow(label: "Machine", value: "Windows 11 Arm")
                ShellMetricRow(label: "Profile", value: snapshot.profileName ?? String(localized: "Not configured"))
                ShellMetricRow(label: "CPU", value: snapshot.cpuCount.map { String(localized: "\($0) cores") } ?? String(localized: "Automatic"))
                ShellMetricRow(label: "Memory", value: snapshot.memoryMB.map { "\(formatGigabytes($0)) GB" } ?? String(localized: "Automatic"))
                ShellMetricRow(label: "Disk Size", value: snapshot.diskGB.map { "\($0) GB" } ?? String(localized: "Automatic"))
                ShellMetricRow(label: "Installer", value: installerResourceName, monospaced: snapshot.installerMediaPath != nil)
                ShellMetricRow(label: "Disk", value: resourceName(from: snapshot.virtualDiskPath), monospaced: snapshot.virtualDiskPath != nil)
                ShellMetricRow(label: "Runtime", value: snapshot.detail)
            }
        }
    }

    private func resourceName(from path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "Not selected"
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var installerResourceName: String {
        if snapshot.windowsInstalled {
            return "Not required after install"
        }

        if let selected = snapshot.installerMediaPath {
            return resourceName(from: selected)
        }

        return "Not selected"
    }

    private func formatGigabytes(_ memoryMB: Int) -> String {
        let gigabytes = Double(memoryMB) / 1_024
        if gigabytes.rounded() == gigabytes {
            return String(Int(gigabytes))
        }

        return String(format: "%.1f", gigabytes)
    }
}

struct RuntimeProvidersPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Runtime Providers",
                subtitle: "The engines on this Mac that can run Windows.",
                symbolName: "bolt.horizontal"
            )

            if snapshot.runtimeProviders.isEmpty {
                ResourcePlanRow(
                    title: "Providers",
                    value: String(localized: "No engine information yet."),
                    symbolName: "questionmark.circle",
                    state: .planned
                )
            } else {
                ForEach(snapshot.runtimeProviders, id: \.kind) { provider in
                    ResourcePlanRow(
                        title: provider.displayName,
                        value: providerDetail(provider),
                        symbolName: symbolName(for: provider),
                        state: state(for: provider)
                    )
                }
            }
        }
    }

    private func providerDetail(_ provider: VMRuntimeProviderSummary) -> String {
        if let executableVersion = provider.executableVersion {
            return "\(provider.mode), \(provider.acceleration), \(executableVersion)"
        }

        if let executablePath = provider.executablePath {
            return "\(provider.mode), \(provider.acceleration), \(URL(fileURLWithPath: executablePath).lastPathComponent)"
        }

        return "\(provider.mode), \(provider.acceleration)"
    }

    private func symbolName(for provider: VMRuntimeProviderSummary) -> String {
        switch provider.kind {
        case .appleVirtualization:
            "apple.logo"
        case .qemuHypervisor:
            "shippingbox"
        }
    }

    private func state(for provider: VMRuntimeProviderSummary) -> IntegrationState {
        switch provider.status {
        case .active:
            .ready
        case .planned:
            .planned
        case .unavailable:
            .blocked
        }
    }
}

struct MacIntegrationPanel: View {
    var snapshot: VMRuntimeSnapshot

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Mac Integration",
                subtitle: "How Windows apps work with this Mac.",
                symbolName: "macwindow"
            )

            ForEach(MacIntegrationFeature.features(windowsInstalled: snapshot.installEvidence.isInstalled)) { feature in
                IntegrationStatusRow(
                    title: feature.title,
                    detail: feature.detail,
                    symbolName: feature.symbolName,
                    state: feature.state
                )
            }
        }
    }
}

/// What Veil does between Windows apps and the Mac, as the Integration settings describe it. Only what
/// works today is listed; all of it needs Windows installed, with the Veil tools setup puts in it.
struct MacIntegrationFeature: Identifiable, Equatable {
    var id: String
    /// Localization keys.
    var title: String
    var detail: String
    var symbolName: String
    var state: IntegrationState

    static func features(windowsInstalled: Bool) -> [MacIntegrationFeature] {
        func feature(_ id: String, _ title: String, _ detail: String, _ symbolName: String) -> MacIntegrationFeature {
            MacIntegrationFeature(
                id: id,
                title: title,
                detail: windowsInstalled ? detail : "Available after Windows is installed.",
                symbolName: symbolName,
                state: windowsInstalled ? .ready : .blocked
            )
        }
        return [
            feature("apps", "Windows Apps on Mac", "Each Windows app opens in its own Mac window.", "macwindow.on.rectangle"),
            feature("clipboard", "Clipboard", "Copy on one side and paste on the other.", "doc.on.clipboard"),
            feature("folders", "Shared Folders", "Windows shows the Mac folder you share as a drive.", "folder")
        ]
    }
}

struct SetupItem: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbolName: String
    var isComplete: Bool
}

struct SetupItemRow: View {
    var item: SetupItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? .green : .secondary)
                .frame(width: 22)

            Image(systemName: item.symbolName)
                .foregroundStyle(item.isComplete ? .green : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(localized: item.title)
                    .font(.callout.weight(.semibold))
                Text(localized: item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}

enum PathPicker: Identifiable {
    case installerMedia
    case installerAndStart
    case driverMedia
    case virtualDisk

    var id: String {
        switch self {
        case .installerMedia:
            "installerMedia"
        case .installerAndStart:
            "installerAndStart"
        case .driverMedia:
            "driverMedia"
        case .virtualDisk:
            "virtualDisk"
        }
    }
}

struct PreflightCheckRow: View {
    var check: VMPreflightCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(localized: check.title)
                Text(localized: check.detail)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .font(.callout)
    }

    private var symbolName: String {
        switch check.state {
        case .passed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle"
        }
    }

    private var symbolColor: Color {
        switch check.state {
        case .passed:
            .green
        case .failed:
            .red
        }
    }
}
