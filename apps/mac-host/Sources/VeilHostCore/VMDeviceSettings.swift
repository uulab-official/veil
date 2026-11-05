import Foundation

/// What the Mac's Command key becomes in the Windows desktop. Control keeps Mac shortcuts such as
/// Command-C working in Windows apps; Windows makes Command the Windows logo key, like UTM's option,
/// so Command-E opens File Explorer. The Mac's own Control key is always Control.
///
/// Only the desktop console honors this. Mirrored app windows post keys straight to one HWND, where a
/// Windows-key shortcut means nothing, so they always map Command to Control.
public enum VMCommandKeyMapping: String, Codable, CaseIterable, Equatable, Sendable {
    case control
    case windows

    public static let `default`: VMCommandKeyMapping = .control
}

/// Which host interfaces a port forward listens on.
public enum VMPortForwardHostBinding: String, Codable, CaseIterable, Equatable, Sendable {
    /// Only this Mac can connect. The default.
    case loopback
    /// Every network interface, so other devices on the network can reach the guest port.
    case allInterfaces

    public var address: String {
        switch self {
        case .loopback:
            QEMUWindowsSharedFolderTransport.hostForwardAddress
        case .allInterfaces:
            "0.0.0.0"
        }
    }
}

public enum VMPortForwardProtocol: String, Codable, CaseIterable, Equatable, Sendable {
    case tcp
    case udp
}

/// One user-defined `hostfwd` rule on the guest's NAT network. QEMU reads the rules when it starts.
public struct VMPortForwardRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var transport: VMPortForwardProtocol
    public var hostBinding: VMPortForwardHostBinding
    public var hostPort: Int
    public var guestPort: Int

    public init(
        id: String = UUID().uuidString,
        transport: VMPortForwardProtocol = .tcp,
        hostBinding: VMPortForwardHostBinding = .loopback,
        hostPort: Int,
        guestPort: Int
    ) {
        self.id = id
        self.transport = transport
        self.hostBinding = hostBinding
        self.hostPort = hostPort
        self.guestPort = guestPort
    }

    /// The clause appended to the single `-netdev user` value.
    public var hostForwardClause: String {
        "hostfwd=\(transport.rawValue):\(hostBinding.address):\(hostPort)-:\(guestPort)"
    }
}

/// Shown in the settings window, so the descriptions come from the app's Localizable.strings.
public enum VMPortForwardRuleError: Error, LocalizedError, Equatable, Sendable {
    case portOutOfRange(Int)
    case privilegedHostPort(Int)
    case reservedHostPort(Int)
    case reservedGuestPort(Int)
    case duplicateHostPort(Int)
    case tooManyRules(Int)

    public var errorDescription: String? {
        switch self {
        case .portOutOfRange(let port):
            String(localized: "Port \(port) is not between 1 and 65535.")
        case .privilegedHostPort(let port):
            String(localized: "Host port \(port) is below 1024, which only an administrator can open on macOS. Choose 1024 or higher.")
        case .reservedHostPort(let port):
            String(localized: "Host port \(port) is reserved for Veil's own connection to Windows.")
        case .reservedGuestPort(let port):
            String(localized: "Windows port \(port) carries Veil's agent or shared folder and cannot be forwarded again.")
        case .duplicateHostPort(let port):
            String(localized: "Host port \(port) is already used by another rule.")
        case .tooManyRules(let limit):
            String(localized: "Veil supports up to \(limit) port forwarding rules.")
        }
    }
}

public enum VMPortForwardRuleValidator {
    public static let maximumRuleCount = 32
    public static let minimumUnprivilegedPort = 1_024

    /// Host ports Veil forwards itself; a second listener on them would stop QEMU from starting.
    public static var reservedHostPorts: Set<Int> {
        [QEMUWindowsBootPlanner.guestAgentHostPort, QEMUWindowsSharedFolderTransport.guestSMBHostPort]
    }

    /// Guest ports behind Veil's own forwards. The agent's control channel is unauthenticated, so a
    /// second forward -- especially one on every interface -- would hand app launch, input, and the
    /// clipboard to anyone who can reach the port.
    public static var reservedGuestPorts: Set<Int> {
        [QEMUWindowsBootPlanner.guestAgentGuestPort, QEMUWindowsSharedFolderTransport.guestSMBGuestPort]
    }

    public static func validate(_ rules: [VMPortForwardRule]) throws {
        guard rules.count <= maximumRuleCount else {
            throw VMPortForwardRuleError.tooManyRules(maximumRuleCount)
        }

        var usedHostPorts = Set<String>()
        for rule in rules {
            for port in [rule.hostPort, rule.guestPort] where !(1...65_535).contains(port) {
                throw VMPortForwardRuleError.portOutOfRange(port)
            }
            guard rule.hostPort >= minimumUnprivilegedPort else {
                throw VMPortForwardRuleError.privilegedHostPort(rule.hostPort)
            }
            guard !reservedHostPorts.contains(rule.hostPort) else {
                throw VMPortForwardRuleError.reservedHostPort(rule.hostPort)
            }
            guard !reservedGuestPorts.contains(rule.guestPort) else {
                throw VMPortForwardRuleError.reservedGuestPort(rule.guestPort)
            }
            // QEMU cannot bind one port twice for the same protocol, whatever the address.
            guard usedHostPorts.insert("\(rule.transport.rawValue):\(rule.hostPort)").inserted else {
                throw VMPortForwardRuleError.duplicateHostPort(rule.hostPort)
            }
        }
    }
}

/// The removable CD drive every Veil Windows has, so an ISO can be inserted or ejected while Windows
/// runs, like UTM's removable drives. It sits on its own AHCI controller because Windows has an
/// inbox AHCI driver and `ide-cd` keeps a tray QMP can open, while `usb-storage` cannot start empty.
public enum VMRemovableOpticalDrive {
    public static let controllerID = "veil-cd-ahci"
    public static let driveID = "veil-cd"
    public static let deviceID = "veil-cd0"

    public static var arguments: [String] {
        [
            "-device", "ich9-ahci,id=\(controllerID)",
            "-drive", "if=none,id=\(driveID),media=cdrom,readonly=on",
            "-device", "ide-cd,bus=\(controllerID).0,drive=\(driveID),id=\(deviceID)"
        ]
    }

    /// Whether a running QEMU was started with this drive. A Windows started by an older Veil has none
    /// until it restarts.
    public static func isPresent(in arguments: [String]) -> Bool {
        arguments.contains { $0.contains("id=\(deviceID)") }
    }
}

public enum VMRemovableMediaError: Error, LocalizedError, Equatable, Sendable {
    case notRunning
    case driveMissing
    case mediaNotFound(String)
    case unsupportedMedia(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            String(localized: "Start Windows before inserting or ejecting a disc.")
        case .driveMissing:
            String(localized: "This Windows was started without Veil's removable CD drive. Restart Windows to use it.")
        case .mediaNotFound(let path):
            String(localized: "The disc image is not available at \(path).")
        case .unsupportedMedia(let path):
            String(localized: "Only ISO disc images can be inserted: \(path)")
        }
    }
}

/// The removable CD drive of the running Windows, read back from QEMU rather than remembered, so an
/// eject Windows did itself shows up too.
public struct VMRemovableMediaStatus: Equatable, Sendable {
    public var isDriveAvailable: Bool
    public var insertedPath: String?
    /// Why the drive cannot be used now, for the settings panel.
    public var unavailableReason: String?

    public init(isDriveAvailable: Bool, insertedPath: String? = nil, unavailableReason: String? = nil) {
        self.isDriveAvailable = isDriveAvailable
        self.insertedPath = insertedPath
        self.unavailableReason = unavailableReason
    }

    public static func unavailable(_ error: VMRemovableMediaError) -> VMRemovableMediaStatus {
        VMRemovableMediaStatus(isDriveAvailable: false, unavailableReason: error.errorDescription)
    }

    /// Reads `info block veil-cd`. Its first line is `veil-cd: [not inserted]` for an empty drive and,
    /// once QEMU has opened a disc, `veil-cd (#block173): /path/disc.iso (raw, read-only)`.
    public static func parse(infoBlock output: String) -> VMRemovableMediaStatus {
        let driveID = VMRemovableOpticalDrive.driveID
        guard let line = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { $0.hasPrefix("\(driveID): ") || $0.hasPrefix("\(driveID) (#") }),
              let separator = line.range(of: ": ") else {
            return .unavailable(.driveMissing)
        }

        let value = line[separator.upperBound...]
        if value.hasPrefix("[not inserted]") {
            return VMRemovableMediaStatus(isDriveAvailable: true)
        }

        let path = value.range(of: " (", options: .backwards).map { String(value[..<$0.lowerBound]) } ?? String(value)
        return VMRemovableMediaStatus(isDriveAvailable: true, insertedPath: path.isEmpty ? nil : path)
    }
}
