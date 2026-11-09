using Veil.Agent;

namespace VeilAgent.Tests;

public class ScreenCopyCaptureTests
{
    private static readonly WindowRect Desktop = new(0, 0, 2048, 1280);

    [Fact]
    public void SamplesAcrossAWindowThatIsWhollyOnTheDesktop()
    {
        var points = GdiWindowFrameCapture.ScreenCopySamplePoints(new WindowRect(100, 50, 1278, 718), Desktop);

        Assert.NotNull(points);
        Assert.Equal(9, points!.Count);
        Assert.All(points, point =>
        {
            Assert.InRange(point.X, 112, 100 + 1278 - 13);
            Assert.InRange(point.Y, 62, 50 + 718 - 13);
        });
    }

    [Theory]
    [InlineData(-7, 0, 1278, 718)]
    [InlineData(900, 700, 1278, 718)]
    [InlineData(10, 10, 20, 20)]
    public void FallsBackToPrintWindowWhenAScreenCopyCouldMissPixels(int x, int y, int width, int height)
    {
        Assert.Null(GdiWindowFrameCapture.ScreenCopySamplePoints(new WindowRect(x, y, width, height), Desktop));
    }
}
