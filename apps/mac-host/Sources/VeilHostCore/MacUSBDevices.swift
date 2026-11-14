import Foundation
import IOKit

/// What handing a Mac USB device to Windows costs the Mac, so the UI can warn before it happens.
public enum MacUSBDeviceRisk: String, Codable, Equatable, Sendable {
    case none
    /// A keyboard, mouse, or other HID device. While Windows owns it, the Mac stops receiving its input.
    case inputDevice
    /// A disk or card reader. Its volumes disappear from the Mac; unmounting first avoids data loss.
    case storage
}

/// One USB device connected to this Mac, as IOKit reports it.
public struct MacUSBDevice: Codable, Equatable, Identifiable, Sendable {
    public var locationID: UInt32
    /// libusb's bus number on macOS: the top byte of the location ID. QEMU's `hostbus` matches it.
    public var busNumber: Int
    /// The USB address macOS assigned. QEMU's `hostaddr` matches it.
    public var address: Int
    public var vendorId: Int
    public var productId: Int
    public var productName: String?
    public var vendorName: String?
    public var serialNumber: String?
    public var deviceClass: Int
    public var interfaceClasses: [Int]
    /// True when a macOS kernel driver is bound to one of the device's interfaces. libusb can take
    /// such a device from macOS only with the `com.apple.vm.device-access` entitlement or root, so
    /// attaching it is expected to fail for a QEMU running as the logged-in user.
    public var isClaimedByMacDriver: Bool

    public var id: String { qemuDeviceId }

    public init(
        locationID: UInt32,
        address: Int,
        vendorId: Int,
        productId: Int,
        productName: String? = nil,
        vendorName: String? = nil,
        serialNumber: String? = nil,
        deviceClass: Int = 0,
        interfaceClasses: [Int] = [],
        isClaimedByMacDriver: Bool = false
    ) {
        self.locationID = locationID
        self.busNumber = Int(locationID >> 24)
        self.address = address
        self.vendorId = vendorId
        self.productId = productId
        self.productName = productName
        self.vendorName = vendorName
        self.serialNumber = serialNumber
        self.deviceClass = deviceClass
        self.interfaceClasses = interfaceClasses
        self.isClaimedByMacDriver = isClaimedByMacDriver
    }

    public var displayName: String {
        if let productName, !productName.isEmpty {
            return productName
        }
        return String(format: "USB device %04x:%04x", vendorId, productId)
    }

    /// The QEMU device id Veil gives this device when it is attached. It encodes the bus, address,
    /// vendor, and product so a running VM's devices can be matched back to the Mac's list after Veil
    /// itself restarts, without any state file.
    public var qemuDeviceId: String {
        String(format: "%@%02x%02x-%04x-%04x", QEMUUSBPassthrough.deviceIdPrefix, busNumber, address, vendorId, productId)
    }

    public var risk: MacUSBDeviceRisk {
        let classes = Set(interfaceClasses + [deviceClass])
        if classes.contains(MacUSBDeviceClass.hid) {
            return .inputDevice
        }
        if classes.contains(MacUSBDeviceClass.massStorage) {
            return .storage
        }
        return .none
    }
}

enum MacUSBDeviceClass {
    static let hid = 0x03
    static let massStorage = 0x08
    static let hub = 0x09
}

/// IORegistry facts about one `IOUSBHostDevice`, separated from IOKit so parsing is testable.
public struct MacUSBRegistryEntry: Sendable {
    public struct Interface: Equatable, Sendable {
        public var interfaceClass: Int
        public var hasDriver: Bool

        public init(interfaceClass: Int, hasDriver: Bool) {
            self.interfaceClass = interfaceClass
            self.hasDriver = hasDriver
        }
    }

    public var properties: [String: MacUSBRegistryValue]
    public var interfaces: [Interface]

    public init(properties: [String: MacUSBRegistryValue], interfaces: [Interface]) {
        self.properties = properties
        self.interfaces = interfaces
    }
}

public enum MacUSBRegistryValue: Equatable, Sendable {
    case integer(Int)
    case string(String)
    case bool(Bool)

    var integer: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

public enum MacUSBDeviceList {
    /// Turns IORegistry entries into devices that can be offered to Windows.
    ///
    /// Hubs and built-in devices are left out: a hub is not something a guest can use on its own, and a
    /// built-in device is part of the Mac. Entries without a location ID or address are skipped because
    /// QEMU could not be pointed at them unambiguously.
    public static func devices(from entries: [MacUSBRegistryEntry]) -> [MacUSBDevice] {
        entries.compactMap { entry -> MacUSBDevice? in
            let properties = entry.properties
            guard let locationID = properties["locationID"]?.integer,
                  let address = properties["USB Address"]?.integer,
                  let vendorId = properties["idVendor"]?.integer,
                  let productId = properties["idProduct"]?.integer else {
                return nil
            }

            let deviceClass = properties["bDeviceClass"]?.integer ?? 0
            if deviceClass == MacUSBDeviceClass.hub || properties["Built-In"]?.bool == true {
                return nil
            }

            return MacUSBDevice(
                locationID: UInt32(truncatingIfNeeded: locationID),
                address: address,
                vendorId: vendorId,
                productId: productId,
                productName: nonEmpty(properties["USB Product Name"]?.string ?? properties["kUSBProductString"]?.string),
                vendorName: nonEmpty(properties["USB Vendor Name"]?.string ?? properties["kUSBVendorString"]?.string),
                serialNumber: nonEmpty(properties["USB Serial Number"]?.string ?? properties["kUSBSerialNumberString"]?.string),
                deviceClass: deviceClass,
                interfaceClasses: entry.interfaces.map(\.interfaceClass),
                isClaimedByMacDriver: entry.interfaces.contains(where: \.hasDriver)
            )
        }
        .sorted { ($0.busNumber, $0.address) < ($1.busNumber, $1.address) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Reads every `IOUSBHostDevice` from the IORegistry. Needs no privileges or entitlements: reading
    /// the registry is not the same as opening the device.
    public static func currentDevices() -> [MacUSBDevice] {
        devices(from: registryEntries())
    }

    static func registryEntries() -> [MacUSBRegistryEntry] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var entries: [MacUSBRegistryEntry] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            entries.append(MacUSBRegistryEntry(
                properties: registryProperties(of: service),
                interfaces: interfaces(below: service, depth: 2)
            ))
        }
        return entries
    }

    private static func registryProperties(of entry: io_registry_entry_t) -> [String: MacUSBRegistryValue] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }

        var result: [String: MacUSBRegistryValue] = [:]
        for (key, value) in dictionary {
            switch value {
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                result[key] = .bool(number.boolValue)
            case let number as NSNumber:
                result[key] = .integer(number.intValue)
            case let string as String:
                result[key] = .string(string)
            default:
                continue
            }
        }
        return result
    }

    /// `IOUSBHostInterface` nubs sit under the device, sometimes one level down. Any child of an
    /// interface is a driver that matched it, which is the same test libusb uses for "kernel driver
    /// active".
    private static func interfaces(below entry: io_registry_entry_t, depth: Int) -> [MacUSBRegistryEntry.Interface] {
        guard depth > 0 else {
            return []
        }

        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(children) }

        var result: [MacUSBRegistryEntry.Interface] = []
        while case let child = IOIteratorNext(children), child != 0 {
            defer { IOObjectRelease(child) }
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 {
                let interfaceClass = registryProperties(of: child)["bInterfaceClass"]?.integer ?? 0
                result.append(.init(interfaceClass: interfaceClass, hasDriver: hasChildren(child)))
            } else {
                result.append(contentsOf: interfaces(below: child, depth: depth - 1))
            }
        }
        return result
    }

    private static func hasChildren(_ entry: io_registry_entry_t) -> Bool {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(children) }

        let child = IOIteratorNext(children)
        guard child != 0 else {
            return false
        }
        IOObjectRelease(child)
        return true
    }
}
