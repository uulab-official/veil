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
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> tileFormatsByWindowId = new();

    public void SetTileFormat(string windowId, byte format) => tileFormatsByWindowId[windowId] = format;
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

            var diagnostics = FrameCaptureDiagnostics.Shared;
            var total = System.Diagnostics.Stopwatch.StartNew();
            var step = System.Diagnostics.Stopwatch.StartNew();
            var geometry = GetCaptureGeometry(window);
            var bounds = geometry.Visible;
            var strategy = diagnostics.Strategy;
            var tileFormat = tileFormatsByWindowId.GetValueOrDefault(window.WindowId, FrameChannelCodec.PngFormat);
            var deflatesTile = tileFormat == FrameChannelCodec.BgraDeflateFormat;
            var bitmap = ReusableBitmap(window.WindowId, geometry.Outer);
            byte[] pixels;
            switch (TryDuplicate(window, geometry, strategy))
            {
                case (DesktopDuplicationCapture.CopyResult.Unchanged, _):
                    // DWM presented nothing since this window's last frame, so its pixels cannot differ.
                    diagnostics.Record("capture", step.Elapsed.TotalMilliseconds);
                    diagnostics.Record("unchangedTotal", total.Elapsed.TotalMilliseconds);
                    return WindowFrameCaptureResult.Unchanged(sequence);
                case (DesktopDuplicationCapture.CopyResult.Copied, { } duplicated):
                    pixels = duplicated;
                    diagnostics.Record("capture", step.Elapsed.TotalMilliseconds);
                    if (!deflatesTile || includeFullFrame)
                    {
                        // The PNG paths encode from the bitmap.
                        WritePixels(bitmap, VisibleRectangle(geometry), pixels);
                    }
                    step.Restart();
                    break;
                default:
                    CaptureInto(bitmap, window, geometry, strategy);
                    diagnostics.Record("capture", step.Elapsed.TotalMilliseconds);
                    step.Restart();
                    pixels = CopyPixels(bitmap, VisibleRectangle(geometry));
                    diagnostics.Record("copy", step.Elapsed.TotalMilliseconds);
                    step.Restart();
                    break;
            }

            var changed = TakeChangedRegion(window.WindowId, pixels, bounds.Width, bounds.Height, cancellationToken);
            diagnostics.Record("diff", step.Elapsed.TotalMilliseconds);

            if (changed is null)
            {
                diagnostics.Record("unchangedTotal", total.Elapsed.TotalMilliseconds);
                // The expensive work -- PNG encode plus base64 -- is skipped entirely here. This is the
                // common case for a window the user is not currently interacting with.
                return WindowFrameCaptureResult.Unchanged(sequence);
            }

            step.Restart();
            var scale = GetWindowScale(window.Hwnd);
            var isKeyFrame = changed.Covers(bounds.Width, bounds.Height);
            var fullFrame = includeFullFrame || (isKeyFrame && !deflatesTile)
                ? EncodeFrame(window, bounds, sequence, bitmap, VisibleRectangle(geometry))
                : null;

            // A PNG key frame's payload is the whole surface, so reuse the full-frame encode instead of
            // encoding the same pixels twice. Deflated tiles come straight from the compared pixel buffer.
            var tilePayload = deflatesTile
                ? EncodeRegionBgraDeflate(pixels, bounds.Width, changed)
                : isKeyFrame
                    ? fullFrame!.EncodedData
                    : EncodeRegion(bitmap, changed, geometry.InsetX, geometry.InsetY);

            var tile = new WindowFrameTile(
                WindowId: window.WindowId,
                Sequence: sequence,
                SurfaceWidth: bounds.Width,
                SurfaceHeight: bounds.Height,
                Scale: scale,
                IsKeyFrame: isKeyFrame,
                Rect: changed,
                EncodedData: tilePayload,
                PayloadFormat: deflatesTile ? FrameChannelCodec.BgraDeflateFormat : FrameChannelCodec.PngFormat
            );
            diagnostics.Record("encode", step.Elapsed.TotalMilliseconds);
            diagnostics.Record("changedTotal", total.Elapsed.TotalMilliseconds);

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
    internal WindowFrameTileRect? TakeChangedRegion(
        string windowId, byte[] pixels, int width, int height, CancellationToken cancellationToken = default)
    {
        lock (pixelGate)
        {
            // PrintWindow itself cannot be interrupted. A retired capture may finish after its
            // stream has been replaced, but must never repopulate that stream's comparison buffer.
            // Check while holding the same lock as ForgetWindow so cancellation and reset cannot
            // be followed by a stale write that suppresses the replacement's first key frame.
            cancellationToken.ThrowIfCancellationRequested();
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

        duplicationVersionsByWindowId.TryRemove(windowId, out _);
        lock (bitmapsByWindowId)
        {
            if (bitmapsByWindowId.Remove(windowId, out var bitmap))
            {
                bitmap.Dispose();
            }
        }
    }

    /// <summary>
    /// Encodes the changed rectangle as BGRA rows compressed with raw deflate at its fastest level; see
    /// <see cref="FrameChannelCodec.BgraDeflateFormat"/>. Reads the pixel buffer already copied for change
    /// detection, so the bitmap is neither cropped nor re-encoded.
    /// </summary>
    internal static string EncodeRegionBgraDeflate(byte[] pixels, int surfaceWidth, WindowFrameTileRect rect)
    {
        using var output = new MemoryStream();
        using (var deflate = new System.IO.Compression.DeflateStream(
            output, System.IO.Compression.CompressionLevel.Fastest, leaveOpen: true))
        {
            var rowBytes = rect.Width * 4;
            for (var row = 0; row < rect.Height; row++)
            {
                deflate.Write(pixels, ((rect.Y + row) * surfaceWidth + rect.X) * 4, rowBytes);
            }
        }
        return Convert.ToBase64String(output.GetBuffer(), 0, (int)output.Length);
    }

    /// <summary>
    /// Encodes just the changed rectangle as its own PNG.
    /// </summary>
    private static string EncodeRegion(Bitmap bitmap, WindowFrameTileRect rect, int offsetX, int offsetY)
    {
        var cropRectangle = new Rectangle(rect.X + offsetX, rect.Y + offsetY, rect.Width, rect.Height);
        using var region = bitmap.Clone(cropRectangle, PixelFormat.Format32bppArgb);
        using var stream = new MemoryStream();
        region.Save(stream, ImageFormat.Png);
        return Convert.ToBase64String(stream.ToArray());
    }

    private static WindowFrame CaptureUnconditionally(LaunchedWindow window, int sequence)
    {
        var geometry = GetCaptureGeometry(window);
        using var bitmap = new Bitmap(geometry.Outer.Width, geometry.Outer.Height, PixelFormat.Format32bppArgb);
        CaptureInto(bitmap, window, geometry, FrameCaptureDiagnostics.AutomaticStrategy, recordsMethod: false);
        return EncodeFrame(window, geometry.Visible, sequence, bitmap, VisibleRectangle(geometry));
    }

    private readonly Dictionary<string, Bitmap> bitmapsByWindowId = new();
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, (WindowRect Region, long Version)>
        duplicationVersionsByWindowId = new();

    /// <summary>
    /// Reads a fully visible window's pixels from Desktop Duplication, or returns
    /// <see cref="DesktopDuplicationCapture.CopyResult.Unavailable"/> for the GDI paths to handle.
    /// </summary>
    private (DesktopDuplicationCapture.CopyResult Result, byte[]? Pixels) TryDuplicate(
        LaunchedWindow window, WindowGeometry geometry, string strategy)
    {
        var allowed = strategy switch
        {
            FrameCaptureDiagnostics.DuplicationStrategy => true,
            FrameCaptureDiagnostics.AutomaticStrategy => IsFullyVisibleOnScreen(window.Hwnd, geometry.Visible),
            _ => false
        };
        if (!allowed)
        {
            return (DesktopDuplicationCapture.CopyResult.Unavailable, null);
        }

        var visible = geometry.Visible;
        // A window that moved or changed size needs its pixels copied again even from an unchanged desktop.
        var knownVersion = duplicationVersionsByWindowId.TryGetValue(window.WindowId, out var known)
            && known.Region == visible
                ? known.Version
                : -1;
        var allocationTimer = System.Diagnostics.Stopwatch.StartNew();
        var pixels = new byte[visible.Width * visible.Height * 4];
        FrameCaptureDiagnostics.Shared.Record("duplicationAllocate", allocationTimer.Elapsed.TotalMilliseconds);
        DesktopDuplicationCapture.CopyResult result;
        try
        {
            result = DesktopDuplicationCapture.Shared.TryCopy(visible, pixels, ref knownVersion);
        }
        catch (Exception error)
        {
            FrameCaptureDiagnostics.Shared.RecordDuplicationFailure($"{error.GetType().Name}: {error.Message}");
            result = DesktopDuplicationCapture.CopyResult.Unavailable;
        }
        if (result == DesktopDuplicationCapture.CopyResult.Unavailable)
        {
            duplicationVersionsByWindowId.TryRemove(window.WindowId, out _);
            return (result, null);
        }

        duplicationVersionsByWindowId[window.WindowId] = (visible, knownVersion);
        FrameCaptureDiagnostics.Shared.RecordMethod(FrameCaptureDiagnostics.DuplicationStrategy);
        return result == DesktopDuplicationCapture.CopyResult.Copied ? (result, pixels) : (result, null);
    }

    private static void WritePixels(Bitmap bitmap, Rectangle rectangle, byte[] pixels)
    {
        var data = bitmap.LockBits(rectangle, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        try
        {
            var rowBytes = rectangle.Width * 4;
            for (var row = 0; row < rectangle.Height; row++)
            {
                Marshal.Copy(pixels, row * rowBytes, data.Scan0 + row * data.Stride, rowBytes);
            }
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }

    /// <summary>
    /// One capture bitmap per window, replaced only when the window changes size. Allocating a fresh
    /// full-window bitmap every tick cost an allocation and a GDI+ object per frame for nothing.
    /// </summary>
    private Bitmap ReusableBitmap(string windowId, WindowRect bounds)
    {
        lock (bitmapsByWindowId)
        {
            if (bitmapsByWindowId.TryGetValue(windowId, out var existing)
                && existing.Width == bounds.Width
                && existing.Height == bounds.Height)
            {
                return existing;
            }

            existing?.Dispose();
            var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
            bitmapsByWindowId[windowId] = bitmap;
            return bitmap;
        }
    }

    /// <summary>
    /// Fills a bitmap the size of the window's outer rectangle. Only the visible frame inside it is used
    /// afterwards; see <see cref="WindowGeometry"/>.
    /// </summary>
    private static void CaptureInto(
        Bitmap bitmap,
        LaunchedWindow window,
        WindowGeometry geometry,
        string strategy,
        bool recordsMethod = true)
    {
        var visible = geometry.Visible;
        using var graphics = Graphics.FromImage(bitmap);

        // PrintWindow makes the app render a fresh copy of itself, which took 50 to 150 ms a frame in the
        // guest and held mirrored drawing to about ten frames a second. A window that is fully on screen and
        // on top is already composed there, so copying those pixels gives the same image in a few
        // milliseconds. The window being used is almost always that one, since input brings it forward.
        var copiesScreen = strategy switch
        {
            FrameCaptureDiagnostics.ScreenCopyStrategy => true,
            FrameCaptureDiagnostics.PrintWindowStrategy => false,
            _ => IsFullyVisibleOnScreen(window.Hwnd, visible)
        };
        if (copiesScreen)
        {
            // Only the visible frame: the invisible borders around it show the windows behind.
            graphics.CopyFromScreen(
                visible.X, visible.Y, geometry.InsetX, geometry.InsetY, new Size(visible.Width, visible.Height));
            if (recordsMethod)
            {
                FrameCaptureDiagnostics.Shared.RecordMethod(FrameCaptureDiagnostics.ScreenCopyStrategy);
            }
            return;
        }

        if (recordsMethod)
        {
            FrameCaptureDiagnostics.Shared.RecordMethod(FrameCaptureDiagnostics.PrintWindowStrategy);
        }
        PrintInto(graphics, window, geometry.Outer);
    }

    private static Rectangle VisibleRectangle(WindowGeometry geometry) =>
        new(geometry.InsetX, geometry.InsetY, geometry.Visible.Width, geometry.Visible.Height);

    private static void PrintInto(Graphics graphics, LaunchedWindow window, WindowRect bounds)
    {
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
    }

    /// <summary>
    /// Copies the bitmap's raw pixels into a contiguous array for comparison.
    /// </summary>
    /// <remarks>
    /// Copies row by row because the locked stride can exceed <c>width * 4</c>, and comparing padding
    /// bytes would report spurious changes.
    /// </remarks>
    private static byte[] CopyPixels(Bitmap bitmap, Rectangle rectangle)
    {
        var data = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var rowBytes = rectangle.Width * 4;
            var pixels = new byte[rowBytes * rectangle.Height];
            for (var row = 0; row < rectangle.Height; row++)
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
        Bitmap bitmap,
        Rectangle visible
    )
    {
        using var stream = new MemoryStream();
        if (visible == new Rectangle(0, 0, bitmap.Width, bitmap.Height))
        {
            bitmap.Save(stream, ImageFormat.Png);
        }
        else
        {
            using var cropped = bitmap.Clone(visible, PixelFormat.Format32bppArgb);
            cropped.Save(stream, ImageFormat.Png);
        }

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

    private static WindowGeometry GetCaptureGeometry(LaunchedWindow window) =>
        WindowGeometry.Read(window.Hwnd) ?? new WindowGeometry(window.Bounds, window.Bounds);

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

    /// <summary>
    /// Whether the screen shows exactly this window across its whole rectangle: inside the virtual desktop,
    /// and on top at every sample point. Popups and other windows over it send capture back to PrintWindow,
    /// which draws the window alone.
    /// </summary>
    private static bool IsFullyVisibleOnScreen(nint hwnd, WindowRect bounds)
    {
        if (!IsWindowVisible(hwnd) || IsIconic(hwnd))
        {
            return false;
        }

        var desktop = new WindowRect(
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_CXVIRTUALSCREEN),
            GetSystemMetrics(SM_CYVIRTUALSCREEN)
        );
        return ScreenCopySamplePoints(bounds, desktop) is { } points
            && points.All(point => GetAncestor(WindowFromPoint(point), GA_ROOT) == hwnd);
    }

    /// <summary>
    /// Points to test for occlusion, or null when the window reaches outside the desktop and a screen copy
    /// would miss part of it. Inset from the edges, where Windows 11 keeps invisible resize borders that
    /// belong to whatever is behind.
    /// </summary>
    internal static IReadOnlyList<NativePoint>? ScreenCopySamplePoints(WindowRect window, WindowRect desktop)
    {
        if (window.Width <= 32
            || window.Height <= 32
            || window.X < desktop.X
            || window.Y < desktop.Y
            || window.X + window.Width > desktop.X + desktop.Width
            || window.Y + window.Height > desktop.Y + desktop.Height)
        {
            return null;
        }

        const int inset = 12;
        var xs = new[] { window.X + inset, window.X + window.Width / 2, window.X + window.Width - 1 - inset };
        var ys = new[] { window.Y + inset, window.Y + window.Height / 2, window.Y + window.Height - 1 - inset };
        return xs.SelectMany(x => ys.Select(y => new NativePoint(x, y))).ToArray();
    }

    [StructLayout(LayoutKind.Sequential)]
    internal readonly record struct NativePoint(int X, int Y);

    private const uint GA_ROOT = 2;
    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;

    [DllImport("user32.dll")]
    private static extern nint WindowFromPoint(NativePoint point);

    [DllImport("user32.dll")]
    private static extern nint GetAncestor(nint hwnd, uint flags);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(nint hwnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(nint hwnd);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

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
}
