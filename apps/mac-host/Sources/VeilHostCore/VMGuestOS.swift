import Foundation

/// The operating system a VM profile runs. Stored in `VMProfile.os` as the raw value, so profiles
/// written before this type existed (`"windows-arm64"`) keep decoding unchanged.
///
/// Windows 11 Arm is the product path: guest agent, answer file, TPM and Secure Boot. The other
/// kinds are plain virtual machines in the UTM sense -- Veil boots their installer and shows the
/// console, with no guest agent or app windows. See docs/architecture.md, "Other guest operating
/// systems".
public enum VMGuestOS: String, Codable, CaseIterable, Equatable, Sendable {
    case windows11Arm = "windows-arm64"
    case linuxArm64 = "linux-arm64"
    /// Any x86_64 operating system, emulated instruction by instruction with QEMU's TCG.
    case x86_64 = "x86_64"

    public var displayName: String {
        switch self {
        case .windows11Arm: "Windows 11 Arm"
        case .linuxArm64: "Linux (Arm64)"
        case .x86_64: "x86_64 (emulated)"
        }
    }

    /// The QEMU system emulator this guest needs.
    public var qemuExecutableName: String {
        switch self {
        case .windows11Arm, .linuxArm64: "qemu-system-aarch64"
        case .x86_64: "qemu-system-x86_64"
        }
    }

    /// Whether the guest runs on Hypervisor.framework (`true`) or QEMU's TCG emulator (`false`).
    public var usesHardwareVirtualization: Bool {
        self != .x86_64
    }

    /// Whether the Windows guest agent, answer file, and app-window integration apply.
    public var usesWindowsIntegration: Bool {
        self == .windows11Arm
    }

    public var defaultResources: VMResourcePlan {
        switch self {
        case .windows11Arm:
            VMResourcePlan(cpuCount: 4, memoryMB: 8_192, diskGB: 128)
        case .linuxArm64:
            VMResourcePlan(cpuCount: 4, memoryMB: 4_096, diskGB: 32)
        case .x86_64:
            // TCG gains little from many vCPUs and every guest megabyte is host memory, so the
            // default stays small; the console is the bottleneck, not RAM.
            VMResourcePlan(cpuCount: 2, memoryMB: 2_048, diskGB: 32)
        }
    }
}

extension VMProfile {
    /// The guest kind this profile describes. Unknown values fall back to Windows, which is what
    /// every profile meant before the field carried other operating systems.
    public var guestOS: VMGuestOS {
        VMGuestOS(rawValue: os) ?? .windows11Arm
    }

    /// A short id, so `<VM folder>/tpm/swtpm.sock` stays under the 104-byte Unix socket path limit.
    public static func newGuestID() -> String {
        "vm_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12)
    }

    /// A new non-Windows guest whose disk, UEFI variables, and TPM state live in `directory`.
    public static func newGuest(
        _ guestOS: VMGuestOS,
        name: String,
        installerMediaPath: String?,
        directory: URL,
        resources: VMResourcePlan? = nil,
        createdAt: Date = Date(),
        id: String = VMProfile.newGuestID()
    ) -> VMProfile {
        let resources = resources ?? guestOS.defaultResources
        return VMProfile(
            id: id,
            name: name,
            os: guestOS.rawValue,
            cpuCount: resources.cpuCount,
            memoryMB: resources.memoryMB,
            diskGB: resources.diskGB,
            autoStart: false,
            suspendOnQuit: false,
            sharedFolderPath: directory.path,
            installerMediaPath: installerMediaPath,
            virtualDiskPath: directory.appendingPathComponent("disk.img").path,
            createdAt: createdAt
        )
    }
}
