import Foundation

/// The virtio memory balloon, through which the host takes back guest memory Windows is not using.
///
/// QEMU maps all of `-m` at start but the Mac only backs the pages the guest has touched, so CPU and
/// untouched memory are already shared with macOS. What is missing is the way back: once Windows has
/// touched a page (it zeroes freed pages, and its file cache grows into free memory) the Mac keeps it
/// for as long as QEMU runs. The balloon is that way back. Inflating it asks the virtio-win `Balloon`
/// driver (installed from `Balloon\w11\ARM64` by `Install-VeilVirtIODrivers.ps1`) for free pages and
/// QEMU discards them; deflating hands them back.
///
/// Two limits, found on macOS 27 with QEMU 11.1.3 and virtio-win 0.1.302:
///
/// - QEMU discards with `MADV_DONTNEED`, which on Darwin leaves the page resident, its contents intact
///   and in the process footprint. A discarded page reaches macOS only with `script/qemu-patches/`
///   applied, which adds `MADV_FREE_REUSABLE`: an Alpine guest touched 900 MB, was ballooned to
///   512 MB, and QEMU's footprint went from 1229 MB to 329 MB with the patch and to 1843 MB without.
///   The host therefore sizes the balloon only on a QEMU bundled with that patch
///   (`releasesMemoryToMac(executablePath:)`); on any other QEMU the device stays idle.
/// - The ARM64 `balloon.sys` carries no free page reporting code, so the host has to set the balloon
///   size itself (QMP `balloon`) from the guest statistics instead of Windows offering free pages;
///   `QEMUMemoryBalloonPolicy` decides the size.
///
/// `deflate-on-oom` lets Windows take pages back from the balloon under memory pressure without
/// waiting for the host.
public enum QEMUMemoryBalloon {
    public static let deviceID = "veil-balloon"

    /// Seconds between the guest statistics QEMU asks the driver for, read with QMP
    /// `qom-get <path> guest-stats`.
    public static let statisticsPollingSeconds = 5

    public static var deviceArguments: [String] {
        [
            "-device",
            "virtio-balloon-pci,id=\(deviceID),deflate-on-oom=on,guest-stats-polling-interval=\(statisticsPollingSeconds)"
        ]
    }

    /// The patch file `script/bundle_qemu_runtime.sh` ships beside a patched `qemu-system-aarch64`.
    public static let releasePatchFileName = "0001-virtio-balloon-release-discarded-pages-on-darwin.patch"

    /// Whether the QEMU at this path gives discarded balloon pages back to macOS: true only for Veil's
    /// bundled runtime built with the release patch (`<Runtime>/licenses/qemu-patches/`).
    public static func releasesMemoryToMac(
        executablePath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        let runtime = URL(fileURLWithPath: executablePath).deletingLastPathComponent().deletingLastPathComponent()
        return fileExists(
            runtime.appendingPathComponent("licenses/qemu-patches/\(releasePatchFileName)").path
        )
    }

    /// Whether a launch's arguments include the balloon device.
    public static func isAttached(arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix("virtio-balloon-pci,id=\(deviceID),") }
    }
}

/// How much memory macOS has to spare, from `DispatchSource.makeMemoryPressureSource`.
public enum HostMemoryPressure: String, Sendable {
    case normal
    case warning
    case critical
}

/// The memory the balloon driver reports for Windows, from QMP `guest-stats`.
public struct GuestMemoryStatistics: Equatable, Sendable {
    /// Memory Windows can hand out without paging: free, zeroed, and standby (cache) pages.
    public var availableBytes: Int64
    /// When the driver last reported, in seconds since the epoch.
    public var lastUpdate: Int64

    public init(availableBytes: Int64, lastUpdate: Int64) {
        self.availableBytes = availableBytes
        self.lastUpdate = lastUpdate
    }

    /// Nil when the driver has not reported yet (QEMU sends -1 for a missing statistic and 0 for
    /// `last-update` before the first report).
    public init?(qmpStatistics: [String: Int64]) {
        guard let available = qmpStatistics["stat-available-memory"], available >= 0,
              let lastUpdate = qmpStatistics["last-update"], lastUpdate > 0 else {
            return nil
        }
        self.init(availableBytes: available, lastUpdate: lastUpdate)
    }
}

/// Decides how big Windows should be through the balloon, so memory it is not using goes back to
/// the Mac and comes back the moment Windows needs it, the way Parallels' adaptive memory behaves.
///
/// Windows keeps `used + cushion`, where used is what it holds beyond its available pages and the
/// cushion shrinks as macOS comes under memory pressure. Growing happens at once; shrinking moves at
/// most `shrinkStepBytes` per decision so Windows trims its cache gradually. Windows never goes
/// below `floorBytes` (or its configured size, if smaller). `deflate-on-oom` on the device covers a
/// sudden demand between two decisions.
public enum QEMUMemoryBalloonPolicy {
    public static let mebibyte: Int64 = 1_048_576
    public static let gibibyte: Int64 = 1_024 * mebibyte
    public static let floorBytes: Int64 = 4 * gibibyte
    public static let shrinkStepBytes: Int64 = 1 * gibibyte
    /// Smaller changes are skipped so the balloon does not chase noise.
    public static let hysteresisBytes: Int64 = 512 * mebibyte
    /// Statistics older than this are not trusted; the driver reports every few seconds.
    public static let staleAfterSeconds: Int64 = 30
    static let granularityBytes: Int64 = 256 * mebibyte

    public static func cushionBytes(configuredBytes: Int64, pressure: HostMemoryPressure) -> Int64 {
        switch pressure {
        case .normal:
            max(1 * gibibyte, configuredBytes / 5)
        case .warning:
            max(768 * mebibyte, configuredBytes / 10)
        case .critical:
            512 * mebibyte
        }
    }

    /// The balloon target to send, or nil to leave the balloon as it is.
    ///
    /// - Parameters:
    ///   - configuredBytes: the `-m` size.
    ///   - actualBytes: the guest's current size from `query-balloon`.
    ///   - statistics: the driver's latest report, or nil when it has none.
    public static func target(
        configuredBytes: Int64,
        actualBytes: Int64,
        statistics: GuestMemoryStatistics?,
        pressure: HostMemoryPressure,
        now: Int64
    ) -> Int64? {
        guard let statistics, now - statistics.lastUpdate <= staleAfterSeconds else {
            // Without fresh numbers Veil cannot tell what Windows needs, so it gives everything back.
            return actualBytes < configuredBytes ? configuredBytes : nil
        }

        let used = max(0, actualBytes - statistics.availableBytes)
        let floor = min(configuredBytes, floorBytes)
        let wanted = roundedUp(used + cushionBytes(configuredBytes: configuredBytes, pressure: pressure))
        let desired = min(configuredBytes, max(floor, wanted))

        if desired > actualBytes {
            return desired - actualBytes >= granularityBytes || desired == configuredBytes ? desired : nil
        }
        guard actualBytes - desired >= hysteresisBytes else {
            return nil
        }
        return max(desired, actualBytes - shrinkStepBytes)
    }

    static func roundedUp(_ bytes: Int64) -> Int64 {
        (bytes + granularityBytes - 1) / granularityBytes * granularityBytes
    }
}
