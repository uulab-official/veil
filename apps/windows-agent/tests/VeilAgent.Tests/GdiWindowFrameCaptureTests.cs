using Veil.Agent;

namespace VeilAgent.Tests;

public class GdiWindowFrameCaptureTests
{
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
