import Darwin
import Foundation

/// Pauses Windows before the Mac volume holding its disk runs out of space, and continues it once there is
/// room again.
///
/// QEMU's emulated NVMe controller, which carries the Windows system disk, does not honour the drive's
/// `werror` policy: a write that fails because the Mac volume is full completes in the guest as an NVMe
/// write fault (`nvme_rw_complete_cb` in QEMU's `hw/nvme/ctrl.c`), instead of stopping the machine the way
/// `werror=enospc` does for virtio-blk. Windows then sees its disk fail mid-write, which can corrupt the
/// file system. The disk image is sparse, so the volume filling up for any reason, not only Windows writing,
/// leads there. Pausing ahead of that point keeps every write either done or not yet issued.
public enum HostDiskSpaceGuard {
    public static let gibibyte: Int64 = 1_073_741_824

    /// Below this much free space on the disk's volume, a running Windows is paused.
    public static let pauseBelowBytes: Int64 = 2 * gibibyte

    /// A paused Windows continues once this much is free. The gap keeps Windows from flapping between
    /// running and paused while it writes and the Mac frees space.
    public static let resumeAtBytes: Int64 = 4 * gibibyte

    /// How often free space is read. One `statfs` call; QEMU is asked only when the answer calls for it.
    public static let checkIntervalSeconds = 2

    public enum Outcome: Equatable, Sendable {
        /// Nothing to do, or nothing could be read.
        case unchanged
        /// Windows was running with too little space and is now paused.
        case paused(availableBytes: Int64)
        /// Windows had been paused here, there is room again, and it is running.
        case resumed(availableBytes: Int64)
        /// Windows had been paused here but is no longer paused (stopped, or continued by something else):
        /// the guard no longer owns that pause.
        case released
    }

    /// What to do given free space alone. QEMU's own status is checked before acting.
    public enum Need: Equatable, Sendable {
        case none
        case pause
        case resume
        case confirmStillPaused
    }

    public static func need(availableBytes: Int64?, pausedByGuard: Bool) -> Need {
        guard let availableBytes else {
            return .none
        }
        if pausedByGuard {
            return availableBytes >= resumeAtBytes ? .resume : .confirmStillPaused
        }
        return availableBytes < pauseBelowBytes ? .pause : .none
    }

    /// Free bytes an unprivileged process can write on the volume that holds `path`, or nil when it cannot
    /// be read. Purgeable space is not counted: QEMU's writes do not make macOS purge it first.
    public static func availableBytes(atPath path: String) -> Int64? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else {
            return nil
        }
        return Int64(stats.f_bavail) * Int64(stats.f_bsize)
    }

    /// The system disk image's path in a launch's arguments: the `file.filename=` of the `id=system`
    /// drive, or the `file=` of one not yet rewritten.
    public static func systemDiskPath(arguments: [String]) -> String? {
        guard let drive = arguments.first(where: { $0.contains("id=system") }) else {
            return nil
        }
        let options = splitOptions(drive)
        for key in ["file.filename=", "file="] {
            if let option = options.first(where: { $0.hasPrefix(key) }) {
                let path = String(option.dropFirst(key.count))
                return path.isEmpty ? nil : path
            }
        }
        return nil
    }

    /// QEMU option lists separate options with a comma and escape a comma inside a value as two.
    static func splitOptions(_ value: String) -> [String] {
        var options: [String] = []
        var current = ""
        var characters = Array(value)[...]
        while let character = characters.popFirst() {
            if character == "," {
                if characters.first == "," {
                    current.append(",")
                    characters = characters.dropFirst()
                } else {
                    options.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        options.append(current)
        return options
    }

    /// One check of the running machine described by `launchRecord`.
    ///
    /// The guard pauses only a machine QEMU reports as running, and continues only one it paused itself and
    /// QEMU still reports as `paused`; a pause by anything else (a suspend in progress, the stalled-runtime
    /// recovery) is never undone here.
    public static func check(
        launchRecord: QEMULaunchRecord?,
        pausedByGuard: Bool,
        qmp: any QEMUQMPControlling,
        processIsRunning: (Int32) -> Bool,
        availableBytes: (String) -> Int64? = HostDiskSpaceGuard.availableBytes(atPath:)
    ) async -> Outcome {
        guard let launchRecord,
              let diskPath = systemDiskPath(arguments: launchRecord.arguments) else {
            return pausedByGuard ? .released : .unchanged
        }
        guard let socketPath = LocalVMRuntimeService.liveQMPSocketPath(
            launchRecord,
            processIsRunning: processIsRunning
        ) else {
            return pausedByGuard ? .released : .unchanged
        }

        let available = availableBytes(diskPath)
        let need = need(availableBytes: available, pausedByGuard: pausedByGuard)
        guard need != .none, let available else {
            return .unchanged
        }

        let status: String?
        do {
            status = try await qmp.run(.queryStatus, socketPath: socketPath, idleTimeoutSeconds: 1).statusReturn
        } catch {
            VeilLog.runtime.error("Disk space guard could not read QEMU's status: \(String(describing: error))")
            return .unchanged
        }

        switch need {
        case .none:
            return .unchanged
        case .pause:
            guard status == "running" else {
                return .unchanged
            }
            do {
                try await qmp.run(.stop, socketPath: socketPath)
            } catch {
                VeilLog.runtime.error("Disk space guard could not pause Windows: \(String(describing: error))")
                return .unchanged
            }
            VeilLog.runtime.notice(
                "Paused Windows: \(available / 1_048_576, privacy: .public) MB free on the volume holding its disk."
            )
            return .paused(availableBytes: available)
        case .confirmStillPaused:
            return status == "paused" ? .unchanged : .released
        case .resume:
            guard status == "paused" else {
                return .released
            }
            do {
                try await qmp.run(.cont, socketPath: socketPath)
            } catch {
                VeilLog.runtime.error("Disk space guard could not continue Windows: \(String(describing: error))")
                return .unchanged
            }
            VeilLog.runtime.notice(
                "Continued Windows: \(available / 1_048_576, privacy: .public) MB free on the volume holding its disk."
            )
            return .resumed(availableBytes: available)
        }
    }
}

extension LocalVMRuntimeService {
    /// One disk space check of the running Windows; see `HostDiskSpaceGuard`.
    public func guardDiskSpace(
        pausedByGuard: Bool,
        qmp: any QEMUQMPControlling = QEMUQMPClient()
    ) async -> HostDiskSpaceGuard.Outcome {
        let launchRecord = try? await qemuLaunchRecordStore.loadLatest()
        return await HostDiskSpaceGuard.check(
            launchRecord: launchRecord,
            pausedByGuard: pausedByGuard,
            qmp: qmp,
            processIsRunning: qemuLaunchProcessIsRunning
        )
    }
}
