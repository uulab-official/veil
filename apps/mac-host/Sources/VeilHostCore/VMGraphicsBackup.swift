import Darwin
import Foundation

/// The restore point Veil takes before Windows first draws on the GPU.
///
/// Installing `viogpu3d` replaces the display driver on the same virtio-gpu device, and afterwards
/// Windows shows nothing on the software runtime. Turning GPU acceleration off therefore means going back
/// to the Windows from before: the system disk, the UEFI variables and the TPM state together, since
/// BitLocker and Windows Hello can be sealed to the TPM.
///
/// The disk is an APFS clone (`clonefile`), which takes no space until either copy changes. A volume
/// without clones refuses the backup rather than copying tens of gigabytes behind the user's back.
public enum VMGraphicsBackup {
    public static let folderName = "Backups"
    static let diskFileName = "system-disk"
    static let firmwareVarsFileName = "uefi-vars.fd"
    static let tpmDirectoryName = "tpm"

    public enum BackupError: Error, LocalizedError, Equatable {
        case noDisk
        case clonesUnsupported(String)
        case missingBackup(String)

        public var errorDescription: String? {
            switch self {
            case .noDisk:
                "There is no Windows disk to back up."
            case .clonesUnsupported(let detail):
                "Veil could not make an instant copy of the Windows disk (\(detail)). GPU acceleration needs the disk on an APFS volume, so Windows can be restored if the GPU driver misbehaves."
            case .missingBackup(let path):
                "The copy of Windows from before GPU acceleration is missing at \(path)."
            }
        }
    }

    /// Where a backup taken now goes: beside the disk, so the clone stays on the disk's volume.
    public static func newBackupDirectory(diskPath: String, now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return URL(fileURLWithPath: diskPath)
            .deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("before-gpu-\(formatter.string(from: now))", isDirectory: true)
    }

    /// Copies the stopped machine's disk, UEFI variables and TPM state into a new backup directory.
    public static func create(diskPath: String, now: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: diskPath) else {
            throw BackupError.noDisk
        }
        let directory = newBackupDirectory(diskPath: diskPath, now: now)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try clone(from: diskPath, to: directory.appendingPathComponent(diskFileName).path)
            let machineDirectory = URL(fileURLWithPath: diskPath).deletingLastPathComponent()
            let vars = machineDirectory.appendingPathComponent(firmwareVarsFileName)
            if fileManager.fileExists(atPath: vars.path) {
                try fileManager.copyItem(at: vars, to: directory.appendingPathComponent(firmwareVarsFileName))
            }
            try copyTPMState(
                from: machineDirectory.appendingPathComponent(tpmDirectoryName, isDirectory: true),
                to: directory.appendingPathComponent(tpmDirectoryName, isDirectory: true)
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        return directory
    }

    /// Puts the backup back over the stopped machine and removes it.
    public static func restore(from directory: URL, diskPath: String) throws {
        let fileManager = FileManager.default
        let backupDisk = directory.appendingPathComponent(diskFileName)
        guard fileManager.fileExists(atPath: backupDisk.path) else {
            throw BackupError.missingBackup(directory.path)
        }
        let machineDirectory = URL(fileURLWithPath: diskPath).deletingLastPathComponent()

        // The current disk moves aside first, so a failed clone leaves it where it was.
        let aside = URL(fileURLWithPath: diskPath + ".before-restore")
        try? fileManager.removeItem(at: aside)
        try fileManager.moveItem(atPath: diskPath, toPath: aside.path)
        do {
            try clone(from: backupDisk.path, to: diskPath)
        } catch {
            try? fileManager.moveItem(atPath: aside.path, toPath: diskPath)
            throw error
        }
        try? fileManager.removeItem(at: aside)

        let backupVars = directory.appendingPathComponent(firmwareVarsFileName)
        if fileManager.fileExists(atPath: backupVars.path) {
            let vars = machineDirectory.appendingPathComponent(firmwareVarsFileName)
            try? fileManager.removeItem(at: vars)
            try fileManager.copyItem(at: backupVars, to: vars)
        }
        let backupTPM = directory.appendingPathComponent(tpmDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: backupTPM.path) {
            try copyTPMState(from: backupTPM, to: machineDirectory.appendingPathComponent(tpmDirectoryName, isDirectory: true))
        }
        try fileManager.removeItem(at: directory)
    }

    static func clone(from source: String, to destination: String) throws {
        guard clonefile(source, destination, 0) == 0 else {
            throw BackupError.clonesUnsupported(String(cString: strerror(errno)))
        }
    }

    /// The TPM's state files only: the emulator's socket, pid and lock files belong to a running emulator.
    static func copyTPMState(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: source.path) else {
            return
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in names where name.hasPrefix("tpm2-") {
            let target = destination.appendingPathComponent(name)
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: source.appendingPathComponent(name), to: target)
        }
    }
}
