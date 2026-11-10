using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// A top-level window's outer rectangle and the part of it that is actually drawn, in physical pixels.
/// </summary>
/// <remarks>
/// On Windows 10 and 11 <c>GetWindowRect</c> includes invisible resize borders, about 7 px at 100% on the
/// left, right, and bottom, which show whatever is behind the window. Mirroring that rectangle put slivers
/// of other windows along a mirrored window's edges. Capture, input, resize, and reported bounds all use
/// the visible frame instead, from <c>DWMWA_EXTENDED_FRAME_BOUNDS</c>:
/// <see href="https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute"/>.
/// </remarks>
internal readonly record struct WindowGeometry(WindowRect Outer, WindowRect Visible)
{
    /// <summary>Where the visible frame starts inside the outer rectangle.</summary>
    public int InsetX => Visible.X - Outer.X;
    public int InsetY => Visible.Y - Outer.Y;

    /// <summary>How much larger the outer rectangle is than the visible frame.</summary>
    public int ExtraWidth => Outer.Width - Visible.Width;
    public int ExtraHeight => Outer.Height - Visible.Height;

    public static WindowGeometry? Read(nint hwnd)
    {
        if (!GetWindowRect(hwnd, out var outer))
        {
            return null;
        }

        var outerRect = ToWindowRect(outer);
        if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out var frame, Marshal.SizeOf<NativeRect>()) != 0)
        {
            return new WindowGeometry(outerRect, outerRect);
        }

        return FromRects(outerRect, ToWindowRect(frame));
    }

    /// <summary>
    /// Keeps the visible frame inside the outer rectangle; a frame DWM reports outside it (or empty) is
    /// ignored and the outer rectangle used as is.
    /// </summary>
    internal static WindowGeometry FromRects(WindowRect outer, WindowRect frame)
    {
        var left = Math.Max(outer.X, frame.X);
        var top = Math.Max(outer.Y, frame.Y);
        var right = Math.Min(outer.X + outer.Width, frame.X + frame.Width);
        var bottom = Math.Min(outer.Y + outer.Height, frame.Y + frame.Height);
        if (right - left <= 0 || bottom - top <= 0)
        {
            return new WindowGeometry(outer, outer);
        }

        return new WindowGeometry(outer, new WindowRect(left, top, right - left, bottom - top));
    }

    private static WindowRect ToWindowRect(NativeRect rect) =>
        new(rect.Left, rect.Top, Math.Max(1, rect.Right - rect.Left), Math.Max(1, rect.Bottom - rect.Top));

    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(nint hWnd, out NativeRect rect);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(nint hwnd, int attribute, out NativeRect value, int size);
}
