namespace Veil.Agent;

/// <summary>
/// Finds the bounding rectangle of pixels that changed between two captures of the same window.
/// </summary>
/// <remarks>
/// Pure logic over two pixel buffers, with no bitmap or GDI dependency, so the row and column scanning is
/// unit testable without a Windows desktop.
///
/// A bounding rectangle rather than a set of tiles: one rectangle keeps the wire format and the host
/// compositor simple, and for the dominant cases -- a blinking caret, a typed glyph, a hovered button --
/// the bounding box is already small. Multiple disjoint regions would only pay off for changes spread
/// across a window, which is also when a key frame is cheaper anyway.
/// </remarks>
public static class WindowFrameDiffer
{
    public const int BytesPerPixel = 4;

    /// <summary>
    /// Fraction of the surface above which a key frame is cheaper than a tile.
    /// </summary>
    /// <remarks>
    /// A tile costs a header plus a PNG whose compression has less context to work with than the whole
    /// frame. Past roughly two thirds coverage the tile stops being a saving, and sending a key frame also
    /// resynchronizes a host that dropped an earlier tile.
    /// </remarks>
    public const double KeyFrameCoverageThreshold = 0.66;

    /// <summary>
    /// Computes the changed region, or <c>null</c> when the buffers are identical.
    /// </summary>
    /// <remarks>
    /// Returns a full-surface rectangle when the buffers have different lengths, since a resize means the
    /// previous buffer no longer describes the same surface.
    /// </remarks>
    public static WindowFrameTileRect? ChangedRegion(
        ReadOnlySpan<byte> previous,
        ReadOnlySpan<byte> current,
        int width,
        int height
    )
    {
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        var rowBytes = width * BytesPerPixel;
        if (current.Length != rowBytes * height)
        {
            // The caller's declared geometry disagrees with the buffer it handed over. Treating that as a
            // full-surface change is the only safe answer.
            return new WindowFrameTileRect(0, 0, width, height);
        }

        if (previous.Length != current.Length)
        {
            return new WindowFrameTileRect(0, 0, width, height);
        }

        var top = -1;
        var bottom = -1;
        for (var row = 0; row < height; row++)
        {
            var offset = row * rowBytes;
            if (previous.Slice(offset, rowBytes).SequenceEqual(current.Slice(offset, rowBytes)))
            {
                continue;
            }

            if (top < 0)
            {
                top = row;
            }

            bottom = row;
        }

        if (top < 0)
        {
            return null;
        }

        // Columns are scanned only across the rows already known to differ, so a small change never costs a
        // full-surface column sweep.
        var left = width;
        var right = -1;
        for (var row = top; row <= bottom; row++)
        {
            var rowOffset = row * rowBytes;
            for (var column = 0; column < left; column++)
            {
                var pixelOffset = rowOffset + column * BytesPerPixel;
                if (!previous.Slice(pixelOffset, BytesPerPixel).SequenceEqual(current.Slice(pixelOffset, BytesPerPixel)))
                {
                    left = column;
                    break;
                }
            }

            for (var column = width - 1; column > right; column--)
            {
                var pixelOffset = rowOffset + column * BytesPerPixel;
                if (!previous.Slice(pixelOffset, BytesPerPixel).SequenceEqual(current.Slice(pixelOffset, BytesPerPixel)))
                {
                    right = column;
                    break;
                }
            }
        }

        if (left > right)
        {
            // Rows differed but no individual pixel did, which cannot happen for equal-length buffers.
            // Falling back to the full surface keeps a logic error from producing an invalid rectangle.
            return new WindowFrameTileRect(0, 0, width, height);
        }

        return new WindowFrameTileRect(left, top, right - left + 1, bottom - top + 1);
    }

    /// <summary>
    /// Whether a changed region covers enough of the surface that a key frame is the better choice.
    /// </summary>
    public static bool ShouldPromoteToKeyFrame(WindowFrameTileRect rect, int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            return true;
        }

        var surfaceArea = (long)width * height;
        var rectArea = (long)rect.Width * rect.Height;
        return rectArea >= surfaceArea * KeyFrameCoverageThreshold;
    }
}
