using System.Runtime.InteropServices;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// Whether the desktop receiving the user's input is the agent's own. It is not while Windows shows a
/// User Account Control prompt, the lock or sign-in screen, or the Ctrl+Alt+Del screen: those run on the
/// Winlogon desktop, which takes over the whole display.
/// </summary>
/// <remarks>
/// While that desktop is up the agent's windows still exist and enumerate as before, but the display shows
/// none of them, <c>SendInput</c> reaches nothing, and a screen copy fails. The host has to be told, so it
/// can show the display itself and answer with input sent through the virtual hardware.
///
/// <c>OpenInputDesktop</c> opens the desktop that receives input
/// (<see href="https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-openinputdesktop"/>). A
/// process running as the user is refused access to the Winlogon desktop, so a refusal is read as the
/// secure desktop being up. Microsoft's documentation does not state that refusal; it is the long-standing
/// behaviour remote-control software relies on, and it is not yet checked on the live Windows 11 Arm guest.
/// </remarks>
public static class InputDesktop
{
    private const int ErrorAccessDenied = 5;
    private const string UserDesktopName = "Default";
    private const long CacheMilliseconds = 100;

    private static readonly object Gate = new();
    private static long checkedAt = long.MinValue;
    private static bool cached;

    /// <summary>
    /// True while the input desktop is not the user's. Read at most every 100 ms: the layout and every
    /// window's frame stream ask on each tick.
    /// </summary>
    public static bool IsSecure()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        var now = Environment.TickCount64;
        lock (Gate)
        {
            if (checkedAt != long.MinValue && now - checkedAt < CacheMilliseconds)
            {
                return cached;
            }

            cached = Probe();
            checkedAt = now;
            return cached;
        }
    }

    /// <summary>
    /// Reads the answer from what opening the input desktop returned.
    /// </summary>
    /// <param name="opened">Whether <c>OpenInputDesktop</c> returned a handle.</param>
    /// <param name="error">The Win32 error when it did not.</param>
    /// <param name="name">The opened desktop's name, or null when it could not be read.</param>
    public static bool IsSecure(bool opened, int error, string? name)
    {
        if (!opened)
        {
            // Any other failure says nothing about which desktop is up; reporting the secure desktop then
            // would freeze every mirrored window over a transient error.
            return error == ErrorAccessDenied;
        }

        // A desktop other than the user's that the agent can open, such as a screen saver's.
        return name is not null && !string.Equals(name, UserDesktopName, StringComparison.OrdinalIgnoreCase);
    }

    private static bool Probe()
    {
        var desktop = OpenInputDesktop(0, false, DESKTOP_READOBJECTS);
        if (desktop == 0)
        {
            return IsSecure(opened: false, Marshal.GetLastWin32Error(), name: null);
        }

        try
        {
            var buffer = new StringBuilder(256);
            var read = GetUserObjectInformation(desktop, UOI_NAME, buffer, buffer.Capacity * sizeof(char), out _);
            return IsSecure(opened: true, error: 0, read ? buffer.ToString() : null);
        }
        finally
        {
            _ = CloseDesktop(desktop);
        }
    }

    private const uint DESKTOP_READOBJECTS = 0x0001;
    private const int UOI_NAME = 2;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint OpenInputDesktop(uint flags, bool inherit, uint desiredAccess);

    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetUserObjectInformation(
        nint handle, int index, StringBuilder buffer, int byteLength, out int neededBytes);

    [DllImport("user32.dll")]
    private static extern bool CloseDesktop(nint desktop);
}
