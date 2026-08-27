using System.Buffers.Binary;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// Binary wire format for window frames.
/// </summary>
/// <remarks>
/// Frames used to travel as base64 inside a JSON object on the shared control connection. That cost 33%
/// inflation before a byte left the guest, forced the host to parse a multi-hundred-kilobyte JSON
/// document per frame to reach the image, and put large frames in front of input messages on the same
/// TCP stream.
///
/// Layout, network byte order throughout:
/// <code>
/// offset  size  field
/// 0       4     magic "VFR1"
/// 4       1     payload format (1 = png)
/// 5       2     window id byte count (uint16)
/// 7       n     window id, UTF-8
/// 7+n     4     sequence (uint32)
/// 11+n    4     surface width in pixels (uint32)
/// 15+n    4     surface height in pixels (uint32)
/// 19+n    4     DPI scale in thousandths (uint32, 1000 = 100%)
/// 23+n    4     payload byte count (uint32)
/// 27+n    m     payload
/// </code>
///
/// The DPI scale is an integer thousandth rather than a float so the format carries no floating point
/// representation or endianness ambiguity. <c>FrameId</c> is deliberately absent: the host derives it
/// from the sequence, so sending it would be redundant bytes on the hot path.
///
/// Must stay byte-for-byte identical to <c>VeilFrameChannelCodec</c> on the macOS host.
/// </remarks>
public static class FrameChannelCodec
{
    public static readonly byte[] Magic = Encoding.ASCII.GetBytes("VFR2");
    public const byte PngFormat = 1;
    public const byte KeyFrameFlag = 0x01;
    public const int HeaderByteCountWithoutWindowId = 36;
    public const int MaximumWindowIdByteCount = 512;
    public const int MaximumSurfaceDimension = 32768;

    /// <summary>
    /// Encodes a frame for the binary channel.
    /// </summary>
    /// <remarks>
    /// The frame's <c>EncodedData</c> is base64 because that is what the JSON path needs. Decoding it
    /// here and sending raw bytes is what removes the 33% inflation; the guest pays one base64 decode
    /// instead of the host paying a JSON parse over an inflated string.
    /// </remarks>
    public static byte[] Encode(WindowFrameTile tile)
    {
        var payload = Convert.FromBase64String(tile.EncodedData);
        if (payload.Length == 0)
        {
            throw new InvalidOperationException("Frame channel messages must carry an image payload.");
        }

        if (tile.SurfaceWidth <= 0
            || tile.SurfaceHeight <= 0
            || tile.SurfaceWidth > MaximumSurfaceDimension
            || tile.SurfaceHeight > MaximumSurfaceDimension)
        {
            throw new InvalidOperationException(
                $"Frame channel surface size {tile.SurfaceWidth}x{tile.SurfaceHeight} is out of range."
            );
        }

        var rect = tile.Rect;
        if (rect.Width <= 0
            || rect.Height <= 0
            || rect.X < 0
            || rect.Y < 0
            || rect.X + rect.Width > tile.SurfaceWidth
            || rect.Y + rect.Height > tile.SurfaceHeight)
        {
            throw new InvalidOperationException(
                $"Frame tile {rect.Width}x{rect.Height} at {rect.X},{rect.Y} does not fit a {tile.SurfaceWidth}x{tile.SurfaceHeight} surface."
            );
        }

        // The host has nothing to composite onto until a key frame arrives, so a partial key frame would
        // leave undefined pixels with no way to detect it.
        if (tile.IsKeyFrame && !rect.Covers(tile.SurfaceWidth, tile.SurfaceHeight))
        {
            throw new InvalidOperationException("A key frame must cover the whole surface.");
        }

        var windowIdBytes = Encoding.UTF8.GetBytes(tile.WindowId);
        if (windowIdBytes.Length == 0)
        {
            throw new InvalidOperationException("Frame channel messages require a window id.");
        }

        if (windowIdBytes.Length > MaximumWindowIdByteCount)
        {
            throw new InvalidOperationException(
                $"Frame channel window id is {windowIdBytes.Length} bytes, above the allowed maximum."
            );
        }

        var message = new byte[HeaderByteCountWithoutWindowId + windowIdBytes.Length + payload.Length];
        var span = message.AsSpan();

        Magic.CopyTo(span);
        span[4] = PngFormat;
        span[5] = tile.IsKeyFrame ? KeyFrameFlag : (byte)0;
        BinaryPrimitives.WriteUInt16BigEndian(span[6..8], (ushort)windowIdBytes.Length);
        windowIdBytes.CopyTo(span[8..]);

        var cursor = 8 + windowIdBytes.Length;
        BinaryPrimitives.WriteUInt32BigEndian(span[cursor..], (uint)Math.Max(0, tile.Sequence));
        cursor += 4;
        BinaryPrimitives.WriteUInt32BigEndian(span[cursor..], (uint)tile.SurfaceWidth);
        cursor += 4;
        BinaryPrimitives.WriteUInt32BigEndian(span[cursor..], (uint)tile.SurfaceHeight);
        cursor += 4;
        BinaryPrimitives.WriteUInt32BigEndian(span[cursor..], (uint)Math.Max(0, (int)Math.Round(tile.Scale * 1000)));
        cursor += 4;
        BinaryPrimitives.WriteUInt16BigEndian(span[cursor..], (ushort)rect.X);
        cursor += 2;
        BinaryPrimitives.WriteUInt16BigEndian(span[cursor..], (ushort)rect.Y);
        cursor += 2;
        BinaryPrimitives.WriteUInt16BigEndian(span[cursor..], (ushort)rect.Width);
        cursor += 2;
        BinaryPrimitives.WriteUInt16BigEndian(span[cursor..], (ushort)rect.Height);
        cursor += 2;
        BinaryPrimitives.WriteUInt32BigEndian(span[cursor..], (uint)payload.Length);
        cursor += 4;
        payload.CopyTo(span[cursor..]);

        return message;
    }
}
