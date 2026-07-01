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
    public var firmwarePath: String?
    public var isFirmwareAvailable: Bool
    public var automaticInstallMediaPath: String?
    public var summary: String
    public var arguments: [String]
    public var warnings: [String]

    public init(
        kind: String = "qemuWindowsArmBootPlan",
        provider: String = "QEMU/HVF",
        isServerBacked: Bool = false,
        executablePath: String,
        isExecutableAvailable: Bool,
        firmwarePath: String? = nil,
        isFirmwareAvailable: Bool = false,
        automaticInstallMediaPath: String? = nil,
        summary: String,
        arguments: [String],
        warnings: [String]
    ) {
        self.kind = kind
        self.provider = provider
        self.isServerBacked = isServerBacked
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
        self.firmwarePath = firmwarePath
        self.isFirmwareAvailable = isFirmwareAvailable
        self.automaticInstallMediaPath = automaticInstallMediaPath
        self.summary = summary
        self.arguments = arguments
        self.warnings = warnings
    }
}

public struct QEMUWindowsBootPlanner: Sendable {
    public static let guestAgentHostPort = 18_444
    public static let guestAgentGuestPort = 18_444

    private let executablePath: String
    private let isExecutableAvailable: Bool
    private let firmwarePath: String?
    private let isFirmwareAvailable: Bool

    public init(
        executablePath: String,
        isExecutableAvailable: Bool,
        firmwarePath: String? = nil,
        isFirmwareAvailable: Bool = false
    ) {
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
        self.firmwarePath = firmwarePath
        self.isFirmwareAvailable = isFirmwareAvailable
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
        let automaticInstallMediaPath = URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("VeilAutoInstall.iso")
            .path
        var warnings: [String] = []

        if !isExecutableAvailable {
            warnings.append(
                "qemu-system-aarch64 is not available at \(executablePath). Install QEMU locally or set VEIL_QEMU_SYSTEM_AARCH64 before executing this plan."
            )
        }

        if let firmwarePath, !isFirmwareAvailable {
            warnings.append(
                "QEMU Arm UEFI firmware is not available at \(firmwarePath). Install QEMU from Homebrew or point Veil at an edk2-aarch64-code.fd file."
            )
        }

        var arguments = [
            "-name", profile.name,
            "-machine", "virt,highmem=on",
            "-accel", "hvf"
        ]

        if let firmwarePath {
            arguments.append(contentsOf: ["-bios", firmwarePath])
        }

        let guestAgentForward = "hostfwd=tcp::\(Self.guestAgentHostPort)-:\(Self.guestAgentGuestPort)"

        arguments.append(contentsOf: [
            "-boot", "order=d",
            "-cpu", "host",
            "-smp", "\(cpuCount)",
            "-m", "\(memoryMB)M",
            "-drive", "driver=raw,file.driver=file,file.locking=off,file.filename=\(installerMediaPath),if=none,id=installer,media=cdrom,readonly=on",
            "-drive", "driver=raw,file.driver=file,file.locking=off,file.filename=\(automaticInstallMediaPath),if=none,id=autounattend,media=cdrom,readonly=on",
            "-device", "qemu-xhci,id=usb0",
            "-device", "usb-storage,drive=installer",
            "-device", "usb-storage,drive=autounattend",
            "-drive", "if=none,id=system,format=raw,file=\(virtualDiskPath)",
            "-device", "virtio-blk-pci,drive=system",
            "-netdev", "user,id=net0,\(guestAgentForward)",
            "-device", "virtio-net-pci,netdev=net0",
            "-display", "cocoa",
            "-device", "ramfb",
            "-device", "virtio-gpu-pci",
            "-device", "usb-kbd",
            "-device", "usb-tablet"
        ])

        return QEMUWindowsBootPlan(
            executablePath: executablePath,
            isExecutableAvailable: isExecutableAvailable,
            firmwarePath: firmwarePath,
            isFirmwareAvailable: isFirmwareAvailable,
            automaticInstallMediaPath: automaticInstallMediaPath,
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

public enum LocalQEMUWindowsBootPlanFactory {
    public static let defaultFirmwarePaths = [
        "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
        "/usr/local/share/qemu/edk2-aarch64-code.fd",
        "/opt/local/share/qemu/edk2-aarch64-code.fd"
    ]

    public static func makePlan(
        for profile: VMProfile,
        architecture: String,
        minimumOSSupported: Bool,
        providerProbe: VMRuntimeProviderProbe = VMRuntimeProviderProbe(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> QEMUWindowsBootPlan {
        let qemuProvider = providerProbe
            .localProviders(
                architecture: architecture,
                minimumOSSupported: minimumOSSupported
            )
            .first { $0.kind == .qemuHypervisor }
        let executablePath = qemuProvider?.executablePath
            ?? VMRuntimeProviderProbe.defaultQEMUExecutablePaths[0]
        let firmwarePath = defaultFirmwarePaths.first(where: fileExists)
        let planner = QEMUWindowsBootPlanner(
            executablePath: executablePath,
            isExecutableAvailable: qemuProvider?.status == .active && qemuProvider?.executablePath != nil,
            firmwarePath: firmwarePath ?? defaultFirmwarePaths[0],
            isFirmwareAvailable: firmwarePath != nil
        )
        return try planner.makePlan(for: profile)
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
            automaticInstallMediaCheck(plan),
            systemDiskCheck(profile),
            qemuExecutableCheck(plan),
            uefiFirmwareCheck(plan),
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

    private func automaticInstallMediaCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        guard let path = nonEmpty(plan?.automaticInstallMediaPath) else {
            return QEMUWindowsReadinessCheck(
                id: "automatic-install-media",
                title: "Automatic install media",
                state: .blocked,
                detail: "No automatic Windows setup media is configured."
            )
        }

        guard fileExists(path) else {
            return QEMUWindowsReadinessCheck(
                id: "automatic-install-media",
                title: "Automatic install media",
                state: .blocked,
                detail: "Automatic setup media is missing at \(path)."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "automatic-install-media",
            title: "Automatic install media",
            state: .passed,
            detail: "Automatic setup media is available at \(path)."
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

    private func uefiFirmwareCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        guard let plan else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "QEMU command plan is unavailable."
            )
        }

        guard let firmwarePath = plan.firmwarePath else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "No Arm UEFI firmware path is configured."
            )
        }

        guard plan.isFirmwareAvailable, fileExists(firmwarePath) else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "Arm UEFI firmware is not available at \(firmwarePath)."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "uefi-firmware",
            title: "Arm UEFI firmware",
            state: .passed,
            detail: "Arm UEFI firmware is available at \(firmwarePath)."
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

        if checks.first(where: { $0.id == "automatic-install-media" })?.state == .blocked {
            actions.append("Run veil-vmctl prepare --installer /path/to/Windows.iso to create VeilAutoInstall.iso.")
        }

        if checks.first(where: { $0.id == "system-disk" })?.state == .blocked {
            actions.append("Run veil-vmctl prepare --installer /path/to/Windows.iso to create Veil's default writable system disk.")
        }

        if checks.first(where: { $0.id == "qemu-executable" })?.state == .blocked {
            actions.append("Install QEMU with Homebrew or set VEIL_QEMU_SYSTEM_AARCH64 to the local qemu-system-aarch64 path.")
        }

        if checks.first(where: { $0.id == "uefi-firmware" })?.state == .blocked {
            actions.append("Install QEMU from Homebrew or point Veil at edk2-aarch64-code.fd before launching Windows setup.")
        }

        if checks.first(where: { $0.id == "hvf-plan" })?.state == .blocked {
            actions.append("Regenerate the QEMU plan and confirm it includes -accel hvf.")
        }

        if actions.isEmpty {
            actions.append("Run veil-vmctl qemu-start to launch the local QEMU/HVF Windows setup window.")
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

public enum QEMUWindowsBootSmokeOutcome: String, Codable, Equatable, Sendable {
    case windowsBootStarted
    case uefiShell
    case bootImageTimeout
    case argumentFailure
    case runningNoDecision
    case exitedEarly
}

public struct QEMUWindowsBootSmokeReport: Codable, Equatable, Sendable {
    public var kind: String
    public var provider: String
    public var outcome: QEMUWindowsBootSmokeOutcome
    public var durationSeconds: Int
    public var detail: String
    public var evidence: [String]
    public var serialLogPath: String
    public var processLogPath: String

    public init(
        kind: String = "qemuWindowsArmBootSmokeReport",
        provider: String = "QEMU/HVF",
        outcome: QEMUWindowsBootSmokeOutcome,
        durationSeconds: Int,
        detail: String,
        evidence: [String],
        serialLogPath: String,
        processLogPath: String
    ) {
        self.kind = kind
        self.provider = provider
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.detail = detail
        self.evidence = evidence
        self.serialLogPath = serialLogPath
        self.processLogPath = processLogPath
    }
}

public enum QEMUWindowsBootSmokeAnalyzer {
    public static func makeReport(
        durationSeconds: Int,
        processOutput: String,
        serialOutput: String,
        didRemainRunningUntilTimeout: Bool,
        serialLogPath: String,
        processLogPath: String
    ) -> QEMUWindowsBootSmokeReport {
        let combinedOutput = "\(processOutput)\n\(serialOutput)"
        var evidence: [String] = []

        if processOutput.contains("qemu-system-aarch64:"),
           !processOutput.contains("terminating on signal") {
            evidence.append("qemu-argument-error")
            return QEMUWindowsBootSmokeReport(
                outcome: .argumentFailure,
                durationSeconds: durationSeconds,
                detail: "QEMU exited before firmware boot because the command line or local resources failed validation.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath
            )
        }

        if combinedOutput.localizedCaseInsensitiveContains("Windows Boot Manager")
            || combinedOutput.localizedCaseInsensitiveContains("Windows Setup") {
            evidence.append("windows-boot-text")
            return QEMUWindowsBootSmokeReport(
                outcome: .windowsBootStarted,
                durationSeconds: durationSeconds,
                detail: "QEMU reached Windows boot text during the bounded smoke run.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath
            )
        }

        if combinedOutput.contains("Time out") || combinedOutput.contains("failed to start Boot") {
            evidence.append("boot-image-timeout")
        }

        if combinedOutput.contains("UEFI Interactive Shell") || combinedOutput.contains("Shell>") {
            evidence.append("uefi-shell")
            return QEMUWindowsBootSmokeReport(
                outcome: .uefiShell,
                durationSeconds: durationSeconds,
                detail: "QEMU reached Arm UEFI, but Windows Setup did not start and firmware fell back to the EDK II shell.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath
            )
        }

        if evidence.contains("boot-image-timeout") {
            return QEMUWindowsBootSmokeReport(
                outcome: .bootImageTimeout,
                durationSeconds: durationSeconds,
                detail: "Arm UEFI attempted the installer boot image, but it timed out before Windows Setup appeared.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath
            )
        }

        if didRemainRunningUntilTimeout {
            evidence.append("qemu-running")
            return QEMUWindowsBootSmokeReport(
                outcome: .runningNoDecision,
                durationSeconds: durationSeconds,
                detail: "QEMU stayed alive for the bounded smoke run, but serial output did not prove Windows Setup or UEFI shell state.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath
            )
        }

        evidence.append("qemu-exited")
        return QEMUWindowsBootSmokeReport(
            outcome: .exitedEarly,
            durationSeconds: durationSeconds,
            detail: "QEMU exited before the bounded smoke run could classify Windows boot progress.",
            evidence: evidence,
            serialLogPath: serialLogPath,
            processLogPath: processLogPath
        )
    }
}

public struct QEMUWindowsBootSmokePlanner: Sendable {
    public init() {}

    public func makeArguments(
        from plan: QEMUWindowsBootPlan,
        serialLogPath: String
    ) -> [String] {
        var arguments = plan.arguments.map { argument in
            Self.lockSafeSystemDriveArgument(argument)
        }

        if let displayIndex = arguments.firstIndex(of: "-display"),
           arguments.indices.contains(displayIndex + 1) {
            arguments[displayIndex + 1] = "none"
        } else {
            arguments.append(contentsOf: ["-display", "none"])
        }

        if !arguments.contains("-snapshot") {
            arguments.append("-snapshot")
        }

        arguments.append(contentsOf: [
            "-serial", "file:\(serialLogPath)",
            "-monitor", "none"
        ])

        return arguments
    }

    private static func lockSafeSystemDriveArgument(_ argument: String) -> String {
        guard argument.contains("id=system"),
              argument.contains("format=raw"),
              let fileRange = argument.range(of: "file=") else {
            return argument
        }

        let prefix = argument[..<fileRange.lowerBound]
        let path = argument[fileRange.upperBound...]
        let pathString = String(path)
        guard prefix.contains("if=none,") else {
            return argument
        }

        return "driver=raw,file.driver=file,file.locking=off,file.filename=\(pathString),if=none,id=system"
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
