import Foundation

/// One balloon decision, for logging and tests.
public struct MemoryBalloonAdjustment: Equatable, Sendable {
    public var previousBytes: Int64
    public var targetBytes: Int64
    public var pressure: HostMemoryPressure
}

extension LocalVMRuntimeService {
    /// Resizes Windows through the memory balloon once, from the driver's latest statistics and the
    /// Mac's memory pressure. Returns nil when nothing changed: no running VM, no balloon device, a QEMU
    /// that would not give the pages to macOS, or a size already right.
    public func adjustMemoryBalloon(
        pressure: HostMemoryPressure,
        qmp: any QEMUQMPControlling = QEMUQMPClient(),
        now: Date = Date()
    ) async -> MemoryBalloonAdjustment? {
        let launchRecord: QEMULaunchRecord?
        do {
            launchRecord = try await qemuLaunchRecordStore.loadLatest()
        } catch {
            return nil
        }
        guard let launchRecord,
              QEMUMemoryBalloon.isAttached(arguments: launchRecord.arguments),
              QEMUMemoryBalloon.releasesMemoryToMac(executablePath: launchRecord.executablePath),
              let configuredBytes = Self.configuredMemoryBytes(arguments: launchRecord.arguments),
              let socketPath = Self.liveQMPSocketPath(launchRecord, processIsRunning: qemuLaunchProcessIsRunning) else {
            return nil
        }

        do {
            let replies = try await qmp.execute(
                [.queryBalloon, .queryBalloonStatistics(deviceID: QEMUMemoryBalloon.deviceID)],
                socketPath: socketPath,
                idleTimeoutSeconds: 1
            )
            guard let actualBytes = replies.first?.balloonActualBytes else {
                return nil
            }
            let statistics = replies.last?.balloonStatistics.flatMap(GuestMemoryStatistics.init(qmpStatistics:))
            guard let target = QEMUMemoryBalloonPolicy.target(
                configuredBytes: configuredBytes,
                actualBytes: actualBytes,
                statistics: statistics,
                pressure: pressure,
                now: Int64(now.timeIntervalSince1970)
            ) else {
                return nil
            }

            try await qmp.run(.setBalloonTarget(bytes: target), socketPath: socketPath)
            VeilLog.runtime.notice(
                "Resized Windows memory from \(actualBytes / QEMUMemoryBalloonPolicy.mebibyte, privacy: .public) MB to \(target / QEMUMemoryBalloonPolicy.mebibyte, privacy: .public) MB (Mac memory pressure \(pressure.rawValue, privacy: .public))."
            )
            return MemoryBalloonAdjustment(previousBytes: actualBytes, targetBytes: target, pressure: pressure)
        } catch {
            VeilLog.runtime.error("Failed to resize the Windows memory balloon: \(String(describing: error))")
            return nil
        }
    }

    /// The `-m` value of a launch, in bytes.
    static func configuredMemoryBytes(arguments: [String]) -> Int64? {
        guard let index = arguments.firstIndex(of: "-m"), arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1]
        guard value.hasSuffix("M"), let megabytes = Int64(value.dropLast()) else {
            return nil
        }
        return megabytes * QEMUMemoryBalloonPolicy.mebibyte
    }
}

/// Follows macOS memory pressure so the balloon cushion can shrink when the Mac needs memory.
public final class HostMemoryPressureMonitor: @unchecked Sendable {
    public static let shared = HostMemoryPressureMonitor()

    private let lock = NSLock()
    private var level: HostMemoryPressure = .normal
    private let source: DispatchSourceMemoryPressure

    private init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            let next: HostMemoryPressure = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            self.lock.withLock { self.level = next }
        }
        source.activate()
    }

    public var current: HostMemoryPressure {
        lock.withLock { level }
    }
}
