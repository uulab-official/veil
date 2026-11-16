import Foundation

extension LocalVMRuntimeService {
    public func createDefaultProfile() async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
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
        try await requireResourceMutationAllowed()
        var profile = try await profileStore.load() ?? defaultProfile()
        profile = try prepareDefaultResources(for: profile)
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
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

        let diskURL: URL
        if let configuredVirtualDiskPath = profile.virtualDiskPath,
           !configuredVirtualDiskPath.isEmpty {
            diskURL = URL(fileURLWithPath: configuredVirtualDiskPath)
        } else {
            diskURL = defaultVirtualDiskURL(for: profile)
        }
        try FileManager.default.createDirectory(
            at: diskURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var isDirectory: ObjCBool = false
        let diskAlreadyExists = FileManager.default.fileExists(
            atPath: diskURL.path,
            isDirectory: &isDirectory
        )
        guard !isDirectory.boolValue else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        // A configured path keeps the format its extension names, so recreating an older `.img`
        // disk keeps it raw; the default path is qcow2 when qemu-img is available.
        if !diskAlreadyExists,
           QEMUDiskImageFormat.detect(atPath: diskURL.path) == .qcow2,
           let diskImageTool {
            do {
                try diskImageTool.createQCOW2(path: diskURL.path, sizeBytes: Int64(profile.diskGB) * 1_024 * 1_024 * 1_024)
            } catch {
                try? FileManager.default.removeItem(at: diskURL)
                throw error
            }
        } else if !diskAlreadyExists {
            let didCreateDisk = FileManager.default.createFile(atPath: diskURL.path, contents: nil)
            guard didCreateDisk else {
                throw CocoaError(.fileWriteUnknown)
            }

            do {
                let fileHandle = try FileHandle(forWritingTo: diskURL)
                defer {
                    try? fileHandle.close()
                }
                try fileHandle.truncate(atOffset: UInt64(profile.diskGB) * 1_024 * 1_024 * 1_024)
            } catch {
                // Do not leave a zero-byte artifact that looks like a prepared disk after a
                // failed allocation. The profile is saved only after all resources succeed, so
                // removing this newly-created file keeps the next retry deterministic.
                try? FileManager.default.removeItem(at: diskURL)
                throw error
            }
        }

        // A missing disk cannot contain an installed Windows guest. Clear stale compatibility
        // evidence when recovery recreates that path; the guest agent can establish installed
        // evidence again after the real Windows setup completes.
        if !diskAlreadyExists {
            profile.windowsInstalled = false
            profile.guestAgentVersion = nil
            profile.guestAgentConnectedAt = nil
        }

        profile.virtualDiskPath = diskURL.path
        try Self.prepareTPMStateDirectory(virtualDiskPath: diskURL.path)
        try Self.prepareUEFIVariablesStore(
            virtualDiskPath: diskURL.path,
            templatePaths: firmwareVarsTemplatePaths,
            shouldUpgradeToSecureVars: profile.windowsInstalled != true
                && !Self.windowsSetupHasWrittenToDisk(diskURL: diskURL, bookmarkData: profile.virtualDiskBookmarkData)
        )
        return profile
    }

    /// Allocated bytes beyond which a disk holds Windows Setup's work rather than a blank image.
    static let windowsSetupStartedAllocatedBytes: Int64 = 64 * 1_024 * 1_024

    /// Once Windows Setup has written to the disk, the UEFI variables hold its "Windows Boot
    /// Manager" entry and boot order, so they belong to that disk and must not be swapped for a
    /// fresh template. Restart Windows Installation discards both together instead.
    static func windowsSetupHasWrittenToDisk(diskURL: URL, bookmarkData: Data?) -> Bool {
        (allocatedFileSize(path: diskURL.path, bookmarkData: bookmarkData) ?? 0) >= windowsSetupStartedAllocatedBytes
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

    static func automaticInstallAnswerFileURL(for profile: VMProfile) -> URL {
        URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("Autounattend.xml")
    }

    static func automaticInstallMediaURL(for profile: VMProfile) -> URL {
        URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("VeilAutoInstall.iso")
    }

    static func guestAgentInstallerBundleURL(for profile: VMProfile) -> URL {
        URL(fileURLWithPath: profile.sharedFolderPath)
            .appendingPathComponent("Veil Guest Agent", isDirectory: true)
    }

    static func shouldPrepareAutomaticInstallMedia(for profile: VMProfile) -> Bool {
        // VEIL_AUTO is guest support media after the first Windows setup, not just an
        // unattended-install artifact. Keep staging it so a newer agent bundle can be
        // delivered through the next normal QEMU boot without reattaching Windows setup media.
        true
    }
}
