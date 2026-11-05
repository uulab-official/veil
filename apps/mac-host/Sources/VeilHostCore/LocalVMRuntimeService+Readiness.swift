import Foundation

extension LocalVMRuntimeService {
    static func hostArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static func diagnosticHost() -> VMRuntimeDiagnosticHost {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        return VMRuntimeDiagnosticHost(
            architecture: hostArchitecture(),
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            operatingSystemVersion: "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)"
        )
    }

    static func diagnosticFileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "veil-vm-diagnostics-\(timestamp).json"
    }

    /// qcow2 like UTM whenever qemu-img is there to create it.
    var newDiskFormat: QEMUDiskImageFormat {
        diskImageTool == nil ? .raw : .qcow2
    }

    /// The original machine keeps `~/Virtual Machines/Veil/<name>.<ext>`; library machines get their
    /// own folder so their `uefi-vars.fd` and `tpm/` (found beside the disk) never collide. The
    /// extension follows the format a new disk is created in; an existing disk's format is read from
    /// its header, so older `.img` names keep working.
    func defaultVirtualDiskURL(for profile: VMProfile) -> URL {
        let directory = VMLibrary.defaultMachineDirectory(for: profile.id, homeDirectory: defaultHomeDirectory)
        if profile.id == VMLibrary.legacyMachineID {
            return directory.appendingPathComponent("\(profile.name).\(newDiskFormat.fileExtension)")
        }
        return directory.appendingPathComponent("Windows.\(newDiskFormat.fileExtension)")
    }

    func defaultProfile() -> VMProfile {
        var profile = VMProfile.defaultWindows11Arm(homeDirectory: defaultHomeDirectory)
        let plan = resourcePlan ?? VMResourcePolicy.currentHostPlan()
        profile.cpuCount = plan.cpuCount
        profile.memoryMB = plan.memoryMB
        profile.diskGB = plan.diskGB
        return profile
    }

    static func runtimeDetail(for state: VMRuntimeState) -> String {
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

    static func bootReport(
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

    static func errorMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    static func bootPathReadiness(
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

    static func stoppedDetail(
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

    static func installEvidence(
        bootPathReadiness: (isReady: Bool, detail: String),
        windowsInstalled: Bool,
        guestAgentVersion: String?,
        virtualDiskAllocatedBytes: Int64?,
        windowsBootManagerRegistered: Bool = false
    ) -> VMInstallEvidenceSummary {
        if let guestAgentVersion {
            return VMInstallEvidenceSummary(
                kind: .guestAgent,
                isInstalled: true,
                title: "Guest agent installed",
                detail: "The Veil guest agent \(guestAgentVersion) is installed in Windows. Veil verifies the live connection separately before opening apps."
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

        // Without a network the agent never connects, but Setup's boot entry already proves the
        // disk holds Windows; treating it as an unfinished install would offer to erase it.
        if windowsBootManagerRegistered {
            return VMInstallEvidenceSummary(
                kind: .windowsBootManager,
                isInstalled: true,
                title: "Windows installed",
                detail: "Windows Setup registered Windows Boot Manager on this disk. Veil Tools connect once Windows has a network."
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

    static func installationSteps(for profile: VMProfile) -> [VMInstallationStep] {
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
                    : "Guest agent \(profile.guestAgentVersion ?? "") is installed; live connection is checked when Windows is running.",
                state: profile.guestAgentVersion == nil ? .pending : .complete
            )
        ]
    }

    static func deviceSummary(for profile: VMProfile) -> VMRuntimeDeviceSummary {
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
                attachment: "NVMe",
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
            entropyDevice: "Virtio entropy",
            audioDevice: audioDeviceDescription(selectedAudioDevice()),
            sharedFolderDevice: sharedFolderDeviceDescription(selectedSharedFolderTransport())
        )
    }

    /// Resolved from the same environment override the boot plan reads, so the summary cannot claim
    /// audio is wired while the plan omits it.
    static func selectedAudioDevice(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> QEMUWindowsAudioDevice {
        QEMUWindowsAudioDevice.selected(
            from: environment[QEMUWindowsAudioDevice.environmentVariableName]
        ).device
    }

    static func audioDeviceDescription(_ device: QEMUWindowsAudioDevice) -> String {
        switch device {
        case .intelHDA:
            VMRuntimeDeviceDefaults.intelHDADescription
        case .usbAudio:
            VMRuntimeDeviceDefaults.usbAudioDescription
        case .disabled:
            VMRuntimeDeviceDefaults.audioDeviceDisabled
        }
    }

    /// Resolved from the same environment override the boot plan reads, for the same reason as audio:
    /// the summary must not claim a shared folder the plan never wired.
    static func selectedSharedFolderTransport(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> QEMUWindowsSharedFolderTransport {
        QEMUWindowsSharedFolderTransport.selected(
            from: environment[QEMUWindowsSharedFolderTransport.environmentVariableName]
        ).transport
    }

    static func sharedFolderDeviceDescription(_ transport: QEMUWindowsSharedFolderTransport) -> String {
        switch transport {
        case .guestSMB:
            VMRuntimeDeviceDefaults.guestSMBSharedFolderDescription
        case .hostSMB:
            VMRuntimeDeviceDefaults.hostSMBSharedFolderDescription
        case .disabled:
            VMRuntimeDeviceDefaults.sharedFolderDisabled
        }
    }

    static func configurationSummary(
        for profile: VMProfile,
        devices: VMRuntimeDeviceSummary
    ) -> VMRuntimeConfigurationSummary {
        let audioDevice = selectedAudioDevice()
        let sharedFolderTransport = selectedSharedFolderTransport()
        return VMRuntimeConfigurationSummary(
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
                sharedFolderPath: profile.sharedFolderPath,
                transport: sharedFolderTransport
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
            audio: VMRuntimeAudioConfigurationSummary(
                isEnabled: audioDevice.isEnabled,
                device: devices.audioDevice,
                hostBackend: audioDevice.isEnabled ? "CoreAudio" : nil
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

    static func preflightChecks(for profile: VMProfile) -> [VMPreflightCheck] {
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

    static func protectedPathNeedsFilePicker(_ path: String, bookmarkData: Data?) -> Bool {
        bookmarkData == nil && isDownloadsPath(path)
    }

    private static func isDownloadsPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .pathComponents
            .contains("Downloads")
    }
}
