import Darwin
import Foundation

/// How busy a QEMU process is, from the CPU time macOS has charged it.
///
/// A guest whose vCPUs sit in WFI costs QEMU almost nothing, so a low rate over several seconds says the
/// guest is idle without asking it. Used to tell a Windows that finished shutting down but never powered
/// off from one still installing updates (`GracefulWindowsShutdown.settledSeconds`).
public final class QEMUProcessActivity: @unchecked Sendable {
    /// Below this share of one core the guest counts as idle. A Windows desktop with one idle app kept
    /// QEMU at 13-17%; after its shutdown finished, at 0.3-1%.
    public static let idleCoreFraction = 0.03

    private let pid: Int32
    private var last: (cpuNanoseconds: UInt64, at: Date)?

    public init(pid: Int32) {
        self.pid = pid
    }

    /// The share of one core used since the previous call, or nil on the first call or when the process
    /// cannot be read.
    public func coreFractionSinceLastSample(now: Date = Date()) -> Double? {
        guard let cpu = Self.cpuNanoseconds(pid: pid) else {
            return nil
        }
        defer { last = (cpu, now) }
        guard let last, now > last.at, cpu >= last.cpuNanoseconds else {
            return nil
        }
        return Double(cpu - last.cpuNanoseconds) / 1_000_000_000 / now.timeIntervalSince(last.at)
    }

    public static func cpuNanoseconds(pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else {
            return nil
        }
        // Mach absolute time units, not nanoseconds: on Apple silicon one unit is 125/3 ns.
        let ticks = info.pti_total_user + info.pti_total_system
        return ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
}
