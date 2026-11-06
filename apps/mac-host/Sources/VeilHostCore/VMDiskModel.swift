import Foundation

/// State of the Configuration window's Disk tab. One operation runs at a time, and every operation
/// ends by showing the disk as it is afterwards.
@MainActor
@Observable
public final class VMDiskModel {
    public private(set) var status: VMDiskStatus?
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    private let manager: any VMDiskManaging

    public init(manager: any VMDiskManaging) {
        self.manager = manager
    }

    public func refresh() async {
        await perform { try await $0.diskStatus() }
    }

    public func grow(toGB sizeGB: Int) async {
        await perform { try await $0.growDisk(toGB: sizeGB) }
    }

    public func convertToQCOW2() async {
        await perform { try await $0.convertDiskToQCOW2() }
    }

    public func createSnapshot(named name: String) async {
        await perform { try await $0.createSnapshot(named: name) }
    }

    public func restoreSnapshot(named name: String) async {
        await perform { try await $0.restoreSnapshot(named: name) }
    }

    public func deleteSnapshot(named name: String) async {
        await perform { try await $0.deleteSnapshot(named: name) }
    }

    /// A name like `Snapshot-2026-11-05-1430`, which the snapshot name policy accepts.
    public static func suggestedSnapshotName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Snapshot-\(formatter.string(from: date))"
    }

    private func perform(_ operation: @Sendable (any VMDiskManaging) async throws -> VMDiskStatus?) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            status = try await operation(manager)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            status = (try? await manager.diskStatus()) ?? status
        }
        isWorking = false
    }
}
