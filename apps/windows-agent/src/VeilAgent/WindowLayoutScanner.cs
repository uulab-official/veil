using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>What one pass over the guest's top-level windows saw.</summary>
public sealed record WindowLayoutScan(
    IReadOnlyList<WindowLayoutEntry> ZOrdered,
    WindowRect Display,
    string? ForegroundWindowId
);

/// <summary>
/// Reads every top-level window in z-order with <c>EnumWindows</c>, which enumerates from the top:
/// <see href="https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-enumwindows"/>.
/// </summary>
public static class WindowLayoutScanner
{
    public static WindowLayoutScan? Scan()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        var entries = new List<WindowLayoutEntry>();
        EnumWindows((hwnd, _) =>
        {
            var geometry = WindowGeometry.Read(hwnd);
            if (geometry is null)
            {
                return true;
            }

            GetWindowThreadProcessId(hwnd, out var processId);
            var shown = IsWindowVisible(hwnd) && !IsIconic(hwnd) && !IsCloaked(hwnd);
            var frame = geometry.Value.Visible;
            entries.Add(new WindowLayoutEntry(
                FormatWindowId(hwnd),
                (int)processId,
                frame,
                shown,
                // Only read for windows that draw at all.
                !shown || WindowLayoutComposer.CoversPixels(frame, LayeredOpacity(hwnd))));
            return true;
        }, 0);

        var display = new WindowRect(
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_CXVIRTUALSCREEN),
            GetSystemMetrics(SM_CYVIRTUALSCREEN));
        var foreground = GetForegroundWindow();
        return new WindowLayoutScan(entries, display, foreground == 0 ? null : FormatWindowId(foreground));
    }

    internal static string FormatWindowId(nint hwnd) => $"hwnd:{((long)hwnd):X8}";

    /// <summary>
    /// Cloaked windows, such as suspended UWP apps and windows on another virtual desktop, are visible to
    /// <c>IsWindowVisible</c> but DWM does not draw them.
    /// </summary>
    private static bool IsCloaked(nint hwnd) =>
        DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out var cloaked, sizeof(int)) == 0 && cloaked != 0;

    /// <summary>
    /// The opacity a layered window set for itself with <c>SetLayeredWindowAttributes</c>, or null: not
    /// layered, or drawn with <c>UpdateLayeredWindow</c>, whose opacity is per pixel and cannot be read.
    /// <see href="https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getlayeredwindowattributes"/>
    /// </summary>
    private static byte? LayeredOpacity(nint hwnd)
    {
        if ((GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64() & WS_EX_LAYERED) == 0
            || !GetLayeredWindowAttributes(hwnd, out _, out var alpha, out var flags)
            || (flags & LWA_ALPHA) == 0)
        {
            return null;
        }

        return alpha;
    }

    private delegate bool EnumWindowsProc(nint hwnd, nint lParam);

    private const int GWL_EXSTYLE = -20;
    private const long WS_EX_LAYERED = 0x00080000;
    private const uint LWA_ALPHA = 0x00000002;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint hwnd, int index);

    [DllImport("user32.dll")]
    private static extern bool GetLayeredWindowAttributes(nint hwnd, out uint colorKey, out byte alpha, out uint flags);

    private const int DWMWA_CLOAKED = 14;
    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(nint hwnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(nint hwnd);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(nint hwnd, int attribute, out int value, int size);
}
