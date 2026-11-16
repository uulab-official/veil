using System.ComponentModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// Win32 clipboard access for images and file drops. Text stays in <see cref="WindowsDesktop"/>.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class WindowsClipboardFormats
{
    private const uint CF_DIB = 8;
    private const uint CF_HDROP = 15;
    private const uint GMEM_MOVEABLE = 0x0002;
    private const uint DROPEFFECT_COPY = 1;
    private const int DropFilesHeaderSize = 20;
    // CF_DIB is uncompressed, so a bitmap at the pixel bound is up to 128 MB plus its headers. Anything larger
    // is refused before it is copied out of the clipboard.
    private const long MaxDibBytes = ClipboardImageMessage.MaxPixels * 4 + 4096;

    public static uint SequenceNumber() => GetClipboardSequenceNumber();

    /// <summary>
    /// Reads the registered <c>PNG</c> format, or converts <c>CF_DIB</c> (which Windows synthesizes from
    /// <c>CF_DIBV5</c> and <c>CF_BITMAP</c>). Conversion happens after <c>CloseClipboard</c>, so a slow GDI+
    /// encode never holds the clipboard every other app is waiting for.
    /// </summary>
    public static byte[]? ReadImagePng()
    {
        var pngFormat = RegisterClipboardFormat("PNG");
        byte[]? png = null;
        byte[]? dib = null;

        OpenWithRetry();
        try
        {
            if (pngFormat != 0 && IsClipboardFormatAvailable(pngFormat))
            {
                png = ReadGlobal(GetClipboardData(pngFormat), ClipboardImageMessage.MaxPngBytes + 4096);
            }

            if (png is null && IsClipboardFormatAvailable(CF_DIB))
            {
                dib = ReadGlobal(GetClipboardData(CF_DIB), MaxDibBytes);
            }
        }
        finally
        {
            CloseClipboard();
        }

        if (png is not null)
        {
            // GlobalSize reports the allocation, which can be rounded up past the PNG's own end. Trimming keeps
            // the hash equal to what the writer placed, which is what echo suppression compares.
            return ClipboardImageMessage.TrimToPngEnd(png);
        }

        return dib is null ? null : ClipboardBitmapConverter.DibToPng(dib);
    }

    public static void WriteImage(byte[] png)
    {
        // Decoded before opening the clipboard, for the same reason ReadImagePng converts after closing it.
        var dib = ClipboardBitmapConverter.PngToDib(png);
        var pngFormat = RegisterClipboardFormat("PNG");
        if (pngFormat == 0)
        {
            throw Win32Failure("RegisterClipboardFormat failed for PNG.");
        }

        OpenWithRetry();
        try
        {
            if (!EmptyClipboard())
            {
                throw Win32Failure("EmptyClipboard failed.");
            }

            SetBytes(pngFormat, png);
            SetBytes(CF_DIB, dib);
        }
        finally
        {
            CloseClipboard();
        }
    }

    /// <summary>
    /// Writes a <c>DROPFILES</c> block with wide paths and a copy drop effect, which is what Explorer itself
    /// places for Copy. Without the drop effect some targets treat the paste as a move out of the share.
    /// </summary>
    public static void WriteFileDrop(IReadOnlyList<string> fullPaths)
    {
        var drop = BuildDropFiles(fullPaths);
        var dropEffectFormat = RegisterClipboardFormat("Preferred DropEffect");

        OpenWithRetry();
        try
        {
            if (!EmptyClipboard())
            {
                throw Win32Failure("EmptyClipboard failed.");
            }

            SetBytes(CF_HDROP, drop);
            if (dropEffectFormat != 0)
            {
                SetBytes(dropEffectFormat, BitConverter.GetBytes(DROPEFFECT_COPY));
            }
        }
        finally
        {
            CloseClipboard();
        }
    }

    /// <summary>Checked without <c>OpenClipboard</c>, so polling it every tick contends with no one.</summary>
    public static bool IsFileDropAvailable() => IsClipboardFormatAvailable(CF_HDROP);

    /// <summary>
    /// Reads <c>CF_HDROP</c> as a list of full paths. The block is copied out and the clipboard closed before
    /// it is parsed, like the image reader.
    /// </summary>
    public static IReadOnlyList<string>? ReadFileDrop()
    {
        byte[]? drop = null;
        OpenWithRetry();
        try
        {
            if (IsClipboardFormatAvailable(CF_HDROP))
            {
                drop = ReadGlobal(GetClipboardData(CF_HDROP), ClipboardFileExport.MaxDropFilesBytes);
            }
        }
        finally
        {
            CloseClipboard();
        }

        return drop is null ? null : ClipboardFileExport.ParseDropFiles(drop);
    }

    /// <summary>DROPFILES: pFiles, POINT pt, BOOL fNC, BOOL fWide, then double-null-terminated UTF-16 paths.</summary>
    internal static byte[] BuildDropFiles(IReadOnlyList<string> fullPaths)
    {
        var names = new StringBuilder();
        foreach (var path in fullPaths)
        {
            names.Append(path).Append('\0');
        }

        names.Append('\0');
        var nameBytes = Encoding.Unicode.GetBytes(names.ToString());
        var drop = new byte[DropFilesHeaderSize + nameBytes.Length];
        BitConverter.TryWriteBytes(drop.AsSpan(0, 4), (uint)DropFilesHeaderSize);
        BitConverter.TryWriteBytes(drop.AsSpan(16, 4), 1);
        Buffer.BlockCopy(nameBytes, 0, drop, DropFilesHeaderSize, nameBytes.Length);
        return drop;
    }

    private static byte[]? ReadGlobal(IntPtr handle, long maxBytes)
    {
        if (handle == IntPtr.Zero)
        {
            return null;
        }

        var size = (long)(ulong)GlobalSize(handle);
        if (size <= 0 || size > maxBytes)
        {
            return null;
        }

        var pointer = GlobalLock(handle);
        if (pointer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var bytes = new byte[size];
            Marshal.Copy(pointer, bytes, 0, (int)size);
            return bytes;
        }
        finally
        {
            _ = GlobalUnlock(handle);
        }
    }

    /// <summary>Must be called with the clipboard open. On success the clipboard owns the memory.</summary>
    private static void SetBytes(uint format, byte[] bytes)
    {
        var handle = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
        if (handle == IntPtr.Zero)
        {
            throw Win32Failure("GlobalAlloc failed for clipboard data.");
        }

        try
        {
            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                throw Win32Failure("GlobalLock failed for clipboard data.");
            }

            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }

            if (SetClipboardData(format, handle) == IntPtr.Zero)
            {
                throw Win32Failure("SetClipboardData failed.");
            }

            handle = IntPtr.Zero;
        }
        finally
        {
            if (handle != IntPtr.Zero)
            {
                _ = GlobalFree(handle);
            }
        }
    }

    private static void OpenWithRetry()
    {
        for (var attempt = 0; attempt < 10; attempt += 1)
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                return;
            }

            Thread.Sleep(25);
        }

        throw Win32Failure("OpenClipboard failed.");
    }

    private static Win32Exception Win32Failure(string message) => new(Marshal.GetLastWin32Error(), message);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsClipboardFormatAvailable(uint format);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint RegisterClipboardFormat(string lpszFormat);

    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern UIntPtr GlobalSize(IntPtr hMem);
}

/// <summary>GDI+ conversions between PNG and the device-independent bitmaps legacy Win32 apps paste.</summary>
[SupportedOSPlatform("windows")]
internal static class ClipboardBitmapConverter
{
    private const int FileHeaderSize = 14;
    private const uint BI_BITFIELDS = 3;
    private const uint BI_ALPHABITFIELDS = 6;

    /// <summary>
    /// Wraps a packed DIB in a BITMAPFILEHEADER so GDI+ can decode it, then encodes PNG. Dimensions are
    /// checked against the protocol bounds from the header before GDI+ allocates anything.
    /// </summary>
    public static byte[]? DibToPng(byte[] dib)
    {
        if (dib.Length < 40)
        {
            return null;
        }

        var headerSize = BitConverter.ToInt32(dib, 0);
        var width = BitConverter.ToInt32(dib, 4);
        var rawHeight = BitConverter.ToInt32(dib, 8);
        var bitCount = BitConverter.ToUInt16(dib, 14);
        var compression = BitConverter.ToUInt32(dib, 16);
        var colorsUsed = BitConverter.ToUInt32(dib, 32);
        if (headerSize < 40 || headerSize > dib.Length || rawHeight == int.MinValue)
        {
            return null;
        }

        // A negative height is a top-down bitmap, not an invalid one.
        var height = Math.Abs(rawHeight);
        if (!ClipboardImageMessage.DimensionsAllowed(width, height))
        {
            return null;
        }

        var maskBytes = headerSize == 40 && compression == BI_BITFIELDS ? 12
            : headerSize == 40 && compression == BI_ALPHABITFIELDS ? 16
            : 0;
        var paletteEntries = colorsUsed != 0 ? colorsUsed : bitCount <= 8 ? 1u << bitCount : 0u;
        if (paletteEntries > 256)
        {
            return null;
        }

        var file = new byte[FileHeaderSize + dib.Length];
        file[0] = (byte)'B';
        file[1] = (byte)'M';
        BitConverter.TryWriteBytes(file.AsSpan(2, 4), file.Length);
        BitConverter.TryWriteBytes(file.AsSpan(10, 4), FileHeaderSize + headerSize + maskBytes + (int)paletteEntries * 4);
        Buffer.BlockCopy(dib, 0, file, FileHeaderSize, dib.Length);

        try
        {
            using var input = new MemoryStream(file);
            using var bitmap = new Bitmap(input);
            using var output = new MemoryStream();
            bitmap.Save(output, ImageFormat.Png);
            return output.ToArray();
        }
        catch (ArgumentException)
        {
            // GDI+ reports a malformed bitmap as "Parameter is not valid".
            return null;
        }
    }

    public static byte[] PngToDib(byte[] png)
    {
        using var input = new MemoryStream(png);
        using var bitmap = new Bitmap(input);
        using var output = new MemoryStream();
        bitmap.Save(output, ImageFormat.Bmp);
        return output.ToArray()[FileHeaderSize..];
    }
}
