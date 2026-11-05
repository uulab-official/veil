using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Veil.Agent;

/// <summary>
/// The virtio-win VirtIO GPU DOD display driver (<c>viogpudo</c>) as seen from inside Windows.
///
/// Veil boots Windows on QEMU's <c>virtio-gpu-pci</c> once this driver is installed, because that is the
/// display whose size can follow the Veil window. Two driver behaviors shape this class, both measured on
/// a Windows 11 Arm guest with virtio-win 0.1.302 (docs/install-flow.md):
///
/// - The driver lists the size the host last asked for as one custom mode, but on QEMU/HVF it never
///   picks up a new host size while Windows runs, so <c>ChangeDisplaySettingsEx</c> answers
///   <c>DISP_CHANGE_BADMODE</c> for any other size. The driver's private escape
///   <c>VIOGPU_SET_CUSTOM_RESOLUTION</c>, the one virtio-win's <c>viogpures.exe</c> sends, replaces that
///   custom mode; after it the normal mode change succeeds. It works from a standard user token.
/// - The escape is private driver data, so it is only ever sent to an adapter whose PCI ID is the
///   virtio-gpu device; another driver could read the same bytes as something else.
///
/// Source of the escape layout: kvm-guest-drivers-windows viogpu/shared/viogpum.h.
/// </summary>
public static class VirtioGpuDisplay
{
    /// <summary>The virtio-gpu PCI function as Windows names it (vendor Red Hat, device 0x1050).</summary>
    public const string PciDeviceIdPrefix = "PCI\\VEN_1AF4&DEV_1050";

    public const string DriverServiceName = "VioGpuDod";

    private const ushort VioGpuSetCustomResolution = 0x02;
    private const int D3DKmtEscapeDriverPrivate = 0;
    private const uint DisplayDeviceAttachedToDesktop = 0x1;
    private const uint DisplayDevicePrimaryDevice = 0x4;

    /// <summary>
    /// True when the virtio-gpu device has <c>viogpudo</c> as its driver. Read from the registry so a
    /// standard-user agent can answer; it stays true while the device is absent (a VM booted on ramfb
    /// alone), which is the case Veil needs to know about before choosing the next boot's display.
    /// </summary>
    public static bool IsDriverInstalled()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using var service = Registry.LocalMachine.OpenSubKey(
                "SYSTEM\\CurrentControlSet\\Services\\" + DriverServiceName);
            if (service == null)
            {
                return false;
            }

            using var pci = Registry.LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Enum\\PCI");
            if (pci == null)
            {
                return false;
            }

            var hardwarePrefix = PciDeviceIdPrefix.Substring("PCI\\".Length);
            foreach (var hardwareName in pci.GetSubKeyNames())
            {
                if (!hardwareName.StartsWith(hardwarePrefix, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                using var hardware = pci.OpenSubKey(hardwareName);
                if (hardware == null)
                {
                    continue;
                }

                foreach (var instanceName in hardware.GetSubKeyNames())
                {
                    using var instance = hardware.OpenSubKey(instanceName);
                    if (instance?.GetValue("Service") is string serviceName
                        && string.Equals(serviceName, DriverServiceName, StringComparison.OrdinalIgnoreCase))
                    {
                        return true;
                    }
                }
            }
        }
        catch (System.Security.SecurityException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        return false;
    }

    /// <summary>
    /// Replaces the driver's custom mode with <paramref name="width"/> x <paramref name="height"/> on the
    /// primary display, when that display is the virtio-gpu device. Returns false without sending
    /// anything for any other adapter.
    /// </summary>
    public static bool TrySetCustomMode(int width, int height)
    {
        if (!OperatingSystem.IsWindows()
            || width <= 0 || width > ushort.MaxValue
            || height <= 0 || height > ushort.MaxValue)
        {
            return false;
        }

        var deviceName = PrimaryVirtioGpuDeviceName();
        if (deviceName == null)
        {
            return false;
        }

        var deviceContext = CreateDC(null, deviceName, null, IntPtr.Zero);
        if (deviceContext == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            var open = new D3DKmtOpenAdapterFromHdc { DeviceContext = deviceContext };
            if (D3DKMTOpenAdapterFromHdc(ref open) != 0)
            {
                return false;
            }

            var payload = Marshal.AllocHGlobal(Marshal.SizeOf<VioGpuEscape>());
            try
            {
                Marshal.StructureToPtr(
                    new VioGpuEscape
                    {
                        Type = VioGpuSetCustomResolution,
                        DataLength = 4,
                        Width = (ushort)width,
                        Height = (ushort)height
                    },
                    payload,
                    false);
                var escape = new D3DKmtEscape
                {
                    Adapter = open.Adapter,
                    Type = D3DKmtEscapeDriverPrivate,
                    PrivateDriverData = payload,
                    PrivateDriverDataSize = (uint)Marshal.SizeOf<VioGpuEscape>()
                };
                return D3DKMTEscape(ref escape) == 0;
            }
            finally
            {
                Marshal.FreeHGlobal(payload);
                var close = new D3DKmtCloseAdapter { Adapter = open.Adapter };
                D3DKMTCloseAdapter(ref close);
            }
        }
        finally
        {
            DeleteDC(deviceContext);
        }
    }

    private static string? PrimaryVirtioGpuDeviceName()
    {
        var device = new DisplayDevice { Size = Marshal.SizeOf<DisplayDevice>() };
        for (uint index = 0; EnumDisplayDevices(null, index, ref device, 0); index++)
        {
            var isPrimary = (device.StateFlags & DisplayDevicePrimaryDevice) != 0
                && (device.StateFlags & DisplayDeviceAttachedToDesktop) != 0;
            if (isPrimary
                && device.DeviceId.StartsWith(PciDeviceIdPrefix, StringComparison.OrdinalIgnoreCase))
            {
                return device.DeviceName;
            }

            device = new DisplayDevice { Size = Marshal.SizeOf<DisplayDevice>() };
        }

        return null;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct VioGpuEscape
    {
        public ushort Type;
        public ushort DataLength;
        public ushort Width;
        public ushort Height;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct D3DKmtOpenAdapterFromHdc
    {
        public IntPtr DeviceContext;
        public uint Adapter;
        public uint AdapterLuidLowPart;
        public int AdapterLuidHighPart;
        public uint VidPnSourceId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct D3DKmtEscape
    {
        public uint Adapter;
        public uint Device;
        public int Type;
        public uint Flags;
        public IntPtr PrivateDriverData;
        public uint PrivateDriverDataSize;
        public uint Context;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct D3DKmtCloseAdapter
    {
        public uint Adapter;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceId;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumDisplayDevices(string? device, uint deviceIndex, ref DisplayDevice displayDevice, uint flags);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateDC(string? driver, string device, string? output, IntPtr initData);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr deviceContext);

    [DllImport("gdi32.dll")]
    private static extern int D3DKMTOpenAdapterFromHdc(ref D3DKmtOpenAdapterFromHdc open);

    [DllImport("gdi32.dll")]
    private static extern int D3DKMTEscape(ref D3DKmtEscape escape);

    [DllImport("gdi32.dll")]
    private static extern int D3DKMTCloseAdapter(ref D3DKmtCloseAdapter close);
}
