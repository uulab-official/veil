using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Veil.Agent;

public sealed class GdiWindowFrameCapture : IWindowFrameCapture
{
    public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken)
    {
        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();

            var bounds = GetCaptureBounds(window);
            using var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
            using var graphics = Graphics.FromImage(bitmap);

            var deviceContext = graphics.GetHdc();
            try
            {
                var printed = PrintWindow(window.Hwnd, deviceContext, PrintWindowFlags.PW_RENDERFULLCONTENT);
                if (!printed)
                {
                    graphics.ReleaseHdc(deviceContext);
                    deviceContext = nint.Zero;
                    graphics.CopyFromScreen(bounds.X, bounds.Y, 0, 0, new Size(bounds.Width, bounds.Height));
                }
            }
            finally
            {
                if (deviceContext != nint.Zero)
                {
                    graphics.ReleaseHdc(deviceContext);
                }
            }

            using var stream = new MemoryStream();
            bitmap.Save(stream, ImageFormat.Png);

            return new WindowFrame(
                WindowId: window.WindowId,
                FrameId: $"frame_{sequence:000000}",
                Sequence: sequence,
                Format: "png",
                Width: bounds.Width,
                Height: bounds.Height,
                Scale: GetWindowScale(window.Hwnd),
                EncodedData: Convert.ToBase64String(stream.ToArray())
            );
        }, cancellationToken);
    }

    private static WindowRect GetCaptureBounds(LaunchedWindow window)
    {
        if (GetWindowRect(window.Hwnd, out var rect))
        {
            var width = Math.Max(1, rect.Right - rect.Left);
            var height = Math.Max(1, rect.Bottom - rect.Top);
            return new WindowRect(rect.Left, rect.Top, width, height);
        }

        return window.Bounds;
    }

    /// <summary>
    /// The window's real DPI scale (1.0 = 100%, 2.0 = 200%, etc). Requires the process to be
    /// Per-Monitor-V2 DPI aware (see <see cref="ProcessDpiAwareness"/>) -- an unaware process always
    /// gets 96 back here regardless of the window's real scale, so this degrades to reporting 1.0
    /// rather than crashing if that declaration didn't take effect (e.g. on a Windows build older
    /// than the version 1703 minimum documented on
    /// <see href="https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setprocessdpiawarenesscontext"/>).
    /// The value is exposed on <see cref="WindowFrame.Scale"/> for future consumers; the current host
    /// rendering path (<c>WindowsAppFrameSurface.swift</c>) already benefits from the sharper source
    /// bitmap this produces without needing to read it, since it stretches the captured PNG's pixel
    /// content to fill the mirror window regardless of any declared point size.
    /// </summary>
    internal static double GetWindowScale(nint hwnd)
    {
        if (!OperatingSystem.IsWindows())
        {
            return 1.0;
        }

        try
        {
            var dpi = GetDpiForWindow(hwnd);
            return dpi > 0 ? dpi / 96.0 : 1.0;
        }
        catch (EntryPointNotFoundException)
        {
            return 1.0;
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(nint hWnd, out NativeRect rect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PrintWindow(nint hwnd, nint hdcBlt, PrintWindowFlags flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetDpiForWindow(nint hwnd);

    [Flags]
    private enum PrintWindowFlags : uint
    {
        PW_CLIENTONLY = 0x00000001,
        PW_RENDERFULLCONTENT = 0x00000002
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
