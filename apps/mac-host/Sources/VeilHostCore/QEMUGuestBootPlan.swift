import Foundation

/// Optional hardware a non-Windows guest may ask for. Both are off by default: most Linux
/// installers need neither, and Windows keeps its own always-on TPM and Secure Boot path in
/// `QEMUWindowsBootPlanner`.
public struct QEMUGuestBootOptions: Codable, Equatable, Sendable {
    public var tpm: Bool
    public var secureBoot: Bool

    public init(tpm: Bool = false, secureBoot: Bool = false) {
        self.tpm = tpm
        self.secureBoot = secureBoot
    }
}

public enum QEMUGuestBootPlanError: Error, LocalizedError, Equatable, Sendable {
    case windowsUsesWindowsPlanner
    case missingVirtualDisk
    case missingFirmware(String)

    public var errorDescription: String? {
        switch self {
        case .windowsUsesWindowsPlanner:
            "Windows 11 Arm guests boot through QEMUWindowsBootPlanner, not the generic guest planner."
        case .missingVirtualDisk:
            "The guest has no virtual disk path."
        case .missingFirmware(let detail):
            detail
        }
    }
}

/// The QEMU command line for a Linux Arm64 or emulated x86_64 guest.
///
/// Kept apart from `QEMUWindowsBootPlan` on purpose: the Windows plan carries the answer-file ISO,
/// the guest agent port forward, the SMB share, and installer workarounds that only make sense for
/// Windows Setup. A generic guest gets standard virtio devices and nothing that talks to an agent.
public struct QEMUGuestBootPlan: Codable, Equatable, Sendable {
    public var guestOS: VMGuestOS
    public var executablePath: String
    public var isExecutableAvailable: Bool
    public var accelerator: String
    public var firmwareCodePath: String
    public var firmwareVarsTemplatePath: String
    public var firmwareVarsPath: String
    public var isFirmwareAvailable: Bool
    public var tpmEmulatorPath: String?
    public var tpmStateDirectoryPath: String?
    public var options: QEMUGuestBootOptions
    public var arguments: [String]
    public var warnings: [String]

    public init(
        guestOS: VMGuestOS,
        executablePath: String,
        isExecutableAvailable: Bool,
        accelerator: String,
        firmwareCodePath: String,
        firmwareVarsTemplatePath: String,
        firmwareVarsPath: String,
        isFirmwareAvailable: Bool,
        tpmEmulatorPath: String?,
        tpmStateDirectoryPath: String?,
        options: QEMUGuestBootOptions,
        arguments: [String],
        warnings: [String]
    ) {
        self.guestOS = guestOS
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
        self.accelerator = accelerator
        self.firmwareCodePath = firmwareCodePath
        self.firmwareVarsTemplatePath = firmwareVarsTemplatePath
        self.firmwareVarsPath = firmwareVarsPath
        self.isFirmwareAvailable = isFirmwareAvailable
        self.tpmEmulatorPath = tpmEmulatorPath
        self.tpmStateDirectoryPath = tpmStateDirectoryPath
        self.options = options
        self.arguments = arguments
        self.warnings = warnings
    }

    /// Whether QEMU can be launched with this plan as it stands.
    public var isLaunchable: Bool {
        isExecutableAvailable && isFirmwareAvailable && (!options.tpm || tpmEmulatorPath != nil)
    }
}

/// Firmware a guest boots with. The code image is read-only; the variable store is copied per VM.
public struct QEMUGuestFirmware: Equatable, Sendable {
    public var codePath: String
    public var varsTemplatePath: String
    public var isAvailable: Bool

    public init(codePath: String, varsTemplatePath: String, isAvailable: Bool) {
        self.codePath = codePath
        self.varsTemplatePath = varsTemplatePath
        self.isAvailable = isAvailable
    }
}

public struct QEMUGuestBootPlanner: Sendable {
    /// Shown with every x86_64 plan. TCG translates each guest instruction, so the guest runs far
    /// slower than an Arm guest on Hypervisor.framework; see docs/architecture.md for measurements.
    public static let emulationPerformanceWarning =
        "x86_64 guests run under QEMU's TCG emulator, not Hypervisor.framework: expect a desktop many times slower than an Arm guest. Use it for installers, servers, and legacy tools, not daily desktop work."

    private let executablePath: String
    private let isExecutableAvailable: Bool
    private let firmware: QEMUGuestFirmware
    private let tpmEmulatorPath: String?
    private let options: QEMUGuestBootOptions

    public init(
        executablePath: String,
        isExecutableAvailable: Bool,
        firmware: QEMUGuestFirmware,
        tpmEmulatorPath: String? = nil,
        options: QEMUGuestBootOptions = QEMUGuestBootOptions()
    ) {
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
        self.firmware = firmware
        self.tpmEmulatorPath = tpmEmulatorPath
        self.options = options
    }

    public func makePlan(for profile: VMProfile) throws -> QEMUGuestBootPlan {
        let guestOS = profile.guestOS
        guard guestOS != .windows11Arm else {
            throw QEMUGuestBootPlanError.windowsUsesWindowsPlanner
        }
        guard let virtualDiskPath = Self.nonEmpty(profile.virtualDiskPath) else {
            throw QEMUGuestBootPlanError.missingVirtualDisk
        }

        let vmDirectory = URL(fileURLWithPath: virtualDiskPath).deletingLastPathComponent()
        let firmwareVarsPath = vmDirectory.appendingPathComponent("uefi-vars.fd").path
        let tpmStateDirectoryPath = options.tpm
            ? vmDirectory.appendingPathComponent("tpm", isDirectory: true).path
            : nil
        var warnings: [String] = []

        if !isExecutableAvailable {
            warnings.append("\(guestOS.qemuExecutableName) is not available at \(executablePath).")
        }
        if !firmware.isAvailable {
            warnings.append("UEFI firmware for \(guestOS.displayName) is not available at \(firmware.codePath).")
        }
        if options.tpm, tpmEmulatorPath == nil {
            warnings.append("A TPM was requested but swtpm was not found.")
        }

        let cpuCount = max(1, profile.cpuCount)
        let memoryMB = max(1_024, profile.memoryMB)
        let installerMediaPath = Self.nonEmpty(profile.installerMediaPath)
        var arguments: [String]

        switch guestOS {
        case .linuxArm64:
            arguments = [
                "-name", profile.name,
                "-machine", "virt,highmem=on",
                "-accel", "hvf",
                "-cpu", "host"
            ]
        case .x86_64:
            warnings.append(Self.emulationPerformanceWarning)
            if options.secureBoot {
                warnings.append(
                    "Secure Boot is not offered for x86_64 guests: Veil ships no x86 variable store with enrolled keys, so the guest boots with Secure Boot off."
                )
            }
            arguments = [
                "-name", profile.name,
                "-machine", "q35",
                // `thread=multi` gives each vCPU its own host thread. QEMU only allows it for an x86
                // guest on an Arm host because TCG inserts the barriers x86's stronger memory order
                // needs; without it every vCPU shares one thread.
                "-accel", "tcg,thread=multi,tb-size=512",
                "-cpu", "max"
            ]
        case .windows11Arm:
            throw QEMUGuestBootPlanError.windowsUsesWindowsPlanner
        }

        arguments.append(contentsOf: [
            "-smp", "\(cpuCount)",
            "-m", "\(memoryMB)M",
            "-drive", "if=pflash,format=raw,readonly=on,file=\(firmware.codePath)",
            "-drive", "if=pflash,format=raw,file=\(firmwareVarsPath)",
            // Disk first, installer second: an empty disk has no EFI system partition, so the
            // firmware falls through to the ISO. Once the installer writes a bootloader the disk wins
            // and the ISO can stay attached, the same order UTM uses.
            "-drive", "if=none,id=system,format=raw,file=\(virtualDiskPath),discard=unmap",
            "-device", "virtio-blk-pci,drive=system,bootindex=0",
            "-netdev", "user,id=net0",
            "-device", "virtio-net-pci,netdev=net0",
            "-device", "virtio-rng-pci",
            "-device", "qemu-xhci,id=usb0",
            "-device", "usb-kbd",
            "-device", "usb-tablet"
        ])

        switch guestOS {
        case .linuxArm64:
            // virt has no legacy display; virtio-gpu is what both the Arm UEFI firmware's GOP and the
            // Linux virtio_gpu driver drive.
            arguments.append(contentsOf: ["-device", "virtio-gpu-pci"])
        default:
            // Standard VGA works with OVMF and every x86 installer, including ones without virtio.
            arguments.append(contentsOf: ["-device", "VGA"])
        }

        if let installerMediaPath {
            // virtio-scsi rather than USB storage: both firmwares boot it and the installer reads the
            // ISO at full speed.
            arguments.append(contentsOf: [
                "-device", "virtio-scsi-pci,id=scsi0",
                "-drive", "if=none,id=installer,media=cdrom,readonly=on,file.locking=off,file=\(installerMediaPath)",
                "-device", "scsi-cd,bus=scsi0.0,drive=installer,bootindex=1"
            ])
        }

        if let tpmStateDirectoryPath, tpmEmulatorPath != nil {
            arguments.append(contentsOf: [
                "-chardev", "socket,id=chrtpm,path=\(tpmStateDirectoryPath)/swtpm.sock",
                "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
                // ppi=off for the same Hypervisor.framework page-size reason as the Windows plan.
                "-device", guestOS == .x86_64 ? "tpm-tis,tpmdev=tpm0" : "tpm-tis-device,tpmdev=tpm0,ppi=off"
            ])
        }

        return QEMUGuestBootPlan(
            guestOS: guestOS,
            executablePath: executablePath,
            isExecutableAvailable: isExecutableAvailable,
            accelerator: guestOS.usesHardwareVirtualization ? "hvf" : "tcg",
            firmwareCodePath: firmware.codePath,
            firmwareVarsTemplatePath: firmware.varsTemplatePath,
            firmwareVarsPath: firmwareVarsPath,
            isFirmwareAvailable: firmware.isAvailable,
            tpmEmulatorPath: options.tpm ? tpmEmulatorPath : nil,
            tpmStateDirectoryPath: tpmEmulatorPath != nil ? tpmStateDirectoryPath : nil,
            options: options,
            arguments: arguments,
            warnings: warnings
        )
    }

    static func nonEmpty(_ path: String?) -> String? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return path
    }
}

/// Resolves executables and firmware for a generic guest on this Mac: Veil's bundled runtime first,
/// then the same Homebrew prefixes the Windows path probes.
public enum LocalQEMUGuestBootPlanFactory {
    public static func makePlan(
        for profile: VMProfile,
        options: QEMUGuestBootOptions = QEMUGuestBootOptions(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledRuntimeDirectory: URL? = VeilBundledRuntime.directory(),
        fileExists: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> QEMUGuestBootPlan {
        let guestOS = profile.guestOS
        let prefixes = searchPrefixes(
            environment: environment,
            homeDirectory: homeDirectory,
            bundledRuntimeDirectory: bundledRuntimeDirectory
        )
        let executableCandidates = prefixes.map { $0.appendingPathComponent("bin/\(guestOS.qemuExecutableName)").path }
        let executablePath = executableCandidates.first(where: fileExists) ?? executableCandidates[0]
        let secureBoot = guestOS == .linuxArm64 && options.secureBoot
        var firmwareDirectories = prefixes.map { $0.appendingPathComponent("share/qemu", isDirectory: true) }
        if secureBoot {
            // Veil's Secure Boot build also lives here when the app was built without it.
            firmwareDirectories.insert(
                homeDirectory.appendingPathComponent("Library/Application Support/Veil/Firmware", isDirectory: true),
                at: min(1, firmwareDirectories.count)
            )
        }
        let firmware = resolveFirmware(
            for: guestOS,
            secureBoot: secureBoot,
            firmwareDirectories: firmwareDirectories,
            fileExists: fileExists
        )
        let tpmCandidates = [environment[LocalQEMUWindowsBootPlanFactory.tpmEmulatorEnvironmentKey]].compactMap { $0 }
            + LocalQEMUWindowsBootPlanFactory.tpmEmulatorPaths(
                environment: environment,
                homeDirectory: homeDirectory,
                bundledRuntimeDirectory: bundledRuntimeDirectory
            )
        let planner = QEMUGuestBootPlanner(
            executablePath: executablePath,
            isExecutableAvailable: fileExists(executablePath),
            firmware: firmware,
            tpmEmulatorPath: options.tpm ? tpmCandidates.first(where: fileExists) : nil,
            options: options
        )
        return try planner.makePlan(for: profile)
    }

    /// `<prefix>/bin/qemu-system-*` and `<prefix>/share/qemu/*` roots, most preferred first.
    static func searchPrefixes(
        environment: [String: String],
        homeDirectory: URL,
        bundledRuntimeDirectory: URL?
    ) -> [URL] {
        var prefixes: [URL] = []
        if let bundledRuntimeDirectory {
            prefixes.append(bundledRuntimeDirectory)
        }
        prefixes.append(homeDirectory.appendingPathComponent("Library/Application Support/Veil/Runtime", isDirectory: true))
        let packagePrefixes = ["/opt/homebrew", "/usr/local", "/opt/local"]
            + VMRuntimeProviderProbe.userPackagePrefixes(environment: environment, homeDirectory: homeDirectory)
        prefixes.append(contentsOf: packagePrefixes.map { URL(fileURLWithPath: $0, isDirectory: true) })
        return prefixes
    }

    /// The firmware pair a guest kind boots with.
    ///
    /// - Linux Arm64: QEMU's own `edk2-aarch64-code.fd`, or Veil's Secure Boot build whose variable
    ///   store enrolls Microsoft's third-party UEFI CA, which signs the shim of mainstream distributions.
    /// - x86_64: QEMU's `edk2-x86_64-code.fd` (OVMF) with the empty `edk2-i386-vars.fd` store.
    static func resolveFirmware(
        for guestOS: VMGuestOS,
        secureBoot: Bool,
        firmwareDirectories: [URL],
        fileExists: (String) -> Bool
    ) -> QEMUGuestFirmware {
        let pairs: [(code: String, vars: String)]
        switch guestOS {
        case .linuxArm64 where secureBoot:
            pairs = [("edk2-aarch64-secure-code.fd", "edk2-arm-secure-vars.fd")]
        case .linuxArm64, .windows11Arm:
            pairs = [("edk2-aarch64-code.fd", "edk2-arm-vars.fd")]
        case .x86_64:
            pairs = [("edk2-x86_64-code.fd", "edk2-i386-vars.fd")]
        }

        for pair in pairs {
            for root in firmwareDirectories {
                let code = root.appendingPathComponent(pair.code).path
                let vars = root.appendingPathComponent(pair.vars).path
                if fileExists(code), fileExists(vars) {
                    return QEMUGuestFirmware(codePath: code, varsTemplatePath: vars, isAvailable: true)
                }
            }
        }

        let fallback = pairs[0]
        let root = firmwareDirectories.first ?? URL(fileURLWithPath: "/opt/homebrew/share/qemu", isDirectory: true)
        return QEMUGuestFirmware(
            codePath: root.appendingPathComponent(fallback.code).path,
            varsTemplatePath: root.appendingPathComponent(fallback.vars).path,
            isAvailable: false
        )
    }
}
