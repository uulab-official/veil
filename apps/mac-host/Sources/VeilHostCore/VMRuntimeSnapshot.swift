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
    /// The local account the next Windows install creates.
    public var windowsAccountName: String?
    /// Start an installed Windows when Veil opens.
    public var autoStart: Bool?
    /// Suspend a running Windows instead of leaving it running when Veil quits.
    public var suspendOnQuit: Bool?
    /// What Command becomes in the Windows desktop.
    public var commandKeyMapping: VMCommandKeyMapping?
    /// User port forwards QEMU adds at the next start.
    public var portForwards: [VMPortForwardRule]?
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
        windowsAccountName: String? = nil,
        autoStart: Bool? = nil,
        suspendOnQuit: Bool? = nil,
        commandKeyMapping: VMCommandKeyMapping? = nil,
        portForwards: [VMPortForwardRule]? = nil,
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
        self.windowsAccountName = windowsAccountName
        self.autoStart = autoStart
        self.suspendOnQuit = suspendOnQuit
        self.commandKeyMapping = commandKeyMapping
        self.portForwards = portForwards
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
            automaticInstallMediaStatus: automaticInstallMediaStatusEvidence(),
            latestConsoleScreenshotPath: latestConsoleScreenshotPath,
            displaySurface: displaySurfaceEvidence(),
            latestConsoleLaunch: latestConsoleLaunch,
            runningQEMUProcess: runningQEMUProcess,
            nextActions: windowsInstallNextActions(generatedAt: generatedAt)
        )
    }

    private func windowsInstallNextActions(generatedAt: Date) -> [String] {
        let mediaRecoveryActions = automaticInstallMediaRecoveryActions()
        if !bootReady {
            var actions = runningRecoveryActions()
            let blockers = preflightChecks
                .filter { $0.state == .failed }
                .map { "\($0.title): \($0.detail)" }
            if !blockers.isEmpty {
                actions.append(contentsOf: blockers)
                if let prepareCommand = windowsInstallPrepareCommand() {
                    actions.append("Re-register the selected installer with `\(prepareCommand)`.")
                }
                return actions
            }

            let blockedSteps = installationSteps
                .filter { $0.state == .blocked }
                .map { "\($0.title): \($0.detail)" }
            if !blockedSteps.isEmpty {
                actions.append(contentsOf: blockedSteps)
                if let prepareCommand = windowsInstallPrepareCommand() {
                    actions.append("Re-register the selected installer with `\(prepareCommand)`.")
                }
                return actions
            }

            if let prepareCommand = windowsInstallPrepareCommand() {
                actions.append("Re-register the selected installer with `\(prepareCommand)`.")
            }
            actions.append("Run `veil-vmctl qemu-doctor --json` to identify the missing Windows install prerequisite.")
            return actions
        }

        if state == .running {
            var actions = runningRecoveryActions()
            if latestConsoleLaunch?.isBootStalled(asOf: generatedAt) == true {
                actions.insert(
                    "Windows boot appears stalled: Veil has observed no usable embedded-console frame for more than 180 seconds. Capture diagnostics, stop Windows, and retry before repairing the guest agent.",
                    at: 0
                )
            } else if latestConsoleLaunch?.isRecentlyBooting(asOf: generatedAt) == true {
                actions.insert(
                    "Windows is still booting: Veil has not observed a usable embedded-console frame yet. Wait for the desktop, then rerun `veil-vmctl qemu-display-smoke --json`; do not reinstall the guest agent yet.",
                    at: 0
                )
            }
            if latestConsoleLaunch?.displaySurface.isLiveCapable == true {
                actions.append("Validate the embedded console with `veil-vmctl qemu-display-smoke --json`.")
            }
            if latestConsoleLaunch?.monitorSocketPath.isEmpty == false {
                actions.append("Refresh install evidence with `veil-vmctl qemu-capture --json` before changing recovery steps.")
            }
            actions.append(contentsOf: mediaRecoveryActions)
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
            if !mediaRecoveryActions.isEmpty {
                return mediaRecoveryActions
            }
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

    private func automaticInstallMediaRecoveryActions() -> [String] {
        let status = automaticInstallMediaStatusEvidence()
        guard status.state == .stale || status.state == .missing else {
            return []
        }

        let command = status.rebuildCommand ?? "veil-vmctl prepare --installer /path/to/Windows.iso"
        if state == .running {
            return [
                "Power down Windows with `veil-vmctl qemu-powerdown --json`, rebuild guest tools media with `\(command)`, then restart Windows so QEMU attaches the refreshed `VeilAutoInstall.iso`."
            ]
        }

        return [
            "Rebuild guest tools media with `\(command)` before starting Windows so attached recovery scripts match the local guest-agent bundle."
        ]
    }

    private func windowsInstallPrepareCommand() -> String? {
        guard let installerMediaPath, !installerMediaPath.isEmpty else {
            return nil
        }

        var command = "veil-vmctl prepare --installer \(shellQuotedArgument(installerMediaPath))"
        if let driverMediaPath, !driverMediaPath.isEmpty {
            command += " --drivers \(shellQuotedArgument(driverMediaPath))"
        }
        return command
    }

    private func shellQuotedArgument(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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

    private func automaticInstallMediaStatusEvidence() -> VMAutomaticInstallMediaStatus {
        let mediaURL = automaticInstallMediaPath.map(URL.init(fileURLWithPath:))
        let sourceURL = automaticInstallSourceDirectoryURL()
        let mediaDate = mediaURL.flatMap { modificationDate(at: $0) }
        let sourceDate = latestAutomaticInstallSourceModificationDate()
        let rebuildCommand = windowsInstallPrepareCommand()

        guard let mediaPath = automaticInstallMediaPath,
              !mediaPath.isEmpty else {
            return VMAutomaticInstallMediaStatus(
                state: .missing,
                isCurrent: false,
                mediaPath: nil,
                sourcePath: sourceURL?.path,
                mediaModifiedAt: nil,
                sourceModifiedAt: sourceDate,
                recommendedAction: "prepare-media",
                rebuildCommand: rebuildCommand,
                requiresRelaunch: state == .running,
                detail: "VeilAutoInstall.iso is missing; prepare Windows before starting or repairing the guest agent."
            )
        }

        guard let mediaDate else {
            return VMAutomaticInstallMediaStatus(
                state: .missing,
                isCurrent: false,
                mediaPath: mediaPath,
                sourcePath: sourceURL?.path,
                mediaModifiedAt: nil,
                sourceModifiedAt: sourceDate,
                recommendedAction: "prepare-media",
                rebuildCommand: rebuildCommand,
                requiresRelaunch: state == .running,
                detail: "VeilAutoInstall.iso is not present at the configured path; rebuild the automatic install media before using guest-agent repair."
            )
        }

        guard let sourceDate else {
            return VMAutomaticInstallMediaStatus(
                state: .unavailable,
                isCurrent: false,
                mediaPath: mediaPath,
                sourcePath: sourceURL?.path,
                mediaModifiedAt: mediaDate,
                sourceModifiedAt: nil,
                recommendedAction: "inspect-media",
                rebuildCommand: rebuildCommand,
                requiresRelaunch: false,
                detail: "Veil cannot compare VeilAutoInstall.iso with the staged Autounattend or guest-agent bundle because source timestamps are unavailable."
            )
        }

        let isCurrent = mediaDate >= sourceDate
        return VMAutomaticInstallMediaStatus(
            state: isCurrent ? .current : .stale,
            isCurrent: isCurrent,
            mediaPath: mediaPath,
            sourcePath: sourceURL?.path,
            mediaModifiedAt: mediaDate,
            sourceModifiedAt: sourceDate,
            recommendedAction: isCurrent ? "none" : "rebuild-media-and-relaunch",
            rebuildCommand: rebuildCommand,
            requiresRelaunch: !isCurrent && state == .running,
            detail: isCurrent
                ? "VeilAutoInstall.iso is current with the staged Autounattend and guest-agent bundle."
                : "VeilAutoInstall.iso is older than the staged Autounattend or guest-agent bundle; rebuild it and relaunch Windows before relying on attached-media guest-agent repair."
        )
    }

    private func automaticInstallSourceDirectoryURL() -> URL? {
        if let automaticInstallAnswerFilePath, !automaticInstallAnswerFilePath.isEmpty {
            return URL(fileURLWithPath: automaticInstallAnswerFilePath).deletingLastPathComponent()
        }

        if let automaticInstallMediaPath, !automaticInstallMediaPath.isEmpty {
            return URL(fileURLWithPath: automaticInstallMediaPath).deletingLastPathComponent()
        }

        return nil
    }

    private func latestAutomaticInstallSourceModificationDate() -> Date? {
        guard let sourceURL = automaticInstallSourceDirectoryURL() else {
            return nil
        }

        let answerDate = modificationDate(at: sourceURL.appendingPathComponent("Autounattend.xml"))
        let agentBundleDate = latestModificationDate(in: sourceURL.appendingPathComponent("Veil Guest Agent", isDirectory: true))

        switch (answerDate, agentBundleDate) {
        case let (answerDate?, agentBundleDate?):
            return max(answerDate, agentBundleDate)
        case let (answerDate?, nil):
            return answerDate
        case let (nil, agentBundleDate?):
            return agentBundleDate
        case (nil, nil):
            return nil
        }
    }

    private func modificationDate(at url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func latestModificationDate(in url: URL) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        var latest = modificationDate(at: url) ?? Date.distantPast
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
