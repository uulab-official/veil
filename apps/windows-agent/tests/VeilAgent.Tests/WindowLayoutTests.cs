using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowLayoutTests
{
    private static readonly WindowRect Display = new(0, 0, 1920, 1080);

    [Fact]
    public void ReportsTrackedWindowsInZOrderWithVisibility()
    {
        var scan = new[]
        {
            new WindowLayoutEntry("hwnd:00000003", 300, new WindowRect(100, 100, 300, 200), true),
            new WindowLayoutEntry("hwnd:00000001", 100, new WindowRect(0, 0, 800, 600), true),
            new WindowLayoutEntry("hwnd:00000002", 200, new WindowRect(1000, 100, 600, 400), true),
        };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null, ["hwnd:00000002"] = null };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, "hwnd:00000001");

        Assert.Equal(new[] { "hwnd:00000001", "hwnd:00000002" }, layout.Windows.Select(window => window.WindowId));
        Assert.Equal(new[] { 0, 1 }, layout.Windows.Select(window => window.ZOrder));
        // Another process's window above covers part of the first one.
        Assert.False(layout.Windows[0].FullyVisible);
        Assert.True(layout.Windows[0].IsForeground);
        Assert.True(layout.Windows[1].FullyVisible);
    }

    [Fact]
    public void SameProcessPopupsAndHiddenWindowsDoNotOcclude()
    {
        var scan = new[]
        {
            new WindowLayoutEntry("hwnd:00000010", 100, new WindowRect(50, 50, 200, 300), true),
            new WindowLayoutEntry("hwnd:00000011", 900, new WindowRect(0, 0, 1920, 1080), false),
            new WindowLayoutEntry("hwnd:00000001", 100, new WindowRect(0, 0, 800, 600), true),
        };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null, ["hwnd:00000010"] = "hwnd:00000001" };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, null);

        Assert.All(layout.Windows, window => Assert.True(window.FullyVisible));
        Assert.Equal("hwnd:00000001", layout.Windows[0].OwnerWindowId);
    }

    [Fact]
    public void AWindowPastTheDisplayEdgeOrMinimizedIsNotFullyVisible()
    {
        var scan = new[]
        {
            new WindowLayoutEntry("hwnd:00000001", 100, new WindowRect(1800, 0, 300, 200), true),
            new WindowLayoutEntry("hwnd:00000002", 100, new WindowRect(0, 0, 300, 200), false),
        };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null, ["hwnd:00000002"] = null };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, null);

        Assert.All(layout.Windows, window => Assert.False(window.FullyVisible));
        Assert.False(layout.Windows[1].IsShown);
    }

    [Fact]
    public void StreamerSendsOnlyChangesAndAnEmptyLayoutWhenTrackingEnds()
    {
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };
        var frame = new WindowRect(0, 0, 800, 600);
        var streamer = new WindowLayoutStreamer(
            () => tracked,
            () => new WindowLayoutScan(new[] { new WindowLayoutEntry("hwnd:00000001", 1, frame, true) }, Display, null));

        var first = streamer.NextEvent();
        Assert.NotNull(first);
        Assert.Equal("window.layout", (string?)first!["type"]);
        Assert.Equal(1, (int?)first["sequence"]);
        Assert.Null(streamer.NextEvent());

        frame = new WindowRect(10, 0, 800, 600);
        var moved = streamer.NextEvent();
        Assert.Equal(10, (int?)moved!["windows"]![0]!["frame"]!["x"]);
        Assert.Equal(2, (int?)moved["sequence"]);

        Assert.Equal(2, (int?)streamer.CurrentEvent()!["sequence"]);

        tracked.Clear();
        var empty = streamer.NextEvent();
        Assert.Empty(empty!["windows"]!.AsArray());
        Assert.Null(streamer.NextEvent());
        Assert.Null(streamer.CurrentEvent());
    }
}
