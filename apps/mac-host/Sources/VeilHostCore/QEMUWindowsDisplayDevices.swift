import Foundation

/// The QEMU display devices a Windows guest boots with.
///
/// Windows on Arm has no inbox driver for `virtio-gpu-pci`, so setup and every Windows without the
/// virtio-win VirtIO GPU DOD driver (`viogpudo`) draws through `ramfb`, the firmware framebuffer, at a
/// fixed 800x600. Once `viogpudo` is installed, Windows draws on `virtio-gpu-pci`, whose size can follow
/// the Veil window. The two cannot simply stay attached together: with both, Windows extends the desktop
/// across a ramfb monitor and a virtio-gpu monitor, and VNC shows only one of them. Measured with
/// QEMU 11.1.3 and virtio-win 0.1.302 in docs/install-flow.md:
///
/// - `ramfb` + `virtio-gpu-pci`: firmware, Windows Setup, and Windows without `viogpudo` on the ramfb
///   console, which QEMU's VNC server shows because ramfb registers its console first.
/// - `virtio-gpu-pci` alone: firmware through EDK2's VirtioGpuDxe, a few black seconds while Windows
///   boots, then `viogpudo` from the sign-in screen on, on one monitor.
public enum QEMUWindowsDisplayDevices {
    /// Whether the next cold start can attach `virtio-gpu-pci` alone. Windows Setup needs ramfb, and so
    /// does a Windows whose agent has not reported `viogpudo` (or reported it missing).
    public static func bootsOnVirtioGPU(_ profile: VMProfile) -> Bool {
        profile.windowsInstalled == true && profile.virtioGPUDriverInstalled == true
    }

    /// `-device` arguments for the profile's current display choice. Uses the stored
    /// `bootsOnVirtioGPU`, never the live driver report, so a resumed session gets the devices it was
    /// saved with.
    public static func deviceArguments(for profile: VMProfile) -> [String] {
        if profile.windowsInstalled == true, profile.bootsOnVirtioGPU == true {
            return ["-device", "virtio-gpu-pci"]
        }

        return ["-device", "ramfb", "-device", "virtio-gpu-pci"]
    }
}
