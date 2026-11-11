using System.Runtime.InteropServices;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// Starts packaged apps by AppUserModelID and tells which app a window belongs to.
/// </summary>
/// <remarks>
/// A packaged app has no executable to pass to <c>Process.Start</c>. <c>IApplicationActivationManager</c>
/// activates it the way Start does and returns the app's process id.
/// See https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-iapplicationactivationmanager.
///
/// A UWP app's top-level window belongs to ApplicationFrameHost.exe, not to the process activation returned,
/// so matching windows by process name misses it. The frame window carries the hosted app's AppUserModelID
/// in its property store, which is how the taskbar groups it, and the app's own CoreWindow is a child of it.
/// A packaged desktop app, such as Windows Terminal, owns its windows, and its process has the id.
/// </remarks>
internal static class PackagedAppActivation
{
    private const int ActivateOptionsNone = 0;
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const int ErrorSuccess = 0;
    private const ushort VtLpwstr = 31;

    private static readonly Guid ApplicationActivationManagerClassId = new("45BA127D-10A8-46EA-8AB7-56EA9078943C");

    // PKEY_AppUserModel_ID: https://learn.microsoft.com/windows/win32/properties/props-system-appusermodel-id
    private static PropertyKey appUserModelIdKey = new()
    {
        FormatId = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
        PropertyId = 5
    };

    /// <summary>Activates the app and returns the process id Windows reports for it.</summary>
    public static int Activate(string appUserModelId, string? arguments)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        var instance = Activator.CreateInstance(
            Type.GetTypeFromCLSID(ApplicationActivationManagerClassId, throwOnError: true)!
        )!;
        try
        {
            var manager = (IApplicationActivationManager)instance;
            var result = manager.ActivateApplication(appUserModelId, arguments, ActivateOptionsNone, out var processId);
            Marshal.ThrowExceptionForHR(result);
            return (int)processId;
        }
        finally
        {
            Marshal.ReleaseComObject(instance);
        }
    }

    /// <summary>
    /// Whether a top-level window belongs to the packaged app with this AppUserModelID.
    /// </summary>
    public static bool WindowBelongsTo(IntPtr hwnd, uint processId, string appUserModelId)
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        return Matches(WindowAppUserModelId(hwnd), appUserModelId)
            || Matches(ProcessAppUserModelId(processId), appUserModelId)
            || HostedChildProcessIds(hwnd, processId).Any(child => Matches(ProcessAppUserModelId(child), appUserModelId));
    }

    private static bool Matches(string? candidate, string appUserModelId) =>
        candidate is not null && string.Equals(candidate, appUserModelId, StringComparison.OrdinalIgnoreCase);

    private static string? WindowAppUserModelId(IntPtr hwnd)
    {
        var storeId = typeof(IPropertyStore).GUID;
        if (SHGetPropertyStoreForWindow(hwnd, ref storeId, out var store) != 0 || store is null)
        {
            return null;
        }

        var value = default(PropVariant);
        try
        {
            if (store.GetValue(ref appUserModelIdKey, out value) != 0 || value.Type != VtLpwstr)
            {
                return null;
            }

            return Marshal.PtrToStringUni(value.Pointer);
        }
        catch (COMException)
        {
            return null;
        }
        finally
        {
            _ = PropVariantClear(ref value);
            Marshal.ReleaseComObject(store);
        }
    }

    private static string? ProcessAppUserModelId(uint processId)
    {
        var process = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (process == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            // APPLICATION_USER_MODEL_ID_MAX_LENGTH is 130 characters, including the terminator.
            uint length = 130;
            var buffer = new StringBuilder((int)length);
            // APPMODEL_ERROR_NO_APPLICATION for a process without package identity, which is most of them.
            return GetApplicationUserModelId(process, ref length, buffer) == ErrorSuccess ? buffer.ToString() : null;
        }
        finally
        {
            _ = CloseHandle(process);
        }
    }

    /// <summary>
    /// Processes owning a child window of a frame window other than the frame's own process: the UWP app
    /// ApplicationFrameHost.exe is showing.
    /// </summary>
    private static HashSet<uint> HostedChildProcessIds(IntPtr hwnd, uint frameProcessId)
    {
        var children = new HashSet<uint>();
        _ = EnumChildWindows(hwnd, (child, unused) =>
        {
            _ = GetWindowThreadProcessId(child, out var childProcessId);
            if (childProcessId != 0 && childProcessId != frameProcessId)
            {
                children.Add(childProcessId);
            }

            return true;
        }, IntPtr.Zero);
        return children;
    }

    [ComImport]
    [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string? arguments,
            int options,
            out uint processId
        );

        [PreserveSig]
        int ActivateForFile(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr itemArray,
            [MarshalAs(UnmanagedType.LPWStr)] string verb,
            out uint processId
        );

        [PreserveSig]
        int ActivateForProtocol(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr itemArray,
            out uint processId
        );
    }

    // https://learn.microsoft.com/windows/win32/api/propsys/nn-propsys-ipropertystore
    [ComImport]
    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        [PreserveSig]
        int GetCount(out uint count);

        [PreserveSig]
        int GetAt(uint index, out PropertyKey key);

        [PreserveSig]
        int GetValue(ref PropertyKey key, out PropVariant value);

        [PreserveSig]
        int SetValue(ref PropertyKey key, ref PropVariant value);

        [PreserveSig]
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;
    }

    // Only the string case is read. The layout matches PROPVARIANT's 16 bytes on 32-bit and 24 on 64-bit.
    [StructLayout(LayoutKind.Sequential)]
    private struct PropVariant
    {
        public ushort Type;
        public ushort Reserved1;
        public ushort Reserved2;
        public ushort Reserved3;
        public IntPtr Pointer;
        public IntPtr Extra;
    }

    private delegate bool EnumChildProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(
        IntPtr hwnd,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore? propertyStore
    );

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PropVariant value);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetApplicationUserModelId(IntPtr process, ref uint length, StringBuilder appUserModelId);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr parent, EnumChildProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
