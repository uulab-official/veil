import Foundation

extension LocalVMRuntimeService {
    public func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
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

    /// Names the local Windows account the next install creates. An empty or unusable name falls
    /// back to this Mac's user name. An installed Windows keeps its existing accounts.
    public func updateWindowsAccountName(_ name: String?) async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        let cleaned = name.flatMap(WindowsAccountName.sanitized)
        guard profile.windowsAccountName != cleaned else {
            return try await loadSnapshot()
        }
        profile.windowsAccountName = cleaned
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    /// Resource changes are intentionally enforced at the service boundary as well as in the
    /// SwiftUI settings policy. A stale callback, CLI caller, or future surface must not replace
    /// the disk/media attachments underneath a live or suspended guest.
    func requireResourceMutationAllowed() async throws {
        switch try await loadSnapshot().state {
        case .running, .starting, .suspended:
            throw VMRuntimeError.resourceMutationRequiresStoppedRuntime
        case .unsupported, .notConfigured, .stopped, .failed:
            return
        }
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

    public func recordVirtioGPUDriverInstalled(_ installed: Bool) async throws {
        guard var profile = try await profileStore.load(),
              profile.virtioGPUDriverInstalled != installed else {
            return
        }

        profile.virtioGPUDriverInstalled = installed
        try await profileStore.save(profile)
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

        guard var profile = try await profileStore.load() else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }
        // The display devices change only on a real cold boot. A start that finds Windows already
        // running, or a saved session waiting to resume, must keep the device list QEMU has.
        let isColdBoot = ![.running, .starting, .suspended].contains(snapshot.state)
        if isColdBoot, await suspendedSession() == nil {
            let bootsOnVirtioGPU = QEMUWindowsDisplayDevices.bootsOnVirtioGPU(profile)
            if profile.bootsOnVirtioGPU != bootsOnVirtioGPU {
                profile.bootsOnVirtioGPU = bootsOnVirtioGPU
                try await profileStore.save(profile)
            }
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
            await saveBootReportLoggingFailure(Self.bootReport(
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
            await saveBootReportLoggingFailure(Self.bootReport(
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

    /// `bootReportStore.save` failing (disk full, permissions, encode error) used to be swallowed
    /// with `try?` -- the boot itself would succeed or fail normally, but the diagnostic record other
    /// tooling relies on (`exportDiagnostics`, `loadSnapshot`'s console-launch evidence) would go
    /// silently stale with zero trace of why. Log it instead of just discarding it.
    private func saveBootReportLoggingFailure(_ report: VMRuntimeBootReport) async {
        do {
            try await bootReportStore.save(report)
        } catch {
            // Not `.public`: a disk-write failure here (permissions, disk full) commonly carries the
            // full destination file path under the host user's home directory in its description --
            // the same class of exposure `exportDiagnostics`'s redaction was added to prevent
            // earlier the same day. Default `.private` redaction keeps that out of Console.app/
            // sysdiagnose output.
            VeilLog.runtime.error("Failed to save boot report: \(String(describing: error))")
        }
    }

    public func stop() async throws -> VMRuntimeSnapshot {
        let profile = try await profileStore.load()
        // `loadLatest()` returns nil (no throw) when no launch record file exists at all -- that's
        // the common, legitimate case. It only throws when the file exists but is corrupt/unreadable,
        // which `try?` used to collapse into the exact same nil as "no record." That's dangerous here
        // specifically: a nil launch record means stopQEMULaunchIfRunning below can't identify the
        // running QEMU process to terminate, silently leaving it orphaned after the user is told
        // "Windows display closed."
        var launchRecordWasUnreadable = false
        let latestLaunchRecord: QEMULaunchRecord?
        do {
            latestLaunchRecord = try await qemuLaunchRecordStore.loadLatest()
        } catch {
            // Not `.public`: file-read failures commonly carry the full path under the host user's
            // home directory in their description.
            VeilLog.runtime.error(
                "Failed to load the latest QEMU launch record while stopping; falling back to process discovery by virtual disk path. \(String(describing: error))"
            )
            latestLaunchRecord = nil
            launchRecordWasUnreadable = true
        }
        await detachUSBDevicesBeforeShutdown(launchRecord: latestLaunchRecord)
        _ = try await bootRunner.stop()
        if let profile {
            Self.stopQEMULaunchIfRunning(
                latestLaunchRecord,
                profile: profile,
                processIsRunning: qemuLaunchProcessIsRunning,
                processTerminator: qemuLaunchProcessTerminator
            )

            // A corrupt/unreadable launch record must not silently orphan a running QEMU process --
            // fall back to the same ps-based discovery `QEMUVMRuntimeBooter` already uses elsewhere
            // (e.g. orphan detection in loadSnapshot()) to find the process by virtual disk path
            // instead of by the launch record's own PID/arguments.
            if launchRecordWasUnreadable,
               let virtualDiskPath = profile.virtualDiskPath,
               let runningProcess = QEMUVMRuntimeBooter.runningProcess(attachedToVirtualDiskPath: virtualDiskPath),
               qemuLaunchProcessIsRunning(runningProcess.pid) {
                VeilLog.runtime.notice("Terminating orphaned QEMU process found via disk-path fallback after an unreadable launch record.")
                _ = qemuLaunchProcessTerminator(runningProcess.pid)
            }
        }
        return try await loadSnapshot()
    }

    /// Suspends the running Windows session to a local memory-state file.
    ///
    /// Unlike `stop()`, this keeps the user's open Windows apps: the guest is paused, its RAM and
    /// device state are streamed to disk, and the QEMU process exits. `resume()` continues the same
    /// session. Suspend is refused rather than silently downgraded to a stop when the active provider
    /// cannot persist a session, so nobody loses open work to a hidden fallback.
    public func suspend() async throws -> VMRuntimeSnapshot {
        guard let profile = try await profileStore.load() else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        let securityScopedAccesses = Self.startSecurityScopedAccesses(for: profile)
        defer {
            securityScopedAccesses.forEach { $0.stop() }
        }
        let sessionProfile = Self.profileByResolvingSecurityScopedURLs(
            profile,
            accesses: securityScopedAccesses
        )

        let startedAt = diagnosticDate()
        do {
            await detachUSBDevicesBeforeShutdown(launchRecord: try? await qemuLaunchRecordStore.loadLatest())
            let resultingState = try await bootRunner.suspend(profile: sessionProfile)
            await saveBootReportLoggingFailure(Self.bootReport(
                startedAt: startedAt,
                completedAt: diagnosticDate(),
                result: .succeeded,
                resultingState: resultingState,
                errorMessage: nil,
                profile: sessionProfile
            ))
            return try await loadSnapshot()
        } catch {
            await saveBootReportLoggingFailure(Self.bootReport(
                startedAt: startedAt,
                completedAt: diagnosticDate(),
                result: .failed,
                resultingState: await bootRunner.runtimeState() ?? .running,
                errorMessage: Self.errorMessage(for: error),
                profile: sessionProfile
            ))
            throw error
        }
    }

    /// Resumes a previously suspended Windows session from its saved memory-state file.
    public func resume() async throws -> VMRuntimeSnapshot {
        guard let profile = try await profileStore.load() else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        let securityScopedAccesses = Self.startSecurityScopedAccesses(for: profile)
        defer {
            securityScopedAccesses.forEach { $0.stop() }
        }
        let sessionProfile = Self.profileByResolvingSecurityScopedURLs(
            profile,
            accesses: securityScopedAccesses
        )

        let startedAt = diagnosticDate()
        do {
            let resultingState = try await bootRunner.resume(profile: sessionProfile)
            await saveBootReportLoggingFailure(Self.bootReport(
                startedAt: startedAt,
                completedAt: diagnosticDate(),
                result: .succeeded,
                resultingState: resultingState,
                errorMessage: nil,
                profile: sessionProfile
            ))
            return try await loadSnapshot()
        } catch {
            await saveBootReportLoggingFailure(Self.bootReport(
                startedAt: startedAt,
                completedAt: diagnosticDate(),
                result: .failed,
                resultingState: await bootRunner.runtimeState() ?? .suspended,
                errorMessage: Self.errorMessage(for: error),
                profile: sessionProfile
            ))
            throw error
        }
    }

    public func suspendedSession() async -> VMSuspensionRecord? {
        guard let record = try? await suspensionRecordStore.loadLatest(),
              FileManager.default.fileExists(atPath: record.stateFilePath) else {
            return nil
        }

        return record
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
        try Self.redactingHomeDirectory(in: data).write(to: outputURL, options: [.atomic])
        return outputURL
    }
}
