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
///   and in the process footprint (a 1 GiB test mapping kept its footprint; `MADV_FREE_REUSABLE` halved
///   it for the half it covered). A discarded page reaches macOS only with `script/qemu-patches/` applied, which adds
///   `MADV_FREE_REUSABLE`. Until a patched QEMU is bundled, the device is in place but returns nothing.
/// - The ARM64 `balloon.sys` carries no free page reporting code, so the host has to set the balloon
///   size itself (QMP `balloon`) from the guest statistics instead of Windows offering free pages.
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
}
