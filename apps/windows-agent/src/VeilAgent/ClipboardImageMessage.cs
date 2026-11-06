using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Builds and verifies <c>clipboard.image.set</c>. See docs/protocol.md "Clipboard Image".
/// </summary>
/// <remarks>
/// Pure byte handling with no Win32 calls, so the bounds are testable on any OS. The host chooses the
/// bytes, so nothing about an incoming image is trusted until its signature, declared length, IHDR
/// dimensions, and SHA-256 all agree; only then does it reach GDI+ and the Windows clipboard.
/// </remarks>
public static class ClipboardImageMessage
{
    public const int MaxPngBytes = 8 * 1024 * 1024;
    public const int MaxDimension = 16_384;
    public const long MaxPixels = 33_554_432;

    private static readonly byte[] PngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    public sealed record Parsed(byte[] Png, string Sha256);

    public sealed record Rejection(string Code, string Message);

    public static bool DimensionsAllowed(int width, int height) =>
        width >= 1 && width <= MaxDimension
        && height >= 1 && height <= MaxDimension
        && (long)width * height <= MaxPixels;

    /// <summary>Reads width and height from the IHDR chunk, which PNG requires to come first.</summary>
    public static bool TryReadDimensions(byte[] png, out int width, out int height)
    {
        width = 0;
        height = 0;
        if (png.Length < 24
            || !png.AsSpan(0, 8).SequenceEqual(PngSignature)
            || png[12] != (byte)'I' || png[13] != (byte)'H' || png[14] != (byte)'D' || png[15] != (byte)'R')
        {
            return false;
        }

        var rawWidth = ReadBigEndian(png, 16);
        var rawHeight = ReadBigEndian(png, 20);
        if (rawWidth > int.MaxValue || rawHeight > int.MaxValue)
        {
            return false;
        }

        width = (int)rawWidth;
        height = (int)rawHeight;
        return true;
    }

    /// <summary>
    /// Cuts the bytes after the IEND chunk. Returns the input unchanged when no complete IEND is found, so a
    /// malformed image still fails the later checks instead of being silently repaired here.
    /// </summary>
    public static byte[] TrimToPngEnd(byte[] png)
    {
        var offset = PngSignature.Length;
        while (offset + 12 <= png.Length)
        {
            var length = ReadBigEndian(png, offset);
            var end = offset + 12L + length;
            if (end > png.Length)
            {
                break;
            }

            if (png[offset + 4] == (byte)'I' && png[offset + 5] == (byte)'E'
                && png[offset + 6] == (byte)'N' && png[offset + 7] == (byte)'D')
            {
                return end == png.Length ? png : png[..(int)end];
            }

            offset = (int)end;
        }

        return png;
    }

    public static string Sha256Hex(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    /// <summary>
    /// The guest broadcast for one clipboard image, or null when the image is outside the protocol bounds.
    /// An oversized image is skipped rather than truncated or re-encoded: a different picture on the Mac
    /// would be worse than none.
    /// </summary>
    public static JsonObject? GuestEvent(int sequence, byte[] png, string sha256)
    {
        if (png.Length > MaxPngBytes
            || !TryReadDimensions(png, out var width, out var height)
            || !DimensionsAllowed(width, height))
        {
            return null;
        }

        return new JsonObject
        {
            ["type"] = MessageTypes.ClipboardImageSet,
            ["requestId"] = $"evt_clipboard_{sequence}",
            ["origin"] = "guest",
            ["sequence"] = sequence,
            ["format"] = "png",
            ["width"] = width,
            ["height"] = height,
            ["byteLength"] = png.Length,
            ["sha256"] = sha256,
            ["pngBase64"] = Convert.ToBase64String(png)
        };
    }

    /// <summary>Verifies a host image. Returns the PNG bytes, or why they were refused.</summary>
    public static (Parsed? Image, Rejection? Rejection) Parse(JsonObject request)
    {
        string? format, sha256, pngBase64;
        int width, height, byteLength;
        try
        {
            format = request["format"]?.GetValue<string>();
            sha256 = request["sha256"]?.GetValue<string>();
            pngBase64 = request["pngBase64"]?.GetValue<string>();
            width = request["width"]?.GetValue<int>() ?? 0;
            height = request["height"]?.GetValue<int>() ?? 0;
            byteLength = request["byteLength"]?.GetValue<int>() ?? 0;
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException)
        {
            return (null, Invalid("clipboard.image.set fields have the wrong types."));
        }

        if (format != "png" || sha256 is null || pngBase64 is null || !IsLowercaseSha256(sha256))
        {
            return (null, Invalid("clipboard.image.set requires format png, a lowercase sha256, and pngBase64."));
        }

        // Bounds come before decoding so an oversized declaration never allocates its claimed size.
        if (byteLength < 1 || byteLength > MaxPngBytes || pngBase64.Length > (MaxPngBytes + 2) / 3 * 4)
        {
            return (null, new Rejection("clipboard_image_too_large", $"Clipboard images are limited to {MaxPngBytes} bytes."));
        }

        if (!DimensionsAllowed(width, height))
        {
            return (null, new Rejection("clipboard_image_too_large", "The clipboard image dimensions exceed the protocol bounds."));
        }

        byte[] png;
        try
        {
            png = Convert.FromBase64String(pngBase64);
        }
        catch (FormatException)
        {
            return (null, Invalid("pngBase64 was not valid base64."));
        }

        if (png.Length != byteLength)
        {
            return (null, Invalid("byteLength does not match the decoded image."));
        }

        if (!TryReadDimensions(png, out var headerWidth, out var headerHeight))
        {
            return (null, Invalid("The clipboard image is not a PNG."));
        }

        if (headerWidth != width || headerHeight != height)
        {
            return (null, Invalid("The clipboard image dimensions do not match its PNG header."));
        }

        var actualSha256 = Sha256Hex(png);
        if (actualSha256 != sha256)
        {
            return (null, Invalid("The clipboard image does not match its sha256."));
        }

        return (new Parsed(png, actualSha256), null);
    }

    private static Rejection Invalid(string message) => new("invalid_message", message);

    private static bool IsLowercaseSha256(string value) =>
        value.Length == 64 && value.All(character => character is (>= '0' and <= '9') or (>= 'a' and <= 'f'));

    private static uint ReadBigEndian(byte[] bytes, int offset) =>
        ((uint)bytes[offset] << 24) | ((uint)bytes[offset + 1] << 16) | ((uint)bytes[offset + 2] << 8) | bytes[offset + 3];
}

/// <summary>
/// Resolves <c>clipboard.files.set</c> entries. See docs/protocol.md "Clipboard Files".
/// </summary>
/// <remarks>
/// String rules in Windows path syntax rather than <c>Path.GetFullPath</c>, so the checks behave the same
/// when the unit tests run off Windows. The host names files relative to the share; the guest decides the
/// root, so no host-supplied path can point outside <c>C:\VeilShared\Veil Clipboard\</c>.
/// </remarks>
public static class ClipboardFilePaths
{
    public const string DirectoryName = "Veil Clipboard";
    public const int MaxFileCount = 64;
    public const int MaxRelativePathLength = 240;

    private static readonly char[] ForbiddenCharacters = ['<', '>', ':', '"', '/', '|', '?', '*'];

    private static readonly HashSet<string> ReservedDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    public static bool TryResolve(string? relativePath, string guestDirectoryPath, out string fullPath)
    {
        fullPath = string.Empty;
        if (string.IsNullOrEmpty(relativePath) || relativePath.Length > MaxRelativePathLength)
        {
            return false;
        }

        var components = relativePath.Split('\\');
        if (components.Length < 2 || components[0] != DirectoryName)
        {
            return false;
        }

        foreach (var component in components)
        {
            if (!IsSafeComponent(component))
            {
                return false;
            }
        }

        fullPath = guestDirectoryPath.TrimEnd('\\') + "\\" + relativePath;
        return true;
    }

    private static bool IsSafeComponent(string component)
    {
        if (component.Length == 0
            || component == "."
            || component == ".."
            || component.EndsWith('.')
            || component.EndsWith(' ')
            || component.IndexOfAny(ForbiddenCharacters) >= 0
            || component.Any(char.IsControl))
        {
            return false;
        }

        var stem = component.Split('.')[0];
        return !ReservedDeviceNames.Contains(stem);
    }
}
