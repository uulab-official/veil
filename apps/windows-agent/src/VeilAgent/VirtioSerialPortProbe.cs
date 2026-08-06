using System.Runtime.InteropServices;
using System.Text;

namespace Veil.Agent;

public sealed record VirtioSerialPortInfo(
    string DevicePath,
    string? PortName,
    bool HostConnected,
    bool GuestConnected
);

/// <summary>
/// Read-only discovery for the Windows vioser device interface.
///
/// This is deliberately a probe, not a transport. A driver being present is not
/// enough to claim that QEMU and the guest can exchange Veil protocol messages.
/// </summary>
public static class VirtioSerialPortProbe
{
    private static readonly Guid VirtioSerialPortInterfaceGuid = new(
        "6fde7521-1b65-48ae-b628-80be62016026"
    );

    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint OpenExisting = 3;
    private const uint FileAttributeNormal = 0x00000080;
    private const uint FileDeviceUnknown = 0x00000022;
    private const uint IoctlGetInformation =
        (FileDeviceUnknown << 16) | (0x800u << 2) | 2u;
    private const int InvalidHandleValue = -1;

    public static IReadOnlyList<VirtioSerialPortInfo> Discover()
    {
        if (!OperatingSystem.IsWindows())
        {
            return Array.Empty<VirtioSerialPortInfo>();
        }

        var interfaceGuid = VirtioSerialPortInterfaceGuid;
        var deviceInfoSet = SetupDiGetClassDevs(
            ref interfaceGuid,
            IntPtr.Zero,
            IntPtr.Zero,
            DigcfPresent | DigcfDeviceInterface
        );

        if (deviceInfoSet == new IntPtr(InvalidHandleValue))
        {
            return Array.Empty<VirtioSerialPortInfo>();
        }

        var results = new List<VirtioSerialPortInfo>();
        try
        {
            for (uint index = 0; ; index++)
            {
                var interfaceData = new DeviceInterfaceData
                {
                    CbSize = Marshal.SizeOf<DeviceInterfaceData>()
                };

                if (!SetupDiEnumDeviceInterfaces(
                        deviceInfoSet,
                        IntPtr.Zero,
                        ref interfaceGuid,
                        index,
                        ref interfaceData
                    ))
                {
                    break;
                }

                var devicePath = ReadDevicePath(deviceInfoSet, ref interfaceData);
                if (devicePath is null)
                {
                    continue;
                }

                var portInfo = ReadPortInfo(devicePath);
                if (portInfo is not null)
                {
                    results.Add(portInfo);
                }
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(deviceInfoSet);
        }

        return results;
    }

    internal static uint GetInformationIoctlCode() => IoctlGetInformation;

    internal static VirtioSerialPortInfo ParsePortInfo(
        string devicePath,
        ReadOnlySpan<byte> buffer,
        int returnedLength
    )
    {
        // VIRTIO_PORT_INFO from the upstream vioser public header is UINT id,
        // three BOOLEAN fields, then a NUL-terminated ANSI name at byte 7.
        var hostConnected = returnedLength > 5 && buffer.Length > 5 && buffer[5] != 0;
        var guestConnected = returnedLength > 6 && buffer.Length > 6 && buffer[6] != 0;
        var name = returnedLength > 7 && buffer.Length > 7
            ? ReadAnsiName(buffer[7..Math.Min(returnedLength, buffer.Length)])
            : string.Empty;

        return new VirtioSerialPortInfo(
            devicePath,
            string.IsNullOrWhiteSpace(name) ? null : name,
            hostConnected,
            guestConnected
        );
    }

    private static string? ReadDevicePath(IntPtr deviceInfoSet, ref DeviceInterfaceData interfaceData)
    {
        SetupDiGetDeviceInterfaceDetail(
            deviceInfoSet,
            ref interfaceData,
            IntPtr.Zero,
            0,
            out var requiredLength,
            IntPtr.Zero
        );

        if (requiredLength <= 0)
        {
            return null;
        }

        var detailData = Marshal.AllocHGlobal(requiredLength);
        try
        {
            Marshal.WriteInt32(detailData, IntPtr.Size == 8 ? 8 : 5);
            if (!SetupDiGetDeviceInterfaceDetail(
                    deviceInfoSet,
                    ref interfaceData,
                    detailData,
                    requiredLength,
                    out _,
                    IntPtr.Zero
                ))
            {
                return null;
            }

            return Marshal.PtrToStringUni(IntPtr.Add(detailData, 4));
        }
        finally
        {
            Marshal.FreeHGlobal(detailData);
        }
    }

    private static VirtioSerialPortInfo? ReadPortInfo(string devicePath)
    {
        var handle = CreateFile(
            devicePath,
            GenericRead | GenericWrite,
            0,
            IntPtr.Zero,
            OpenExisting,
            FileAttributeNormal,
            IntPtr.Zero
        );

        if (handle == new IntPtr(InvalidHandleValue))
        {
            return null;
        }

        try
        {
            var buffer = new byte[4096];
            var returnedLength = 0u;
            if (!DeviceIoControl(
                    handle,
                    IoctlGetInformation,
                    IntPtr.Zero,
                    0,
                    buffer,
                    buffer.Length,
                    out returnedLength,
                    IntPtr.Zero
                ))
            {
                return null;
            }

            return ParsePortInfo(devicePath, buffer, (int)returnedLength);
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    private static string ReadAnsiName(ReadOnlySpan<byte> bytes)
    {
        var terminator = bytes.IndexOf((byte)0);
        return Encoding.ASCII.GetString(terminator >= 0 ? bytes[..terminator] : bytes);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInterfaceData
    {
        public int CbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(
        ref Guid classGuid,
        IntPtr enumerator,
        IntPtr hwndParent,
        uint flags
    );

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr deviceInfoSet,
        IntPtr deviceInfoData,
        ref Guid interfaceClassGuid,
        uint memberIndex,
        ref DeviceInterfaceData deviceInterfaceData
    );

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr deviceInfoSet,
        ref DeviceInterfaceData deviceInterfaceData,
        IntPtr deviceInterfaceDetailData,
        int deviceInterfaceDetailDataSize,
        out int requiredSize,
        IntPtr deviceInfoData
    );

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(
        IntPtr device,
        uint controlCode,
        IntPtr inputBuffer,
        int inputBufferSize,
        [Out] byte[] outputBuffer,
        int outputBufferSize,
        out uint bytesReturned,
        IntPtr overlapped
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
}
