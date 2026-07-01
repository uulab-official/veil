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

public enum QEMUWindowsReadinessState: String, Codable, Equatable, Sendable {
    case passed
    case warning
    case blocked
    case ready
}

public struct QEMUWindowsReadinessCheck: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var state: QEMUWindowsReadinessState
    public var detail: String

    public init(
        id: String,
        title: String,
        state: QEMUWindowsReadinessState,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.detail = detail
    }
}

public struct QEMUWindowsReadinessReport: Codable, Equatable, Sendable {
    public var kind: String
    public var provider: String
    public var isServerBacked: Bool
    public var overallState: QEMUWindowsReadinessState
    public var checks: [QEMUWindowsReadinessCheck]
    public var nextActions: [String]

    public init(
        kind: String = "qemuWindowsArmReadinessReport",
        provider: String = "QEMU/HVF",
        isServerBacked: Bool = false,
        overallState: QEMUWindowsReadinessState,
        checks: [QEMUWindowsReadinessCheck],
        nextActions: [String]
    ) {
        self.kind = kind
        self.provider = provider
        self.isServerBacked = isServerBacked
        self.overallState = overallState
        self.checks = checks
        self.nextActions = nextActions
    }
}

public struct QEMUWindowsReadinessDoctor: Sendable {
    private let fileExists: @Sendable (String) -> Bool

    public init(
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.fileExists = fileExists
    }

    public func makeReport(
        profile: VMProfile?,
        plan: QEMUWindowsBootPlan?
    ) -> QEMUWindowsReadinessReport {
        let checks = [
            profileCheck(profile),
            installerMediaCheck(profile),
            systemDiskCheck(profile),
            qemuExecutableCheck(plan),
            hvfPlanCheck(plan)
        ]
        let overallState: QEMUWindowsReadinessState = checks.contains { $0.state == .blocked }
            ? .blocked
            : .ready

        return QEMUWindowsReadinessReport(
            overallState: overallState,
            checks: checks,
            nextActions: nextActions(for: checks)
        )
    }

    private func profileCheck(_ profile: VMProfile?) -> QEMUWindowsReadinessCheck {
        guard let profile else {
            return QEMUWindowsReadinessCheck(
                id: "vm-profile",
                title: "VM profile",
                state: .blocked,
                detail: "No prepared Windows VM profile exists."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "vm-profile",
            title: "VM profile",
            state: .passed,
            detail: "\(profile.name) targets \(profile.os) with \(profile.cpuCount) CPU cores and \(profile.memoryMB) MB memory."
        )
    }

    private func installerMediaCheck(_ profile: VMProfile?) -> QEMUWindowsReadinessCheck {
        guard let path = nonEmpty(profile?.installerMediaPath) else {
            return QEMUWindowsReadinessCheck(
                id: "installer-media",
                title: "Installer media",
                state: .blocked,
                detail: "No Windows installer ISO is configured."
            )
        }

        guard fileExists(path) else {
            return QEMUWindowsReadinessCheck(
                id: "installer-media",
                title: "Installer media",
                state: .blocked,
                detail: "Installer media is missing at \(path)."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "installer-media",
            title: "Installer media",
            state: .passed,
            detail: "Installer ISO is available at \(path)."
        )
    }

    private func systemDiskCheck(_ profile: VMProfile?) -> QEMUWindowsReadinessCheck {
        guard let path = nonEmpty(profile?.virtualDiskPath) else {
            return QEMUWindowsReadinessCheck(
                id: "system-disk",
                title: "System disk",
                state: .blocked,
                detail: "No writable Windows system disk is configured."
            )
        }

        guard fileExists(path) else {
            return QEMUWindowsReadinessCheck(
                id: "system-disk",
                title: "System disk",
                state: .blocked,
                detail: "System disk is missing at \(path)."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "system-disk",
            title: "System disk",
            state: .passed,
            detail: "Writable system disk is available at \(path)."
        )
    }

    private func qemuExecutableCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        guard let plan else {
            return QEMUWindowsReadinessCheck(
                id: "qemu-executable",
                title: "QEMU executable",
                state: .blocked,
                detail: "QEMU plan could not be generated."
            )
        }

        guard plan.isExecutableAvailable, fileExists(plan.executablePath) else {
            return QEMUWindowsReadinessCheck(
                id: "qemu-executable",
                title: "QEMU executable",
                state: .blocked,
                detail: "qemu-system-aarch64 is not available at \(plan.executablePath)."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "qemu-executable",
            title: "QEMU executable",
            state: .passed,
            detail: "qemu-system-aarch64 is available at \(plan.executablePath)."
        )
    }

    private func hvfPlanCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        guard let plan else {
            return QEMUWindowsReadinessCheck(
                id: "hvf-plan",
                title: "HVF command plan",
                state: .blocked,
                detail: "QEMU command plan is unavailable."
            )
        }

        guard plan.arguments.containsSequence(["-accel", "hvf"]) else {
            return QEMUWindowsReadinessCheck(
                id: "hvf-plan",
                title: "HVF command plan",
                state: .blocked,
                detail: "QEMU command plan does not enable HVF acceleration."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "hvf-plan",
            title: "HVF command plan",
            state: .passed,
            detail: "QEMU command plan enables HVF acceleration and local devices."
        )
    }

    private func nextActions(for checks: [QEMUWindowsReadinessCheck]) -> [String] {
        var actions: [String] = []

        if checks.first(where: { $0.id == "vm-profile" })?.state == .blocked {
            actions.append("Run veil-vmctl prepare --installer /path/to/Windows.iso to create the local profile and disk.")
        }

        if checks.first(where: { $0.id == "installer-media" })?.state == .blocked {
            actions.append("Choose a local Windows 11 Arm ISO and run veil-vmctl prepare --installer /path/to/Windows.iso.")
        }

        if checks.first(where: { $0.id == "system-disk" })?.state == .blocked {
            actions.append("Run veil-vmctl prepare --installer /path/to/Windows.iso to create Veil's default writable system disk.")
        }

        if checks.first(where: { $0.id == "qemu-executable" })?.state == .blocked {
            actions.append("Install QEMU with Homebrew or set VEIL_QEMU_SYSTEM_AARCH64 to the local qemu-system-aarch64 path.")
        }

        if checks.first(where: { $0.id == "hvf-plan" })?.state == .blocked {
            actions.append("Regenerate the QEMU plan and confirm it includes -accel hvf.")
        }

        if actions.isEmpty {
            actions.append("Run veil-vmctl qemu-plan --json to review the exact command before execution support lands.")
        }

        return actions
    }

    private func nonEmpty(_ path: String?) -> String? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return path
    }
}

private extension [String] {
    func containsSequence(_ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, count >= sequence.count else {
            return false
        }

        for startIndex in 0...(count - sequence.count) {
            if Array(self[startIndex..<(startIndex + sequence.count)]) == sequence {
                return true
            }
        }

        return false
    }
}
