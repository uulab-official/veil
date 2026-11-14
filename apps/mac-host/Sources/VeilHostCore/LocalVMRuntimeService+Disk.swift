import Foundation

/// The Windows system disk as the Configuration window shows it: format, size, and snapshots.
public struct VMDiskStatus: Equatable, Sendable {
    public var path: String
    public var format: QEMUDiskImageFormat
    /// The size Windows sees, from `qemu-img info`.
    public var virtualSizeBytes: Int64?
    /// The space the disk takes on the Mac.
    public var allocatedBytes: Int64?
    public var snapshots: [VMSnapshotSummary]
    public var isDiskToolAvailable: Bool
    /// Why the snapshot list could not be read, when it could not.
    public var snapshotListError: String?

    public init(
        path: String,
        format: QEMUDiskImageFormat,
        virtualSizeBytes: Int64? = nil,
        allocatedBytes: Int64? = nil,
        snapshots: [VMSnapshotSummary] = [],
        isDiskToolAvailable: Bool,
        snapshotListError: String? = nil
    ) {
        self.path = path
        self.format = format
        self.virtualSizeBytes = virtualSizeBytes
        self.allocatedBytes = allocatedBytes
        self.snapshots = snapshots
        self.isDiskToolAvailable = isDiskToolAvailable
        self.snapshotListError = snapshotListError
    }

    public var supportsSnapshots: Bool {
        format == .qcow2 && isDiskToolAvailable
    }
}

public enum VMDiskError: Error, LocalizedError, Equatable, Sendable {
    case noDisk
    case toolUnavailable
    case snapshotsNeedQCOW2
    case snapshotsNeedRunningOrStoppedWindows
    case snapshotHasNoMemoryState(String)

    public var errorDescription: String? {
        switch self {
        case .noDisk:
            "No Windows disk is configured yet."
        case .toolUnavailable:
            QEMUDiskImageError.toolUnavailable.errorDescription
        case .snapshotsNeedQCOW2:
            "Snapshots need a qcow2 disk. Convert the disk to qcow2 first."
        case .snapshotsNeedRunningOrStoppedWindows:
            "Wait until Windows is running or stopped. A suspended or starting Windows cannot take or restore snapshots."
        case .snapshotHasNoMemoryState(let tag):
            "Snapshot '\(tag)' was taken while Windows was off, so it holds no running Windows to return to. Shut down Windows, then restore it."
        }
    }
}

/// Disk and snapshot management behind the Configuration window.
public protocol VMDiskManaging: Sendable {
    func diskStatus() async throws -> VMDiskStatus?
    func growDisk(toGB sizeGB: Int) async throws -> VMDiskStatus?
    func convertDiskToQCOW2() async throws -> VMDiskStatus?
    func createSnapshot(named name: String) async throws -> VMDiskStatus?
    func restoreSnapshot(named name: String) async throws -> VMDiskStatus?
    func deleteSnapshot(named name: String) async throws -> VMDiskStatus?
}

extension LocalVMRuntimeService: VMDiskManaging {
    public func diskStatus() async throws -> VMDiskStatus? {
        guard let profile = try await profileStore.load(),
              let path = profile.virtualDiskPath, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let format = QEMUDiskImageFormat.detect(atPath: path)
        var status = VMDiskStatus(
            path: path,
            format: format,
            virtualSizeBytes: try? diskImageTool?.info(path: path).virtualSizeBytes,
            allocatedBytes: Self.allocatedFileSize(path: path, bookmarkData: profile.virtualDiskBookmarkData),
            isDiskToolAvailable: diskImageTool != nil
        )
        if format == .qcow2, let diskImageTool {
            // `-U` reads the snapshot table without a lock, so this also works while Windows runs.
            do {
                status.snapshots = try diskImageTool.listSnapshots(path: path)
            } catch {
                status.snapshotListError = error.localizedDescription
            }
        }
        return status
    }

    /// Makes the disk bigger while Windows is stopped. Windows then extends C: in Disk Management.
    public func growDisk(toGB sizeGB: Int) async throws -> VMDiskStatus? {
        try await requireResourceMutationAllowed()
        guard var profile = try await profileStore.load(),
              let path = profile.virtualDiskPath, !path.isEmpty else {
            throw VMDiskError.noDisk
        }
        guard let diskImageTool else {
            throw VMDiskError.toolUnavailable
        }

        let info = try diskImageTool.info(path: path)
        try diskImageTool.grow(
            path: path,
            format: info.format,
            currentBytes: info.virtualSizeBytes,
            newSizeBytes: Int64(sizeGB) * 1_024 * 1_024 * 1_024
        )
        profile.diskGB = sizeGB
        try await profileStore.save(profile)
        return try await diskStatus()
    }

    /// Copies a raw disk into a qcow2 one next to it, switches the VM to the copy, and moves the raw
    /// file to the Trash. Only on the user's request: it needs about as much free space as the raw
    /// disk uses.
    public func convertDiskToQCOW2() async throws -> VMDiskStatus? {
        try await convertDiskToQCOW2(availableBytes: Self.volumeAvailableBytes(for:))
    }

    func convertDiskToQCOW2(availableBytes: (URL) -> Int64?) async throws -> VMDiskStatus? {
        try await requireResourceMutationAllowed()
        guard var profile = try await profileStore.load(),
              let sourcePath = profile.virtualDiskPath, !sourcePath.isEmpty,
              FileManager.default.fileExists(atPath: sourcePath) else {
            throw VMDiskError.noDisk
        }
        guard let diskImageTool else {
            throw VMDiskError.toolUnavailable
        }
        guard QEMUDiskImageFormat.detect(atPath: sourcePath) == .raw else {
            throw QEMUDiskImageError.alreadyQCOW2
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destinationURL = Self.convertedDiskURL(for: sourceURL)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw QEMUDiskImageError.destinationExists(destinationURL.path)
        }

        // qcow2 stores only written clusters, so the copy needs about what the raw file has allocated,
        // plus metadata headroom.
        let requiredBytes = (Self.allocatedFileSize(path: sourcePath, bookmarkData: profile.virtualDiskBookmarkData) ?? 0)
            + Self.conversionHeadroomBytes
        if let available = availableBytes(destinationURL.deletingLastPathComponent()), available < requiredBytes {
            throw QEMUDiskImageError.insufficientSpace(requiredBytes: requiredBytes, availableBytes: available)
        }

        // Converted under a temporary name so a failed or interrupted copy never looks like a disk.
        let partialURL = destinationURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partialURL)
        do {
            try diskImageTool.convertToQCOW2(source: sourcePath, destination: partialURL.path)
            try FileManager.default.moveItem(at: partialURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }

        profile.virtualDiskPath = destinationURL.path
        profile.virtualDiskBookmarkData = Self.bookmarkData(for: destinationURL.path)
        try await profileStore.save(profile)
        do {
            try installationDiscarder(sourceURL)
        } catch {
            // The VM already uses the qcow2 copy; a raw file left behind only costs space.
            VeilLog.runtime.notice("Converted the Windows disk but could not move the raw original to the Trash: \(String(describing: error))")
        }
        return try await diskStatus()
    }

    public func createSnapshot(named name: String) async throws -> VMDiskStatus? {
        try await performSnapshotAction(name: name, live: { tag, socket in
            try await snapshotController.create(tag: tag, qmpSocketPath: socket)
        }, offline: { tool, path, tag in
            try tool.createSnapshot(path: path, tag: tag)
        })
    }

    public func restoreSnapshot(named name: String) async throws -> VMDiskStatus? {
        try await performSnapshotAction(name: name, live: { tag, socket in
            try await snapshotController.restore(tag: tag, qmpSocketPath: socket)
        }, offline: { tool, path, tag in
            try tool.applySnapshot(path: path, tag: tag)
        }, requiresMemoryStateWhenLive: true)
    }

    public func deleteSnapshot(named name: String) async throws -> VMDiskStatus? {
        try await performSnapshotAction(name: name, live: { tag, socket in
            try await snapshotController.delete(tag: tag, qmpSocketPath: socket)
        }, offline: { tool, path, tag in
            try tool.deleteSnapshot(path: path, tag: tag)
        })
    }

    /// A running Windows snapshots memory and disk together through QEMU; a stopped one snapshots the
    /// disk alone through qemu-img, and restoring such a snapshot starts Windows fresh next time.
    private func performSnapshotAction(
        name: String,
        live: @Sendable (String, String) async throws -> String,
        offline: (QEMUDiskImageTool, String, String) throws -> Void,
        requiresMemoryStateWhenLive: Bool = false
    ) async throws -> VMDiskStatus? {
        let tag = try QEMUSnapshotTagPolicy.validate(name)
        guard let profile = try await profileStore.load(),
              let path = profile.virtualDiskPath, !path.isEmpty else {
            throw VMDiskError.noDisk
        }
        guard let diskImageTool else {
            throw VMDiskError.toolUnavailable
        }
        guard QEMUDiskImageFormat.detect(atPath: path) == .qcow2 else {
            throw VMDiskError.snapshotsNeedQCOW2
        }

        switch try await loadSnapshot().state {
        case .running:
            if requiresMemoryStateWhenLive,
               let snapshot = try diskImageTool.listSnapshots(path: path).first(where: { $0.tag == tag }),
               !Self.snapshotHasMemoryState(snapshot) {
                throw VMDiskError.snapshotHasNoMemoryState(tag)
            }
            guard let socket = try? await qemuLaunchRecordStore.loadLatest()?.qmpSocketPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !socket.isEmpty else {
                throw VMSnapshotError.qmpUnavailable
            }
            _ = try await live(tag, socket)
        case .stopped, .failed, .notConfigured, .unsupported:
            try offline(diskImageTool, path, tag)
        case .starting, .suspended:
            throw VMDiskError.snapshotsNeedRunningOrStoppedWindows
        }
        return try await diskStatus()
    }

    static let conversionHeadroomBytes: Int64 = 1_024 * 1_024 * 1_024

    /// `Windows 11 Arm.img` becomes `Windows 11 Arm.qcow2`; a raw file already named `.qcow2` gets a
    /// distinct name instead of being overwritten.
    static func convertedDiskURL(for sourceURL: URL) -> URL {
        let base = sourceURL.deletingPathExtension()
        let candidate = base.appendingPathExtension(QEMUDiskImageFormat.qcow2.fileExtension)
        guard candidate.path != sourceURL.path else {
            return URL(fileURLWithPath: base.path + "-converted").appendingPathExtension(QEMUDiskImageFormat.qcow2.fileExtension)
        }
        return candidate
    }

    /// qemu-img prints "0 B" in the VM SIZE column for a disk-only snapshot.
    static func snapshotHasMemoryState(_ snapshot: VMSnapshotSummary) -> Bool {
        guard let value = Double(snapshot.vmStateSize.split(separator: " ").first ?? "") else {
            return true
        }
        return value > 0
    }

    static func volumeAvailableBytes(for directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
