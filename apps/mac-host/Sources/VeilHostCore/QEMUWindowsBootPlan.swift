import Darwin
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
    public var firmwareVarsTemplatePath: String?
    public var isFirmwareVarsTemplateAvailable: Bool
    public var firmwareVarsPath: String?
    public var isSecureBootFirmwareAvailable: Bool
    public var tpmEmulatorPath: String?
    public var isTPMEmulatorAvailable: Bool
    public var tpmStateDirectoryPath: String?
    public var automaticInstallMediaPath: String?
    public var networkAdapter: QEMUWindowsNetworkAdapter
    public var networkDeviceArgument: String
    public var audioDevice: QEMUWindowsAudioDevice
    public var audioBackendArgument: String?
    public var sharedFolderTransport: QEMUWindowsSharedFolderTransport
    /// The `hostfwd=` clause the shared folder needs, or `nil` when the transport does not use one or
    /// the host port was unavailable when this plan was built.
    public var sharedFolderForwardClause: String?
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
        firmwareVarsTemplatePath: String? = nil,
        isFirmwareVarsTemplateAvailable: Bool = false,
        firmwareVarsPath: String? = nil,
        isSecureBootFirmwareAvailable: Bool = false,
        tpmEmulatorPath: String? = nil,
        isTPMEmulatorAvailable: Bool = false,
        tpmStateDirectoryPath: String? = nil,
        automaticInstallMediaPath: String? = nil,
        networkAdapter: QEMUWindowsNetworkAdapter = .usbNet,
        networkDeviceArgument: String = QEMUWindowsNetworkAdapter.usbNet.deviceArgument,
        audioDevice: QEMUWindowsAudioDevice = .intelHDA,
        audioBackendArgument: String? = QEMUWindowsAudioDevice.intelHDA.backendArgument,
        sharedFolderTransport: QEMUWindowsSharedFolderTransport = .guestSMB,
        sharedFolderForwardClause: String? = QEMUWindowsSharedFolderTransport.guestSMB.hostForwardClause,
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
        self.firmwareVarsTemplatePath = firmwareVarsTemplatePath
        self.isFirmwareVarsTemplateAvailable = isFirmwareVarsTemplateAvailable
        self.firmwareVarsPath = firmwareVarsPath
        self.isSecureBootFirmwareAvailable = isSecureBootFirmwareAvailable
        self.tpmEmulatorPath = tpmEmulatorPath
        self.isTPMEmulatorAvailable = isTPMEmulatorAvailable
        self.tpmStateDirectoryPath = tpmStateDirectoryPath
        self.automaticInstallMediaPath = automaticInstallMediaPath
        self.networkAdapter = networkAdapter
        self.networkDeviceArgument = networkDeviceArgument
        self.audioDevice = audioDevice
        self.audioBackendArgument = audioBackendArgument
        self.sharedFolderTransport = sharedFolderTransport
        self.sharedFolderForwardClause = sharedFolderForwardClause
        self.summary = summary
        self.arguments = arguments
        self.warnings = warnings
    }
}

public enum QEMUWindowsNetworkAdapter: String, Codable, CaseIterable, Equatable, Sendable {
    case usbNet = "usb-net"
    case e1000 = "e1000"
    case e1000e = "e1000e"
    case rtl8139 = "rtl8139"
    case vmxnet3 = "vmxnet3"
    case virtioNetPCI = "virtio-net-pci"
    case virtioNetDevice = "virtio-net-device"

    public static let environmentVariableName = "VEIL_QEMU_NETWORK_DEVICE"

    public struct Selection: Equatable, Sendable {
        public var adapter: QEMUWindowsNetworkAdapter
        public var warning: String?
        public var isExplicit: Bool

        public init(adapter: QEMUWindowsNetworkAdapter, warning: String?, isExplicit: Bool) {
            self.adapter = adapter
            self.warning = warning
            self.isExplicit = isExplicit
        }
    }

    public var deviceArgument: String {
        "\(rawValue),netdev=net0"
    }

    public static func selected(
        from rawValue: String?
    ) -> Selection {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Selection(adapter: .usbNet, warning: nil, isExplicit: false)
        }

        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let adapter = QEMUWindowsNetworkAdapter(rawValue: normalizedValue) {
            return Selection(adapter: adapter, warning: nil, isExplicit: true)
        }

        let supportedValues = QEMUWindowsNetworkAdapter.allCases
            .map(\.rawValue)
            .joined(separator: ", ")
        return Selection(
            adapter: .usbNet,
            warning: "Ignoring unsupported \(environmentVariableName)=\(normalizedValue). Supported values: \(supportedValues).",
            isExplicit: true
        )
    }
}

/// Sound device attached to the Windows guest.
///
/// Veil shipped without any audio device at all, which made a Parallels-class comparison fail on the
/// first video call or media tab. `intelHDA` is the default because Windows on ARM includes a native
/// HD Audio class driver and the duplex codec provides playback and capture in one device.
///
/// `none` exists on purpose: a QEMU build without CoreAudio support fails to start when an audio
/// backend is requested, so a user has to be able to turn sound off without rebuilding QEMU.
public enum QEMUWindowsAudioDevice: String, Codable, CaseIterable, Equatable, Sendable {
    case intelHDA = "intel-hda"
    /// Routed through the `qemu-xhci` controller the plan already creates, for hosts where the
    /// emulated HD Audio controller misbehaves under Windows on ARM.
    case usbAudio = "usb-audio"
    /// Named `disabled` rather than `none` so it can never be confused with `Optional.none` at a call
    /// site. The wire and environment value stays `none`.
    case disabled = "none"

    public static let environmentVariableName = "VEIL_QEMU_AUDIO_DEVICE"
    public static let audioBackendId = "veilaudio"

    public struct Selection: Equatable, Sendable {
        public var device: QEMUWindowsAudioDevice
        public var warning: String?
        public var isExplicit: Bool

        public init(device: QEMUWindowsAudioDevice, warning: String?, isExplicit: Bool) {
            self.device = device
            self.warning = warning
            self.isExplicit = isExplicit
        }
    }

    public var isEnabled: Bool {
        self != .disabled
    }

    /// macOS host backend. CoreAudio is the only sensible choice on a Mac host; it stays a computed
    /// property so a future Linux/CI host could return a different backend without touching callers.
    public var backendArgument: String? {
        isEnabled ? "coreaudio,id=\(Self.audioBackendId)" : nil
    }

    /// QEMU device arguments for this sound device, in the order they must be appended.
    ///
    /// `intel-hda` needs two entries: the controller and the codec that carries the audiodev binding.
    /// `usb-audio` is a single device on the existing USB controller.
    public var deviceArguments: [String] {
        switch self {
        case .intelHDA:
            ["-device", "intel-hda", "-device", "hda-duplex,audiodev=\(Self.audioBackendId)"]
        case .usbAudio:
            ["-device", "usb-audio,audiodev=\(Self.audioBackendId)"]
        case .disabled:
            []
        }
    }

    public static func selected(from rawValue: String?) -> Selection {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Selection(device: .intelHDA, warning: nil, isExplicit: false)
        }

        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let device = QEMUWindowsAudioDevice(rawValue: normalizedValue) {
            return Selection(device: device, warning: nil, isExplicit: true)
        }

        let supportedValues = QEMUWindowsAudioDevice.allCases
            .map(\.rawValue)
            .joined(separator: ", ")
        return Selection(
            device: .intelHDA,
            warning: "Ignoring unsupported \(environmentVariableName)=\(normalizedValue). Supported values: \(supportedValues).",
            isExplicit: true
        )
    }
}

public enum QEMUWindowsBootDisplayMode: String, Codable, Equatable, Sendable {
    case nativeCocoa
    case headless
    case vncLoopback
}

/// Probes the display backends compiled into the selected QEMU binary.
///
/// QEMU distributions are not interchangeable here: the UTM-bundled Arm binary used by Veil may
/// expose VNC and `none` while omitting the Cocoa backend. Checking `-display help` before launching
/// prevents a misleading "started" state and avoids starting a TPM daemon for a VM that will fail
/// before it creates a display.
public enum QEMUDisplayBackendProbe {
    public static func availableBackends(in helpOutput: String) -> [String] {
        var backends: [String] = []
        var isBackendSection = false

        for rawLine in helpOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "Available display backend types:" {
                isBackendSection = true
                continue
            }
            guard isBackendSection else {
                continue
            }
            if line.isEmpty {
                break
            }
            if line.hasPrefix("Some display backends") || line.hasPrefix("-display") {
                continue
            }
            let backend = line.split(separator: ",", maxSplits: 1).first.map(String.init) ?? line
            guard !backend.isEmpty,
                  !backend.contains(where: { $0.isWhitespace }) else {
                continue
            }
            backends.append(backend)
        }

        return backends
    }

    public static func supportsBackend(_ backend: String, in helpOutput: String) -> Bool {
        availableBackends(in: helpOutput).contains(backend)
    }

    public static func availableBackends(executablePath: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-display", "help"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        return availableBackends(
            in: String(
                decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }
}

public struct QEMUWindowsBootPlanner: Sendable {
    public static let guestAgentHostPort = 18_444
    public static let guestAgentGuestPort = 18_444

    private let executablePath: String
    private let isExecutableAvailable: Bool
    private let firmwarePath: String?
    private let isFirmwareAvailable: Bool
    private let firmwareVarsTemplatePath: String?
    private let isFirmwareVarsTemplateAvailable: Bool
    private let firmwareVarsPath: String?
    private let isSecureBootFirmwareAvailable: Bool
    private let tpmEmulatorPath: String?
    private let isTPMEmulatorAvailable: Bool
    private let tpmStateDirectoryPath: String?
    private let networkAdapter: QEMUWindowsNetworkAdapter
    private let audioDevice: QEMUWindowsAudioDevice
    private let sharedFolderTransport: QEMUWindowsSharedFolderTransport
    /// Whether the shared folder's host port was free when the plan was built. A busy port drops the
    /// forward instead of leaving it in the command line, because QEMU refuses to start when it cannot
    /// bind a `hostfwd` port and a shared folder is not worth trading a bootable VM for.
    private let isSharedFolderHostPortAvailable: Bool
    private let configurationWarnings: [String]

    public init(
        executablePath: String,
        isExecutableAvailable: Bool,
        firmwarePath: String? = nil,
        isFirmwareAvailable: Bool = false,
        firmwareVarsTemplatePath: String? = nil,
        isFirmwareVarsTemplateAvailable: Bool = false,
        firmwareVarsPath: String? = nil,
        isSecureBootFirmwareAvailable: Bool = false,
        tpmEmulatorPath: String? = nil,
        isTPMEmulatorAvailable: Bool = false,
        tpmStateDirectoryPath: String? = nil,
        networkAdapter: QEMUWindowsNetworkAdapter = .usbNet,
        audioDevice: QEMUWindowsAudioDevice = .intelHDA,
        sharedFolderTransport: QEMUWindowsSharedFolderTransport = .guestSMB,
        isSharedFolderHostPortAvailable: Bool = true,
        configurationWarnings: [String] = []
    ) {
        self.executablePath = executablePath
        self.isExecutableAvailable = isExecutableAvailable
        self.firmwarePath = firmwarePath
        self.isFirmwareAvailable = isFirmwareAvailable
        self.firmwareVarsTemplatePath = firmwareVarsTemplatePath
        self.isFirmwareVarsTemplateAvailable = isFirmwareVarsTemplateAvailable
        self.firmwareVarsPath = firmwareVarsPath
        self.isSecureBootFirmwareAvailable = isSecureBootFirmwareAvailable
        self.tpmEmulatorPath = tpmEmulatorPath
        self.isTPMEmulatorAvailable = isTPMEmulatorAvailable
        self.tpmStateDirectoryPath = tpmStateDirectoryPath
        self.networkAdapter = networkAdapter
        self.audioDevice = audioDevice
        self.sharedFolderTransport = sharedFolderTransport
        self.isSharedFolderHostPortAvailable = isSharedFolderHostPortAvailable
        self.configurationWarnings = configurationWarnings
    }

    public func makePlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        let windowsInstalled = profile.windowsInstalled == true
        let shouldAttachInstallerMedia = !windowsInstalled
        // Windows always boots from the system disk after installation, but the separate
        // VEIL_AUTO support ISO must remain read-only attached so agent repair and updates can
        // reach an already-installed guest without reattaching the Windows installer ISO.
        let installerMediaPath = nonEmpty(profile.installerMediaPath)

        guard !shouldAttachInstallerMedia || installerMediaPath != nil else {
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
        let driverMediaPath = nonEmpty(profile.driverMediaPath)
        var warnings = configurationWarnings

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

        if let firmwareVarsTemplatePath, !isFirmwareVarsTemplateAvailable {
            warnings.append(
                "QEMU Arm UEFI variable template is not available at \(firmwareVarsTemplatePath). Install QEMU from Homebrew or point Veil at an edk2-arm-vars.fd file."
            )
        }

        var arguments = [
            "-name", profile.name,
            "-machine", "virt,highmem=on",
            "-accel", "hvf"
        ]

        if let firmwarePath, let firmwareVarsPath {
            arguments.append(contentsOf: [
                "-drive", "if=pflash,format=raw,readonly=on,file=\(firmwarePath)",
                "-drive", "if=pflash,format=raw,file=\(firmwareVarsPath)"
            ])
        } else if let firmwarePath {
            arguments.append(contentsOf: ["-bios", firmwarePath])
        }

        if let tpmStateDirectoryPath {
            arguments.append(contentsOf: [
                "-chardev", "socket,id=chrtpm,path=\(tpmStateDirectoryPath)/swtpm.sock",
                "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
                "-device", "tpm-tis-device,tpmdev=tpm0"
            ])
        }

        // Bound to 127.0.0.1 rather than every interface. An empty host address in a `hostfwd` clause
        // binds all of them, which published the guest agent's control channel -- app launch,
        // synthesized input, clipboard read/write, all unauthenticated -- to the local network. The host
        // has always connected over ws://127.0.0.1:18444, so nothing legitimate needed the wider bind.
        let guestAgentForward = "hostfwd=tcp:\(QEMUWindowsSharedFolderTransport.hostForwardAddress):\(Self.guestAgentHostPort)-:\(Self.guestAgentGuestPort)"

        // Forwards are collected into the single existing netdev instead of adding a second one, so the
        // guest keeps exactly one NIC no matter how many host ports are mapped into it.
        var userNetworkForwards = [guestAgentForward]
        if let sharedFolderForward = sharedFolderTransport.hostForwardClause,
           isSharedFolderHostPortAvailable {
            userNetworkForwards.append(sharedFolderForward)
        }

        if sharedFolderTransport.hostForwardClause != nil, !isSharedFolderHostPortAvailable {
            warnings.append(
                "Host port \(QEMUWindowsSharedFolderTransport.guestSMBHostPort) was unavailable when this plan was built, so the shared folder port forward was left out and Windows will boot without a live shared folder. A Veil VM that is already running holds this port, which is the usual reason; otherwise find the listener with `lsof -nP -iTCP:\(QEMUWindowsSharedFolderTransport.guestSMBHostPort) -sTCP:LISTEN`."
            )
        }

        arguments.append(contentsOf: [
            "-boot", windowsInstalled ? "order=c" : "order=d",
            "-cpu", "host",
            "-smp", "\(cpuCount)",
            "-m", "\(memoryMB)M",
            "-device", "qemu-xhci,id=usb0",
            "-drive", "if=none,id=system,format=raw,file=\(virtualDiskPath)",
            "-device", "nvme,drive=system,serial=veil-system",
            "-netdev", "user,id=net0,\(userNetworkForwards.joined(separator: ","))",
            "-device", networkAdapter.deviceArgument,
            "-device", "virtio-rng-pci",
            "-display", "cocoa",
            "-device", "ramfb",
            "-device", "virtio-gpu-pci",
            "-device", "usb-kbd",
            "-device", "usb-tablet"
        ])

        // Audio is appended after the USB controller exists, because `usb-audio` attaches to it. The
        // backend has to precede the device that references its id.
        if let audioBackendArgument = audioDevice.backendArgument {
            arguments.append(contentsOf: ["-audiodev", audioBackendArgument])
            arguments.append(contentsOf: audioDevice.deviceArguments)
        }

        if let installerMediaPath, shouldAttachInstallerMedia {
            arguments.append(contentsOf: [
                "-drive", "driver=raw,file.driver=file,file.locking=off,file.filename=\(installerMediaPath),if=none,id=installer,media=cdrom,readonly=on",
                "-device", "usb-storage,drive=installer"
            ])
        }

        arguments.append(contentsOf: [
            "-drive", "driver=raw,file.driver=file,file.locking=off,file.filename=\(automaticInstallMediaPath),if=none,id=autounattend,media=cdrom,readonly=on",
            "-device", "usb-storage,drive=autounattend"
        ])

        if let driverMediaPath {
            arguments.append(contentsOf: [
                "-drive", "driver=raw,file.driver=file,file.locking=off,file.filename=\(driverMediaPath),if=none,id=drivers,media=cdrom,readonly=on",
                "-device", "usb-storage,drive=drivers"
            ])
        }

        return QEMUWindowsBootPlan(
            executablePath: executablePath,
            isExecutableAvailable: isExecutableAvailable,
            firmwarePath: firmwarePath,
            isFirmwareAvailable: isFirmwareAvailable,
            firmwareVarsTemplatePath: firmwareVarsTemplatePath,
            isFirmwareVarsTemplateAvailable: isFirmwareVarsTemplateAvailable,
            firmwareVarsPath: firmwareVarsPath,
            isSecureBootFirmwareAvailable: isSecureBootFirmwareAvailable,
            tpmEmulatorPath: tpmEmulatorPath,
            isTPMEmulatorAvailable: isTPMEmulatorAvailable,
            tpmStateDirectoryPath: tpmStateDirectoryPath,
            automaticInstallMediaPath: automaticInstallMediaPath,
            networkAdapter: networkAdapter,
            networkDeviceArgument: networkAdapter.deviceArgument,
            audioDevice: audioDevice,
            audioBackendArgument: audioDevice.backendArgument,
            sharedFolderTransport: sharedFolderTransport,
            sharedFolderForwardClause: isSharedFolderHostPortAvailable
                ? sharedFolderTransport.hostForwardClause
                : nil,
            summary: windowsInstalled
                ? "Dry-run QEMU/HVF command plan for \(profile.name). Windows boots from the installed system disk; the Windows installer ISO is detached and read-only Veil guest support media stays attached."
                : "Dry-run QEMU/HVF command plan for \(profile.name). Veil does not execute this plan yet.",
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
    public static let tpmEmulatorEnvironmentKey = "VEIL_SWTPM"
    public static let defaultFirmwarePaths = [
        "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
        "/usr/local/share/qemu/edk2-aarch64-code.fd",
        "/opt/local/share/qemu/edk2-aarch64-code.fd"
    ]
    public static func defaultSecureFirmwarePaths(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        [
            homeDirectory
                .appendingPathComponent("Library/Application Support/Veil/Firmware", isDirectory: true)
                .appendingPathComponent("edk2-aarch64-secure-code.fd")
                .path,
            "/Applications/UTM.app/Contents/Resources/qemu/edk2-aarch64-secure-code.fd",
            "/Applications/UTM.app/Contents/Resources/edk2-aarch64-secure-code.fd",
            "/Applications/UTM.app/Contents/Frameworks/QEMU.framework/Resources/edk2-aarch64-secure-code.fd",
            "/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd",
            "/usr/local/share/qemu/edk2-aarch64-secure-code.fd",
            "/opt/local/share/qemu/edk2-aarch64-secure-code.fd"
        ]
    }
    public static let defaultFirmwareVarsTemplatePaths = [
        "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
        "/usr/local/share/qemu/edk2-arm-vars.fd",
        "/opt/local/share/qemu/edk2-arm-vars.fd"
    ]
    public static func defaultSecureFirmwareVarsTemplatePaths(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        [
            homeDirectory
                .appendingPathComponent("Library/Application Support/Veil/Firmware", isDirectory: true)
                .appendingPathComponent("edk2-arm-secure-vars.fd")
                .path,
            "/Applications/UTM.app/Contents/Resources/qemu/edk2-arm-secure-vars.fd",
            "/Applications/UTM.app/Contents/Resources/edk2-arm-secure-vars.fd",
            "/Applications/UTM.app/Contents/Frameworks/QEMU.framework/Resources/edk2-arm-secure-vars.fd"
        ]
    }
    public static let defaultTPMEmulatorPaths = [
        "/opt/homebrew/bin/swtpm",
        "/usr/local/bin/swtpm",
        "/opt/local/bin/swtpm"
    ]

    public static func tpmEmulatorPaths(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        [
            homeDirectory
                .appendingPathComponent("Library/Application Support/Veil/Runtime/bin", isDirectory: true)
                .appendingPathComponent("swtpm")
                .path
        ] + defaultTPMEmulatorPaths
    }

    /// Whether a loopback TCP port can still be bound.
    ///
    /// A direct `bind` rather than shelling out to `lsof`, because plan building sits on status-polling
    /// paths where spawning a subprocess per call would be a needless cost. `SO_REUSEADDR` is
    /// deliberately not set: the question being asked is exactly the one QEMU will ask at startup, and
    /// answering it more permissively than QEMU does would defeat the point.
    public static let isLoopbackPortFree: @Sendable (Int) -> Bool = { port in
        guard port > 0, port <= 65_535 else {
            return false
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else {
            // The probe itself failed. Reporting the port as free keeps a transient host resource
            // problem from silently turning folder sharing off.
            return true
        }
        defer {
            close(descriptor)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr(QEMUWindowsSharedFolderTransport.hostForwardAddress)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                Darwin.bind(descriptor, addressPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return bindResult == 0
    }

    public static func makePlan(
        for profile: VMProfile,
        architecture: String,
        minimumOSSupported: Bool,
        providerProbe: VMRuntimeProviderProbe = VMRuntimeProviderProbe(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        secureFirmwarePaths: [String] = defaultSecureFirmwarePaths(),
        secureVarsTemplatePaths: [String] = defaultSecureFirmwareVarsTemplatePaths(),
        firmwareVarsTemplatePaths: [String] = defaultFirmwareVarsTemplatePaths,
        isHostPortFree: @escaping @Sendable (Int) -> Bool = LocalQEMUWindowsBootPlanFactory.isLoopbackPortFree,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> QEMUWindowsBootPlan {
        let qemuProvider = providerProbe
            .localProviders(
                architecture: architecture,
                minimumOSSupported: minimumOSSupported
            )
            .first { $0.kind == .qemuHypervisor }
        let executablePath = qemuProvider?.executablePath
            ?? VMRuntimeProviderProbe.qemuExecutablePaths(homeDirectory: homeDirectory)[0]
        let secureFirmwarePath = secureFirmwarePaths.first(where: fileExists)
        let secureFirmwareVarsTemplatePath = secureVarsTemplatePaths.first(where: fileExists)
        let isSecureBootFirmwareAvailable = secureFirmwarePath != nil && secureFirmwareVarsTemplatePath != nil
        let firmwarePath = (secureFirmwareVarsTemplatePath != nil ? secureFirmwarePath : nil)
            ?? defaultFirmwarePaths.first(where: fileExists)
        let firmwareVarsTemplatePath = secureFirmwareVarsTemplatePath
            ?? firmwareVarsTemplatePaths.first(where: fileExists)
        let fallbackFirmwareVarsTemplatePath = secureVarsTemplatePaths.first
            ?? firmwareVarsTemplatePaths.first
            ?? defaultFirmwareVarsTemplatePaths[0]
        let firmwareVarsPath = profile.virtualDiskPath
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("uefi-vars.fd").path }
        let tpmEmulatorCandidates = [environment[tpmEmulatorEnvironmentKey]]
            .compactMap { path in
                guard let path,
                      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return path
            }
            + tpmEmulatorPaths(homeDirectory: homeDirectory)
        let tpmEmulatorPath = tpmEmulatorCandidates.first(where: fileExists)
        let tpmStateDirectoryPath = profile.virtualDiskPath
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("tpm", isDirectory: true).path }
        let networkSelection = QEMUWindowsNetworkAdapter.selected(
            from: environment[QEMUWindowsNetworkAdapter.environmentVariableName]
        )
        var configurationWarnings = networkSelection.warning.map { [$0] } ?? []
        let hasDriverMedia = profile.driverMediaPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        // The inbox Windows ARM image does not reliably expose a usable IP address through
        // usb-net. When the user has attached the VirtIO driver ISO, select the matching NIC
        // automatically so one-click setup can install the driver and bring up the agent without
        // requiring an environment variable. An explicit override remains authoritative for
        // compatibility probes and alternate driver images.
        let networkAdapter: QEMUWindowsNetworkAdapter = hasDriverMedia && !networkSelection.isExplicit
            ? .virtioNetPCI
            : networkSelection.adapter
        if hasDriverMedia && !networkSelection.isExplicit {
            configurationWarnings.append(
                "Using virtio-net-pci because driver media is configured; set \(QEMUWindowsNetworkAdapter.environmentVariableName) to override it for a compatibility probe."
            )
        }
        let audioSelection = QEMUWindowsAudioDevice.selected(
            from: environment[QEMUWindowsAudioDevice.environmentVariableName]
        )
        if let audioWarning = audioSelection.warning {
            configurationWarnings.append(audioWarning)
        }
        if audioSelection.device == .disabled {
            configurationWarnings.append(
                "Windows guest audio is disabled by \(QEMUWindowsAudioDevice.environmentVariableName)=none. Windows will have no sound device."
            )
        }
        let sharedFolderSelection = QEMUWindowsSharedFolderTransport.selected(
            from: environment[QEMUWindowsSharedFolderTransport.environmentVariableName]
        )
        if let sharedFolderWarning = sharedFolderSelection.warning {
            configurationWarnings.append(sharedFolderWarning)
        }
        if sharedFolderSelection.transport == .hostSMB {
            configurationWarnings.append(
                "\(QEMUWindowsSharedFolderTransport.environmentVariableName)=host-smb needs File Sharing turned on in macOS System Settings, and it publishes the share on every network interface rather than only to the guest. Veil adds no port forward for this transport."
            )
        }
        if sharedFolderSelection.transport == .disabled {
            configurationWarnings.append(
                "Live folder sharing is disabled by \(QEMUWindowsSharedFolderTransport.environmentVariableName)=none. Files reach Windows only through drag-and-drop file open, which is capped at 50 MB."
            )
        }
        // Probed rather than assumed: QEMU exits at startup when it cannot bind a `hostfwd` port, so an
        // occupied port has to drop the forward instead of the whole VM.
        let isSharedFolderHostPortAvailable = sharedFolderSelection.transport.hostForwardClause == nil
            || isHostPortFree(QEMUWindowsSharedFolderTransport.guestSMBHostPort)
        let planner = QEMUWindowsBootPlanner(
            executablePath: executablePath,
            isExecutableAvailable: qemuProvider?.status == .active && qemuProvider?.executablePath != nil,
            firmwarePath: firmwarePath ?? defaultFirmwarePaths[0],
            isFirmwareAvailable: firmwarePath != nil,
            firmwareVarsTemplatePath: firmwareVarsTemplatePath ?? fallbackFirmwareVarsTemplatePath,
            isFirmwareVarsTemplateAvailable: firmwareVarsTemplatePath != nil,
            firmwareVarsPath: firmwareVarsPath,
            isSecureBootFirmwareAvailable: isSecureBootFirmwareAvailable,
            tpmEmulatorPath: tpmEmulatorPath ?? tpmEmulatorCandidates[0],
            isTPMEmulatorAvailable: tpmEmulatorPath != nil,
            tpmStateDirectoryPath: tpmStateDirectoryPath,
            networkAdapter: networkAdapter,
            audioDevice: audioSelection.device,
            sharedFolderTransport: sharedFolderSelection.transport,
            isSharedFolderHostPortAvailable: isSharedFolderHostPortAvailable,
            configurationWarnings: configurationWarnings
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
            automaticInstallMediaCheck(profile: profile, plan: plan),
            systemDiskCheck(profile),
            qemuExecutableCheck(plan),
            uefiFirmwareCheck(plan),
            secureBootCheck(plan),
            tpmEmulatorCheck(plan),
            hvfPlanCheck(plan),
            sharedFolderCheck(plan)
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
        if profile?.windowsInstalled == true {
            guard let diskPath = nonEmpty(profile?.virtualDiskPath), fileExists(diskPath) else {
                let diskDescription = nonEmpty(profile?.virtualDiskPath)
                    .map { " at \($0)" } ?? ""
                return QEMUWindowsReadinessCheck(
                    id: "installer-media",
                    title: "Installer media",
                    state: .blocked,
                    detail: "Windows is marked installed, but its system disk is missing\(diskDescription). Re-run prepare with a Windows installer ISO to recover the VM."
                )
            }

            return QEMUWindowsReadinessCheck(
                id: "installer-media",
                title: "Installer media",
                state: .passed,
                detail: "Windows is installed on the system disk; the installer ISO is no longer required for boot."
            )
        }

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

    private func automaticInstallMediaCheck(profile: VMProfile?, plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
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
            detail: "Read-only Veil guest support media is available at \(path) for install, repair, and agent updates."
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

    /// Never returns `.blocked`. A missing shared folder is a lost convenience, not a reason to refuse
    /// to boot Windows, and `makeReport` turns any blocked check into a blocked overall state.
    private func sharedFolderCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        let title = "Live shared folder"

        guard let plan else {
            return QEMUWindowsReadinessCheck(
                id: "shared-folder",
                title: title,
                state: .warning,
                detail: "QEMU command plan is unavailable, so the shared folder port forward cannot be confirmed."
            )
        }

        switch plan.sharedFolderTransport {
        case .disabled:
            return QEMUWindowsReadinessCheck(
                id: "shared-folder",
                title: title,
                state: .warning,
                detail: "Live folder sharing is off via \(QEMUWindowsSharedFolderTransport.environmentVariableName)=none. Files reach Windows only through drag-and-drop file open, which is capped at 50 MB."
            )

        case .hostSMB:
            return QEMUWindowsReadinessCheck(
                id: "shared-folder",
                title: title,
                state: .warning,
                detail: "Configured for host-served SMB, which needs File Sharing turned on in macOS System Settings and publishes the share on every network interface. Veil adds no port forward for this transport."
            )

        case .guestSMB:
            guard let clause = plan.sharedFolderForwardClause,
                  plan.arguments.contains(where: { $0.contains(clause) }) else {
                return QEMUWindowsReadinessCheck(
                    id: "shared-folder",
                    title: title,
                    state: .warning,
                    detail: "Host port \(QEMUWindowsSharedFolderTransport.guestSMBHostPort) was unavailable when this plan was built, so Windows will boot without a live shared folder. A Veil VM that is already running holds this port, which is the usual reason."
                )
            }

            return QEMUWindowsReadinessCheck(
                id: "shared-folder",
                title: title,
                state: .passed,
                detail: "Windows shares \(QEMUWindowsSharedFolderTransport.guestDirectoryPath) as \(QEMUWindowsSharedFolderTransport.shareName); mount it on this Mac from \(QEMUWindowsSharedFolderTransport.guestSMB.hostMountURL ?? "smb://") once Windows is running."
            )
        }
    }

    private func tpmEmulatorCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        guard let plan else {
            return QEMUWindowsReadinessCheck(
                id: "tpm-emulator",
                title: "TPM 2.0 emulator",
                state: .blocked,
                detail: "QEMU command plan is unavailable."
            )
        }

        guard let tpmEmulatorPath = plan.tpmEmulatorPath,
              !tpmEmulatorPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return QEMUWindowsReadinessCheck(
                id: "tpm-emulator",
                title: "TPM 2.0 emulator",
                state: .blocked,
                detail: "No swtpm executable path is configured."
            )
        }

        guard plan.isTPMEmulatorAvailable, fileExists(tpmEmulatorPath) else {
            return QEMUWindowsReadinessCheck(
                id: "tpm-emulator",
                title: "TPM 2.0 emulator",
                state: .blocked,
                detail: "swtpm is not available at \(tpmEmulatorPath)."
            )
        }

        guard let tpmStateDirectoryPath = plan.tpmStateDirectoryPath,
              fileExists(tpmStateDirectoryPath) else {
            return QEMUWindowsReadinessCheck(
                id: "tpm-emulator",
                title: "TPM 2.0 emulator",
                state: .blocked,
                detail: "TPM state directory is missing."
            )
        }

        guard plan.arguments.containsSequence(["-tpmdev", "emulator,id=tpm0,chardev=chrtpm"]),
              plan.arguments.containsSequence(["-device", "tpm-tis-device,tpmdev=tpm0"]) else {
            return QEMUWindowsReadinessCheck(
                id: "tpm-emulator",
                title: "TPM 2.0 emulator",
                state: .blocked,
                detail: "QEMU command plan does not attach a TPM 2.0 emulator device."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "tpm-emulator",
            title: "TPM 2.0 emulator",
            state: .passed,
            detail: "swtpm is available and the QEMU command plan attaches a TPM 2.0 emulator."
        )
    }

    private func secureBootCheck(_ plan: QEMUWindowsBootPlan?) -> QEMUWindowsReadinessCheck {
        guard let plan else {
            return QEMUWindowsReadinessCheck(
                id: "secure-boot",
                title: "Secure Boot firmware",
                state: .blocked,
                detail: "QEMU command plan is unavailable."
            )
        }

        if !plan.isSecureBootFirmwareAvailable,
           plan.firmwareVarsTemplatePath?.hasSuffix("edk2-arm-secure-vars.fd") == true {
            return QEMUWindowsReadinessCheck(
                id: "secure-boot",
                title: "Secure Boot firmware",
                state: .warning,
                detail: "AArch64 EDK2 secure variable template is available, but matching edk2-aarch64-secure-code.fd is missing."
            )
        }

        guard plan.isSecureBootFirmwareAvailable else {
            return QEMUWindowsReadinessCheck(
                id: "secure-boot",
                title: "Secure Boot firmware",
                state: .warning,
                detail: "The local AArch64 EDK2 firmware does not advertise secure-boot; Windows Setup may still report Secure Boot unsupported."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "secure-boot",
            title: "Secure Boot firmware",
            state: .warning,
            detail: "AArch64 EDK2 secure variable template is available, but Secure Boot is not proven until a live Windows setup smoke passes the requirement check."
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

        guard let firmwareVarsTemplatePath = plan.firmwareVarsTemplatePath else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "No Arm UEFI variable template path is configured."
            )
        }

        guard let firmwareVarsPath = plan.firmwareVarsPath else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "No writable Arm UEFI variable store path is configured."
            )
        }

        guard plan.isFirmwareVarsTemplateAvailable, fileExists(firmwareVarsTemplatePath) else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "Arm UEFI variable template is not available at \(firmwareVarsTemplatePath)."
            )
        }

        guard fileExists(firmwareVarsPath) else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "Writable Arm UEFI variable store is missing at \(firmwareVarsPath)."
            )
        }

        guard plan.arguments.containsSequence(["-drive", "if=pflash,format=raw,readonly=on,file=\(firmwarePath)"]),
              plan.arguments.containsSequence(["-drive", "if=pflash,format=raw,file=\(firmwareVarsPath)"]) else {
            return QEMUWindowsReadinessCheck(
                id: "uefi-firmware",
                title: "Arm UEFI firmware",
                state: .blocked,
                detail: "QEMU command plan does not attach Arm UEFI firmware and variables as pflash drives."
            )
        }

        return QEMUWindowsReadinessCheck(
            id: "uefi-firmware",
            title: "Arm UEFI firmware",
            state: .passed,
            detail: "Arm UEFI firmware and writable variable store are available."
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
            actions.append("Install QEMU from Homebrew or point Veil at edk2-aarch64-code.fd and edk2-arm-vars.fd before launching Windows setup.")
            actions.append("Run veil-vmctl prepare --installer /path/to/Windows.iso to create Veil's writable UEFI variable store.")
        }

        if let secureBootCheck = checks.first(where: { $0.id == "secure-boot" }),
           secureBootCheck.state == .warning {
            if secureBootCheck.detail.contains("edk2-aarch64-secure-code.fd is missing") {
                actions.append("Provide edk2-aarch64-secure-code.fd alongside edk2-arm-secure-vars.fd before rerunning Windows Setup smoke.")
            } else {
                actions.append("Run veil-vmctl qemu-smoke --json --seconds 120 and confirm Windows Setup no longer reports Secure Boot before marking Secure Boot support complete.")
            }
        }

        if checks.first(where: { $0.id == "tpm-emulator" })?.state == .blocked {
            actions.append("Install swtpm locally so Veil can attach a TPM 2.0 emulator for Windows 11 setup.")
        }

        if checks.first(where: { $0.id == "hvf-plan" })?.state == .blocked {
            actions.append("Regenerate the QEMU plan and confirm it includes -accel hvf.")
        }

        // Only the port conflict earns an action. `none` and `host-smb` are choices the user made, and
        // nagging about a setting someone deliberately set is noise rather than guidance.
        if let sharedFolderCheck = checks.first(where: { $0.id == "shared-folder" }),
           sharedFolderCheck.state == .warning,
           sharedFolderCheck.detail.contains("was unavailable when this plan was built") {
            actions.append("Free host port \(QEMUWindowsSharedFolderTransport.guestSMBHostPort) with `lsof -nP -iTCP:\(QEMUWindowsSharedFolderTransport.guestSMBHostPort) -sTCP:LISTEN` and restart the VM to get the live shared folder back.")
        }

        if actions.isEmpty {
            actions.append("Run veil-vmctl qemu-start to launch Windows with Veil's embedded display.")
        } else if !checks.contains(where: { $0.state == .blocked }) {
            actions.append("Run veil-vmctl qemu-start to launch Windows with Veil's embedded display.")
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
    public var consoleScreenshotPath: String
    public var nextActions: [String]

    public init(
        kind: String = "qemuWindowsArmBootSmokeReport",
        provider: String = "QEMU/HVF",
        outcome: QEMUWindowsBootSmokeOutcome,
        durationSeconds: Int,
        detail: String,
        evidence: [String],
        serialLogPath: String,
        processLogPath: String,
        consoleScreenshotPath: String,
        nextActions: [String]
    ) {
        self.kind = kind
        self.provider = provider
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.detail = detail
        self.evidence = evidence
        self.serialLogPath = serialLogPath
        self.processLogPath = processLogPath
        self.consoleScreenshotPath = consoleScreenshotPath
        self.nextActions = nextActions
    }
}

public enum QEMUWindowsBootSmokeAnalyzer {
    public static func makeReport(
        durationSeconds: Int,
        processOutput: String,
        serialOutput: String,
        didRemainRunningUntilTimeout: Bool,
        serialLogPath: String,
        processLogPath: String,
        consoleScreenshotPath: String,
        runEvidence: [String] = []
    ) -> QEMUWindowsBootSmokeReport {
        let combinedOutput = "\(processOutput)\n\(serialOutput)"
        var evidence = runEvidence

        if combinedOutput.contains("Tpm2GetCapabilityPcrs")
            || combinedOutput.contains("SyncPcrAllocationsAndPcrMask") {
            evidence.append("tpm2-detected")
        }

        if processOutput.contains("qemu-system-aarch64:"),
           !processOutput.contains("terminating on signal") {
            evidence.append("qemu-argument-error")
            return QEMUWindowsBootSmokeReport(
                outcome: .argumentFailure,
                durationSeconds: durationSeconds,
                detail: "QEMU exited before firmware boot because the command line or local resources failed validation.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath,
                consoleScreenshotPath: consoleScreenshotPath,
                nextActions: nextActions(for: .argumentFailure, evidence: evidence)
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
                processLogPath: processLogPath,
                consoleScreenshotPath: consoleScreenshotPath,
                nextActions: nextActions(for: .windowsBootStarted, evidence: evidence)
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
                processLogPath: processLogPath,
                consoleScreenshotPath: consoleScreenshotPath,
                nextActions: nextActions(for: .uefiShell, evidence: evidence)
            )
        }

        if evidence.contains("boot-image-timeout") {
            return QEMUWindowsBootSmokeReport(
                outcome: .bootImageTimeout,
                durationSeconds: durationSeconds,
                detail: "Arm UEFI attempted the installer boot image, but it timed out before Windows Setup appeared.",
                evidence: evidence,
                serialLogPath: serialLogPath,
                processLogPath: processLogPath,
                consoleScreenshotPath: consoleScreenshotPath,
                nextActions: nextActions(for: .bootImageTimeout, evidence: evidence)
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
                processLogPath: processLogPath,
                consoleScreenshotPath: consoleScreenshotPath,
                nextActions: nextActions(for: .runningNoDecision, evidence: evidence)
            )
        }

        evidence.append("qemu-exited")
        return QEMUWindowsBootSmokeReport(
            outcome: .exitedEarly,
            durationSeconds: durationSeconds,
            detail: "QEMU exited before the bounded smoke run could classify Windows boot progress.",
            evidence: evidence,
            serialLogPath: serialLogPath,
            processLogPath: processLogPath,
            consoleScreenshotPath: consoleScreenshotPath,
            nextActions: nextActions(for: .exitedEarly, evidence: evidence)
        )
    }

    private static func nextActions(
        for outcome: QEMUWindowsBootSmokeOutcome,
        evidence: [String]
    ) -> [String] {
        var actions: [String]

        switch outcome {
        case .windowsBootStarted:
            actions = [
                "Continue the Windows installer and install the Veil guest agent after the first desktop login.",
                "Keep the console screenshot and serial log as proof that the current boot recipe reaches Windows setup."
            ]
        case .uefiShell:
            actions = [
                "Confirm the installer ISO is attached as the first bootable USB/CD-ROM device and contains efi/boot/bootaa64.efi."
            ]
            if evidence.contains("boot-prompt-key-sent") {
                actions.append("The smoke run already sent boot prompt key input; inspect the console screenshot before changing the device recipe.")
            } else {
                actions.append("Try the visible qemu-start path and press a key when the firmware prompts to boot from CD/DVD.")
            }
            actions.append("Open the console screenshot and serial log together to compare the visible firmware state with the boot text.")
        case .bootImageTimeout:
            actions = [
                "Retry with the visible qemu-start path and press a key during the boot prompt window.",
                "Confirm the Windows Arm ISO boots on another VM host or re-download the installer from an official Microsoft source."
            ]
        case .argumentFailure:
            actions = [
                "Open the process log and fix the rejected QEMU argument or local resource path before retrying.",
                "Run veil-vmctl qemu-doctor --json to confirm QEMU, firmware, installer media, automatic install media, and disk paths."
            ]
        case .runningNoDecision:
            actions = [
                "Increase --seconds and compare the console screenshot with the serial log before changing the boot recipe.",
                "Use qemu-start for an interactive visible run if the headless smoke report remains inconclusive."
            ]
        case .exitedEarly:
            actions = [
                "Open the process log to identify whether QEMU exited because of a local file, firmware, or device configuration issue.",
                "Run veil-vmctl qemu-doctor --json before retrying the smoke run."
            ]
        }

        if evidence.contains("boot-image-timeout"),
           !actions.contains("Confirm the installer ISO is attached as the first bootable USB/CD-ROM device and contains efi/boot/bootaa64.efi.") {
            actions.append("Confirm the installer ISO is attached as the first bootable USB/CD-ROM device and contains efi/boot/bootaa64.efi.")
        }

        return actions
    }
}

public struct QEMUWindowsBootSmokePlanner: Sendable {
    public init() {}

    public func makeArguments(
        from plan: QEMUWindowsBootPlan,
        serialLogPath: String,
        monitorSocketPath: String,
        qmpSocketPath: String
    ) -> [String] {
        var arguments = plan.arguments.map(QEMUWindowsBootArgumentRewriter.lockSafeSystemDriveArgument)

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
            "-monitor", "unix:\(monitorSocketPath),server,nowait",
            "-qmp", "unix:\(qmpSocketPath),server,nowait"
        ])

        return arguments
    }

}

public struct QEMUWindowsBootLaunchPlanner: Sendable {
    public init() {}

    public func makeArguments(
        from plan: QEMUWindowsBootPlan,
        serialLogPath: String,
        monitorSocketPath: String,
        qmpSocketPath: String,
        bootDiskFirst: Bool = false,
        displayMode: QEMUWindowsBootDisplayMode = .nativeCocoa,
        vncDisplay: Int? = nil,
        /// Path to a suspended memory-state stream. When present, QEMU starts paused and loads this
        /// stream instead of booting, so the guest continues from where it was suspended.
        incomingMemoryStatePath: String? = nil
    ) -> [String] {
        var arguments = plan.arguments.map(QEMUWindowsBootArgumentRewriter.lockSafeSystemDriveArgument)
        if bootDiskFirst {
            arguments = QEMUWindowsBootArgumentRewriter.bootDiskFirstArguments(arguments)
        }
        if displayMode == .headless || displayMode == .vncLoopback {
            if let displayIndex = arguments.firstIndex(of: "-display"),
               arguments.indices.contains(displayIndex + 1) {
                arguments[displayIndex + 1] = "none"
            } else {
                arguments.append(contentsOf: ["-display", "none"])
            }
        }
        if displayMode == .vncLoopback, let vncDisplay {
            arguments.append(contentsOf: [
                "-vnc", "127.0.0.1:\(vncDisplay)"
            ])
        }

        arguments.append(contentsOf: [
            "-serial", "file:\(serialLogPath)",
            "-monitor", "unix:\(monitorSocketPath),server,nowait",
            "-qmp", "unix:\(qmpSocketPath),server,nowait"
        ])

        if let incomingMemoryStatePath {
            arguments.append(contentsOf: [
                "-incoming", "exec:cat \(QEMUQMPCommand.shellSingleQuoted(incomingMemoryStatePath))"
            ])
        }

        return arguments
    }
}

public enum QEMUWindowsInstallerBootPolicy {
    // The installer can allocate a few GiB while it is still staging WinPE and has not written a
    // bootable Windows partition. Keep booting the installer below 8 GiB; a completed Windows image
    // is substantially larger and can safely take over on the next restart.
    public static let partialInstallDiskAllocatedBytes: Int64 = 8 * 1_024 * 1_024 * 1_024

    public static func shouldSendBootKey(
        profile: VMProfile,
        virtualDiskAllocatedBytes: Int64?
    ) -> Bool {
        shouldSendBootKey(
            windowsInstalled: profile.windowsInstalled == true,
            virtualDiskAllocatedBytes: virtualDiskAllocatedBytes
        )
    }

    public static func shouldSendBootKey(
        windowsInstalled: Bool,
        virtualDiskAllocatedBytes: Int64?
    ) -> Bool {
        if windowsInstalled {
            return false
        }

        guard let virtualDiskAllocatedBytes else {
            return true
        }

        return virtualDiskAllocatedBytes < partialInstallDiskAllocatedBytes
    }

    public static func allocatedFileSize(path: String?) -> Int64? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
        if let allocatedSize = values?.fileAllocatedSize {
            return Int64(allocatedSize)
        }
        if let allocatedSize = values?.totalFileAllocatedSize {
            return Int64(allocatedSize)
        }

        return nil
    }
}

private enum QEMUWindowsBootArgumentRewriter {
    static func bootDiskFirstArguments(_ arguments: [String]) -> [String] {
        var rewritten = arguments
        guard let bootIndex = rewritten.firstIndex(of: "-boot"),
              rewritten.indices.contains(bootIndex + 1) else {
            rewritten.append(contentsOf: ["-boot", "order=c"])
            return rewritten
        }

        rewritten[bootIndex + 1] = "order=c"
        return rewritten
    }

    static func lockSafeSystemDriveArgument(_ argument: String) -> String {
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

public struct QEMUWindowsBootPromptAutomation: Sendable {
    public var firstSendSecond: Int
    public var maxSendCount: Int
    private var sentSeconds: Set<Int>

    public init(firstSendSecond: Int = 1, maxSendCount: Int = 12) {
        self.firstSendSecond = firstSendSecond
        self.maxSendCount = maxSendCount
        self.sentSeconds = []
    }

    @discardableResult
    public mutating func tick(
        elapsedSeconds: Int,
        monitorSocketURL: URL,
        sendBootKey: (URL) -> Bool
    ) -> Bool {
        guard elapsedSeconds >= firstSendSecond else {
            return false
        }

        let lastSendSecond = firstSendSecond + maxSendCount - 1
        guard elapsedSeconds <= lastSendSecond,
              !sentSeconds.contains(elapsedSeconds) else {
            return false
        }

        let didSend = sendBootKey(monitorSocketURL)
        if didSend {
            sentSeconds.insert(elapsedSeconds)
        }
        return didSend
    }
}

public enum QEMUQMPKeyboardCommandError: Error, LocalizedError, Equatable, Sendable {
    case emptyKey
    case unsupportedKey(String)
    case textTooLong(maximum: Int)
    case unsupportedCharacter(String)
    case serializationFailed

    public var errorDescription: String? {
        switch self {
        case .emptyKey:
            "QMP keyboard command requires a non-empty key."
        case .unsupportedKey(let key):
            "Unsupported QMP key '\(key)'."
        case .textTooLong(let maximum):
            "QMP text input is limited to \(maximum) characters."
        case .unsupportedCharacter(let character):
            "Unsupported QMP text character '\(character)'."
        case .serializationFailed:
            "QMP keyboard command could not be encoded as JSON."
        }
    }
}

public enum QEMUQMPKeyboardCommandBuilder {
    public static func capabilitiesCommand() -> String {
        #"{"execute":"qmp_capabilities"}"#
    }

    public static func sendKeyCommand(for key: String) throws -> String {
        let qcodes = try qcodes(for: key)
        let keys = qcodes.map { ["type": "qcode", "data": $0] }
        return try jsonLine([
            "execute": "send-key",
            "arguments": [
                "keys": keys
            ]
        ])
    }

    public static func inputEventCommand(for key: String) throws -> String {
        let qcodes = try qcodes(for: key)
        let downEvents = qcodes.map { inputKeyEvent(qcode: $0, isDown: true) }
        let upEvents = qcodes.reversed().map { inputKeyEvent(qcode: $0, isDown: false) }
        return try jsonLine([
            "execute": "input-send-event",
            "arguments": [
                "events": downEvents + upEvents
            ]
        ])
    }

    public static func oobeBypassCommands() throws -> [String] {
        try QEMUOOBEBypassKeySequence.steps.map(\.key).map(inputEventCommand(for:))
    }

    public static func keySequence(forText text: String, maximumLength: Int = 2_048) throws -> [String] {
        guard text.count <= maximumLength else {
            throw QEMUQMPKeyboardCommandError.textTooLong(maximum: maximumLength)
        }

        return try text.map(qkey)
    }

    private static func qcodes(for key: String) throws -> [String] {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw QEMUQMPKeyboardCommandError.emptyKey
        }

        if normalized.contains("-") {
            return try normalized
                .split(separator: "-")
                .map { try qcode(forSingleKey: String($0)) }
        }

        return [try qcode(forSingleKey: normalized)]
    }

    private static func qcode(forSingleKey key: String) throws -> String {
        switch key {
        case "return", "enter":
            return "ret"
        case "space":
            return "spc"
        case "escape":
            return "esc"
        case "cmd", "meta", "win", "windows":
            return "meta_l"
        default:
            break
        }

        if key.count == 1,
           let scalar = key.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
            return key
        }

        let accepted = Set([
            "shift", "ctrl", "alt", "meta_l",
            "esc", "ret", "spc", "tab", "backspace",
            "backslash", "slash", "minus", "equal", "dot", "comma",
            "semicolon", "apostrophe", "grave_accent", "bracket_left", "bracket_right",
            "f1", "f2", "f3", "f4", "f5", "f6",
            "f7", "f8", "f9", "f10", "f11", "f12",
            "up", "down", "left", "right", "home", "end", "pgup", "pgdn", "delete"
        ])
        guard accepted.contains(key) else {
            throw QEMUQMPKeyboardCommandError.unsupportedKey(key)
        }
        return key
    }

    private static func qkey(for character: Character) throws -> String {
        if character >= "a" && character <= "z" {
            return String(character)
        }

        if character >= "A" && character <= "Z" {
            return "shift-\(String(character).lowercased())"
        }

        if character >= "0" && character <= "9" {
            return String(character)
        }

        switch character {
        case " ":
            return "spc"
        case "\n":
            return "ret"
        case "\\":
            return "backslash"
        case "/":
            return "slash"
        case "-":
            return "minus"
        case "=":
            return "equal"
        case ".":
            return "dot"
        case ",":
            return "comma"
        case ";":
            return "semicolon"
        case "'":
            return "apostrophe"
        case "`":
            return "grave_accent"
        case "[":
            return "bracket_left"
        case "]":
            return "bracket_right"
        case "!":
            return "shift-1"
        case "@":
            return "shift-2"
        case "#":
            return "shift-3"
        case "$":
            return "shift-4"
        case "%":
            return "shift-5"
        case "^":
            return "shift-6"
        case "&":
            return "shift-7"
        case "*":
            return "shift-8"
        case "(":
            return "shift-9"
        case ")":
            return "shift-0"
        case "_":
            return "shift-minus"
        case "+":
            return "shift-equal"
        case ":":
            return "shift-semicolon"
        case "\"":
            return "shift-apostrophe"
        case "|":
            return "shift-backslash"
        case "?":
            return "shift-slash"
        case "<":
            return "shift-comma"
        case ">":
            return "shift-dot"
        case "{":
            return "shift-bracket_left"
        case "}":
            return "shift-bracket_right"
        case "~":
            return "shift-grave_accent"
        default:
            throw QEMUQMPKeyboardCommandError.unsupportedCharacter(String(character))
        }
    }

    private static func inputKeyEvent(qcode: String, isDown: Bool) -> [String: Any] {
        [
            "type": "key",
            "data": [
                "down": isDown,
                "key": [
                    "type": "qcode",
                    "data": qcode
                ]
            ]
        ]
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        try QEMUQMPCommandJSONEncoder.jsonLine(object)
    }
}

public struct QEMUKeySequenceStep: Equatable, Sendable {
    public var key: String
    public var delayAfterSend: TimeInterval

    public init(key: String, delayAfterSend: TimeInterval) {
        self.key = key
        self.delayAfterSend = delayAfterSend
    }
}

public enum QEMUOOBEBypassKeySequence {
    public static let steps: [QEMUKeySequenceStep] = [
        QEMUKeySequenceStep(key: "esc", delayAfterSend: 0.4),
        QEMUKeySequenceStep(key: "shift-f10", delayAfterSend: 3.0),
        QEMUKeySequenceStep(key: "o", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "o", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "b", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "e", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "backslash", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "b", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "y", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "p", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "a", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "s", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "s", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "n", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "r", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "o", delayAfterSend: 0.12),
        QEMUKeySequenceStep(key: "ret", delayAfterSend: 0.25)
    ]
}

public enum QEMUGuestAgentInstallKeySequence {
    public static let startButtonTapNormalizedX = 0.304
    public static let startButtonTapNormalizedY = 0.958
    public static let runConfirmTapNormalizedX = 0.21
    public static let runConfirmTapNormalizedY = 0.85
    public static let uacApproveTapNormalizedX = 0.375
    public static let uacApproveTapNormalizedY = 0.745
    public static let uacApproveKeySteps: [QEMUKeySequenceStep] = [
        QEMUKeySequenceStep(key: "left", delayAfterSend: 0.2),
        QEMUKeySequenceStep(key: "ret", delayAfterSend: 0.5)
    ]

    public static let commandText =
        #"cmd.exe /c for %d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist "%d:\Veil Guest Agent\V.cmd" call "%d:\Veil Guest Agent\V.cmd""#

    public static let openRunSteps: [QEMUKeySequenceStep] = [
        QEMUKeySequenceStep(key: "meta-r", delayAfterSend: 1.0)
    ]

    public static var commandTextSteps: [QEMUKeySequenceStep] {
        get throws {
            var textSteps = try QEMUQMPKeyboardCommandBuilder
                .keySequence(forText: commandText)
                .map { QEMUKeySequenceStep(key: $0, delayAfterSend: 0.035) }
            if !textSteps.isEmpty {
                textSteps[textSteps.count - 1].delayAfterSend = 1.0
            }
            return [
                QEMUKeySequenceStep(key: "ctrl-a", delayAfterSend: 0.2)
            ] + textSteps
        }
    }

    public static var stepsAfterRunOpened: [QEMUKeySequenceStep] {
        get throws {
            openRunSteps + (try commandTextSteps)
        }
    }

    public static var steps: [QEMUKeySequenceStep] {
        get throws {
            return [
                QEMUKeySequenceStep(key: "esc", delayAfterSend: 0.3)
            ] + (try stepsAfterRunOpened) + [
                QEMUKeySequenceStep(key: "ret", delayAfterSend: 1.0)
            ]
        }
    }
}

public enum QEMUSparsePackagePreparationKeySequence {
    public static let startButtonTapNormalizedX = QEMUGuestAgentInstallKeySequence.startButtonTapNormalizedX
    public static let startButtonTapNormalizedY = QEMUGuestAgentInstallKeySequence.startButtonTapNormalizedY
    public static let runConfirmTapNormalizedX = QEMUGuestAgentInstallKeySequence.runConfirmTapNormalizedX
    public static let runConfirmTapNormalizedY = QEMUGuestAgentInstallKeySequence.runConfirmTapNormalizedY
    public static let uacApproveTapNormalizedX = QEMUGuestAgentInstallKeySequence.uacApproveTapNormalizedX
    public static let uacApproveTapNormalizedY = QEMUGuestAgentInstallKeySequence.uacApproveTapNormalizedY
    public static let uacApproveKeySteps = QEMUGuestAgentInstallKeySequence.uacApproveKeySteps

    public static let commandText =
        #"cmd.exe /c for %d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist "%d:\Veil Guest Agent\P.cmd" call "%d:\Veil Guest Agent\P.cmd""#

    public static let openRunSteps = QEMUGuestAgentInstallKeySequence.openRunSteps

    public static var commandTextSteps: [QEMUKeySequenceStep] {
        get throws {
            var textSteps = try QEMUQMPKeyboardCommandBuilder
                .keySequence(forText: commandText)
                .map { QEMUKeySequenceStep(key: $0, delayAfterSend: 0.035) }
            if !textSteps.isEmpty {
                textSteps[textSteps.count - 1].delayAfterSend = 1.0
            }
            return [
                QEMUKeySequenceStep(key: "ctrl-a", delayAfterSend: 0.2)
            ] + textSteps
        }
    }

    public static var stepsAfterRunOpened: [QEMUKeySequenceStep] {
        get throws {
            openRunSteps + (try commandTextSteps)
        }
    }

    public static var steps: [QEMUKeySequenceStep] {
        get throws {
            return [
                QEMUKeySequenceStep(key: "esc", delayAfterSend: 0.3)
            ] + (try stepsAfterRunOpened) + [
                QEMUKeySequenceStep(key: "ret", delayAfterSend: 1.0)
            ]
        }
    }
}

public enum QEMUQMPControlCommandBuilder {
    public static func powerDownCommand() throws -> String {
        try QEMUQMPCommandJSONEncoder.jsonLine([
            "execute": "system_powerdown"
        ])
    }
}

public enum QEMUQMPPointerCommandError: Error, LocalizedError, Equatable, Sendable {
    case coordinateOutOfRange(axis: String, value: Int)

    public var errorDescription: String? {
        switch self {
        case .coordinateOutOfRange(let axis, let value):
            "QMP pointer \(axis) coordinate \(value) is outside the valid 0...32767 absolute range."
        }
    }
}

public enum QEMUQMPPointerCommandBuilder {
    public static let minimumAbsoluteCoordinate = 0
    public static let maximumAbsoluteCoordinate = 32_767

    public static func absoluteMoveCommand(x: Int, y: Int) throws -> String {
        try validate(x: x, y: y)
        return try QEMUQMPCommandJSONEncoder.jsonLine([
            "execute": "input-send-event",
            "arguments": [
                "events": [
                    [
                        "type": "abs",
                        "data": [
                            "axis": "x",
                            "value": x
                        ]
                    ],
                    [
                        "type": "abs",
                        "data": [
                            "axis": "y",
                            "value": y
                        ]
                    ]
                ]
            ]
        ])
    }

    public static func leftButtonCommand(isDown: Bool) throws -> String {
        try QEMUQMPCommandJSONEncoder.jsonLine([
            "execute": "input-send-event",
            "arguments": [
                "events": [
                    [
                        "type": "btn",
                        "data": [
                            "button": "left",
                            "down": isDown
                        ]
                    ]
                ]
            ]
        ])
    }

    private static func validate(x: Int, y: Int) throws {
        guard (minimumAbsoluteCoordinate...maximumAbsoluteCoordinate).contains(x) else {
            throw QEMUQMPPointerCommandError.coordinateOutOfRange(axis: "x", value: x)
        }
        guard (minimumAbsoluteCoordinate...maximumAbsoluteCoordinate).contains(y) else {
            throw QEMUQMPPointerCommandError.coordinateOutOfRange(axis: "y", value: y)
        }
    }
}

public enum QEMUForceStopAuthorization {
    public static let acknowledgementFlag = "--i-understand-data-loss"

    public static func isAuthorized(arguments: [String]) -> Bool {
        arguments.contains(acknowledgementFlag)
    }
}

private enum QEMUQMPCommandJSONEncoder {
    static func jsonLine(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw QEMUQMPKeyboardCommandError.serializationFailed
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw QEMUQMPKeyboardCommandError.serializationFailed
        }
        return line
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
