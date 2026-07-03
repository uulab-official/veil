import Foundation

public protocol VMRuntimeService: Sendable {
    func loadSnapshot() async throws -> VMRuntimeSnapshot
    func prepareDefaultVM() async throws -> VMRuntimeSnapshot
    func createDefaultProfile() async throws -> VMRuntimeSnapshot
    func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot
    func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot
    func markWindowsInstalled() async throws -> VMRuntimeSnapshot
    func markGuestAgentConnected(agentVersion: String) async throws -> VMRuntimeSnapshot
    func start() async throws -> VMRuntimeSnapshot
    func stop() async throws -> VMRuntimeSnapshot
    func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord
    func sendConsoleKey(_ key: String) async throws -> QEMUKeySendRecord
    func exportDiagnostics(to directory: URL) async throws -> URL
}

public protocol VMRuntimeBooting: Sendable {
    func runtimeState() async -> VMRuntimeState?
    func start(profile: VMProfile) async throws -> VMRuntimeState
    func stop() async throws -> VMRuntimeState
}

public struct UnavailableVMRuntimeBooter: VMRuntimeBooting {
    public init() {}

    public func runtimeState() async -> VMRuntimeState? {
        nil
    }

    public func start(profile: VMProfile) async throws -> VMRuntimeState {
        throw VMRuntimeError.bootNotImplemented
    }

    public func stop() async throws -> VMRuntimeState {
        .stopped
    }
}

public enum VMRuntimeState: String, Codable, Equatable, Sendable {
    case unsupported
    case notConfigured
    case stopped
    case starting
    case running
    case suspended
    case failed
}

public enum VMRuntimeProviderKind: String, Codable, Equatable, Sendable {
    case appleVirtualization
    case qemuHypervisor
}

public enum VMRuntimeProviderStatus: String, Codable, Equatable, Sendable {
    case active
    case planned
    case unavailable
}

public struct VMRuntimeProviderSummary: Codable, Equatable, Sendable {
    public var kind: VMRuntimeProviderKind
    public var displayName: String
    public var mode: String
    public var acceleration: String
    public var isServerBacked: Bool
    public var status: VMRuntimeProviderStatus
    public var detail: String
    public var executablePath: String?
    public var executableVersion: String?

    public init(
        kind: VMRuntimeProviderKind,
        displayName: String,
        mode: String,
        acceleration: String,
        isServerBacked: Bool,
        status: VMRuntimeProviderStatus,
        detail: String,
        executablePath: String? = nil,
        executableVersion: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.mode = mode
        self.acceleration = acceleration
        self.isServerBacked = isServerBacked
        self.status = status
        self.detail = detail
        self.executablePath = executablePath
        self.executableVersion = executableVersion
    }
}

public struct VMRuntimeProviderProbe: Sendable {
    public static let qemuEnvironmentKey = "VEIL_QEMU_SYSTEM_AARCH64"
    public static let defaultQEMUExecutablePaths = [
        "/opt/homebrew/bin/qemu-system-aarch64",
        "/usr/local/bin/qemu-system-aarch64",
        "/opt/local/bin/qemu-system-aarch64"
    ]

    private let environment: [String: String]
    private let fileExists: @Sendable (String) -> Bool
    private let executableVersion: @Sendable (String) -> String?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        executableVersion: @escaping @Sendable (String) -> String? = Self.qemuVersionOutput(executablePath:)
    ) {
        self.environment = environment
        self.fileExists = fileExists
        self.executableVersion = executableVersion
    }

    public func localProviders(
        architecture: String,
        minimumOSSupported: Bool
    ) -> [VMRuntimeProviderSummary] {
        [
            appleVirtualizationProvider(
                architecture: architecture,
                minimumOSSupported: minimumOSSupported
            ),
            qemuHypervisorProvider()
        ]
    }

    private func appleVirtualizationProvider(
        architecture: String,
        minimumOSSupported: Bool
    ) -> VMRuntimeProviderSummary {
        let isAvailable = architecture == "arm64" && minimumOSSupported
        return VMRuntimeProviderSummary(
            kind: .appleVirtualization,
            displayName: "Apple Virtualization",
            mode: "Local VM runtime",
            acceleration: "Apple Hypervisor",
            isServerBacked: false,
            status: isAvailable ? .active : .unavailable,
            detail: isAvailable
                ? "Runs locally inside Veil.app with no server VM backend."
                : "Requires macOS 15+ on Apple Silicon."
        )
    }

    private func qemuHypervisorProvider() -> VMRuntimeProviderSummary {
        if let executablePath = qemuExecutablePath() {
            return VMRuntimeProviderSummary(
                kind: .qemuHypervisor,
                displayName: "QEMU/HVF",
                mode: "Local compatibility provider",
                acceleration: "HVF",
                isServerBacked: false,
                status: .active,
                detail: "qemu-system-aarch64 found locally for UTM-style Windows compatibility experiments.",
                executablePath: executablePath,
                executableVersion: Self.firstVersionLine(from: executableVersion(executablePath))
            )
        }

        return VMRuntimeProviderSummary(
            kind: .qemuHypervisor,
            displayName: "QEMU/HVF",
            mode: "Local compatibility provider",
            acceleration: "HVF",
            isServerBacked: false,
            status: .planned,
            detail: "qemu-system-aarch64 not found. Install QEMU locally or set VEIL_QEMU_SYSTEM_AARCH64 to a local executable path."
        )
    }

    private func qemuExecutablePath() -> String? {
        if let overridePath = environment[Self.qemuEnvironmentKey],
           !overridePath.isEmpty,
           fileExists(overridePath) {
            return overridePath
        }

        return Self.defaultQEMUExecutablePaths.first(where: fileExists)
    }

    private static func firstVersionLine(from output: String?) -> String? {
        output?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func qemuVersionOutput(executablePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

public struct VMRuntimeSnapshot: Codable, Equatable, Sendable {
    public var state: VMRuntimeState
    public var virtualizationAvailable: Bool
    public var architecture: String
    public var minimumOSSupported: Bool
    public var profileName: String?
    public var cpuCount: Int?
    public var memoryMB: Int?
    public var diskGB: Int?
    public var installerMediaPath: String?
    public var discoveredInstallerMediaPath: String?
    public var driverMediaPath: String?
    public var virtualDiskPath: String?
    public var virtualDiskAllocatedBytes: Int64?
    public var automaticInstallAnswerFilePath: String?
    public var automaticInstallMediaPath: String?
    public var latestConsoleScreenshotPath: String?
    public var latestConsoleLaunch: VMConsoleLaunchEvidence?
    public var runningQEMUProcess: QEMURunningProcess?
    public var runtimeProvider: VMRuntimeProviderSummary?
    public var runtimeProviders: [VMRuntimeProviderSummary]
    public var installationSteps: [VMInstallationStep]
    public var preflightChecks: [VMPreflightCheck]
    public var deviceSummary: VMRuntimeDeviceSummary?
    public var configurationSummary: VMRuntimeConfigurationSummary?
    public var installEvidence: VMInstallEvidenceSummary
    public var bootReady: Bool
    public var windowsInstalled: Bool
    public var detail: String

    public init(
        state: VMRuntimeState,
        virtualizationAvailable: Bool,
        architecture: String,
        minimumOSSupported: Bool,
        profileName: String?,
        cpuCount: Int? = nil,
        memoryMB: Int? = nil,
        diskGB: Int? = nil,
        installerMediaPath: String? = nil,
        discoveredInstallerMediaPath: String? = nil,
        driverMediaPath: String? = nil,
        virtualDiskPath: String? = nil,
        virtualDiskAllocatedBytes: Int64? = nil,
        automaticInstallAnswerFilePath: String? = nil,
        automaticInstallMediaPath: String? = nil,
        latestConsoleScreenshotPath: String? = nil,
        latestConsoleLaunch: VMConsoleLaunchEvidence? = nil,
        runningQEMUProcess: QEMURunningProcess? = nil,
        runtimeProvider: VMRuntimeProviderSummary? = nil,
        runtimeProviders: [VMRuntimeProviderSummary] = [],
        installationSteps: [VMInstallationStep] = [],
        preflightChecks: [VMPreflightCheck] = [],
        deviceSummary: VMRuntimeDeviceSummary? = nil,
        configurationSummary: VMRuntimeConfigurationSummary? = nil,
        installEvidence: VMInstallEvidenceSummary = .notConfigured,
        bootReady: Bool = false,
        windowsInstalled: Bool = false,
        detail: String
    ) {
        self.state = state
        self.virtualizationAvailable = virtualizationAvailable
        self.architecture = architecture
        self.minimumOSSupported = minimumOSSupported
        self.profileName = profileName
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskGB = diskGB
        self.installerMediaPath = installerMediaPath
        self.discoveredInstallerMediaPath = discoveredInstallerMediaPath
        self.driverMediaPath = driverMediaPath
        self.virtualDiskPath = virtualDiskPath
        self.virtualDiskAllocatedBytes = virtualDiskAllocatedBytes
        self.automaticInstallAnswerFilePath = automaticInstallAnswerFilePath
        self.automaticInstallMediaPath = automaticInstallMediaPath
        self.latestConsoleScreenshotPath = latestConsoleScreenshotPath
        self.latestConsoleLaunch = latestConsoleLaunch
        self.runningQEMUProcess = runningQEMUProcess
        self.runtimeProvider = runtimeProvider
        self.runtimeProviders = runtimeProviders
        self.installationSteps = installationSteps
        self.preflightChecks = preflightChecks
        self.deviceSummary = deviceSummary
        self.configurationSummary = configurationSummary
        self.installEvidence = installEvidence
        self.bootReady = bootReady
        self.windowsInstalled = windowsInstalled
        self.detail = detail
    }
}

public struct VMWindowsInstallStatusReport: Codable, Equatable, Sendable {
    public var kind: String
    public var generatedAt: Date
    public var state: VMRuntimeState
    public var profileName: String?
    public var bootReady: Bool
    public var windowsInstalled: Bool
    public var installEvidence: VMInstallEvidenceSummary
    public var installerMediaPath: String?
    public var driverMediaPath: String?
    public var virtualDiskPath: String?
    public var automaticInstallMediaPath: String?
    public var latestConsoleScreenshotPath: String?
    public var displaySurface: VMConsoleDisplaySurface
    public var latestConsoleLaunch: VMConsoleLaunchEvidence?
    public var runningQEMUProcess: QEMURunningProcess?
    public var nextActions: [String]

    public init(
        kind: String = "qemuWindowsInstallStatus",
        generatedAt: Date,
        state: VMRuntimeState,
        profileName: String?,
        bootReady: Bool,
        windowsInstalled: Bool,
        installEvidence: VMInstallEvidenceSummary,
        installerMediaPath: String?,
        driverMediaPath: String?,
        virtualDiskPath: String?,
        automaticInstallMediaPath: String?,
        latestConsoleScreenshotPath: String?,
        displaySurface: VMConsoleDisplaySurface,
        latestConsoleLaunch: VMConsoleLaunchEvidence?,
        runningQEMUProcess: QEMURunningProcess?,
        nextActions: [String]
    ) {
        self.kind = kind
        self.generatedAt = generatedAt
        self.state = state
        self.profileName = profileName
        self.bootReady = bootReady
        self.windowsInstalled = windowsInstalled
        self.installEvidence = installEvidence
        self.installerMediaPath = installerMediaPath
        self.driverMediaPath = driverMediaPath
        self.virtualDiskPath = virtualDiskPath
        self.automaticInstallMediaPath = automaticInstallMediaPath
        self.latestConsoleScreenshotPath = latestConsoleScreenshotPath
        self.displaySurface = displaySurface
        self.latestConsoleLaunch = latestConsoleLaunch
        self.runningQEMUProcess = runningQEMUProcess
        self.nextActions = nextActions
    }
}

public extension VMRuntimeSnapshot {
    func windowsInstallStatusReport(generatedAt: Date = Date()) -> VMWindowsInstallStatusReport {
        VMWindowsInstallStatusReport(
            generatedAt: generatedAt,
            state: state,
            profileName: profileName,
            bootReady: bootReady,
            windowsInstalled: windowsInstalled,
            installEvidence: installEvidence,
            installerMediaPath: installerMediaPath,
            driverMediaPath: driverMediaPath,
            virtualDiskPath: virtualDiskPath,
            automaticInstallMediaPath: automaticInstallMediaPath,
            latestConsoleScreenshotPath: latestConsoleScreenshotPath,
            displaySurface: displaySurfaceEvidence(),
            latestConsoleLaunch: latestConsoleLaunch,
            runningQEMUProcess: runningQEMUProcess,
            nextActions: windowsInstallNextActions()
        )
    }

    private func windowsInstallNextActions() -> [String] {
        if !bootReady {
            var actions = runningRecoveryActions()
            let blockers = preflightChecks
                .filter { $0.state == .failed }
                .map { "\($0.title): \($0.detail)" }
            if !blockers.isEmpty {
                actions.append(contentsOf: blockers)
                return actions
            }

            let blockedSteps = installationSteps
                .filter { $0.state == .blocked }
                .map { "\($0.title): \($0.detail)" }
            if !blockedSteps.isEmpty {
                actions.append(contentsOf: blockedSteps)
                return actions
            }

            actions.append("Run `veil-vmctl qemu-doctor --json` to identify the missing Windows install prerequisite.")
            return actions
        }

        if state == .running {
            var actions = runningRecoveryActions()
            if latestConsoleLaunch?.displaySurface.isLiveCapable == true {
                actions.append("Validate the embedded console with `veil-vmctl qemu-display-smoke --json`.")
            }
            if latestConsoleLaunch?.monitorSocketPath.isEmpty == false {
                actions.append("Refresh install evidence with `veil-vmctl qemu-capture --json` before changing recovery steps.")
            }
            if !windowsInstalled {
                actions.append("Continue Windows Setup in the console; use `veil-vmctl qemu-oobe-bypass --json` only when OOBE network setup blocks local account creation.")
            } else if installEvidence.kind != .guestAgent {
                actions.append("Install the guest agent with `veil-vmctl qemu-install-agent --json` once the Windows desktop is visible.")
            } else {
                actions.append("Check the app runtime bridge with `veil-vmctl app-runtime-status --json`.")
            }
            return actions
        }

        if windowsInstalled, installEvidence.kind != .guestAgent {
            return [
                "Start the installed Windows disk with `veil-vmctl qemu-start --wait-seconds 15`.",
                "Install the guest agent with `veil-vmctl qemu-install-agent --json` once the Windows desktop is visible."
            ]
        }

        if windowsInstalled {
            return ["Start Windows and verify the app runtime bridge with `veil-vmctl app-runtime-status --json`."]
        }

        return ["Start the visible install with `veil-vmctl qemu-start --wait-seconds 15`."]
    }

    private func runningRecoveryActions() -> [String] {
        guard state == .running else {
            return []
        }

        if latestConsoleLaunch == nil, let runningQEMUProcess {
            return [
                "Close existing QEMU/Windows PID \(runningQEMUProcess.pid) before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record."
            ]
        }

        if latestConsoleLaunch == nil {
            return [
                "Close the existing QEMU/Windows process before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record."
            ]
        }

        return [
            "Capture the current console before changing setup state, then shut down with `veil-vmctl qemu-powerdown --json` if you need to reselect media or relaunch."
        ]
    }

    private func displaySurfaceEvidence() -> VMConsoleDisplaySurface {
        if let surface = latestConsoleLaunch?.displaySurface,
           surface.kind != .unavailable {
            return surface
        }

        guard let latestConsoleScreenshotPath else {
            return .unavailable
        }

        return VMConsoleDisplaySurface(
            kind: .screenshot,
            endpoint: nil,
            screenshotPath: latestConsoleScreenshotPath,
            isLiveCapable: false
        )
    }
}

public struct VMConsoleLaunchEvidence: Codable, Equatable, Sendable {
    public var provider: String
    public var pid: Int32?
    public var processLogPath: String
    public var monitorSocketPath: String
    public var qmpSocketPath: String?
    public var vncHost: String?
    public var vncPort: Int?
    public var consoleScreenshotPath: String?
    public var consoleScreenshotRefreshedAt: Date?
    public var previewStatus: VMConsolePreviewStatus
    public var startedAt: Date

    public var displaySurface: VMConsoleDisplaySurface {
        if let vncHost, let vncPort {
            return VMConsoleDisplaySurface(
                kind: .vncLoopback,
                endpoint: "\(vncHost):\(vncPort)",
                screenshotPath: consoleScreenshotPath,
                isLiveCapable: true,
                validationCommand: VMRuntimeDeviceDefaults.liveDisplayValidationCommand
            )
        }

        if let consoleScreenshotPath {
            return VMConsoleDisplaySurface(
                kind: .screenshot,
                endpoint: nil,
                screenshotPath: consoleScreenshotPath,
                isLiveCapable: false,
                validationCommand: nil
            )
        }

        return .unavailable
    }

    public init(
        provider: String,
        pid: Int32?,
        processLogPath: String,
        monitorSocketPath: String,
        qmpSocketPath: String? = nil,
        vncHost: String? = nil,
        vncPort: Int? = nil,
        consoleScreenshotPath: String?,
        consoleScreenshotRefreshedAt: Date? = nil,
        previewStatus: VMConsolePreviewStatus = .unavailable,
        startedAt: Date
    ) {
        self.provider = provider
        self.pid = pid
        self.processLogPath = processLogPath
        self.monitorSocketPath = monitorSocketPath
        self.qmpSocketPath = qmpSocketPath
        self.vncHost = vncHost
        self.vncPort = vncPort
        self.consoleScreenshotPath = consoleScreenshotPath
        self.consoleScreenshotRefreshedAt = consoleScreenshotRefreshedAt
        self.previewStatus = previewStatus
        self.startedAt = startedAt
    }
}

public enum VMConsoleDisplaySurfaceKind: String, Codable, Equatable, Sendable {
    case vncLoopback
    case screenshot
    case unavailable
}

public struct VMConsoleDisplaySurface: Codable, Equatable, Sendable {
    public var kind: VMConsoleDisplaySurfaceKind
    public var endpoint: String?
    public var screenshotPath: String?
    public var isLiveCapable: Bool
    public var plannedWidthInPixels: Int
    public var plannedHeightInPixels: Int
    public var scalingMode: String
    public var dynamicResolution: String
    public var retinaScaling: String
    public var validationCommand: String?

    public init(
        kind: VMConsoleDisplaySurfaceKind,
        endpoint: String?,
        screenshotPath: String?,
        isLiveCapable: Bool,
        plannedWidthInPixels: Int = VMRuntimeDeviceDefaults.graphicsWidthInPixels,
        plannedHeightInPixels: Int = VMRuntimeDeviceDefaults.graphicsHeightInPixels,
        scalingMode: String = VMRuntimeDeviceDefaults.displayScalingMode,
        dynamicResolution: String = VMRuntimeDeviceDefaults.dynamicResolutionPolicy,
        retinaScaling: String = VMRuntimeDeviceDefaults.retinaScalingPolicy,
        validationCommand: String? = nil
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.screenshotPath = screenshotPath
        self.isLiveCapable = isLiveCapable
        self.plannedWidthInPixels = plannedWidthInPixels
        self.plannedHeightInPixels = plannedHeightInPixels
        self.scalingMode = scalingMode
        self.dynamicResolution = dynamicResolution
        self.retinaScaling = retinaScaling
        self.validationCommand = validationCommand
    }

    public static let unavailable = VMConsoleDisplaySurface(
        kind: .unavailable,
        endpoint: nil,
        screenshotPath: nil,
        isLiveCapable: false,
        validationCommand: nil
    )
}

public enum VMConsolePreviewStatus: String, Codable, Equatable, Sendable {
    case fresh
    case stale
    case unavailable
}

public enum VMInstallEvidenceKind: String, Codable, Equatable, Sendable {
    case notConfigured
    case setupBlocked
    case sparseDisk
    case setupReady
    case profileFlag
    case guestAgent
}

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

    public init(
        platform: String,
        bootLoader: String,
        storageDevices: [VMRuntimeStorageDeviceSummary],
        networkMode: String,
        graphics: VMRuntimeGraphicsSummary,
        inputDevices: [String],
        entropyDevice: String
    ) {
        self.platform = platform
        self.bootLoader = bootLoader
        self.storageDevices = storageDevices
        self.networkMode = networkMode
        self.graphics = graphics
        self.inputDevices = inputDevices
        self.entropyDevice = entropyDevice
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

public struct VMRuntimeSharingConfigurationSummary: Codable, Equatable, Sendable {
    public var sharedFolderPath: String

    public init(sharedFolderPath: String) {
        self.sharedFolderPath = sharedFolderPath
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
    public var guestAgent: VMRuntimeGuestAgentConfigurationSummary

    public init(
        system: VMRuntimeSystemConfigurationSummary,
        display: VMRuntimeDisplayConfigurationSummary,
        sharing: VMRuntimeSharingConfigurationSummary,
        storage: VMRuntimeStorageConfigurationSummary,
        network: VMRuntimeNetworkConfigurationSummary,
        input: VMRuntimeInputConfigurationSummary,
        guestAgent: VMRuntimeGuestAgentConfigurationSummary
    ) {
        self.system = system
        self.display = display
        self.sharing = sharing
        self.storage = storage
        self.network = network
        self.input = input
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
}

public enum VMInstallationStepState: String, Codable, Equatable, Sendable {
    case complete
    case pending
    case blocked
}

public struct VMInstallationStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var state: VMInstallationStepState

    public init(
        id: String,
        title: String,
        detail: String,
        state: VMInstallationStepState
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public enum VMPreflightCheckState: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

public struct VMPreflightCheck: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var state: VMPreflightCheckState

    public init(
        id: String,
        title: String,
        detail: String,
        state: VMPreflightCheckState
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public struct VMRuntimeDiagnosticHost: Codable, Equatable, Sendable {
    public var architecture: String
    public var processorCount: Int
    public var physicalMemoryBytes: UInt64
    public var operatingSystemVersion: String

    public init(
        architecture: String,
        processorCount: Int,
        physicalMemoryBytes: UInt64,
        operatingSystemVersion: String
    ) {
        self.architecture = architecture
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.operatingSystemVersion = operatingSystemVersion
    }
}

public struct VMRuntimeDiagnosticBundle: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var host: VMRuntimeDiagnosticHost
    public var snapshot: VMRuntimeSnapshot
    public var profile: VMProfile?
    public var lastBootReport: VMRuntimeBootReport?

    public init(
        generatedAt: Date,
        host: VMRuntimeDiagnosticHost,
        snapshot: VMRuntimeSnapshot,
        profile: VMProfile?,
        lastBootReport: VMRuntimeBootReport? = nil
    ) {
        self.generatedAt = generatedAt
        self.host = host
        self.snapshot = snapshot
        self.profile = profile
        self.lastBootReport = lastBootReport
    }
}

public enum VMRuntimeBootReportResult: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

public struct VMRuntimeBootReport: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var completedAt: Date
    public var result: VMRuntimeBootReportResult
    public var resultingState: VMRuntimeState
    public var errorMessage: String?
    public var profile: VMProfile
    public var deviceSummary: VMRuntimeDeviceSummary

    public init(
        startedAt: Date,
        completedAt: Date,
        result: VMRuntimeBootReportResult,
        resultingState: VMRuntimeState,
        errorMessage: String?,
        profile: VMProfile,
        deviceSummary: VMRuntimeDeviceSummary
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
        self.resultingState = resultingState
        self.errorMessage = errorMessage
        self.profile = profile
        self.deviceSummary = deviceSummary
    }

    public func withoutSecurityScopedBookmarks() -> VMRuntimeBootReport {
        VMRuntimeBootReport(
            startedAt: startedAt,
            completedAt: completedAt,
            result: result,
            resultingState: resultingState,
            errorMessage: errorMessage,
            profile: profile.withoutSecurityScopedBookmarks(),
            deviceSummary: deviceSummary
        )
    }
}

public protocol VMRuntimeBootReportStore: Sendable {
    func load() async throws -> VMRuntimeBootReport?
    func save(_ report: VMRuntimeBootReport) async throws
}

public struct JSONVMRuntimeBootReportStore: VMRuntimeBootReportStore {
    public static var defaultDirectory: URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return baseDirectory
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private let directory: URL
    private let fileName: String

    public init(
        directory: URL = Self.defaultDirectory,
        fileName: String = "last-boot-report.json"
    ) {
        self.directory = directory
        self.fileName = fileName
    }

    public func load() async throws -> VMRuntimeBootReport? {
        let url = reportURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.veilDiagnostics.decode(VMRuntimeBootReport.self, from: data)
    }

    public func save(_ report: VMRuntimeBootReport) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.veilDiagnostics.encode(report)
        try data.write(to: reportURL, options: [.atomic])
    }

    private var reportURL: URL {
        directory.appendingPathComponent(fileName)
    }
}

public extension JSONEncoder {
    static var veilDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var veilDiagnostics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum VMRuntimeError: Error, LocalizedError, Equatable, Sendable {
    case capabilityProbeFailed
    case bootNotImplemented
    case bootPrerequisitesMissing
    case automaticInstallMediaCreationFailed(String)
    case qemuNotReady(String)
    case qemuDisplayPortUnavailable
    case qemuAlreadyRunning(pid: Int32)

    public var errorDescription: String? {
        switch self {
        case .capabilityProbeFailed:
            "Unable to inspect VM runtime capabilities."
        case .bootNotImplemented:
            "VM boot is not implemented yet."
        case .bootPrerequisitesMissing:
            "Windows setup media is required before installation; after Windows is installed, the system disk, shared folder, and preflight checks must be ready before starting."
        case let .automaticInstallMediaCreationFailed(message):
            "Unable to create automatic Windows install media: \(message)"
        case let .qemuNotReady(message):
            "QEMU/HVF is not ready: \(message)"
        case .qemuDisplayPortUnavailable:
            "No loopback VNC display port is available. Close stale QEMU/VNC listeners and try again."
        case let .qemuAlreadyRunning(pid):
            "QEMU is already running as PID \(pid) with the configured Windows disk attached. Shut down that VM before starting another one."
        }
    }
}

public protocol AutomaticInstallMediaBuilding: Sendable {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws
}

public struct HdiutilAutomaticInstallMediaBuilder: AutomaticInstallMediaBuilding {
    private let processRunner: @Sendable (String, [String]) throws -> Int32

    public init(
        processRunner: @escaping @Sendable (String, [String]) throws -> Int32 = Self.runProcess
    ) {
        self.processRunner = processRunner
    }

    public func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: answerFileURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("Autounattend.xml is missing.")
        }

        let agentBundleURL = answerFileURL.deletingLastPathComponent()
            .appendingPathComponent("Veil Guest Agent", isDirectory: true)
        if Self.mediaIsCurrent(
            mediaURL: mediaURL,
            answerFileURL: answerFileURL,
            agentBundleURL: agentBundleURL
        ) {
            return
        }

        let buildID = UUID().uuidString
        let stagingDirectory = mediaURL.deletingLastPathComponent()
            .appendingPathComponent(".veil-auto-install-media-\(buildID)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        try fileManager.copyItem(
            at: answerFileURL,
            to: stagingDirectory.appendingPathComponent("Autounattend.xml")
        )
        if fileManager.fileExists(atPath: agentBundleURL.path) {
            try fileManager.copyItem(
                at: agentBundleURL,
                to: stagingDirectory.appendingPathComponent("Veil Guest Agent", isDirectory: true)
            )
        }

        let temporaryOutputURL = mediaURL.deletingLastPathComponent()
            .appendingPathComponent("\(mediaURL.deletingPathExtension().lastPathComponent)-\(buildID)")
            .appendingPathExtension("iso.tmp")
        let generatedURL = temporaryOutputURL.appendingPathExtension("iso")
        defer {
            try? fileManager.removeItem(at: temporaryOutputURL)
            try? fileManager.removeItem(at: generatedURL)
        }

        let exitCode = try processRunner(
            "/usr/bin/hdiutil",
            [
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                "VEIL_AUTO",
                "-o",
                temporaryOutputURL.path,
                stagingDirectory.path
            ]
        )

        guard exitCode == 0 else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("hdiutil exited with code \(exitCode).")
        }

        if fileManager.fileExists(atPath: generatedURL.path) {
            try? fileManager.removeItem(at: mediaURL)
            try fileManager.moveItem(at: generatedURL, to: mediaURL)
        } else if fileManager.fileExists(atPath: temporaryOutputURL.path) {
            try? fileManager.removeItem(at: mediaURL)
            try fileManager.moveItem(at: temporaryOutputURL, to: mediaURL)
        } else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("hdiutil did not produce an ISO image.")
        }
    }

    private static func mediaIsCurrent(mediaURL: URL, answerFileURL: URL, agentBundleURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: mediaURL.path),
              let mediaDate = try? fileManager.attributesOfItem(atPath: mediaURL.path)[.modificationDate] as? Date,
              let answerDate = try? fileManager.attributesOfItem(atPath: answerFileURL.path)[.modificationDate] as? Date else {
            return false
        }

        let payloadDate = max(answerDate, latestModificationDate(in: agentBundleURL) ?? answerDate)
        return mediaDate >= payloadDate
    }

    private static func latestModificationDate(in url: URL) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        var latest = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            ?? Date.distantPast
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return latest
        }

        for case let fileURL as URL in enumerator {
            guard let modificationDate = try? fileURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else {
                continue
            }
            latest = max(latest, modificationDate)
        }
        return latest
    }

    public static func runProcess(executablePath: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public enum VMRuntimePhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
public final class VMRuntimeModel {
    public private(set) var phase: VMRuntimePhase = .idle
    public private(set) var snapshot: VMRuntimeSnapshot?
    public private(set) var errorMessage: String?
    public private(set) var diagnosticsURL: URL?

    private let service: any VMRuntimeService

    public init(service: any VMRuntimeService) {
        self.service = service
    }

    public var statusText: String {
        guard let snapshot else {
            return phase == .failed ? (errorMessage ?? "VM runtime unavailable") : "VM runtime not loaded"
        }

        switch snapshot.state {
        case .unsupported:
            return "VM runtime unsupported"
        case .notConfigured:
            return "VM profile not configured"
        case .stopped:
            return "VM stopped"
        case .starting:
            return "VM starting"
        case .running:
            return "VM running"
        case .suspended:
            return "VM suspended"
        case .failed:
            return "VM failed"
        }
    }

    public var canStart: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.virtualizationAvailable &&
            snapshot.minimumOSSupported &&
            snapshot.profileName != nil &&
            snapshot.bootReady &&
            (snapshot.state == .stopped || snapshot.state == .suspended)
    }

    public var canStop: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.state == .running || snapshot.state == .suspended
    }

    public var capabilitySummary: String {
        guard let snapshot else {
            return "VM runtime capabilities not loaded"
        }

        if let runtimeProvider = snapshot.runtimeProvider {
            let availability = snapshot.virtualizationAvailable ? "available" : "unavailable"
            return "\(runtimeProvider.displayName) local provider \(availability) on \(snapshot.architecture)"
        }

        let availability = snapshot.virtualizationAvailable ? "available" : "unavailable"
        return "Virtualization.framework \(availability) on \(snapshot.architecture)"
    }

    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.loadSnapshot()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func refreshRuntimeEvidence() async {
        do {
            snapshot = try await service.loadSnapshot()
            errorMessage = nil
            if phase == .idle || phase == .failed {
                phase = .loaded
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func createDefaultProfile() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.createDefaultProfile()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func prepareDefaultVM() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.prepareDefaultVM()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func createDefaultVirtualDisk() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.createDefaultVirtualDisk()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.updateProfilePaths(
                installerMediaPath: installerMediaPath,
                driverMediaPath: driverMediaPath,
                virtualDiskPath: virtualDiskPath
            )
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func markGuestAgentConnected(agentVersion: String) async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.markGuestAgentConnected(agentVersion: agentVersion)
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func markWindowsInstalled() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.markWindowsInstalled()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func start() async {
        phase = .loading
        errorMessage = nil

        if canStart, var startingSnapshot = snapshot {
            startingSnapshot.state = .starting
            startingSnapshot.detail = "Starting Windows setup. Veil keeps runtime status and setup evidence in the main window."
            snapshot = startingSnapshot
        }

        do {
            snapshot = try await service.start()
            phase = .loaded
        } catch {
            let message = userMessage(for: error)
            if var failedSnapshot = snapshot {
                failedSnapshot.state = .failed
                failedSnapshot.detail = message
                snapshot = failedSnapshot
            }
            errorMessage = message
            phase = .failed
        }
    }

    public func stop() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.stop()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async {
        do {
            _ = try await service.sendConsolePointerTap(
                normalizedX: normalizedX,
                normalizedY: normalizedY
            )
            errorMessage = nil
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func sendConsoleKey(_ key: String) async {
        do {
            _ = try await service.sendConsoleKey(key)
            errorMessage = nil
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func exportDiagnostics(to directory: URL) async {
        phase = .loading
        errorMessage = nil

        do {
            diagnosticsURL = try await service.exportDiagnostics(to: directory)
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}

public struct LocalVMRuntimeService: VMRuntimeService {
    private static let armUEFIVariablesStoreSizeBytes: UInt64 = 64 * 1_024 * 1_024

    private let profileStore: any VMProfileStore
    private let defaultHomeDirectory: URL
    private let bootRunner: any VMRuntimeBooting
    private let bootReportStore: any VMRuntimeBootReportStore
    private let qemuLaunchRecordStore: any QEMULaunchRecordStore
    private let providerProbe: VMRuntimeProviderProbe
    private let resourcePlan: VMResourcePlan?
    private let diagnosticDate: @Sendable () -> Date
    private let automaticInstallMediaBuilder: any AutomaticInstallMediaBuilding
    private let consoleScreenshotRefresher: @Sendable (URL, URL) -> Void
    private let pointerEventSender: (any QEMUPointerEventSending)?
    private let keySequenceSender: (any QEMUKeySequenceSending)?
    private let qemuLaunchProcessIsRunning: @Sendable (Int32) -> Bool
    private let qemuLaunchProcessTerminator: @Sendable (Int32) -> Bool
    private let firmwareVarsTemplatePaths: [String]

    public init(
        profileStore: any VMProfileStore = JSONVMProfileStore(),
        defaultHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bootRunner: any VMRuntimeBooting = UnavailableVMRuntimeBooter(),
        bootReportStore: any VMRuntimeBootReportStore = JSONVMRuntimeBootReportStore(),
        qemuLaunchRecordStore: any QEMULaunchRecordStore = JSONQEMULaunchRecordStore(),
        providerProbe: VMRuntimeProviderProbe = VMRuntimeProviderProbe(),
        resourcePlan: VMResourcePlan? = nil,
        diagnosticDate: @escaping @Sendable () -> Date = Date.init,
        automaticInstallMediaBuilder: any AutomaticInstallMediaBuilding = HdiutilAutomaticInstallMediaBuilder(),
        consoleScreenshotRefresher: @escaping @Sendable (URL, URL) -> Void = QEMUVMRuntimeBooter.captureConsoleScreenshot,
        pointerEventSender: (any QEMUPointerEventSending)? = nil,
        keySequenceSender: (any QEMUKeySequenceSending)? = nil,
        qemuLaunchProcessIsRunning: @escaping @Sendable (Int32) -> Bool = LocalVMRuntimeService.processIsRunning,
        qemuLaunchProcessTerminator: @escaping @Sendable (Int32) -> Bool = LocalVMRuntimeService.terminateProcess,
        firmwareVarsTemplatePaths: [String]? = nil
    ) {
        self.profileStore = profileStore
        self.defaultHomeDirectory = defaultHomeDirectory
        self.bootRunner = bootRunner
        self.bootReportStore = bootReportStore
        self.qemuLaunchRecordStore = qemuLaunchRecordStore
        self.providerProbe = providerProbe
        self.resourcePlan = resourcePlan
        self.diagnosticDate = diagnosticDate
        self.automaticInstallMediaBuilder = automaticInstallMediaBuilder
        self.consoleScreenshotRefresher = consoleScreenshotRefresher
        self.pointerEventSender = pointerEventSender
        self.keySequenceSender = keySequenceSender
        self.qemuLaunchProcessIsRunning = qemuLaunchProcessIsRunning
        self.qemuLaunchProcessTerminator = qemuLaunchProcessTerminator
        self.firmwareVarsTemplatePaths = firmwareVarsTemplatePaths
            ?? (
                LocalQEMUWindowsBootPlanFactory.defaultSecureFirmwareVarsTemplatePaths(homeDirectory: defaultHomeDirectory)
                    + LocalQEMUWindowsBootPlanFactory.defaultFirmwareVarsTemplatePaths
            )
    }

    public func loadSnapshot() async throws -> VMRuntimeSnapshot {
        let architecture = Self.hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let virtualizationAvailable = architecture == "arm64" && minimumOSSupported
        let runtimeProviders = providerProbe.localProviders(
            architecture: architecture,
            minimumOSSupported: minimumOSSupported
        )
        let activeProvider = runtimeProviders.first { $0.kind == .qemuHypervisor && $0.status == .active }
            ?? runtimeProviders.first { $0.kind == .appleVirtualization }
        let profile = try await profileStore.load()

        if virtualizationAvailable, let profile {
            let latestLaunchRecord = try? await qemuLaunchRecordStore.loadLatest()
            let latestConsoleScreenshot = refreshedConsoleScreenshot(from: latestLaunchRecord)
            let installationSteps = Self.installationSteps(for: profile)
            let preflightChecks = Self.preflightChecks(for: profile)
            let bootPathReadiness = Self.bootPathReadiness(
                installationSteps: installationSteps,
                preflightChecks: preflightChecks
            )
            let runtimeState = await bootRunner.runtimeState()
            let orphanQEMUProcess = QEMUVMRuntimeBooter.runningProcess(
                attachedToVirtualDiskPath: profile.virtualDiskPath
            )
            let recordedQEMUState = Self.qemuLaunchRuntimeState(
                from: latestLaunchRecord,
                profile: profile,
                processIsRunning: qemuLaunchProcessIsRunning
            )
            let inferredRuntimeState = runtimeState
                ?? recordedQEMUState
                ?? (orphanQEMUProcess == nil ? nil : .running)
            let state = inferredRuntimeState
                ?? .stopped
            let virtualDiskAllocatedBytes = Self.allocatedFileSize(
                path: profile.virtualDiskPath,
                bookmarkData: profile.virtualDiskBookmarkData
            )
            let windowsInstalled = profile.windowsInstalled == true
            let deviceSummary = Self.deviceSummary(for: profile)
            let installEvidence = Self.installEvidence(
                bootPathReadiness: bootPathReadiness,
                windowsInstalled: windowsInstalled,
                guestAgentVersion: profile.guestAgentVersion,
                virtualDiskAllocatedBytes: virtualDiskAllocatedBytes
            )
            return VMRuntimeSnapshot(
                state: state,
                virtualizationAvailable: true,
                architecture: architecture,
                minimumOSSupported: true,
                profileName: profile.name,
                cpuCount: profile.cpuCount,
                memoryMB: profile.memoryMB,
                diskGB: profile.diskGB,
                installerMediaPath: profile.installerMediaPath,
                driverMediaPath: profile.driverMediaPath,
                virtualDiskPath: profile.virtualDiskPath,
                virtualDiskAllocatedBytes: virtualDiskAllocatedBytes,
                automaticInstallAnswerFilePath: Self.automaticInstallAnswerFilePathIfExists(for: profile),
                automaticInstallMediaPath: Self.automaticInstallMediaPathIfExists(for: profile),
                latestConsoleScreenshotPath: latestConsoleScreenshot.path,
                latestConsoleLaunch: Self.consoleLaunchEvidence(
                    from: latestLaunchRecord,
                    consoleScreenshotPath: latestConsoleScreenshot.path,
                    consoleScreenshotRefreshedAt: latestConsoleScreenshot.refreshedAt
                ),
                runningQEMUProcess: orphanQEMUProcess,
                runtimeProvider: activeProvider,
                runtimeProviders: runtimeProviders,
                installationSteps: installationSteps,
                preflightChecks: preflightChecks,
                deviceSummary: deviceSummary,
                configurationSummary: Self.configurationSummary(for: profile, devices: deviceSummary),
                installEvidence: installEvidence,
                bootReady: bootPathReadiness.isReady,
                windowsInstalled: windowsInstalled,
                detail: inferredRuntimeState.map(Self.runtimeDetail(for:)) ?? (
                    Self.stoppedDetail(
                        bootPathReadiness: bootPathReadiness,
                        windowsInstalled: windowsInstalled,
                        virtualDiskAllocatedBytes: virtualDiskAllocatedBytes
                    )
                )
            )
        }

        return VMRuntimeSnapshot(
            state: virtualizationAvailable ? .notConfigured : .unsupported,
            virtualizationAvailable: virtualizationAvailable,
            architecture: architecture,
            minimumOSSupported: minimumOSSupported,
            profileName: nil,
            runtimeProvider: activeProvider,
            runtimeProviders: runtimeProviders,
            detail: virtualizationAvailable
                ? "No Windows VM profile has been created."
                : "Veil requires macOS 15+ on Apple Silicon."
        )
    }

    public func createDefaultProfile() async throws -> VMRuntimeSnapshot {
        let profile = defaultProfile()
        try FileManager.default.createDirectory(
            atPath: profile.sharedFolderPath,
            withIntermediateDirectories: true
        )
        try Self.prepareGuestAgentInstallerBundle(for: profile)
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func prepareDefaultVM() async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        profile = try prepareDefaultResources(for: profile)
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        if profile.virtualDiskPath != nil {
            return try await loadSnapshot()
        }

        profile = try prepareDefaultResources(for: profile)
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    private func prepareDefaultResources(for profile: VMProfile) throws -> VMProfile {
        var profile = profile

        try FileManager.default.createDirectory(
            atPath: profile.sharedFolderPath,
            withIntermediateDirectories: true
        )
        if Self.shouldPrepareAutomaticInstallMedia(for: profile) {
            try Self.prepareGuestAgentInstallerBundle(for: profile)
            try Self.prepareAutomaticInstallAnswerFile(for: profile)
            try automaticInstallMediaBuilder.prepareMedia(
                answerFileURL: Self.automaticInstallAnswerFileURL(for: profile),
                mediaURL: Self.automaticInstallMediaURL(for: profile)
            )
        }

        if let virtualDiskPath = profile.virtualDiskPath {
            try Self.prepareTPMStateDirectory(virtualDiskPath: virtualDiskPath)
            try Self.prepareUEFIVariablesStore(
                virtualDiskPath: virtualDiskPath,
                templatePaths: firmwareVarsTemplatePaths,
                shouldUpgradeToSecureVars: profile.windowsInstalled != true
            )
            return profile
        }

        let diskURL = defaultVirtualDiskURL(for: profile)
        try FileManager.default.createDirectory(
            at: diskURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: diskURL.path) {
            let didCreateDisk = FileManager.default.createFile(atPath: diskURL.path, contents: nil)
            guard didCreateDisk else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let fileHandle = try FileHandle(forWritingTo: diskURL)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.truncate(atOffset: UInt64(profile.diskGB) * 1_024 * 1_024 * 1_024)

        profile.virtualDiskPath = diskURL.path
        try Self.prepareTPMStateDirectory(virtualDiskPath: diskURL.path)
        try Self.prepareUEFIVariablesStore(
            virtualDiskPath: diskURL.path,
            templatePaths: firmwareVarsTemplatePaths,
            shouldUpgradeToSecureVars: profile.windowsInstalled != true
        )
        return profile
    }

    private static func prepareTPMStateDirectory(virtualDiskPath: String) throws {
        let tpmStateURL = URL(fileURLWithPath: virtualDiskPath)
            .deletingLastPathComponent()
            .appendingPathComponent("tpm", isDirectory: true)
        try FileManager.default.createDirectory(at: tpmStateURL, withIntermediateDirectories: true)
    }

    private static func prepareUEFIVariablesStore(
        virtualDiskPath: String,
        templatePaths: [String],
        shouldUpgradeToSecureVars: Bool
    ) throws {
        guard let templatePath = templatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }

        let varsURL = URL(fileURLWithPath: virtualDiskPath)
            .deletingLastPathComponent()
            .appendingPathComponent("uefi-vars.fd")
        let shouldReplaceExisting = shouldUpgradeToSecureVars
            && templatePath.hasSuffix("edk2-arm-secure-vars.fd")
            && FileManager.default.fileExists(atPath: varsURL.path)
        if shouldReplaceExisting {
            try FileManager.default.removeItem(at: varsURL)
        }

        guard !FileManager.default.fileExists(atPath: varsURL.path) else {
            return
        }

        try FileManager.default.copyItem(atPath: templatePath, toPath: varsURL.path)
        let fileHandle = try FileHandle(forWritingTo: varsURL)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.truncate(atOffset: armUEFIVariablesStoreSizeBytes)
    }

    private static func automaticInstallAnswerFileURL(for profile: VMProfile) -> URL {
        URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("Autounattend.xml")
    }

    private static func automaticInstallMediaURL(for profile: VMProfile) -> URL {
        URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("VeilAutoInstall.iso")
    }

    private static func guestAgentInstallerBundleURL(for profile: VMProfile) -> URL {
        URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("Veil Guest Agent", isDirectory: true)
    }

    private static func shouldPrepareAutomaticInstallMedia(for profile: VMProfile) -> Bool {
        profile.windowsInstalled != true || profile.guestAgentVersion == nil
    }

    private static func prepareGuestAgentInstallerBundle(for profile: VMProfile) throws {
        let fileManager = FileManager.default
        let bundleURL = guestAgentInstallerBundleURL(for: profile)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let sourceURL = windowsAgentSourceURL()
        try copyWindowsAgentSubdirectory(
            named: "scripts",
            from: sourceURL,
            to: bundleURL
        )
        try copyWindowsAgentSubdirectoryIfPresent(
            named: "app",
            from: sourceURL,
            to: bundleURL
        )
        try copyWindowsAgentSubdirectory(
            named: "src",
            from: sourceURL,
            to: bundleURL
        )

        try installAgentCommandText.write(
            to: bundleURL.appendingPathComponent("Install Veil Agent.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try startAgentCommandText.write(
            to: bundleURL.appendingPathComponent("Start Veil Agent.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try collectAgentDiagnosticsCommandText.write(
            to: bundleURL.appendingPathComponent("Collect Veil Agent Diagnostics.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try guestAgentReadmeText.write(
            to: bundleURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func copyWindowsAgentSubdirectory(named name: String, from sourceRootURL: URL, to bundleURL: URL) throws {
        let fileManager = FileManager.default
        let sourceURL = sourceRootURL.appendingPathComponent(name, isDirectory: true)
        let destinationURL = bundleURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed(
                "Windows agent source folder is missing at \(sourceURL.path)."
            )
        }

        if directoryContentsMatch(sourceURL, destinationURL) {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func copyWindowsAgentSubdirectoryIfPresent(named name: String, from sourceRootURL: URL, to bundleURL: URL) throws {
        let fileManager = FileManager.default
        let sourceURL = sourceRootURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }

        let destinationURL = bundleURL.appendingPathComponent(name, isDirectory: true)
        if directoryContentsMatch(sourceURL, destinationURL) {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private struct DirectoryFileManifestEntry: Equatable {
        var relativePath: String
        var byteCount: Int?
        var modifiedAt: Date?
    }

    private static func directoryContentsMatch(_ sourceURL: URL, _ destinationURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              FileManager.default.fileExists(atPath: destinationURL.path) else {
            return false
        }

        return directoryFileManifest(for: sourceURL) == directoryFileManifest(for: destinationURL)
    }

    private static func directoryFileManifest(for directoryURL: URL) -> [DirectoryFileManifestEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { item -> DirectoryFileManifestEntry? in
                guard let url = item as? URL,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }

                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let relativePath = String(url.path.dropFirst(directoryURL.path.count + 1))
                return DirectoryFileManifestEntry(
                    relativePath: relativePath,
                    byteCount: values?.fileSize,
                    modifiedAt: values?.contentModificationDate
                )
            }
            .sorted { $0.relativePath < $1.relativePath }
    }

    private static func windowsAgentSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("windows-agent", isDirectory: true)
    }

    private static let installAgentCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Install-VeilAgent.ps1" %*
    if errorlevel 1 pause

    """

    private static let startAgentCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Start-VeilAgent.ps1" %*
    if errorlevel 1 pause

    """

    private static let collectAgentDiagnosticsCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Collect-VeilAgentDiagnostics.ps1" %*
    if errorlevel 1 pause

    """

    private static let guestAgentReadmeText = """
    Veil Guest Agent

    Run Install Veil Agent.cmd after Windows 11 reaches the desktop.
    The installer uses the packaged VeilAgent.exe bundle when present, registers the VeilAgent user logon task, and points it at ws://127.0.0.1:18444/.
    Bootstrap and installer logs are written under %LOCALAPPDATA%\\Veil\\Agent\\logs.
    If this media does not include app\\VeilAgent.exe, build it on the Mac with apps/windows-agent/scripts/publish-veil-agent-bundle.sh before preparing the VM again.

    Run Start Veil Agent.cmd to start the agent immediately after installation.
    Run Collect Veil Agent Diagnostics.cmd to write a metadata-only diagnostics ZIP to the Windows desktop when install, start, or connection checks fail.
    Keep this folder in the Veil Shared drive while Veil is in pre-alpha.

    """

    private static func automaticInstallAnswerFilePathIfExists(for profile: VMProfile) -> String? {
        let url = automaticInstallAnswerFileURL(for: profile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url.path
    }

    private static func automaticInstallMediaPathIfExists(for profile: VMProfile) -> String? {
        let url = automaticInstallMediaURL(for: profile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url.path
    }

    private static func existingConsoleScreenshotPath(from launchRecord: QEMULaunchRecord?) -> String? {
        guard let path = launchRecord?.consoleScreenshotPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !protectedPathNeedsFilePicker(path, bookmarkData: nil),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return path
    }

    private static func qemuLaunchRuntimeState(
        from launchRecord: QEMULaunchRecord?,
        profile: VMProfile,
        processIsRunning: @Sendable (Int32) -> Bool
    ) -> VMRuntimeState? {
        guard let pid = launchRecord?.pid,
              let virtualDiskPath = profile.virtualDiskPath,
              launchRecord?.arguments.contains(where: { $0.contains(virtualDiskPath) }) == true,
              processIsRunning(pid) else {
            return nil
        }

        return .running
    }

    public static func processIsRunning(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func terminateProcess(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", String(pid)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func stopQEMULaunchIfRunning(
        _ launchRecord: QEMULaunchRecord?,
        profile: VMProfile,
        processIsRunning: @Sendable (Int32) -> Bool,
        processTerminator: @Sendable (Int32) -> Bool
    ) {
        guard let pid = launchRecord?.pid,
              let virtualDiskPath = profile.virtualDiskPath,
              launchRecord?.arguments.contains(where: { $0.contains(virtualDiskPath) }) == true,
              processIsRunning(pid) else {
            return
        }

        _ = processTerminator(pid)
    }

    private struct ConsoleScreenshotRefresh {
        var path: String?
        var refreshedAt: Date?
    }

    private struct ConsoleScreenshotFileEvidence: Equatable {
        var modifiedAt: Date?
        var byteCount: Int?
        var digest: UInt64?
    }

    private func refreshedConsoleScreenshot(from launchRecord: QEMULaunchRecord?) -> ConsoleScreenshotRefresh {
        guard let path = Self.existingConsoleScreenshotPath(from: launchRecord),
              let monitorSocketPath = launchRecord?.monitorSocketPath,
              FileManager.default.fileExists(atPath: monitorSocketPath) else {
            return ConsoleScreenshotRefresh(
                path: Self.existingConsoleScreenshotPath(from: launchRecord),
                refreshedAt: nil
            )
        }

        let beforeEvidence = Self.consoleScreenshotFileEvidence(atPath: path)
        consoleScreenshotRefresher(
            URL(fileURLWithPath: monitorSocketPath),
            URL(fileURLWithPath: path)
        )
        let refreshedPath = Self.existingConsoleScreenshotPath(from: launchRecord) ?? path
        let afterEvidence = Self.consoleScreenshotFileEvidence(atPath: refreshedPath)
        let refreshedAt = Self.consoleScreenshotDidRefresh(
            before: beforeEvidence,
            after: afterEvidence
        ) ? diagnosticDate() : nil
        return ConsoleScreenshotRefresh(path: refreshedPath, refreshedAt: refreshedAt)
    }

    private static func consoleScreenshotFileEvidence(atPath path: String) -> ConsoleScreenshotFileEvidence? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let data = try? Data(contentsOf: url)
        return ConsoleScreenshotFileEvidence(
            modifiedAt: values?.contentModificationDate,
            byteCount: values?.fileSize ?? data?.count,
            digest: data.map(stableDigest)
        )
    }

    private static func consoleScreenshotDidRefresh(
        before: ConsoleScreenshotFileEvidence?,
        after: ConsoleScreenshotFileEvidence?
    ) -> Bool {
        guard let after else {
            return false
        }
        guard let before else {
            return true
        }
        return before != after
    }

    private static func stableDigest(for data: Data) -> UInt64 {
        data.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)).multipliedReportingOverflow(by: 0x0000_0100_0000_01b3).partialValue
        }
    }

    private static func consoleLaunchEvidence(
        from launchRecord: QEMULaunchRecord?,
        consoleScreenshotPath: String? = nil,
        consoleScreenshotRefreshedAt: Date? = nil
    ) -> VMConsoleLaunchEvidence? {
        guard let launchRecord else {
            return nil
        }

        return VMConsoleLaunchEvidence(
            provider: launchRecord.provider,
            pid: launchRecord.pid,
            processLogPath: launchRecord.processLogPath,
            monitorSocketPath: launchRecord.monitorSocketPath,
            qmpSocketPath: launchRecord.qmpSocketPath,
            vncHost: launchRecord.vncHost,
            vncPort: launchRecord.vncPort,
            consoleScreenshotPath: consoleScreenshotPath ?? existingConsoleScreenshotPath(from: launchRecord),
            consoleScreenshotRefreshedAt: consoleScreenshotRefreshedAt,
            previewStatus: consolePreviewStatus(
                consoleScreenshotPath: consoleScreenshotPath ?? existingConsoleScreenshotPath(from: launchRecord),
                consoleScreenshotRefreshedAt: consoleScreenshotRefreshedAt
            ),
            startedAt: launchRecord.startedAt
        )
    }

    private static func consolePreviewStatus(
        consoleScreenshotPath: String?,
        consoleScreenshotRefreshedAt: Date?
    ) -> VMConsolePreviewStatus {
        guard consoleScreenshotPath != nil else {
            return .unavailable
        }

        return consoleScreenshotRefreshedAt == nil ? .stale : .fresh
    }

    private static func prepareAutomaticInstallAnswerFile(for profile: VMProfile) throws {
        let answerFileURL = automaticInstallAnswerFileURL(for: profile)
        let answerFile = automaticInstallAnswerFile()
        if FileManager.default.fileExists(atPath: answerFileURL.path),
           (try? String(contentsOf: answerFileURL, encoding: .utf8)) == answerFile {
            return
        }

        try answerFile.write(to: answerFileURL, atomically: true, encoding: .utf8)
    }

    private static func automaticInstallAnswerFile() -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <settings pass="windowsPE">
            <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <SetupUILanguage>
                <UILanguage>ko-KR</UILanguage>
              </SetupUILanguage>
              <InputLocale>ko-KR</InputLocale>
              <SystemLocale>ko-KR</SystemLocale>
              <UILanguage>ko-KR</UILanguage>
              <UserLocale>ko-KR</UserLocale>
            </component>
            <component name="Microsoft-Windows-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <DiskConfiguration>
                <Disk wcm:action="add">
                  <DiskID>0</DiskID>
                  <WillWipeDisk>true</WillWipeDisk>
                  <CreatePartitions>
                    <CreatePartition wcm:action="add">
                      <Order>1</Order>
                      <Type>EFI</Type>
                      <Size>100</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                      <Order>2</Order>
                      <Type>MSR</Type>
                      <Size>16</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                      <Order>3</Order>
                      <Type>Primary</Type>
                      <Extend>true</Extend>
                    </CreatePartition>
                  </CreatePartitions>
                  <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                      <Order>1</Order>
                      <PartitionID>1</PartitionID>
                      <Label>System</Label>
                      <Format>FAT32</Format>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                      <Order>2</Order>
                      <PartitionID>3</PartitionID>
                      <Label>Windows</Label>
                      <Letter>C</Letter>
                      <Format>NTFS</Format>
                    </ModifyPartition>
                  </ModifyPartitions>
                </Disk>
                <WillShowUI>Never</WillShowUI>
              </DiskConfiguration>
              <ImageInstall>
                <OSImage>
                  <InstallTo>
                    <DiskID>0</DiskID>
                    <PartitionID>3</PartitionID>
                  </InstallTo>
                  <InstallFrom>
                    <MetaData wcm:action="add">
                      <Key>/IMAGE/NAME</Key>
                      <Value>Windows 11 Pro</Value>
                    </MetaData>
                  </InstallFrom>
                  <WillShowUI>Never</WillShowUI>
                </OSImage>
              </ImageInstall>
              <UserData>
                <AcceptEula>true</AcceptEula>
                <ProductKey>
                  <WillShowUI>Never</WillShowUI>
                </ProductKey>
              </UserData>
            </component>
          </settings>
          <settings pass="specialize">
            <component name="Microsoft-Windows-Deployment" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                  <Order>1</Order>
                  <Path>cmd /c reg add HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                  <Description>Allow Windows OOBE offline setup when no inbox network driver is available</Description>
                </RunSynchronousCommand>
              </RunSynchronous>
            </component>
          </settings>
          <settings pass="oobeSystem">
            <component name="Microsoft-Windows-International-Core" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <InputLocale>ko-KR</InputLocale>
              <SystemLocale>ko-KR</SystemLocale>
              <UILanguage>ko-KR</UILanguage>
              <UserLocale>ko-KR</UserLocale>
            </component>
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
              <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
              </OOBE>
              <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                  <Order>1</Order>
                  <Description>Install and start the Veil guest agent from VEIL_AUTO media</Description>
                  <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$volume = Get-Volume -FileSystemLabel 'VEIL_AUTO' -ErrorAction SilentlyContinue | Select-Object -First 1; if ($volume -and $volume.DriveLetter) { $script = Join-Path ($volume.DriveLetter + ':\\') 'Veil Guest Agent\\scripts\\Bootstrap-VeilAgentFromMedia.ps1'; if (Test-Path $script) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script } }"</CommandLine>
                </SynchronousCommand>
              </FirstLogonCommands>
            </component>
          </settings>
        </unattend>

        """
    }

    private static func allocatedFileSize(path: String?, bookmarkData: Data? = nil) -> Int64? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if protectedPathNeedsFilePicker(path, bookmarkData: bookmarkData) {
            return nil
        }

        let access = securityScopedAccess(role: .disk, bookmarkData: bookmarkData)
        defer {
            access?.stop()
        }
        let url = access?.url ?? URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ])

        if let totalAllocatedSize = values?.totalFileAllocatedSize {
            return Int64(totalAllocatedSize)
        }

        if let allocatedSize = values?.fileAllocatedSize {
            return Int64(allocatedSize)
        }

        return nil
    }

    public func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        let existingProfile = profile
        profile.installerMediaPath = installerMediaPath
        profile.installerMediaBookmarkData = Self.bookmarkData(
            for: installerMediaPath,
            existingPath: existingProfile.installerMediaPath,
            existingBookmarkData: existingProfile.installerMediaBookmarkData
        )
        profile.driverMediaPath = driverMediaPath
        profile.driverMediaBookmarkData = Self.bookmarkData(
            for: driverMediaPath,
            existingPath: existingProfile.driverMediaPath,
            existingBookmarkData: existingProfile.driverMediaBookmarkData
        )
        profile.virtualDiskPath = virtualDiskPath
        profile.virtualDiskBookmarkData = Self.bookmarkData(
            for: virtualDiskPath,
            existingPath: existingProfile.virtualDiskPath,
            existingBookmarkData: existingProfile.virtualDiskBookmarkData
        )
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func markGuestAgentConnected(agentVersion: String) async throws -> VMRuntimeSnapshot {
        guard var profile = try await profileStore.load() else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        profile.windowsInstalled = true
        profile.guestAgentVersion = agentVersion
        profile.guestAgentConnectedAt = diagnosticDate()
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func markWindowsInstalled() async throws -> VMRuntimeSnapshot {
        guard var profile = try await profileStore.load(),
              profile.virtualDiskPath != nil else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        profile.windowsInstalled = true
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func start() async throws -> VMRuntimeSnapshot {
        let snapshot = try await loadSnapshot()
        guard snapshot.bootReady else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        guard let profile = try await profileStore.load() else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }
        let securityScopedAccesses = Self.startSecurityScopedAccesses(for: profile)
        defer {
            securityScopedAccesses.forEach { $0.stop() }
        }
        let bootProfile = Self.profileByResolvingSecurityScopedURLs(
            profile,
            accesses: securityScopedAccesses
        )

        let startedAt = diagnosticDate()
        do {
            let resultingState = try await bootRunner.start(profile: bootProfile)
            try? await bootReportStore.save(Self.bootReport(
                startedAt: startedAt,
                completedAt: diagnosticDate(),
                result: .succeeded,
                resultingState: resultingState,
                errorMessage: nil,
                profile: bootProfile
            ))
            return try await loadSnapshot()
        } catch {
            let resultingState = await bootRunner.runtimeState() ?? .failed
            try? await bootReportStore.save(Self.bootReport(
                startedAt: startedAt,
                completedAt: diagnosticDate(),
                result: .failed,
                resultingState: resultingState,
                errorMessage: Self.errorMessage(for: error),
                profile: bootProfile
            ))
            throw error
        }
    }

    public func stop() async throws -> VMRuntimeSnapshot {
        let profile = try await profileStore.load()
        let latestLaunchRecord = try? await qemuLaunchRecordStore.loadLatest()
        _ = try await bootRunner.stop()
        if let profile {
            Self.stopQEMULaunchIfRunning(
                latestLaunchRecord,
                profile: profile,
                processIsRunning: qemuLaunchProcessIsRunning,
                processTerminator: qemuLaunchProcessTerminator
            )
        }
        return try await loadSnapshot()
    }

    public func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord {
        let sender = pointerEventSender ?? QEMUPointerEventSender(launchRecordStore: qemuLaunchRecordStore)
        return try await sender.sendTap(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    public func sendConsoleKey(_ key: String) async throws -> QEMUKeySendRecord {
        let sender = keySequenceSender ?? QEMUKeySequenceSender(launchRecordStore: qemuLaunchRecordStore)
        return try await sender.send(steps: [
            QEMUKeySequenceStep(key: key, delayAfterSend: 0)
        ])
    }

    public func exportDiagnostics(to directory: URL) async throws -> URL {
        let generatedAt = diagnosticDate()
        let snapshot = try await loadSnapshot()
        let profile = try await profileStore.load()
        let lastBootReport = try await bootReportStore.load()
        let bundle = VMRuntimeDiagnosticBundle(
            generatedAt: generatedAt,
            host: Self.diagnosticHost(),
            snapshot: snapshot,
            profile: profile?.withoutSecurityScopedBookmarks(),
            lastBootReport: lastBootReport?.withoutSecurityScopedBookmarks()
        )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let outputURL = directory.appendingPathComponent(Self.diagnosticFileName(for: generatedAt))
        let data = try JSONEncoder.veilDiagnostics.encode(bundle)
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private struct SecurityScopedFileAccess {
        var role: Role
        var url: URL
        var didStart: Bool

        enum Role {
            case installer
            case drivers
            case disk
        }

        func stop() {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private static func bookmarkData(
        for path: String?,
        existingPath: String? = nil,
        existingBookmarkData: Data? = nil
    ) -> Data? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if path == existingPath, let existingBookmarkData {
            return existingBookmarkData
        }

        return try? URL(fileURLWithPath: path).bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func startSecurityScopedAccesses(for profile: VMProfile) -> [SecurityScopedFileAccess] {
        [
            securityScopedAccess(
                role: .installer,
                bookmarkData: profile.installerMediaBookmarkData
            ),
            securityScopedAccess(
                role: .drivers,
                bookmarkData: profile.driverMediaBookmarkData
            ),
            securityScopedAccess(
                role: .disk,
                bookmarkData: profile.virtualDiskBookmarkData
            )
        ].compactMap { $0 }
    }

    private static func securityScopedAccess(
        role: SecurityScopedFileAccess.Role,
        bookmarkData: Data?
    ) -> SecurityScopedFileAccess? {
        guard let bookmarkData else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return SecurityScopedFileAccess(
                role: role,
                url: url,
                didStart: url.startAccessingSecurityScopedResource()
            )
        } catch {
            return nil
        }
    }

    private static func profileByResolvingSecurityScopedURLs(
        _ profile: VMProfile,
        accesses: [SecurityScopedFileAccess]
    ) -> VMProfile {
        var profile = profile
        for access in accesses {
            switch access.role {
            case .installer:
                profile.installerMediaPath = access.url.path
            case .drivers:
                profile.driverMediaPath = access.url.path
            case .disk:
                profile.virtualDiskPath = access.url.path
            }
        }
        return profile
    }

    private static func hostArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func diagnosticHost() -> VMRuntimeDiagnosticHost {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        return VMRuntimeDiagnosticHost(
            architecture: hostArchitecture(),
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            operatingSystemVersion: "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)"
        )
    }

    private static func diagnosticFileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "veil-vm-diagnostics-\(timestamp).json"
    }

    private func defaultVirtualDiskURL(for profile: VMProfile) -> URL {
        defaultHomeDirectory
            .appendingPathComponent("Virtual Machines", isDirectory: true)
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("\(profile.name).img")
    }

    private func defaultProfile() -> VMProfile {
        var profile = VMProfile.defaultWindows11Arm(homeDirectory: defaultHomeDirectory)
        let plan = resourcePlan ?? VMResourcePolicy.currentHostPlan()
        profile.cpuCount = plan.cpuCount
        profile.memoryMB = plan.memoryMB
        profile.diskGB = plan.diskGB
        return profile
    }

    private static func runtimeDetail(for state: VMRuntimeState) -> String {
        switch state {
        case .starting:
            "Windows VM is starting."
        case .running:
            "Windows VM is running."
        case .suspended:
            "Windows VM is suspended."
        case .failed:
            "Windows VM failed."
        case .stopped:
            "Windows VM is stopped."
        case .notConfigured:
            "No Windows VM profile has been created."
        case .unsupported:
            "Veil requires macOS 15+ on Apple Silicon."
        }
    }

    private static func bootReport(
        startedAt: Date,
        completedAt: Date,
        result: VMRuntimeBootReportResult,
        resultingState: VMRuntimeState,
        errorMessage: String?,
        profile: VMProfile
    ) -> VMRuntimeBootReport {
        VMRuntimeBootReport(
            startedAt: startedAt,
            completedAt: completedAt,
            result: result,
            resultingState: resultingState,
            errorMessage: errorMessage,
            profile: profile.withoutSecurityScopedBookmarks(),
            deviceSummary: deviceSummary(for: profile)
        )
    }

    private static func errorMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    private static func bootPathReadiness(
        installationSteps: [VMInstallationStep],
        preflightChecks: [VMPreflightCheck]
    ) -> (isReady: Bool, detail: String) {
        let hasFailedPreflight = preflightChecks.contains(where: { $0.state == .failed })

        for step in installationSteps where step.id != "guest-agent" && step.state != .complete {
            if step.id == "windows-installer" || step.id == "virtual-disk" {
                let missingPathDetails = [
                    "Select a Windows 11 Arm installer before setup can continue.",
                    "Select a virtual disk file before setup can continue."
                ]

                if missingPathDetails.contains(step.detail) {
                    return (false, "Installer media and virtual disk paths are required before boot.")
                }

                return (false, step.detail)
            }

            if hasFailedPreflight {
                return (false, "VM profile needs attention before boot.")
            }

            return (false, step.detail)
        }

        if hasFailedPreflight {
            return (false, "VM profile needs attention before boot.")
        }

        return (true, "Ready to start Windows.")
    }

    private static func stoppedDetail(
        bootPathReadiness: (isReady: Bool, detail: String),
        windowsInstalled: Bool,
        virtualDiskAllocatedBytes: Int64?
    ) -> String {
        if windowsInstalled {
            return "Windows is installed and can be started."
        }

        guard bootPathReadiness.isReady else {
            return bootPathReadiness.detail
        }

        if let virtualDiskAllocatedBytes,
           virtualDiskAllocatedBytes < 1_024 * 1_024 * 1_024 {
            return "Windows is not installed yet."
        }

        return "Windows setup can start."
    }

    private static func installEvidence(
        bootPathReadiness: (isReady: Bool, detail: String),
        windowsInstalled: Bool,
        guestAgentVersion: String?,
        virtualDiskAllocatedBytes: Int64?
    ) -> VMInstallEvidenceSummary {
        if let guestAgentVersion {
            return VMInstallEvidenceSummary(
                kind: .guestAgent,
                isInstalled: true,
                title: "Guest agent connected",
                detail: "Windows is running the Veil guest agent \(guestAgentVersion) over the local runtime channel."
            )
        }

        if windowsInstalled {
            return VMInstallEvidenceSummary(
                kind: .profileFlag,
                isInstalled: true,
                title: "Windows installed",
                detail: "The local profile is marked installed. Guest-agent evidence should replace this before developer preview."
            )
        }

        guard bootPathReadiness.isReady else {
            return VMInstallEvidenceSummary(
                kind: .setupBlocked,
                isInstalled: false,
                title: "Setup blocked",
                detail: bootPathReadiness.detail
            )
        }

        if let virtualDiskAllocatedBytes,
           virtualDiskAllocatedBytes < 1_024 * 1_024 * 1_024 {
            return VMInstallEvidenceSummary(
                kind: .sparseDisk,
                isInstalled: false,
                title: "Windows not installed",
                detail: "The selected virtual disk is still sparse, so Veil should open Windows Setup instead of the launcher."
            )
        }

        return VMInstallEvidenceSummary(
            kind: .setupReady,
            isInstalled: false,
            title: "Windows setup ready",
            detail: "Boot the installer, complete Windows setup, then connect the Veil guest agent."
        )
    }

    private static func fileValidationDetail(path: String, label: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "\(label) path does not exist."
        }

        if isDirectory.boolValue {
            return "\(label) path must reference a file."
        }

        return nil
    }

    private static func installationSteps(for profile: VMProfile) -> [VMInstallationStep] {
        let windowsInstalled = profile.windowsInstalled == true
        let installerState = windowsInstalled
            ? (
                state: VMInstallationStepState.complete,
                detail: "Windows is installed on the selected disk. The installer ISO is no longer required for normal boot."
            )
            : fileStepState(
                path: profile.installerMediaPath,
                bookmarkData: profile.installerMediaBookmarkData,
                bookmarkRole: .installer,
                missingDetail: "Select a Windows 11 Arm installer before setup can continue.",
                validationLabel: "Installer media"
            )
        let diskState = fileStepState(
            path: profile.virtualDiskPath,
            bookmarkData: profile.virtualDiskBookmarkData,
            bookmarkRole: .disk,
            missingDetail: "Select a virtual disk file before setup can continue.",
            validationLabel: "Virtual disk"
        )
        let sharedFolderState = directoryStepState(path: profile.sharedFolderPath)
        let answerFileURL = automaticInstallAnswerFileURL(for: profile)
        let answerMediaURL = automaticInstallMediaURL(for: profile)
        let answerFileState = fileStepState(
            path: answerFileURL.path,
            missingDetail: "Run Prepare VM to create the Windows unattended setup answer file.",
            validationLabel: "Automatic install answer file"
        )
        let answerMediaState = fileStepState(
            path: answerMediaURL.path,
            missingDetail: "Run Prepare VM to create the Windows unattended setup media.",
            validationLabel: "Automatic install media"
        )
        let automaticInstallDetail: String
        let automaticInstallStepState: VMInstallationStepState
        if windowsInstalled {
            automaticInstallDetail = profile.guestAgentVersion == nil
                ? "Windows is installed. Guest-agent media can be rebuilt only when agent recovery is needed."
                : "Guest agent evidence is present. Automatic install media is no longer required at boot."
            automaticInstallStepState = .complete
        } else {
            automaticInstallDetail = automaticInstallStepDetail(
                answerFileState: answerFileState,
                answerMediaState: answerMediaState
            )
            automaticInstallStepState = answerFileState.state == .complete && answerMediaState.state == .complete ? .complete : .blocked
        }

        return [
            VMInstallationStep(
                id: "windows-installer",
                title: "Windows 11 Arm installer",
                detail: installerState.detail ?? "User-provided installer media is ready.",
                state: installerState.state
            ),
            VMInstallationStep(
                id: "virtual-disk",
                title: "Virtual disk",
                detail: diskState.detail ?? "User-provided virtual disk path is ready.",
                state: diskState.state
            ),
            VMInstallationStep(
                id: "shared-folder",
                title: "macOS shared folder",
                detail: sharedFolderState.detail ?? "Shared folder is ready for host and guest file exchange.",
                state: sharedFolderState.state
            ),
            VMInstallationStep(
                id: "auto-install-answer-file",
                title: "Automatic install media",
                detail: automaticInstallDetail,
                state: automaticInstallStepState
            ),
            VMInstallationStep(
                id: "guest-agent",
                title: "Veil guest agent",
                detail: profile.guestAgentVersion == nil
                    ? "Install the guest agent inside Windows after setup."
                    : "Guest agent \(profile.guestAgentVersion ?? "") is connected.",
                state: profile.guestAgentVersion == nil ? .pending : .complete
            )
        ]
    }

    private static func deviceSummary(for profile: VMProfile) -> VMRuntimeDeviceSummary {
        var storageDevices: [VMRuntimeStorageDeviceSummary] = []

        if profile.windowsInstalled != true {
            storageDevices.append(VMRuntimeStorageDeviceSummary(
                role: "installer",
                attachment: "USB mass storage",
                path: profile.installerMediaPath,
                readOnly: true
            ))
        }

        if shouldPrepareAutomaticInstallMedia(for: profile) {
            storageDevices.append(VMRuntimeStorageDeviceSummary(
                role: "auto-install",
                attachment: "USB mass storage",
                path: automaticInstallMediaPathIfExists(for: profile),
                readOnly: true
            ))
        }

        if let driverMediaPath = profile.driverMediaPath {
            storageDevices.append(
                VMRuntimeStorageDeviceSummary(
                    role: "drivers",
                    attachment: "USB mass storage",
                    path: driverMediaPath,
                    readOnly: true
                )
            )
        }

        storageDevices.append(
            VMRuntimeStorageDeviceSummary(
                role: "system-disk",
                attachment: "Virtio block",
                path: profile.virtualDiskPath,
                readOnly: false
            )
        )

        return VMRuntimeDeviceSummary(
            platform: "Generic",
            bootLoader: "EFI",
            storageDevices: storageDevices,
            networkMode: "NAT",
            graphics: VMRuntimeGraphicsSummary(
                widthInPixels: VMRuntimeDeviceDefaults.graphicsWidthInPixels,
                heightInPixels: VMRuntimeDeviceDefaults.graphicsHeightInPixels
            ),
            inputDevices: ["USB keyboard", "USB screen-coordinate pointer"],
            entropyDevice: "Virtio entropy"
        )
    }

    private static func configurationSummary(
        for profile: VMProfile,
        devices: VMRuntimeDeviceSummary
    ) -> VMRuntimeConfigurationSummary {
        VMRuntimeConfigurationSummary(
            system: VMRuntimeSystemConfigurationSummary(
                name: profile.name,
                architecture: "arm64",
                cpuCount: profile.cpuCount,
                memoryMB: profile.memoryMB,
                diskGB: profile.diskGB
            ),
            display: VMRuntimeDisplayConfigurationSummary(
                surface: "Embedded VNC loopback",
                widthInPixels: devices.graphics.widthInPixels,
                heightInPixels: devices.graphics.heightInPixels,
                scalingMode: VMRuntimeDeviceDefaults.displayScalingMode,
                dynamicResolution: VMRuntimeDeviceDefaults.dynamicResolutionPolicy,
                retinaScaling: VMRuntimeDeviceDefaults.retinaScalingPolicy
            ),
            sharing: VMRuntimeSharingConfigurationSummary(
                sharedFolderPath: profile.sharedFolderPath
            ),
            storage: VMRuntimeStorageConfigurationSummary(
                devices: devices.storageDevices
            ),
            network: VMRuntimeNetworkConfigurationSummary(
                mode: devices.networkMode
            ),
            input: VMRuntimeInputConfigurationSummary(
                devices: devices.inputDevices
            ),
            guestAgent: VMRuntimeGuestAgentConfigurationSummary(
                isInstalled: profile.guestAgentVersion != nil,
                version: profile.guestAgentVersion
            )
        )
    }

    private static func fileStepState(
        path: String?,
        bookmarkData: Data? = nil,
        bookmarkRole: SecurityScopedFileAccess.Role = .installer,
        missingDetail: String,
        validationLabel: String
    ) -> (state: VMInstallationStepState, detail: String?) {
        if let detail = protectedFolderAccessDetail(
            path: path,
            bookmarkData: bookmarkData,
            label: validationLabel
        ) {
            return (.blocked, detail)
        }

        let access = securityScopedAccess(role: bookmarkRole, bookmarkData: bookmarkData)
        defer {
            access?.stop()
        }
        let resolvedPath = access?.url.path ?? path

        guard let path = resolvedPath, !path.isEmpty else {
            return (.blocked, missingDetail)
        }

        if let detail = fileValidationDetail(path: path, label: validationLabel) {
            return (.blocked, detail)
        }

        return (.complete, nil)
    }

    private static func automaticInstallStepDetail(
        answerFileState: (state: VMInstallationStepState, detail: String?),
        answerMediaState: (state: VMInstallationStepState, detail: String?)
    ) -> String {
        if answerFileState.state != .complete {
            return answerFileState.detail ?? "Run Prepare VM to create the Windows unattended setup answer file."
        }

        if answerMediaState.state != .complete {
            return answerMediaState.detail ?? "Run Prepare VM to create the Windows unattended setup media."
        }

        return "VeilAutoInstall.iso is ready for Windows Setup unattended inputs."
    }

    private static func directoryStepState(path: String) -> (state: VMInstallationStepState, detail: String?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return (.blocked, "Create the macOS shared folder before Windows setup can continue.")
        }

        guard isDirectory.boolValue else {
            return (.blocked, "Shared folder path must reference a directory.")
        }

        return (.complete, nil)
    }

    private static func preflightChecks(for profile: VMProfile) -> [VMPreflightCheck] {
        [
            installerMediaPreflightCheck(for: profile),
            VMPreflightCheck(
                id: "guest-os",
                title: "Windows Arm guest",
                detail: profile.os == "windows-arm64"
                    ? "Configured for Windows 11 Arm."
                    : "Only Windows 11 Arm profiles are supported on Apple Silicon.",
                state: profile.os == "windows-arm64" ? .passed : .failed
            ),
            VMPreflightCheck(
                id: "cpu",
                title: "CPU allocation",
                detail: profile.cpuCount >= 2
                    ? "\(profile.cpuCount) virtual CPUs configured."
                    : "At least 2 virtual CPUs are required.",
                state: profile.cpuCount >= 2 ? .passed : .failed
            ),
            VMPreflightCheck(
                id: "memory",
                title: "Memory allocation",
                detail: profile.memoryMB >= 4096
                    ? "\(profile.memoryMB) MB memory configured."
                    : "At least 4096 MB memory is required.",
                state: profile.memoryMB >= 4096 ? .passed : .failed
            ),
            VMPreflightCheck(
                id: "disk-size",
                title: "Disk size",
                detail: profile.diskGB >= 64
                    ? "\(profile.diskGB) GB virtual disk configured."
                    : "At least 64 GB disk capacity is required.",
                state: profile.diskGB >= 64 ? .passed : .failed
            )
        ]
    }

    private static func installerMediaPreflightCheck(for profile: VMProfile) -> VMPreflightCheck {
        if profile.windowsInstalled == true {
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: "Windows is installed on the system disk; the installer ISO is no longer required for boot.",
                state: .passed
            )
        }

        return installerMediaPreflightCheck(
            for: profile.installerMediaPath,
            bookmarkData: profile.installerMediaBookmarkData
        )
    }

    private static func installerMediaPreflightCheck(
        for path: String?,
        bookmarkData: Data? = nil
    ) -> VMPreflightCheck {
        if let detail = protectedFolderAccessDetail(
            path: path,
            bookmarkData: bookmarkData,
            label: "Installer media"
        ) {
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: detail,
                state: .failed
            )
        }

        let access = securityScopedAccess(role: .installer, bookmarkData: bookmarkData)
        defer {
            access?.stop()
        }
        let resolvedPath = access?.url.path ?? path

        guard let path = resolvedPath, !path.isEmpty else {
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: "Select a bootable ISO installer for Windows setup.",
                state: .failed
            )
        }

        if let detail = fileValidationDetail(path: path, label: "Installer media") {
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: detail,
                state: .failed
            )
        }

        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch fileExtension {
        case "iso":
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: "Bootable ISO installer selected.",
                state: .passed
            )
        case "vhd", "vhdx":
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: "Select a bootable ISO installer for Windows setup. VHDX files should be used as disk images, not installer media.",
                state: .failed
            )
        default:
            return VMPreflightCheck(
                id: "installer-media",
                title: "Installer media",
                detail: "Select a bootable ISO installer for Windows setup.",
                state: .failed
            )
        }
    }

    private static func protectedFolderAccessDetail(
        path: String?,
        bookmarkData: Data?,
        label: String
    ) -> String? {
        guard let path,
              !path.isEmpty,
              protectedPathNeedsFilePicker(path, bookmarkData: bookmarkData) else {
            return nil
        }

        return "\(label) is in Downloads. Re-select it with the file picker so Veil can store macOS file access before starting Windows."
    }

    private static func protectedPathNeedsFilePicker(_ path: String, bookmarkData: Data?) -> Bool {
        bookmarkData == nil && isDownloadsPath(path)
    }

    private static func isDownloadsPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .pathComponents
            .contains("Downloads")
    }
}
