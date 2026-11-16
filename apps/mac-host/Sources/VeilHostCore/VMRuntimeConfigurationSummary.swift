import Foundation

public struct VMInstallEvidenceSummary: Codable, Equatable, Sendable {
    public var kind: VMInstallEvidenceKind
    public var isInstalled: Bool
    public var title: String
    public var detail: String

    public init(
        kind: VMInstallEvidenceKind,
        isInstalled: Bool,
        title: String,
        detail: String
    ) {
        self.kind = kind
        self.isInstalled = isInstalled
        self.title = title
        self.detail = detail
    }

    public static let notConfigured = VMInstallEvidenceSummary(
        kind: .notConfigured,
        isInstalled: false,
        title: "Windows not configured",
        detail: "Create or prepare a local Windows 11 Arm profile before installation can start."
    )
}

public struct VMRuntimeStorageDeviceSummary: Codable, Equatable, Sendable {
    public var role: String
    public var attachment: String
    public var path: String?
    public var readOnly: Bool

    public init(role: String, attachment: String, path: String?, readOnly: Bool) {
        self.role = role
        self.attachment = attachment
        self.path = path
        self.readOnly = readOnly
    }
}

public struct VMRuntimeGraphicsSummary: Codable, Equatable, Sendable {
    public var widthInPixels: Int
    public var heightInPixels: Int

    public init(widthInPixels: Int, heightInPixels: Int) {
        self.widthInPixels = widthInPixels
        self.heightInPixels = heightInPixels
    }
}

public struct VMRuntimeDeviceSummary: Codable, Equatable, Sendable {
    public var platform: String
    public var bootLoader: String
    public var storageDevices: [VMRuntimeStorageDeviceSummary]
    public var networkMode: String
    public var graphics: VMRuntimeGraphicsSummary
    public var inputDevices: [String]
    public var entropyDevice: String
    public var audioDevice: String
    public var sharedFolderDevice: String

    public init(
        platform: String,
        bootLoader: String,
        storageDevices: [VMRuntimeStorageDeviceSummary],
        networkMode: String,
        graphics: VMRuntimeGraphicsSummary,
        inputDevices: [String],
        entropyDevice: String,
        audioDevice: String = VMRuntimeDeviceDefaults.audioDeviceDisabled,
        sharedFolderDevice: String = VMRuntimeDeviceDefaults.sharedFolderDisabled
    ) {
        self.platform = platform
        self.bootLoader = bootLoader
        self.storageDevices = storageDevices
        self.networkMode = networkMode
        self.graphics = graphics
        self.inputDevices = inputDevices
        self.entropyDevice = entropyDevice
        self.audioDevice = audioDevice
        self.sharedFolderDevice = sharedFolderDevice
    }
}

public struct VMRuntimeSystemConfigurationSummary: Codable, Equatable, Sendable {
    public var name: String
    public var architecture: String
    public var cpuCount: Int
    public var memoryMB: Int
    public var diskGB: Int

    public init(name: String, architecture: String, cpuCount: Int, memoryMB: Int, diskGB: Int) {
        self.name = name
        self.architecture = architecture
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskGB = diskGB
    }
}

public struct VMRuntimeDisplayConfigurationSummary: Codable, Equatable, Sendable {
    public var surface: String
    public var widthInPixels: Int
    public var heightInPixels: Int
    public var scalingMode: String
    public var dynamicResolution: String
    public var retinaScaling: String

    public init(
        surface: String,
        widthInPixels: Int,
        heightInPixels: Int,
        scalingMode: String,
        dynamicResolution: String,
        retinaScaling: String
    ) {
        self.surface = surface
        self.widthInPixels = widthInPixels
        self.heightInPixels = heightInPixels
        self.scalingMode = scalingMode
        self.dynamicResolution = dynamicResolution
        self.retinaScaling = retinaScaling
    }
}

/// Host-guest file sharing.
///
/// Two different things live here and they are easy to confuse, so both are named explicitly:
///
/// - `sharedFolderPath` is a **macOS staging directory**. Despite the name it has never been shared
///   with the guest; its real job is holding `VeilAutoInstall.iso`. The name predates live sharing and
///   is kept because the boot plan derives the unattended-install ISO path from it.
/// - Everything else describes the **live shared folder**, which is served by Windows and mounted on
///   the Mac.
public struct VMRuntimeSharingConfigurationSummary: Codable, Equatable, Sendable {
    /// macOS staging directory for install media. Not shared with the guest.
    public var sharedFolderPath: String
    public var isLiveSharingEnabled: Bool
    public var transport: QEMUWindowsSharedFolderTransport
    public var transportSummary: String
    public var shareName: String?
    /// Folder inside Windows that holds the shared files.
    public var guestDirectoryPath: String?
    /// URL that mounts the share on this Mac.
    public var hostMountURL: String?
    public var overrideEnvironmentVariable: String

    public init(
        sharedFolderPath: String,
        transport: QEMUWindowsSharedFolderTransport = .guestSMB,
        overrideEnvironmentVariable: String = QEMUWindowsSharedFolderTransport.environmentVariableName
    ) {
        self.sharedFolderPath = sharedFolderPath
        self.isLiveSharingEnabled = transport.isEnabled
        self.transport = transport
        self.transportSummary = transport.summary
        self.shareName = transport.isEnabled ? QEMUWindowsSharedFolderTransport.shareName : nil
        self.guestDirectoryPath = transport.expectedGuestDirectoryPath
        self.hostMountURL = transport.hostMountURL
        self.overrideEnvironmentVariable = overrideEnvironmentVariable
    }
}

public struct VMRuntimeStorageConfigurationSummary: Codable, Equatable, Sendable {
    public var devices: [VMRuntimeStorageDeviceSummary]

    public init(devices: [VMRuntimeStorageDeviceSummary]) {
        self.devices = devices
    }
}

public struct VMRuntimeNetworkConfigurationSummary: Codable, Equatable, Sendable {
    public var mode: String

    public init(mode: String) {
        self.mode = mode
    }
}

public struct VMRuntimeInputConfigurationSummary: Codable, Equatable, Sendable {
    public var devices: [String]

    public init(devices: [String]) {
        self.devices = devices
    }
}

/// Guest sound configuration.
///
/// Reported as its own section rather than folded into `input` so a status surface can say plainly
/// whether Windows has a sound device at all. Veil shipped with no audio device for a long time and
/// nothing in the configuration summary made that visible.
public struct VMRuntimeAudioConfigurationSummary: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var device: String
    public var hostBackend: String?
    public var overrideEnvironmentVariable: String

    public init(
        isEnabled: Bool,
        device: String,
        hostBackend: String? = nil,
        overrideEnvironmentVariable: String = QEMUWindowsAudioDevice.environmentVariableName
    ) {
        self.isEnabled = isEnabled
        self.device = device
        self.hostBackend = hostBackend
        self.overrideEnvironmentVariable = overrideEnvironmentVariable
    }
}

public struct VMRuntimeGuestAgentConfigurationSummary: Codable, Equatable, Sendable {
    public var isInstalled: Bool
    public var version: String?

    public init(isInstalled: Bool, version: String?) {
        self.isInstalled = isInstalled
        self.version = version
    }
}

public struct VMRuntimeConfigurationSummary: Codable, Equatable, Sendable {
    public var system: VMRuntimeSystemConfigurationSummary
    public var display: VMRuntimeDisplayConfigurationSummary
    public var sharing: VMRuntimeSharingConfigurationSummary
    public var storage: VMRuntimeStorageConfigurationSummary
    public var network: VMRuntimeNetworkConfigurationSummary
    public var input: VMRuntimeInputConfigurationSummary
    public var audio: VMRuntimeAudioConfigurationSummary
    public var guestAgent: VMRuntimeGuestAgentConfigurationSummary

    public init(
        system: VMRuntimeSystemConfigurationSummary,
        display: VMRuntimeDisplayConfigurationSummary,
        sharing: VMRuntimeSharingConfigurationSummary,
        storage: VMRuntimeStorageConfigurationSummary,
        network: VMRuntimeNetworkConfigurationSummary,
        input: VMRuntimeInputConfigurationSummary,
        audio: VMRuntimeAudioConfigurationSummary,
        guestAgent: VMRuntimeGuestAgentConfigurationSummary
    ) {
        self.system = system
        self.display = display
        self.sharing = sharing
        self.storage = storage
        self.network = network
        self.input = input
        self.audio = audio
        self.guestAgent = guestAgent
    }
}

public enum VMRuntimeDeviceDefaults {
    public static let systemDiskIdentifier = "veil-system-disk"
    public static let graphicsWidthInPixels = 1440
    public static let graphicsHeightInPixels = 900
    public static let displayScalingMode = "aspect-fit host window"
    public static let dynamicResolutionPolicy = "fixed guest framebuffer until guest agent display bridge"
    public static let retinaScalingPolicy = "host-rendered Retina interpolation"
    public static let liveDisplayValidationCommand = "veil-vmctl qemu-display-smoke --json"
    public static let audioDeviceDisabled = "none"
    public static let intelHDADescription = "Intel HD Audio duplex (playback and capture)"
    public static let usbAudioDescription = "USB Audio Class duplex (playback and capture)"
    public static let sharedFolderDisabled = "none"
    public static let guestSMBSharedFolderDescription = "Guest-served SMB share over a loopback port forward"
    public static let hostSMBSharedFolderDescription = "Host-served SMB share reached through the usermode gateway"
}
