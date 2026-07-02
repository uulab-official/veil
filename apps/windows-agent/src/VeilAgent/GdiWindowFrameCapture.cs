using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Veil.Agent;

public sealed class GdiWindowFrameCapture : IWindowFrameCapture
{
    public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken)
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

        return Task.FromResult(new WindowFrame(
            WindowId: window.WindowId,
            FrameId: $"frame_{sequence:000000}",
            Sequence: sequence,
            Format: "png",
            Width: bounds.Width,
            Height: bounds.Height,
            Scale: 1,
            EncodedData: Convert.ToBase64String(stream.ToArray())
        ));
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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(nint hWnd, out NativeRect rect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PrintWindow(nint hwnd, nint hdcBlt, PrintWindowFlags flags);

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
