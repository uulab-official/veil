import Foundation

/// State behind the USB Devices menu: the Mac's devices, which ones Windows has, and the last failure.
@MainActor
@Observable
public final class USBPassthroughModel {
    public private(set) var snapshot: USBPassthroughSnapshot?
    /// Devices with an attach or detach in flight, so their toggles cannot be flipped twice.
    public private(set) var busyDeviceIds: Set<String> = []
    public private(set) var lastError: USBPassthroughError?

    private let service: any VMRuntimeService

    public init(service: any VMRuntimeService) {
        self.service = service
    }

    public func refresh() async {
        // A refresh that lands while a toggle is in flight would show the old state for that device.
        guard busyDeviceIds.isEmpty else {
            return
        }
        snapshot = await service.usbPassthroughSnapshot()
    }

    public func setAttached(_ attached: Bool, device: MacUSBDevice) async {
        let id = device.qemuDeviceId
        guard !busyDeviceIds.contains(id) else {
            return
        }

        busyDeviceIds.insert(id)
        lastError = nil
        do {
            snapshot = attached
                ? try await service.attachUSBDevice(device)
                : try await service.detachUSBDevice(id: id)
        } catch let error as USBPassthroughError {
            lastError = error
            snapshot = await service.usbPassthroughSnapshot()
        } catch {
            lastError = .qemuRefused(message: error.localizedDescription)
            snapshot = await service.usbPassthroughSnapshot()
        }
        busyDeviceIds.remove(id)
    }

    public func dismissError() {
        lastError = nil
    }
}
