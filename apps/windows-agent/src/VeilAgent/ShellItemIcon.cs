using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Reads an icon the way Start and File Explorer draw it, at a size the Mac can show in the Dock.
/// </summary>
/// <remarks>
/// <see cref="Icon.ExtractAssociatedIcon"/> returns the 32 px icon of an executable. For packaged inbox apps
/// such as Paint that executable is an app execution alias stub, so the result is a small generic window
/// instead of the app's own logo. The shell resolves both cases: a <c>shell:AppsFolder\{AUMID}</c> item gives a
/// packaged app's logo and an executable path gives its largest embedded icon.
/// See https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishellitemimagefactory.
/// </remarks>
internal static class ShellItemIcon
{
    public const int DefaultSize = 256;

    private const int SIIGBF_BIGGERSIZEOK = 0x1;
    private const int SIIGBF_ICONONLY = 0x4;

    public static string AppsFolderPath(string appUserModelId) => $@"shell:AppsFolder\{appUserModelId}";

    /// <summary>Returns PNG bytes with the icon's alpha intact, or null when the shell has no image for it.</summary>
    public static byte[]? TryGetPng(string parsingName, int size = DefaultSize)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        IntPtr hbitmap = IntPtr.Zero;
        try
        {
            var factoryId = typeof(IShellItemImageFactory).GUID;
            if (SHCreateItemFromParsingName(parsingName, IntPtr.Zero, ref factoryId, out var factory) != 0
                || factory is null)
            {
                return null;
            }

            try
            {
                var requested = new NativeSize { Width = size, Height = size };
                if (factory.GetImage(requested, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, out hbitmap) != 0
                    || hbitmap == IntPtr.Zero)
                {
                    return null;
                }
            }
            finally
            {
                Marshal.ReleaseComObject(factory);
            }

            return EncodePng(hbitmap);
        }
        catch (Exception error) when (error is COMException or ExternalException or ArgumentException)
        {
            Console.Error.WriteLine(
                $"ShellItemIcon: no shell image for {parsingName}. {error.GetType().Name}: {error.Message}"
            );
            return null;
        }
        finally
        {
            if (hbitmap != IntPtr.Zero)
            {
                DeleteObject(hbitmap);
            }
        }
    }

    /// <summary>
    /// <see cref="Image.FromHbitmap(IntPtr)"/> drops the alpha channel, which would put a black square behind
    /// every icon. The shell returns a 32 bpp premultiplied DIB section, so its bits are read directly.
    /// </summary>
    private static byte[]? EncodePng(IntPtr hbitmap)
    {
        var section = new DibSection();
        if (GetObject(hbitmap, Marshal.SizeOf<DibSection>(), ref section) == 0
            || section.Bitmap.BitsPixel != 32
            || section.Bitmap.Bits == IntPtr.Zero)
        {
            return null;
        }

        var width = section.Bitmap.Width;
        var height = section.Bitmap.Height;
        var stride = section.Bitmap.WidthBytes;
        using var premultiplied = new Bitmap(width, height, stride, PixelFormat.Format32bppPArgb, section.Bitmap.Bits);
        using var image = premultiplied.Clone(new Rectangle(0, 0, width, height), PixelFormat.Format32bppArgb);
        // A positive header height means a bottom-up DIB.
        if (section.Header.Height > 0)
        {
            image.RotateFlip(RotateFlipType.RotateNoneFlipY);
        }

        using var stream = new MemoryStream();
        image.Save(stream, ImageFormat.Png);
        return stream.ToArray();
    }

    [ComImport]
    [Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(NativeSize size, int flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeSize
    {
        public int Width;
        public int Height;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeBitmap
    {
        public int Type;
        public int Width;
        public int Height;
        public int WidthBytes;
        public ushort Planes;
        public ushort BitsPixel;
        public IntPtr Bits;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ClrUsed;
        public uint ClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DibSection
    {
        public NativeBitmap Bitmap;
        public BitmapInfoHeader Header;
        public uint BitFields0;
        public uint BitFields1;
        public uint BitFields2;
        public IntPtr Section;
        public uint Offset;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHCreateItemFromParsingName(
        string path,
        IntPtr bindContext,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory? item
    );

    [DllImport("gdi32.dll")]
    private static extern int GetObject(IntPtr handle, int size, ref DibSection section);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr handle);
}
