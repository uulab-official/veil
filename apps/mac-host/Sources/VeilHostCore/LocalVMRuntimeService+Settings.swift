import Foundation

extension LocalVMRuntimeService {
    /// Gives Windows a new CPU and memory size, kept inside this Mac's limits. QEMU reads them at the
    /// next start, so Windows must be stopped (not suspended: a saved session needs the same sizes).
    public func updateHardware(cpuCount: Int, memoryMB: Int) async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
        var profile = try await profileStore.load() ?? defaultProfile()
        let limits = resourceLimits ?? VMResourceLimits.currentHost()
        profile.cpuCount = limits.clampedCPUCount(cpuCount)
        profile.memoryMB = limits.clampedMemoryMB(memoryMB)
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    /// What Veil does with Windows when it opens and quits. These change no VM hardware, so they can be
    /// set while Windows runs.
    public func updateStartupBehavior(autoStart: Bool, suspendOnQuit: Bool) async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        profile.autoStart = autoStart
        profile.suspendOnQuit = suspendOnQuit
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }
}

extension LocalVMRuntimeService {
    /// What Command becomes in the Windows desktop. Read on every key press, so it applies at once.
    public func updateCommandKeyMapping(_ mapping: VMCommandKeyMapping) async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        profile.commandKeyMapping = mapping
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    /// Replaces the user port forwards. QEMU binds them at the next start, so they can be edited while
    /// Windows runs without touching the running machine.
    public func updatePortForwards(_ rules: [VMPortForwardRule]) async throws -> VMRuntimeSnapshot {
        try VMPortForwardRuleValidator.validate(rules)
        var profile = try await profileStore.load() ?? defaultProfile()
        profile.portForwards = rules
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    /// Moves Windows between software rendering and the Mac's GPU, for the next start.
    ///
    /// Turning it on backs Windows up first (`VMGraphicsBackup`): once Windows installs its GPU driver it
    /// shows nothing on the software runtime, and the backup is the way back. Turning it off with
    /// `restoringBackup` puts that copy back, losing what changed in Windows since; without it, Windows
    /// is left as it is, which suits a Windows that never installed the driver.
    public func updateGraphicsAcceleration(
        _ value: VMGraphicsAcceleration,
        restoringBackup: Bool
    ) async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
        guard var profile = try await profileStore.load(),
              let diskPath = profile.virtualDiskPath, !diskPath.isEmpty else {
            throw VMGraphicsBackup.BackupError.noDisk
        }
        guard value != profile.effectiveGraphicsAcceleration else {
            return try await loadSnapshot()
        }

        switch value {
        case .gpu:
            guard QEMUGPURuntime.bundled() != nil else {
                throw VMRuntimeError.gpuRuntimeMissing
            }
            let backup = try VMGraphicsBackup.create(diskPath: diskPath)
            profile.graphicsBackupPath = backup.path
            profile.graphicsAcceleration = .gpu
        case .software:
            if restoringBackup, let backupPath = profile.graphicsBackupPath {
                try VMGraphicsBackup.restore(from: URL(fileURLWithPath: backupPath), diskPath: diskPath)
                profile.graphicsBackupPath = nil
            }
            profile.graphicsAcceleration = .software
        }
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func removableMediaStatus() async -> VMRemovableMediaStatus {
        do {
            let socketPath = try await removableDriveQMPSocket()
            return try await readRemovableMediaStatus(socketPath: socketPath)
        } catch let error as VMRemovableMediaError {
            return .unavailable(error)
        } catch {
            return VMRemovableMediaStatus(isDriveAvailable: false, unavailableReason: error.localizedDescription)
        }
    }

    /// Inserts an ISO into the running Windows' removable CD drive, replacing any disc in it.
    public func insertRemovableMedia(path: String) async throws -> VMRemovableMediaStatus {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension.caseInsensitiveCompare("iso") == .orderedSame else {
            throw VMRemovableMediaError.unsupportedMedia(url.path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw VMRemovableMediaError.mediaNotFound(url.path)
        }

        let socketPath = try await removableDriveQMPSocket()
        try await qmpController.run(
            .changeRemovableMedium(deviceID: VMRemovableOpticalDrive.deviceID, filePath: url.path),
            socketPath: socketPath
        )
        return try await readRemovableMediaStatus(socketPath: socketPath)
    }

    /// Stages the tools this Veil ships, builds a disc from them, and inserts it into the running
    /// Windows, where `QEMUGuestToolsUpdateKeySequence` runs its `U.cmd`.
    public func insertGuestToolsUpdateMedia() async throws -> VMRemovableMediaStatus {
        guard let profile = try await profileStore.load() else {
            throw VMRemovableMediaError.notRunning
        }
        try Self.prepareGuestAgentInstallerBundle(for: profile)
        let mediaURL = URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent(GuestToolsUpdateMedia.fileName)
        try GuestToolsUpdateMedia.build(
            agentBundleURL: Self.guestAgentInstallerBundleURL(for: profile),
            mediaURL: mediaURL
        )
        return try await insertRemovableMedia(path: mediaURL.path)
    }

    public func ejectRemovableMedia() async throws -> VMRemovableMediaStatus {
        let socketPath = try await removableDriveQMPSocket()
        try await qmpController.run(
            .ejectRemovableMedium(deviceID: VMRemovableOpticalDrive.deviceID),
            socketPath: socketPath
        )
        return try await readRemovableMediaStatus(socketPath: socketPath)
    }

    private func readRemovableMediaStatus(socketPath: String) async throws -> VMRemovableMediaStatus {
        let reply = try await qmpController.run(
            .humanMonitor("info block \(VMRemovableOpticalDrive.driveID)"),
            socketPath: socketPath
        )
        return VMRemovableMediaStatus.parse(infoBlock: reply.textReturn ?? "")
    }

    /// The QMP socket of the QEMU Veil launched, when that QEMU still runs and has the removable drive.
    /// Presses the running Windows' ACPI power button, for guests without a tools shutdown.
    public func pressPowerButton() async throws {
        guard let record = try await qemuLaunchRecordStore.loadLatest(),
              let pid = record.pid,
              qemuLaunchProcessIsRunning(pid),
              let socketPath = record.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !socketPath.isEmpty else {
            throw VMRemovableMediaError.notRunning
        }
        try await qmpController.run(.systemPowerdown, socketPath: socketPath)
    }

    private func removableDriveQMPSocket() async throws -> String {
        guard let record = try await qemuLaunchRecordStore.loadLatest(),
              let pid = record.pid,
              qemuLaunchProcessIsRunning(pid),
              let socketPath = record.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !socketPath.isEmpty else {
            throw VMRemovableMediaError.notRunning
        }
        guard VMRemovableOpticalDrive.isPresent(in: record.arguments) else {
            throw VMRemovableMediaError.driveMissing
        }
        return socketPath
    }
}
