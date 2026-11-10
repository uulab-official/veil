using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowGeometrySettlingTests
{
    [Fact]
    public void TheFirstCaptureUsesTheScreen()
    {
        var settling = new WindowGeometrySettling();

        Assert.False(settling.IsSettling("hwnd:1", new WindowRect(0, 0, 800, 600), 10_000));
    }

    [Fact]
    public void AResizeSettlesBeforeScreenCopiesResume()
    {
        var settling = new WindowGeometrySettling();
        settling.IsSettling("hwnd:1", new WindowRect(0, 0, 800, 600), 10_000);

        Assert.True(settling.IsSettling("hwnd:1", new WindowRect(0, 0, 900, 600), 10_100));
        Assert.True(settling.IsSettling("hwnd:1", new WindowRect(0, 0, 900, 600), 10_399));
        Assert.False(settling.IsSettling("hwnd:1", new WindowRect(0, 0, 900, 600), 10_400));
    }

    [Fact]
    public void AMoveCountsAsAChangeAndForgettingStartsOver()
    {
        var settling = new WindowGeometrySettling();
        settling.IsSettling("hwnd:1", new WindowRect(0, 0, 800, 600), 10_000);

        Assert.True(settling.IsSettling("hwnd:1", new WindowRect(40, 0, 800, 600), 20_000));

        settling.Forget("hwnd:1");
        Assert.False(settling.IsSettling("hwnd:1", new WindowRect(80, 0, 800, 600), 20_010));
    }
}
