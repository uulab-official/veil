import Foundation

extension LocalVMRuntimeService {
    public func usbPassthroughSnapshot() async -> USBPassthroughSnapshot {
        let macDevices = MacUSBDeviceList.currentDevices()
        guard let qmpSocketPath = await runningQMPSocketPath() else {
            return USBPassthroughSnapshot(isVMRunning: false, macDevices: macDevices)
        }

        do {
            return try await QEMUUSBPassthroughController().snapshot(macDevices: macDevices, qmpSocketPath: qmpSocketPath)
        } catch {
            // A QMP hiccup must not show every device as detached while Windows still has them, so the
            // menu says the VM cannot be asked rather than guessing.
            VeilLog.runtime.error("Failed to read USB passthrough state: \(String(describing: error))")
            return USBPassthroughSnapshot(isVMRunning: false, macDevices: macDevices)
        }
    }

    public func attachUSBDevice(_ device: MacUSBDevice) async throws -> USBPassthroughSnapshot {
        guard let qmpSocketPath = await runningQMPSocketPath() else {
            throw USBPassthroughError.vmNotRunning
        }
        // Re-read the registry: the menu's list can be minutes old, and a re-plugged device has a new
        // address that QEMU would otherwise wait on forever.
        guard let current = MacUSBDeviceList.currentDevices().first(where: { $0.qemuDeviceId == device.qemuDeviceId }) else {
            throw USBPassthroughError.deviceNotFound
        }

        try await QEMUUSBPassthroughController().attach(current, qmpSocketPath: qmpSocketPath)
        VeilLog.runtime.notice("Attached USB device \(current.qemuDeviceId, privacy: .public) to Windows.")
        return await usbPassthroughSnapshot()
    }

    public func detachUSBDevice(id: String) async throws -> USBPassthroughSnapshot {
        guard let qmpSocketPath = await runningQMPSocketPath() else {
            throw USBPassthroughError.vmNotRunning
        }

        try await QEMUUSBPassthroughController().detach(deviceId: id, qmpSocketPath: qmpSocketPath)
        VeilLog.runtime.notice("Returned USB device \(id, privacy: .public) to the Mac.")
        return await usbPassthroughSnapshot()
    }

    /// Returns every passed-through device to the Mac before the VM stops or suspends. A suspended
    /// session that still contains a `usb-host` device could not be resumed, because the next boot
    /// plan does not create that device and QEMU refuses an incoming state with an unknown device.
    func detachUSBDevicesBeforeShutdown(launchRecord: QEMULaunchRecord?) async {
        guard let qmpSocketPath = Self.liveQMPSocketPath(launchRecord, processIsRunning: qemuLaunchProcessIsRunning) else {
            return
        }

        let removed = await QEMUUSBPassthroughController().detachAll(qmpSocketPath: qmpSocketPath)
        if !removed.isEmpty {
            VeilLog.runtime.notice("Returned \(removed.count, privacy: .public) USB device(s) to the Mac before shutdown.")
        }
    }

    func runningQMPSocketPath() async -> String? {
        let launchRecord: QEMULaunchRecord?
        do {
            launchRecord = try await qemuLaunchRecordStore.loadLatest()
        } catch {
            VeilLog.runtime.error("Failed to load the QEMU launch record for USB passthrough: \(String(describing: error))")
            return nil
        }
        return Self.liveQMPSocketPath(launchRecord, processIsRunning: qemuLaunchProcessIsRunning)
    }

    static func liveQMPSocketPath(
        _ launchRecord: QEMULaunchRecord?,
        processIsRunning: (Int32) -> Bool
    ) -> String? {
        guard let launchRecord,
              let pid = launchRecord.pid,
              processIsRunning(pid),
              let path = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }
}
