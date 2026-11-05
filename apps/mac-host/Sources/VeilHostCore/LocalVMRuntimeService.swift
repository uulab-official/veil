import Foundation

public struct LocalVMRuntimeService: VMRuntimeService {
    static let armUEFIVariablesStoreSizeBytes: UInt64 = 64 * 1_024 * 1_024

    let profileStore: any VMProfileStore
    let defaultHomeDirectory: URL
    let bootRunner: any VMRuntimeBooting
    let bootReportStore: any VMRuntimeBootReportStore
    let qemuLaunchRecordStore: any QEMULaunchRecordStore
    let suspensionRecordStore: any VMSuspensionRecordStore
    private let providerProbe: VMRuntimeProviderProbe
    let resourcePlan: VMResourcePlan?
    let resourceLimits: VMResourceLimits?
    let diagnosticDate: @Sendable () -> Date
    let automaticInstallMediaBuilder: any AutomaticInstallMediaBuilding
    let consoleScreenshotRefresher: @Sendable (URL, URL) -> Void
    let pointerEventSender: (any QEMUPointerEventSending)?
    let keySequenceSender: (any QEMUKeySequenceSending)?
    let qemuLaunchProcessIsRunning: @Sendable (Int32) -> Bool
    let qemuLaunchProcessTerminator: @Sendable (Int32) -> Bool
    let firmwareVarsTemplatePaths: [String]
    let installationDiscarder: @Sendable (URL) throws -> Void

    public init(
        profileStore: any VMProfileStore = JSONVMProfileStore(),
        defaultHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bootRunner: any VMRuntimeBooting = UnavailableVMRuntimeBooter(),
        bootReportStore: any VMRuntimeBootReportStore = JSONVMRuntimeBootReportStore(),
        qemuLaunchRecordStore: any QEMULaunchRecordStore = JSONQEMULaunchRecordStore(),
        suspensionRecordStore: any VMSuspensionRecordStore = JSONVMSuspensionRecordStore(),
        providerProbe: VMRuntimeProviderProbe = VMRuntimeProviderProbe(),
        resourcePlan: VMResourcePlan? = nil,
        resourceLimits: VMResourceLimits? = nil,
        diagnosticDate: @escaping @Sendable () -> Date = Date.init,
        automaticInstallMediaBuilder: any AutomaticInstallMediaBuilding = HdiutilAutomaticInstallMediaBuilder(),
        consoleScreenshotRefresher: @escaping @Sendable (URL, URL) -> Void = QEMUVMRuntimeBooter.captureConsoleScreenshot,
        pointerEventSender: (any QEMUPointerEventSending)? = nil,
        keySequenceSender: (any QEMUKeySequenceSending)? = nil,
        qemuLaunchProcessIsRunning: @escaping @Sendable (Int32) -> Bool = LocalVMRuntimeService.processIsRunning,
        qemuLaunchProcessTerminator: @escaping @Sendable (Int32) -> Bool = LocalVMRuntimeService.terminateProcess,
        firmwareVarsTemplatePaths: [String]? = nil,
        installationDiscarder: @escaping @Sendable (URL) throws -> Void = LocalVMRuntimeService.moveToTrash
    ) {
        self.profileStore = profileStore
        self.defaultHomeDirectory = defaultHomeDirectory
        self.bootRunner = bootRunner
        self.bootReportStore = bootReportStore
        self.qemuLaunchRecordStore = qemuLaunchRecordStore
        self.suspensionRecordStore = suspensionRecordStore
        self.providerProbe = providerProbe
        self.resourcePlan = resourcePlan
        self.resourceLimits = resourceLimits
        self.diagnosticDate = diagnosticDate
        self.automaticInstallMediaBuilder = automaticInstallMediaBuilder
        self.consoleScreenshotRefresher = consoleScreenshotRefresher
        self.pointerEventSender = pointerEventSender
        self.keySequenceSender = keySequenceSender
        self.qemuLaunchProcessIsRunning = qemuLaunchProcessIsRunning
        self.qemuLaunchProcessTerminator = qemuLaunchProcessTerminator
        self.installationDiscarder = installationDiscarder
        self.firmwareVarsTemplatePaths = firmwareVarsTemplatePaths
            ?? (
                LocalQEMUWindowsBootPlanFactory.defaultSecureFirmwareVarsTemplatePaths(homeDirectory: defaultHomeDirectory)
                    + LocalQEMUWindowsBootPlanFactory.firmwareVarsTemplatePaths(homeDirectory: defaultHomeDirectory)
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
            // Unlike stop()'s copy of this read, a corrupt/unreadable launch record here already
            // degrades gracefully -- `orphanQEMUProcess` a few lines below independently detects a
            // running QEMU process by virtual disk path and `inferredRuntimeState` falls back to it,
            // so this path was never at risk of masking an orphan the way stop()'s was. Still log it
            // (not `.error`, since it's non-fatal and this runs on every snapshot refresh/poll tick)
            // for the same reason every other silently-discarded failure in this file now logs: a
            // recurring read failure should be diagnosable without guessing.
            let latestLaunchRecord: QEMULaunchRecord?
            do {
                latestLaunchRecord = try await qemuLaunchRecordStore.loadLatest()
            } catch {
                VeilLog.runtime.notice("Failed to load the latest QEMU launch record: \(String(describing: error))")
                latestLaunchRecord = nil
            }
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
            // A machine that is actually executing always wins over stored evidence. Only when
            // nothing is running does a saved memory-state file make the VM `.suspended` rather than
            // `.stopped` -- otherwise a stale suspension record would hide a live Windows session.
            let orphanRuntimeState: VMRuntimeState? = orphanQEMUProcess == nil ? nil : .running
            let liveRuntimeState: VMRuntimeState? = [runtimeState, recordedQEMUState, orphanRuntimeState]
                .compactMap { $0 }
                .first { $0 == .running || $0 == .starting }
            let suspendedSessionRecord = await suspendedSession()
            var suspendedRuntimeState: VMRuntimeState?
            if liveRuntimeState == nil, suspendedSessionRecord != nil {
                suspendedRuntimeState = .suspended
            }
            let inferredRuntimeState = liveRuntimeState
                ?? suspendedRuntimeState
                ?? runtimeState
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
                suspendedSession: suspendedSessionRecord,
                runtimeProvider: activeProvider,
                runtimeProviders: runtimeProviders,
                installationSteps: installationSteps,
                preflightChecks: preflightChecks,
                deviceSummary: deviceSummary,
                configurationSummary: Self.configurationSummary(for: profile, devices: deviceSummary),
                installEvidence: installEvidence,
                bootReady: bootPathReadiness.isReady,
                windowsInstalled: windowsInstalled,
                windowsAccountName: WindowsAccountName.resolve(preferred: profile.windowsAccountName),
                autoStart: profile.autoStart,
                suspendOnQuit: profile.suspendOnQuit,
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
            windowsAccountName: WindowsAccountName.resolve(preferred: nil),
            detail: virtualizationAvailable
                ? "No Windows VM profile has been created."
                : "Veil requires macOS 15+ on Apple Silicon."
        )
    }

}
