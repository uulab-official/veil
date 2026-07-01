import Foundation

public enum QEMUWindowsBootPlanError: Error, LocalizedError, Equatable, Sendable {
    case missingInstallerMedia
    case missingVirtualDisk

    public var errorDescription: String? {
        switch self {
        case .missingInstallerMedia:
            "QEMU plan requires installer media on the VM profile."
        case .missingVirtualDisk:
            "QEMU plan requires a virtual disk on the VM profile."
        }
    }
}

public struct QEMUWindowsBootPlan: Codable, Equatable, Sendable {
    public var kind: String
    public var provider: String
    public var isServerBacked: Bool
    public var executablePath: String
    public var isExecutableAvailable: Bool
    public var summary: String
    public var arguments: [String]
    public var warnings: [String]

    public init(
        kind: String = "qemuWindowsArmBootPlan",
        provider: String = "QEMU/HVF",
        isServerBacked: Bool = false,
        executablePath: String,
        isExecutableAvailable: Bool,
        summary: String,
        arguments: [String],
        warnings: [String]
    ) {
        self.kind = kind
        self.provider = provider
        self.isServerBacked = isServerBacked
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
        self.summary = summary
        self.arguments = arguments
        self.warnings = warnings
    }
}

public struct QEMUWindowsBootPlanner: Sendable {
    private let executablePath: String
    private let isExecutableAvailable: Bool

    public init(
        executablePath: String,
        isExecutableAvailable: Bool
    ) {
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
    }

    public func makePlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        guard let installerMediaPath = nonEmpty(profile.installerMediaPath) else {
            throw QEMUWindowsBootPlanError.missingInstallerMedia
        }

        guard let virtualDiskPath = nonEmpty(profile.virtualDiskPath) else {
            throw QEMUWindowsBootPlanError.missingVirtualDisk
        }

        let cpuCount = max(2, profile.cpuCount)
        let memoryMB = max(4_096, profile.memoryMB)
        var warnings: [String] = []

        if !isExecutableAvailable {
            warnings.append(
                "qemu-system-aarch64 is not available at \(executablePath). Install QEMU locally or set VEIL_QEMU_SYSTEM_AARCH64 before executing this plan."
            )
        }

        let arguments = [
            "-name", profile.name,
            "-machine", "virt,highmem=on",
            "-accel", "hvf",
            "-cpu", "host",
            "-smp", "\(cpuCount)",
            "-m", "\(memoryMB)M",
            "-drive", "if=none,id=installer,media=cdrom,readonly=on,file=\(installerMediaPath)",
            "-device", "usb-storage,drive=installer",
            "-drive", "if=none,id=system,format=raw,file=\(virtualDiskPath)",
            "-device", "virtio-blk-pci,drive=system",
            "-netdev", "user,id=net0",
            "-device", "virtio-net-pci,netdev=net0",
            "-display", "cocoa",
            "-device", "virtio-gpu-pci",
            "-device", "usb-kbd",
            "-device", "usb-tablet"
        ]

        return QEMUWindowsBootPlan(
            executablePath: executablePath,
            isExecutableAvailable: isExecutableAvailable,
            summary: "Dry-run QEMU/HVF command plan for \(profile.name). Veil does not execute this plan yet.",
            arguments: arguments,
            warnings: warnings
        )
    }

    private func nonEmpty(_ path: String?) -> String? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return path
    }
}
