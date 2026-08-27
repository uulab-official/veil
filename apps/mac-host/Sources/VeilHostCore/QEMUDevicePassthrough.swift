import Foundation

/// Why a device-level integration is or is not available on this host.
///
/// `requiresPrivilegedHelper` is the field that matters. Both USB passthrough and the bridged network
/// modes need root on macOS, and Veil deliberately runs QEMU as the logged-in user. Reporting them as
/// merely "unsupported" would hide the fact that the blocker is a product decision Veil has not made,
/// not a missing implementation.
public enum VMDevicePassthroughState: String, Codable, Equatable, Sendable {
    case available
    /// Works, but only behind a root-privileged helper Veil does not ship.
    case requiresPrivilegedHelper
    /// The local QEMU binary has no such device compiled in, so privileges are not even the first
    /// problem. Distinguished from ``requiresPrivilegedHelper`` because the two need different answers.
    case notBuiltIntoQEMU
    /// Known not to work on this platform regardless of privileges or build options.
    case unsupportedOnThisPlatform
    case unknown
}

public struct VMDevicePassthroughCapability: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var state: VMDevicePassthroughState
    public var isAvailable: Bool
    public var requiresPrivilegedHelper: Bool
    /// What would have to be true for this to work. Required for every state except `available`, so a
    /// report can never say "no" without saying why.
    public var prerequisite: String?
    /// The alternative a user can actually use today, when one exists.
    public var alternative: String?
    public var detail: String
    /// Public evidence for the claim, so a reader can check it rather than trust it.
    public var reference: String?

    public init(
        id: String,
        title: String,
        state: VMDevicePassthroughState,
        requiresPrivilegedHelper: Bool = false,
        prerequisite: String? = nil,
        alternative: String? = nil,
        detail: String,
        reference: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.isAvailable = state == .available
        self.requiresPrivilegedHelper = requiresPrivilegedHelper
        self.prerequisite = prerequisite
        self.alternative = alternative
        self.detail = detail
        self.reference = reference
    }
}

public struct VMDevicePassthroughReport: Codable, Equatable, Sendable {
    public var kind: String
    public var generatedAt: Date
    public var provider: String
    public var qemuExecutablePath: String?
    /// Whether Veil could ask the local QEMU what devices it has. When false, availability is reported
    /// as `unknown` rather than guessed.
    public var didProbeQEMU: Bool
    public var capabilities: [VMDevicePassthroughCapability]
    /// The architectural decision both unavailable capabilities are waiting on. Carried in the report so
    /// the answer to "why not" is in the same place as the "no".
    public var privilegedHelperDecision: String
    public var nextActions: [String]

    public init(
        kind: String = "vmDevicePassthroughStatus",
        generatedAt: Date,
        provider: String = "QEMU/HVF",
        qemuExecutablePath: String? = nil,
        didProbeQEMU: Bool,
        capabilities: [VMDevicePassthroughCapability],
        privilegedHelperDecision: String = VMDevicePassthroughReportFactory.privilegedHelperDecision,
        nextActions: [String]
    ) {
        self.kind = kind
        self.generatedAt = generatedAt
        self.provider = provider
        self.qemuExecutablePath = qemuExecutablePath
        self.didProbeQEMU = didProbeQEMU
        self.capabilities = capabilities
        self.privilegedHelperDecision = privilegedHelperDecision
        self.nextActions = nextActions
    }
}

public enum VMDevicePassthroughReportFactory {
    public static let usbPassthroughId = "usb-passthrough"
    public static let bridgedNetworkId = "network-bridged"
    public static let hostOnlyNetworkId = "network-host-only"
    public static let sharedNATNetworkId = "network-usermode-nat"

    public static let privilegedHelperDecision = """
        Parallels ships a signed system extension and a privileged helper; Veil runs QEMU as the \
        logged-in user, which is why it needs no admin password. USB passthrough and the bridged and \
        host-only network modes all require root on macOS, so closing them means adopting a privileged \
        helper installed with SMAppService, or Apple-granted vm.networking entitlements. Running QEMU \
        under sudo is refused: it would put a user-controlled command line and a network-reachable \
        guest behind root. The decision is open and deliberately not made by this report.
        """

    /// - Parameter qemuDeviceNames: Device model names the local QEMU reports, normally from
    ///   `-device help`. Pass `nil` when QEMU could not be asked; availability is then `unknown`
    ///   instead of guessed.
    public static func make(
        generatedAt: Date,
        qemuExecutablePath: String?,
        qemuDeviceNames: Set<String>?
    ) -> VMDevicePassthroughReport {
        let capabilities = [
            usbPassthrough(qemuDeviceNames: qemuDeviceNames),
            bridgedNetwork(),
            hostOnlyNetwork(),
            usermodeNATNetwork()
        ]

        return VMDevicePassthroughReport(
            generatedAt: generatedAt,
            qemuExecutablePath: qemuExecutablePath,
            didProbeQEMU: qemuDeviceNames != nil,
            capabilities: capabilities,
            nextActions: nextActions(capabilities: capabilities)
        )
    }

    static func usbPassthrough(qemuDeviceNames: Set<String>?) -> VMDevicePassthroughCapability {
        let sharedFolderAlternative = "For moving files, use the live shared folder instead: veil-vmctl shared-folder-status --json. It needs no privileges and has no size cap."

        guard let qemuDeviceNames else {
            return VMDevicePassthroughCapability(
                id: usbPassthroughId,
                title: "USB device passthrough",
                state: .unknown,
                prerequisite: "Veil could not ask the local QEMU which devices it supports, so USB passthrough availability is unknown rather than assumed.",
                alternative: sharedFolderAlternative,
                detail: "Run veil-vmctl qemu-doctor --json to confirm a working qemu-system-aarch64 first."
            )
        }

        guard qemuDeviceNames.contains("usb-host") else {
            return VMDevicePassthroughCapability(
                id: usbPassthroughId,
                title: "USB device passthrough",
                state: .notBuiltIntoQEMU,
                prerequisite: "The local qemu-system-aarch64 has no usb-host device, which means it was built without libusb. A QEMU built with libusb is required before privileges are even the next problem.",
                alternative: sharedFolderAlternative,
                detail: "Reported separately from the privilege problem because the two need different fixes, and a build without libusb rejects usb-host as an unknown device model rather than failing at access time.",
                reference: "https://gitlab.com/qemu-project/qemu/-/work_items/2178"
            )
        }

        return VMDevicePassthroughCapability(
            id: usbPassthroughId,
            title: "USB device passthrough",
            state: .requiresPrivilegedHelper,
            requiresPrivilegedHelper: true,
            prerequisite: "macOS binds most USB devices to a kernel driver, and libusb cannot take exclusive access from it without root. QEMU upstream tracks this as unusable on Apple Silicon without root.",
            alternative: sharedFolderAlternative,
            detail: "This QEMU has usb-host, so the remaining blocker is privileges. Veil does not attach the device: a usb-host that cannot claim its device fails at runtime, and on some builds prevents QEMU from starting at all, which would turn a clear 'not supported' into a confusing boot failure.",
            reference: "https://gitlab.com/qemu-project/qemu/-/work_items/1951"
        )
    }

    static func bridgedNetwork() -> VMDevicePassthroughCapability {
        VMDevicePassthroughCapability(
            id: bridgedNetworkId,
            title: "Bridged networking",
            state: .requiresPrivilegedHelper,
            requiresPrivilegedHelper: true,
            prerequisite: "macOS exposes bridged networking through the vmnet framework, which requires root or the com.apple.vm.networking entitlement that Apple grants case by case.",
            alternative: "Usermode NAT already gives the guest outbound network access. Reaching the guest from this Mac works through a loopback port forward, which is how the guest agent and the shared folder are reached.",
            detail: "Not added to the boot plan: QEMU exits when it cannot open the vmnet interface, so offering this would trade a working network for a VM that does not boot."
        )
    }

    static func hostOnlyNetwork() -> VMDevicePassthroughCapability {
        VMDevicePassthroughCapability(
            id: hostOnlyNetworkId,
            title: "Host-only networking",
            state: .requiresPrivilegedHelper,
            requiresPrivilegedHelper: true,
            prerequisite: "Also a vmnet mode, so it carries the same root or entitlement requirement as bridged networking.",
            alternative: "Loopback port forwards give this Mac private access to guest services without exposing them to any network, which is the isolation host-only mode is usually wanted for.",
            detail: "Not added to the boot plan, for the same reason as bridged networking."
        )
    }

    static func usermodeNATNetwork() -> VMDevicePassthroughCapability {
        VMDevicePassthroughCapability(
            id: sharedNATNetworkId,
            title: "Usermode NAT networking",
            state: .available,
            detail: "The shipping default. The guest reaches the internet, and this Mac reaches guest services through loopback-scoped port forwards. Nothing on the local network can reach the guest, which is the intended isolation."
        )
    }

    static func nextActions(capabilities: [VMDevicePassthroughCapability]) -> [String] {
        var actions: [String] = []

        if capabilities.contains(where: { $0.state == .unknown }) {
            actions.append("Run veil-vmctl qemu-doctor --json to resolve the local QEMU installation, then re-run this report.")
        }

        if capabilities.contains(where: { $0.state == .notBuiltIntoQEMU }) {
            actions.append("Install a QEMU built with libusb if USB passthrough matters to you. Note that this only moves the blocker to the privilege problem below; it does not make passthrough work.")
        }

        if capabilities.contains(where: { $0.requiresPrivilegedHelper }) {
            // Named as a decision rather than a task. Someone reading this should understand that no
            // amount of host-side code closes it.
            actions.append("USB passthrough and the bridged and host-only network modes need a root-privileged helper that Veil does not ship. This is an open product decision, not pending implementation work.")
            actions.append("Do not work around it by running QEMU under sudo. That puts a user-controlled command line and a network-reachable guest behind root.")
        }

        for capability in capabilities where !capability.isAvailable {
            if let alternative = capability.alternative {
                actions.append("\(capability.title): \(alternative)")
            }
        }

        if actions.isEmpty {
            actions.append("Every reported device integration is available on this host.")
        }

        return actions
    }
}

/// Asks the local QEMU which device models it has.
///
/// Kept out of status-polling paths on purpose: it spawns a process, and `app-runtime-status` is polled.
/// Only the diagnostic command runs it.
public enum QEMUDeviceModelProbe {
    public static func deviceNames(
        qemuExecutablePath: String?,
        runProcess: (String, [String]) -> String? = QEMUDeviceModelProbe.runCapturingOutput
    ) -> Set<String>? {
        guard let qemuExecutablePath,
              !qemuExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.isExecutableFile(atPath: qemuExecutablePath) else {
            return nil
        }

        guard let output = runProcess(qemuExecutablePath, ["-device", "help"]) else {
            return nil
        }

        return parseDeviceNames(from: output)
    }

    /// `-device help` prints lines like `name "usb-host", bus usb-bus`. Only the quoted name is taken, so
    /// a bus or description that happens to contain a device-like word cannot be mistaken for a device.
    static func parseDeviceNames(from output: String) -> Set<String> {
        var names: Set<String> = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let nameRange = line.range(of: "name \"") else {
                continue
            }

            let remainder = line[nameRange.upperBound...]
            guard let closingQuote = remainder.firstIndex(of: "\"") else {
                continue
            }

            let name = String(remainder[remainder.startIndex..<closingQuote])
            if !name.isEmpty {
                names.insert(name)
            }
        }

        return names
    }

    public static func runCapturingOutput(_ executablePath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // `-device help` writes to stdout on current QEMU but has used stderr before. Both are read so a
        // version difference reads as "no such device" rather than an empty probe.
        process.standardError = output

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
