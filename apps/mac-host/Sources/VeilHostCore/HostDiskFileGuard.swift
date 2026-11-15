import Darwin
import Foundation

/// Puts the Windows system disk back on the Mac when its file is deleted while Windows runs.
///
/// QEMU keeps the disk image open, so deleting it in Finder or a shell leaves Windows running on a file
/// with no name. Nothing looks wrong until QEMU exits: a shut down, a suspend or a Mac restart then
/// frees the file, and Windows is gone with everything in it. While QEMU still has it open, a
/// `drive-mirror` copies the drive into a new image at the original path as Windows keeps running, and
/// completing the job moves the drive onto that copy, so the next start finds its disk where it was.
///
/// The copy holds the disk's current contents only. Internal snapshots in a qcow2 image do not come
/// along: a mirror copies what the guest sees, not the image's snapshot table.
public enum HostDiskFileGuard {
    public static let rescueJobID = "veil-disk-rescue"

    /// The drive id Veil's boot plan gives the Windows system disk.
    public static let systemDriveID = "system"

    /// Throttle for the copy, so the Mac stays responsive while it runs. QEMU counts unallocated
    /// stretches it skips against it as well, so a 128 GiB sparse disk takes a few minutes.
    public static let copyBytesPerSecond: Int64 = 512 * 1_048_576

    /// Free space to leave on the volume beyond the copy, so the disk space guard has room to work.
    public static let spareBytes: Int64 = HostDiskSpaceGuard.resumeAtBytes

    public enum Outcome: Equatable, Sendable {
        /// The disk file is where the launch put it, or there is no running Windows to check.
        case present
        /// The disk file had been deleted; Windows now runs on a new copy at the same path.
        case restored(path: String)
        /// The disk file is gone and the volume has too little free space for a copy.
        case notEnoughSpace(neededBytes: Int64, availableBytes: Int64)
        /// The disk file is gone and copying it failed. Windows still runs on the deleted file.
        case failed(reason: String)
    }

    /// What the app shows while the disk file is missing.
    public enum Issue: Equatable, Sendable {
        case restoring
        case notEnoughSpace(neededBytes: Int64, availableBytes: Int64)
        case failed(reason: String)
    }

    /// Whether nothing exists at `path` any more. A path that cannot be checked for another reason,
    /// such as permissions, counts as present: only a definite answer starts a copy.
    public static func fileIsMissing(atPath path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 {
            return false
        }
        return errno == ENOENT
    }

    /// The system disk path of the running launch when that file has been deleted; nil otherwise.
    public static func missingDiskPath(
        launchRecord: QEMULaunchRecord?,
        processIsRunning: (Int32) -> Bool,
        fileIsMissing: (String) -> Bool = HostDiskFileGuard.fileIsMissing(atPath:)
    ) -> String? {
        guard let launchRecord,
              let path = HostDiskSpaceGuard.systemDiskPath(arguments: launchRecord.arguments),
              LocalVMRuntimeService.liveQMPSocketPath(launchRecord, processIsRunning: processIsRunning) != nil,
              fileIsMissing(path) else {
            return nil
        }
        return path
    }

    /// Copies the running system disk back to `path` and moves the drive onto the copy. Returns once the
    /// drive reads the new file, or with the reason it could not. A copy left running by an earlier
    /// Veil is picked up rather than started again.
    public static func restore(
        path: String,
        socketPath: String,
        qmp: any QEMUQMPControlling,
        availableBytes: (String) -> Int64? = HostDiskSpaceGuard.availableBytes(atPath:),
        pause: @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }
    ) async -> Outcome {
        do {
            let jobs = try await qmp.run(.queryJobs, socketPath: socketPath, idleTimeoutSeconds: 2).jobsReturn ?? []
            if !jobs.contains(where: { $0.id == rescueJobID }) {
                if let refusal = try await startCopy(
                    path: path,
                    socketPath: socketPath,
                    qmp: qmp,
                    availableBytes: availableBytes
                ) {
                    return refusal
                }
            }
            return try await finishCopy(path: path, socketPath: socketPath, qmp: qmp, pause: pause)
        } catch is CancellationError {
            return .failed(reason: "cancelled")
        } catch {
            VeilLog.runtime.error("Could not restore the deleted Windows disk: \(String(describing: error))")
            return .failed(reason: String(describing: error))
        }
    }

    private static func startCopy(
        path: String,
        socketPath: String,
        qmp: any QEMUQMPControlling,
        availableBytes: (String) -> Int64?
    ) async throws -> Outcome? {
        let devices = try await qmp.run(.queryBlock, socketPath: socketPath, idleTimeoutSeconds: 2).blockDevicesReturn ?? []
        guard let drive = devices.first(where: { $0.device == systemDriveID }) else {
            return .failed(reason: "QEMU reports no system drive")
        }

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let needed = (drive.actualSize ?? drive.virtualSize ?? 0) + spareBytes
        if let available = availableBytes(directory), available < needed {
            return .notEnoughSpace(neededBytes: needed, availableBytes: available)
        }

        VeilLog.runtime.notice(
            "The Windows disk file was deleted while Windows runs; copying \((drive.actualSize ?? 0) / 1_048_576, privacy: .public) MB back to its path."
        )
        try await qmp.run(
            .driveMirror(
                jobID: rescueJobID,
                device: systemDriveID,
                targetPath: path,
                format: drive.format,
                bytesPerSecond: copyBytesPerSecond
            ),
            socketPath: socketPath,
            idleTimeoutSeconds: 5
        )
        return nil
    }

    private static func finishCopy(
        path: String,
        socketPath: String,
        qmp: any QEMUQMPControlling,
        pause: @Sendable () async throws -> Void
    ) async throws -> Outcome {
        var askedToComplete = false
        while true {
            let jobs = try await qmp.run(.queryJobs, socketPath: socketPath, idleTimeoutSeconds: 2).jobsReturn ?? []
            guard let job = jobs.first(where: { $0.id == rescueJobID }) else {
                // Dismissed on its own once it concluded. Only a finished switch leaves the file behind
                // as the drive's image; a failed copy is removed by QEMU's own cleanup or stays partial.
                return try await confirmSwitch(path: path, socketPath: socketPath, qmp: qmp)
            }
            if let error = job.error {
                try? await qmp.run(.jobDismiss(jobID: rescueJobID), socketPath: socketPath)
                return .failed(reason: error)
            }
            if job.isConcluded {
                try? await qmp.run(.jobDismiss(jobID: rescueJobID), socketPath: socketPath)
                return try await confirmSwitch(path: path, socketPath: socketPath, qmp: qmp)
            }
            if job.status == "ready", !askedToComplete {
                try await qmp.run(.jobComplete(jobID: rescueJobID), socketPath: socketPath)
                askedToComplete = true
            }
            try await pause()
        }
    }

    /// The drive reads a file that exists at `path` again.
    private static func confirmSwitch(path: String, socketPath: String, qmp: any QEMUQMPControlling) async throws -> Outcome {
        let devices = try await qmp.run(.queryBlock, socketPath: socketPath, idleTimeoutSeconds: 2).blockDevicesReturn ?? []
        guard devices.contains(where: { $0.device == systemDriveID && $0.filename == path }),
              !fileIsMissing(atPath: path) else {
            return .failed(reason: "the copy finished but the drive did not switch to it")
        }
        VeilLog.runtime.notice("Windows now runs on the restored disk file.")
        return .restored(path: path)
    }
}

extension LocalVMRuntimeService {
    /// The running Windows' system disk path when its file has been deleted; see `HostDiskFileGuard`.
    public func missingSystemDiskPath() async -> String? {
        let launchRecord = try? await qemuLaunchRecordStore.loadLatest()
        return HostDiskFileGuard.missingDiskPath(
            launchRecord: launchRecord,
            processIsRunning: qemuLaunchProcessIsRunning
        )
    }

    /// Copies a deleted system disk back while Windows runs; see `HostDiskFileGuard.restore`.
    public func restoreMissingSystemDisk(
        qmp: any QEMUQMPControlling = QEMUQMPClient()
    ) async -> HostDiskFileGuard.Outcome {
        guard let launchRecord = try? await qemuLaunchRecordStore.loadLatest(),
              let path = HostDiskFileGuard.missingDiskPath(
                  launchRecord: launchRecord,
                  processIsRunning: qemuLaunchProcessIsRunning
              ),
              let socketPath = LocalVMRuntimeService.liveQMPSocketPath(
                  launchRecord,
                  processIsRunning: qemuLaunchProcessIsRunning
              ) else {
            return .present
        }
        return await HostDiskFileGuard.restore(path: path, socketPath: socketPath, qmp: qmp)
    }
}
