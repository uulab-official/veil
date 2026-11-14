import Foundation

extension LocalVMRuntimeService {
    /// Starts Windows Setup over on a clean machine: a blank system disk, fresh UEFI variables, and
    /// an empty TPM, with the installer, shared folder, and resources kept.
    ///
    /// An interrupted setup leaves partitions and boot entries behind that the next boot trusts. The
    /// disk passes the "already installed" size check and boots into the UEFI shell, and stale boot
    /// entries can hold the installer at its boot loader, so only a full reset reliably restarts it.
    /// The old files go to the Trash rather than being deleted, and an installed Windows is refused.
    public func restartWindowsInstallation() async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
        guard var profile = try await profileStore.load() else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }
        guard profile.windowsInstalled != true else {
            throw VMRuntimeError.restartInstallationRequiresUninstalledWindows
        }

        if let diskPath = profile.virtualDiskPath, !diskPath.isEmpty {
            let vmDirectory = URL(fileURLWithPath: diskPath).deletingLastPathComponent()
            for url in [
                URL(fileURLWithPath: diskPath),
                vmDirectory.appendingPathComponent("uefi-vars.fd"),
                vmDirectory.appendingPathComponent("tpm", isDirectory: true)
            ] where FileManager.default.fileExists(atPath: url.path) {
                try installationDiscarder(url)
            }
        }
        // A saved session belongs to the disk being discarded and must never be resumed onto the new one.
        if let record = try? await suspensionRecordStore.loadLatest() {
            try? FileManager.default.removeItem(atPath: record.stateFilePath)
            try? await suspensionRecordStore.clear()
        }

        profile.windowsInstalled = false
        profile.guestAgentVersion = nil
        profile.guestAgentConnectedAt = nil
        try await profileStore.save(profile)
        return try await prepareDefaultVM()
    }

    public static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
