using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowFrameDifferTests
{
    private const int Width = 8;
    private const int Height = 6;

    private static byte[] MakeSurface(byte value = 0x10) =>
        Enumerable.Repeat(value, Width * Height * WindowFrameDiffer.BytesPerPixel).ToArray();

    private static void SetPixel(byte[] surface, int x, int y, byte value)
    {
        var offset = (y * Width + x) * WindowFrameDiffer.BytesPerPixel;
        for (var channel = 0; channel < WindowFrameDiffer.BytesPerPixel; channel++)
        {
            surface[offset + channel] = value;
        }
    }

    [Fact]
    public void ReportsNoChangeForIdenticalSurfaces()
    {
        Assert.Null(WindowFrameDiffer.ChangedRegion(MakeSurface(), MakeSurface(), Width, Height));
    }

    [Fact]
    public void FindsASinglePixelChange()
    {
        var previous = MakeSurface();
        var current = MakeSurface();
        SetPixel(current, 3, 2, 0xFF);

        var rect = WindowFrameDiffer.ChangedRegion(previous, current, Width, Height);

        Assert.NotNull(rect);
        Assert.Equal(new WindowFrameTileRect(3, 2, 1, 1), rect);
    }

    [Fact]
    public void BoundsMultipleDisjointChanges()
    {
        // One bounding box rather than a set of regions. For the dominant cases -- a caret, a glyph, a
        // hover highlight -- the bounding box is already small.
        var previous = MakeSurface();
        var current = MakeSurface();
        SetPixel(current, 1, 1, 0xFF);
        SetPixel(current, 5, 4, 0xFF);

        var rect = WindowFrameDiffer.ChangedRegion(previous, current, Width, Height);

        Assert.Equal(new WindowFrameTileRect(1, 1, 5, 4), rect);
    }

    [Fact]
    public void FindsChangesAtEveryEdge()
    {
        foreach (var (x, y) in new[] { (0, 0), (Width - 1, 0), (0, Height - 1), (Width - 1, Height - 1) })
        {
            var current = MakeSurface();
            SetPixel(current, x, y, 0xFF);

            var rect = WindowFrameDiffer.ChangedRegion(MakeSurface(), current, Width, Height);

            Assert.Equal(new WindowFrameTileRect(x, y, 1, 1), rect);
        }
    }

    [Fact]
    public void TreatsABufferLengthChangeAsAFullSurfaceChange()
    {
        // A resize means the previous buffer no longer describes the same surface, so nothing in it can be
        // trusted as a comparison baseline.
        var previous = new byte[Width * Height * WindowFrameDiffer.BytesPerPixel / 2];

        var rect = WindowFrameDiffer.ChangedRegion(previous, MakeSurface(), Width, Height);

        Assert.Equal(new WindowFrameTileRect(0, 0, Width, Height), rect);
    }

    [Fact]
    public void TreatsGeometryThatDisagreesWithTheBufferAsAFullSurfaceChange()
    {
        var rect = WindowFrameDiffer.ChangedRegion(MakeSurface(), MakeSurface(), Width, Height + 1);

        Assert.Equal(new WindowFrameTileRect(0, 0, Width, Height + 1), rect);
    }

    [Fact]
    public void ReportsNothingForAZeroSizedSurface()
    {
        Assert.Null(WindowFrameDiffer.ChangedRegion(MakeSurface(), MakeSurface(), 0, Height));
        Assert.Null(WindowFrameDiffer.ChangedRegion(MakeSurface(), MakeSurface(), Width, 0));
    }

    [Fact]
    public void PromotesLargeChangesToAKeyFrame()
    {
        // Past roughly two thirds coverage a tile stops being a saving, and a key frame also resynchronizes
        // a host that dropped an earlier tile.
        Assert.False(WindowFrameDiffer.ShouldPromoteToKeyFrame(new WindowFrameTileRect(0, 0, 1, 1), 100, 100));
        Assert.False(WindowFrameDiffer.ShouldPromoteToKeyFrame(new WindowFrameTileRect(0, 0, 50, 50), 100, 100));
        Assert.True(WindowFrameDiffer.ShouldPromoteToKeyFrame(new WindowFrameTileRect(0, 0, 90, 90), 100, 100));
        Assert.True(WindowFrameDiffer.ShouldPromoteToKeyFrame(new WindowFrameTileRect(0, 0, 100, 100), 100, 100));
    }

    [Fact]
    public void PromotesToAKeyFrameForADegenerateSurface()
    {
        Assert.True(WindowFrameDiffer.ShouldPromoteToKeyFrame(new WindowFrameTileRect(0, 0, 1, 1), 0, 0));
    }

    [Fact]
    public void DoesNotOverflowAreaComparisonOnALargeSurface()
    {
        // 32768x32768 exceeds Int32 when multiplied, so the comparison has to widen before multiplying.
        var full = new WindowFrameTileRect(0, 0, 32768, 32768);

        Assert.True(WindowFrameDiffer.ShouldPromoteToKeyFrame(full, 32768, 32768));
        Assert.False(WindowFrameDiffer.ShouldPromoteToKeyFrame(new WindowFrameTileRect(0, 0, 4, 4), 32768, 32768));
    }
}
