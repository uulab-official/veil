import Foundation

/// Why a Mac USB device could not be handed to Windows. Each case names a different fix, so the UI
/// shows a different explanation for each instead of one generic failure.
public enum USBPassthroughError: Error, LocalizedError, Equatable, Sendable {
    /// USB devices attach to a running QEMU only; there is no saved list to apply at the next start.
    case vmNotRunning
    /// The device is gone from the Mac, or its USB address changed after a re-plug.
    case deviceNotFound
    /// A macOS driver owns the device, and taking it away needs `com.apple.vm.device-access` or root.
    /// QEMU kept the request pending without claiming the device, so Veil removed it again.
    case macDriverHoldsDevice(name: String)
    /// No macOS driver was seen, yet QEMU still could not open the device.
    case deviceNotClaimed(name: String)
    case qemuRefused(message: String)

    public var errorDescription: String? {
        switch self {
        case .vmNotRunning:
            "Start Windows before connecting a USB device."
        case .deviceNotFound:
            "The USB device is no longer connected to this Mac."
        case .macDriverHoldsDevice(let name):
            "macOS is using \(name), and Veil cannot take it from macOS without Apple's USB device capture entitlement."
        case .deviceNotClaimed(let name):
            "QEMU could not open \(name). Unplug it, plug it back in, and try again."
        case .qemuRefused(let message):
            "QEMU refused the USB device: \(message)"
        }
    }
}

/// What the USB menu shows: the Mac's devices and which of them Windows currently has.
public struct USBPassthroughSnapshot: Equatable, Sendable {
    public var isVMRunning: Bool
    public var macDevices: [MacUSBDevice]
    /// QEMU device ids of the devices Windows has. Compare with ``MacUSBDevice/qemuDeviceId``.
    public var attachedDeviceIds: Set<String>

    public init(isVMRunning: Bool, macDevices: [MacUSBDevice], attachedDeviceIds: Set<String> = []) {
        self.isVMRunning = isVMRunning
        self.macDevices = macDevices
        self.attachedDeviceIds = attachedDeviceIds
    }

    public func isAttached(_ device: MacUSBDevice) -> Bool {
        attachedDeviceIds.contains(device.qemuDeviceId)
    }
}

public enum QEMUUSBPassthrough {
    /// Every device Veil adds carries this prefix, so Veil only ever removes devices it added and never
    /// the keyboard, tablet, network adapter, or install media the boot plan created.
    public static let deviceIdPrefix = "veil-usb-"
    /// The bus of the `qemu-xhci` controller in ``QEMUWindowsBootPlan/usbControllerArgument``.
    public static let busName = "usb0.0"

    /// Device ids Veil added, read from HMP `info usb`, whose lines end in `ID: <id>` for devices that
    /// were given one. A `usb-host` that has not claimed its device is listed too.
    public static func veilDeviceIds(fromInfoUSB output: String) -> [String] {
        output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let range = line.range(of: "ID: ", options: .backwards) else {
                    return nil
                }
                let id = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return id.hasPrefix(deviceIdPrefix) ? id : nil
            }
    }

    public static func attachCommand(for device: MacUSBDevice) -> QEMUQMPCommand {
        .addUSBHostDevice(
            id: device.qemuDeviceId,
            bus: busName,
            hostBus: device.busNumber,
            hostAddress: device.address,
            vendorId: device.vendorId,
            productId: device.productId
        )
    }
}

/// Attaches and detaches Mac USB devices on a running QEMU over QMP.
public struct QEMUUSBPassthroughController: Sendable {
    private let qmp: any QEMUQMPControlling
    private let pause: @Sendable (Duration) async -> Void
    /// How many times to ask whether QEMU claimed the device. libusb opens the device synchronously
    /// inside `device_add`, so the first answer is normally final; the retries cover a slow re-enumeration.
    private let attachConfirmationAttempts: Int

    public init(
        qmp: any QEMUQMPControlling = QEMUQMPClient(),
        attachConfirmationAttempts: Int = 3,
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.qmp = qmp
        self.attachConfirmationAttempts = max(1, attachConfirmationAttempts)
        self.pause = pause
    }

    /// Ids of the devices Veil added to this VM.
    public func addedDeviceIds(qmpSocketPath: String) async throws -> [String] {
        let reply = try await qmp.run(.humanMonitor("info usb"), socketPath: qmpSocketPath)
        return QEMUUSBPassthrough.veilDeviceIds(fromInfoUSB: reply.textReturn ?? "")
    }

    /// Hands the device to Windows and confirms QEMU really claimed it.
    ///
    /// `device_add usb-host` succeeds even when libusb cannot open the device: QEMU then keeps the
    /// device pending and retries in the background, which Windows sees as nothing at all. Veil asks
    /// QEMU's `attached` property instead, and removes the pending device when it never attaches so a
    /// failed attempt leaves no half-state behind.
    public func attach(_ device: MacUSBDevice, qmpSocketPath: String) async throws {
        do {
            try await qmp.run(QEMUUSBPassthrough.attachCommand(for: device), socketPath: qmpSocketPath)
        } catch QEMUQMPClientError.commandFailed(_, let message) {
            throw USBPassthroughError.qemuRefused(message: message)
        }

        for attempt in 1...attachConfirmationAttempts {
            let reply = try? await qmp.run(.queryUSBDeviceAttached(id: device.qemuDeviceId), socketPath: qmpSocketPath)
            if reply?.boolReturn == true {
                return
            }
            if attempt < attachConfirmationAttempts {
                await pause(.milliseconds(500))
            }
        }

        _ = try? await qmp.run(.deleteDevice(id: device.qemuDeviceId), socketPath: qmpSocketPath)
        throw device.isClaimedByMacDriver
            ? USBPassthroughError.macDriverHoldsDevice(name: device.displayName)
            : USBPassthroughError.deviceNotClaimed(name: device.displayName)
    }

    /// Gives the device back to the Mac. Only ids Veil created are accepted.
    public func detach(deviceId: String, qmpSocketPath: String) async throws {
        guard deviceId.hasPrefix(QEMUUSBPassthrough.deviceIdPrefix) else {
            throw USBPassthroughError.deviceNotFound
        }
        do {
            try await qmp.run(.deleteDevice(id: deviceId), socketPath: qmpSocketPath)
        } catch QEMUQMPClientError.commandFailed(_, let message) {
            throw USBPassthroughError.qemuRefused(message: message)
        }
    }

    /// Gives every Veil-added device back to the Mac. Used before stop and suspend: a saved session
    /// must not contain a device the next boot does not create, and Windows should see an orderly
    /// removal rather than a vanished controller port. Returns the ids it removed.
    @discardableResult
    public func detachAll(qmpSocketPath: String) async -> [String] {
        guard let ids = try? await addedDeviceIds(qmpSocketPath: qmpSocketPath), !ids.isEmpty else {
            return []
        }
        var removed: [String] = []
        for id in ids {
            if (try? await detach(deviceId: id, qmpSocketPath: qmpSocketPath)) != nil {
                removed.append(id)
            }
        }
        return removed
    }

    /// The menu's view of the VM. Added devices whose Mac device is gone (unplugged, or re-enumerated
    /// at a new address) are removed: their `usb-host` would otherwise wait forever for an address
    /// that will not come back.
    public func snapshot(macDevices: [MacUSBDevice], qmpSocketPath: String) async throws -> USBPassthroughSnapshot {
        let added = try await addedDeviceIds(qmpSocketPath: qmpSocketPath)
        let present = Set(macDevices.map(\.qemuDeviceId))
        for staleId in added where !present.contains(staleId) {
            _ = try? await detach(deviceId: staleId, qmpSocketPath: qmpSocketPath)
        }
        return USBPassthroughSnapshot(
            isVMRunning: true,
            macDevices: macDevices,
            attachedDeviceIds: Set(added).intersection(present)
        )
    }
}
