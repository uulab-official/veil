import SwiftUI
import VeilHostCore

/// UTM-style USB menu: every USB device on this Mac with a switch that hands it to the running
/// Windows or gives it back. Devices return to the Mac on their own when Windows stops or suspends.
struct USBDevicesPanel: View {
    @State private var usb: USBPassthroughModel
    /// A device whose attach waits for the user to accept that the Mac loses it meanwhile.
    @State private var pendingRiskyDevice: MacUSBDevice?

    init(service: any VMRuntimeService) {
        _usb = State(initialValue: USBPassthroughModel(service: service))
    }

    var body: some View {
        ShellPanel(spacing: 12) {
            HStack(alignment: .top) {
                ShellPanelHeader(
                    title: "USB Devices",
                    subtitle: "Connect a USB device on this Mac to the running Windows.",
                    symbolName: "cable.connector"
                )
                Spacer()
                Button("Refresh") {
                    Task { await usb.refresh() }
                }
            }

            if let error = usb.lastError {
                errorBanner(error)
            }

            if let snapshot = usb.snapshot {
                if !snapshot.isVMRunning {
                    Label("Start Windows to connect USB devices.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if snapshot.macDevices.isEmpty {
                    Text("No USB devices are connected to this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.macDevices) { device in
                            deviceRow(device, snapshot: snapshot)
                            if device.id != snapshot.macDevices.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text("Devices macOS already has a driver for, such as keyboards, mice, disks, and most audio devices, can only be taken from macOS with Apple's USB device capture entitlement, which this build of Veil does not have. Devices without a macOS driver, such as many development boards and dongles, connect directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // The registry changes when something is plugged in, and Windows can drop a device on its
            // own, so the list stays live while the panel is visible.
            while !Task.isCancelled {
                await usb.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .confirmationDialog(
            Text(localized: pendingRiskyDevice.map(riskTitle) ?? ""),
            isPresented: Binding(
                get: { pendingRiskyDevice != nil },
                set: { if !$0 { pendingRiskyDevice = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRiskyDevice
        ) { device in
            Button("Connect to Windows") {
                Task { await usb.setAttached(true, device: device) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text(localized: riskMessage(device.risk))
        }
    }

    private func deviceRow(_ device: MacUSBDevice, snapshot: USBPassthroughSnapshot) -> some View {
        let isAttached = snapshot.isAttached(device)
        let isBusy = usb.busyDeviceIds.contains(device.qemuDeviceId)

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbolName(for: device.risk))
                .font(.system(size: 16))
                .foregroundStyle(isAttached ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.body.weight(.medium))
                Text(detailLine(for: device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if device.isClaimedByMacDriver, !isAttached {
                    Text("In use by macOS")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(isAttached ? "Connected to Windows" : "On this Mac")
                    .font(.caption)
                    .foregroundStyle(isAttached ? Color.accentColor : .secondary)
            }

            Toggle("Connect to Windows", isOn: Binding(
                get: { isAttached },
                set: { attach in
                    if attach, device.risk != .none {
                        pendingRiskyDevice = device
                    } else {
                        Task { await usb.setAttached(attach, device: device) }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!snapshot.isVMRunning || isBusy)
        }
        .padding(.vertical, 8)
    }

    private func detailLine(for device: MacUSBDevice) -> String {
        let ids = String(format: "%04X:%04X", device.vendorId, device.productId)
        if let vendor = device.vendorName {
            return "\(vendor) · \(ids)"
        }
        return ids
    }

    private func symbolName(for risk: MacUSBDeviceRisk) -> String {
        switch risk {
        case .inputDevice: "keyboard"
        case .storage: "externaldrive"
        case .none: "cable.connector"
        }
    }

    private func riskTitle(_ device: MacUSBDevice) -> String {
        switch device.risk {
        case .inputDevice: "Connect this input device to Windows?"
        case .storage: "Connect this disk to Windows?"
        case .none: "Connect to Windows?"
        }
    }

    private func riskMessage(_ risk: MacUSBDeviceRisk) -> String {
        switch risk {
        case .inputDevice:
            "While Windows uses it, this Mac stops receiving its input. Keep another keyboard and mouse connected to the Mac."
        case .storage:
            "Its volumes disappear from this Mac while Windows uses it. Eject the disk in Finder first so no data is lost."
        case .none:
            "The Mac cannot use this device while Windows has it."
        }
    }

    @ViewBuilder
    private func errorBanner(_ error: USBPassthroughError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            errorText(error)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Close") {
                usb.dismissError()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorText(_ error: USBPassthroughError) -> Text {
        switch error {
        case .vmNotRunning:
            Text("Start Windows before connecting a USB device.")
        case .deviceNotFound:
            Text("The USB device is no longer connected to this Mac.")
        case .macDriverHoldsDevice(let name):
            Text("macOS is using \(name), and Veil cannot take it from macOS without Apple's USB device capture entitlement.")
        case .deviceNotClaimed(let name):
            Text("QEMU could not open \(name). Unplug it, plug it back in, and try again.")
        case .qemuRefused(let message):
            Text("QEMU refused the USB device: \(message)")
        }
    }
}
