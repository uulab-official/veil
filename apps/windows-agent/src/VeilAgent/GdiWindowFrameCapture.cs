using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Veil.Agent;

public sealed class GdiWindowFrameCapture : IWindowFrameCapture
{
    /// <summary>
    /// Previous captured pixel buffer per window, used to decide whether anything actually changed.
    /// </summary>
    /// <remarks>
    /// Exact byte comparison rather than a hash: a hash collision would silently drop a real frame, and
    /// the vectorized span comparison is cheap next to the PNG encode it avoids. The memory cost is one
    /// extra full-window buffer per streamed window, released by ForgetWindow when the stream stops.
    /// </remarks>
    private readonly Dictionary<string, byte[]> previousPixelsByWindowId = new();
    private readonly object pixelGate = new();

    public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken)
    {
        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            return CaptureUnconditionally(window, sequence);
        }, cancellationToken);
    }

    /// <summary>
    /// Captures, and encodes only the region that changed since the previous capture.
    /// </summary>
    /// <param name="includeFullFrame">
    /// Whether to also produce a self-contained full-surface frame for legacy JSON subscribers. Skipped
    /// when nothing is listening on that path, so the normal case pays for one tile encode only.
    /// </param>
    public Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
        LaunchedWindow window,
        int sequence,
        bool includeFullFrame,
        CancellationToken cancellationToken
    )
    {
        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();

            var bounds = GetCaptureBounds(window);
            using var bitmap = CaptureBitmap(window, bounds);
            var pixels = CopyPixels(bitmap);
            var changed = TakeChangedRegion(window.WindowId, pixels, bounds.Width, bounds.Height);

            if (changed is null)
            {
                // The expensive work -- PNG encode plus base64 -- is skipped entirely here. This is the
                // common case for a window the user is not currently interacting with.
                return WindowFrameCaptureResult.Unchanged(sequence);
            }

            var scale = GetWindowScale(window.Hwnd);
            var isKeyFrame = changed.Covers(bounds.Width, bounds.Height);
            var fullFrame = includeFullFrame || isKeyFrame
                ? EncodeFrame(window, bounds, sequence, bitmap)
                : null;

            // A key frame's payload is the whole surface, so reuse the full-frame encode instead of
            // encoding the same pixels twice.
            var tilePayload = isKeyFrame
                ? fullFrame!.EncodedData
                : EncodeRegion(bitmap, changed);

            var tile = new WindowFrameTile(
                WindowId: window.WindowId,
                Sequence: sequence,
                SurfaceWidth: bounds.Width,
                SurfaceHeight: bounds.Height,
                Scale: scale,
                IsKeyFrame: isKeyFrame,
                Rect: changed,
                EncodedData: tilePayload
            );

            return WindowFrameCaptureResult.Changed(includeFullFrame ? fullFrame : null, tile);
        }, cancellationToken);
    }

    public Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
        LaunchedWindow window,
        int sequence,
        CancellationToken cancellationToken
    ) => CaptureFrameResultAsync(window, sequence, includeFullFrame: true, cancellationToken);

    /// <summary>
    /// Returns the changed region and retains the new buffer, or <c>null</c> when nothing changed.
    /// </summary>
    /// <remarks>
    /// Forces a full-surface region on the first capture of a stream and after a resize: the host has
    /// nothing to composite onto in the first case, and a stale buffer of a different size in the second.
    /// </remarks>
    private WindowFrameTileRect? TakeChangedRegion(string windowId, byte[] pixels, int width, int height)
    {
        lock (pixelGate)
        {
            if (!previousPixelsByWindowId.TryGetValue(windowId, out var previous))
            {
                previousPixelsByWindowId[windowId] = pixels;
                return new WindowFrameTileRect(0, 0, width, height);
            }

            var changed = WindowFrameDiffer.ChangedRegion(previous, pixels, width, height);
            if (changed is null)
            {
                return null;
            }

            previousPixelsByWindowId[windowId] = pixels;
            return WindowFrameDiffer.ShouldPromoteToKeyFrame(changed, width, height)
                ? new WindowFrameTileRect(0, 0, width, height)
                : changed;
        }
    }

    /// <summary>
    /// Drops the retained comparison buffer for a window.
    /// </summary>
    /// <remarks>
    /// Called when a stream stops so a closed window's full-size buffer is not retained for the rest of
    /// the agent process's lifetime, and so a restarted stream begins with a guaranteed full frame
    /// instead of comparing against pixels from a previous session.
    /// </remarks>
    public void ForgetWindow(string windowId)
    {
        lock (pixelGate)
        {
            previousPixelsByWindowId.Remove(windowId);
        }
    }

    /// <summary>
    /// Encodes just the changed rectangle as its own PNG.
    /// </summary>
    private static string EncodeRegion(Bitmap bitmap, WindowFrameTileRect rect)
    {
        var cropRectangle = new Rectangle(rect.X, rect.Y, rect.Width, rect.Height);
        using var region = bitmap.Clone(cropRectangle, PixelFormat.Format32bppArgb);
        using var stream = new MemoryStream();
        region.Save(stream, ImageFormat.Png);
        return Convert.ToBase64String(stream.ToArray());
    }

    private static WindowFrame CaptureUnconditionally(LaunchedWindow window, int sequence)
    {
        var bounds = GetCaptureBounds(window);
        using var bitmap = CaptureBitmap(window, bounds);
        return EncodeFrame(window, bounds, sequence, bitmap);
    }

    private static Bitmap CaptureBitmap(LaunchedWindow window, WindowRect bounds)
    {
        var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
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

        return bitmap;
    }

    /// <summary>
    /// Copies the bitmap's raw pixels into a contiguous array for comparison.
    /// </summary>
    /// <remarks>
    /// Copies row by row because the locked stride can exceed <c>width * 4</c>, and comparing padding
    /// bytes would report spurious changes.
    /// </remarks>
    private static byte[] CopyPixels(Bitmap bitmap)
    {
        var rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var rowBytes = bitmap.Width * 4;
            var pixels = new byte[rowBytes * bitmap.Height];
            for (var row = 0; row < bitmap.Height; row++)
            {
                Marshal.Copy(
                    data.Scan0 + row * data.Stride,
                    pixels,
                    row * rowBytes,
                    rowBytes
                );
            }

            return pixels;
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    private static WindowFrame EncodeFrame(
        LaunchedWindow window,
        WindowRect bounds,
        int sequence,
        Bitmap bitmap
    )
    {
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
