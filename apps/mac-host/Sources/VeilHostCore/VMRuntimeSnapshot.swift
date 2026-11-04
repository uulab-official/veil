import Foundation

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
    /// Present only when a saved memory-state file exists on disk, so a status surface can offer
    /// resume without first probing the filesystem itself.
    public var suspendedSession: VMSuspensionRecord?
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
        suspendedSession: VMSuspensionRecord? = nil,
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
        self.suspendedSession = suspendedSession
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
    public var automaticInstallMediaStatus: VMAutomaticInstallMediaStatus
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
        automaticInstallMediaStatus: VMAutomaticInstallMediaStatus,
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
        self.automaticInstallMediaStatus = automaticInstallMediaStatus
        self.latestConsoleScreenshotPath = latestConsoleScreenshotPath
        self.displaySurface = displaySurface
        self.latestConsoleLaunch = latestConsoleLaunch
        self.runningQEMUProcess = runningQEMUProcess
        self.nextActions = nextActions
    }
}

public enum VMAutomaticInstallMediaState: String, Codable, Equatable, Sendable {
    case current
    case stale
    case missing
    case unavailable
}

public struct VMAutomaticInstallMediaStatus: Codable, Equatable, Sendable {
    public var state: VMAutomaticInstallMediaState
    public var isCurrent: Bool
    public var mediaPath: String?
    public var sourcePath: String?
    public var mediaModifiedAt: Date?
    public var sourceModifiedAt: Date?
    public var recommendedAction: String
    public var rebuildCommand: String?
    public var requiresRelaunch: Bool
    public var detail: String

    public init(
        state: VMAutomaticInstallMediaState,
        isCurrent: Bool,
        mediaPath: String?,
        sourcePath: String?,
        mediaModifiedAt: Date?,
        sourceModifiedAt: Date?,
        recommendedAction: String,
        rebuildCommand: String?,
        requiresRelaunch: Bool,
        detail: String
    ) {
        self.state = state
        self.isCurrent = isCurrent
        self.mediaPath = mediaPath
        self.sourcePath = sourcePath
        self.mediaModifiedAt = mediaModifiedAt
        self.sourceModifiedAt = sourceModifiedAt
        self.recommendedAction = recommendedAction
        self.rebuildCommand = rebuildCommand
        self.requiresRelaunch = requiresRelaunch
        self.detail = detail
    }
}
