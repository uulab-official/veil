using Veil.Agent;

namespace VeilAgent.Tests;

public class GdiWindowFrameCaptureTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CancelledCaptureCannotReplaceTheActiveStreamsComparisonBuffer(bool hasReplacementFrame)
    {
        var capture = new GdiWindowFrameCapture();
        const string windowId = "hwnd:00000010";
        var currentPixels = new byte[16];
        var retiredPixels = Enumerable.Repeat((byte)255, 16).ToArray();
        capture.TakeChangedRegion(windowId, retiredPixels, 2, 2);
        capture.ForgetWindow(windowId);
        if (hasReplacementFrame) capture.TakeChangedRegion(windowId, currentPixels, 2, 2);
        using var retired = new CancellationTokenSource();
        retired.Cancel();

        Assert.ThrowsAny<OperationCanceledException>(() =>
            capture.TakeChangedRegion(windowId, retiredPixels, 2, 2, retired.Token));

        var nextRegion = capture.TakeChangedRegion(windowId, currentPixels, 2, 2);
        if (hasReplacementFrame)
        {
            Assert.Null(nextRegion);
        }
        else
        {
            Assert.NotNull(nextRegion);
            Assert.True(nextRegion!.Covers(2, 2));
        }
    }

    [Fact]
    public void ReturnsOneOnNonWindowsPlatforms()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        Assert.Equal(1.0, GdiWindowFrameCapture.GetWindowScale(0));
    }

    [Fact]
    public void ReturnsOneForAnInvalidWindowHandle()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        // GetDpiForWindow returns 0 for a handle that doesn't identify a real window --
        // GetWindowScale must fall back to 1.0 (unscaled) rather than propagating a bogus
        // division result like 0 or NaN.
        Assert.Equal(1.0, GdiWindowFrameCapture.GetWindowScale(0));
    }
}
