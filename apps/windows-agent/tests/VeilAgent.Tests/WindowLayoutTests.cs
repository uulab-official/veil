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
    public void WindowsThatDrawNothingDoNotOcclude()
    {
        var scan = new[]
        {
            // A one-pixel helper window and a transparent overlay, both of other processes and both above.
            new WindowLayoutEntry("hwnd:00000020", 700, new WindowRect(400, 300, 1, 1), true, CoversPixels: false),
            new WindowLayoutEntry("hwnd:00000021", 800, new WindowRect(0, 0, 1920, 1080), true, CoversPixels: false),
            new WindowLayoutEntry("hwnd:00000001", 100, new WindowRect(0, 0, 800, 600), true),
        };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, "hwnd:00000001");

        Assert.True(layout.Windows.Single().FullyVisible);
    }

    [Theory]
    [InlineData(300, 200, null, true)]
    // SetLayeredWindowAttributes with partial opacity still draws.
    [InlineData(300, 200, 128, true)]
    [InlineData(300, 200, 0, false)]
    [InlineData(1, 1, null, false)]
    [InlineData(1, 200, null, false)]
    [InlineData(300, 1, null, false)]
    public void TellsWhetherAShownWindowCanHideAnother(int width, int height, int? opacity, bool expected)
    {
        var frame = new WindowRect(10, 10, width, height);

        Assert.Equal(expected, WindowLayoutComposer.CoversPixels(frame, (byte?)opacity));
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

    [Fact]
    public void NoWindowIsFullyVisibleWhileTheSecureDesktopIsUp()
    {
        var scan = new[] { new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(0, 0, 800, 600), true) };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, "hwnd:00000001", secureDesktop: true);

        Assert.True(layout.SecureDesktop);
        Assert.True(layout.Windows[0].IsShown);
        Assert.False(layout.Windows[0].FullyVisible);
        Assert.True((bool?)layout.ToEvent(1)["secureDesktop"]);
        Assert.False((bool?)WindowLayoutComposer.Compose(scan, tracked, Display, null).ToEvent(1)["secureDesktop"]);
    }

    [Fact]
    public void StreamerReportsTheSecureDesktopComingAndGoing()
    {
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };
        var secure = false;
        var streamer = new WindowLayoutStreamer(
            () => tracked,
            () => new WindowLayoutScan(
                new[] { new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(0, 0, 800, 600), true) }, Display, null),
            inputDesktopIsSecure: () => secure);

        Assert.False((bool?)streamer.NextEvent()!["secureDesktop"]);

        secure = true;
        var raised = streamer.NextEvent();
        Assert.True((bool?)raised!["secureDesktop"]);
        Assert.False((bool?)raised["windows"]![0]!["fullyVisible"]);
        Assert.Null(streamer.NextEvent());
        // A host that connects during the prompt starts from it.
        Assert.True((bool?)streamer.CurrentEvent()!["secureDesktop"]);

        secure = false;
        var lowered = streamer.NextEvent();
        Assert.False((bool?)lowered!["secureDesktop"]);
        Assert.True((bool?)lowered["windows"]![0]!["fullyVisible"]);
    }

    [Fact]
    public void StreamerReportsTheSecureDesktopWithNoWindowTracked()
    {
        var tracked = new Dictionary<string, string?>();
        var secure = false;
        var streamer = new WindowLayoutStreamer(
            () => tracked,
            () => new WindowLayoutScan(Array.Empty<WindowLayoutEntry>(), Display, null),
            inputDesktopIsSecure: () => secure);

        Assert.Null(streamer.NextEvent());

        secure = true;
        var raised = streamer.NextEvent();
        Assert.True((bool?)raised!["secureDesktop"]);
        Assert.Empty(raised["windows"]!.AsArray());
        Assert.Equal(Display.Width, (int?)raised["display"]!["width"]);
        Assert.Null(streamer.NextEvent());

        secure = false;
        var lowered = streamer.NextEvent();
        Assert.False((bool?)lowered!["secureDesktop"]);
        Assert.Null(streamer.NextEvent());
    }

    [Theory]
    // Refused: the Winlogon desktop of a prompt or the lock screen.
    [InlineData(false, 5, null, true)]
    // Any other failure says nothing.
    [InlineData(false, 6, null, false)]
    [InlineData(false, 0, null, false)]
    [InlineData(true, 0, "Default", false)]
    [InlineData(true, 0, "default", false)]
    [InlineData(true, 0, "Screen-saver", true)]
    // Opened but unnamed: not enough to freeze every window.
    [InlineData(true, 0, null, false)]
    public void ReadsTheSecureDesktopFromOpeningTheInputDesktop(bool opened, int error, string? name, bool expected)
    {
        Assert.Equal(expected, InputDesktop.IsSecure(opened, error, name));
    }

    [Fact]
    public void ACoveredWindowReportsThePartsTheDisplayStillShows()
    {
        var scan = new[]
        {
            // In front, over the lower right quarter of the window behind.
            new WindowLayoutEntry("hwnd:00000002", 2, new WindowRect(500, 400, 600, 500), true),
            new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(100, 100, 800, 600), true)
        };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null, ["hwnd:00000002"] = null };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, "hwnd:00000002");

        Assert.True(layout.Windows[0].FullyVisible);
        Assert.Null(layout.Windows[0].VisibleRegion);
        var behind = layout.Windows[1];
        Assert.False(behind.FullyVisible);
        // The window in front and the 64 pixels around it its shadow reaches are left out.
        Assert.Equal(
            new[] { new WindowRect(100, 100, 800, 236), new WindowRect(100, 336, 336, 364) },
            behind.VisibleRegion);
        Assert.Equal(800 * 600 - 464 * 364, behind.VisibleRegion!.Sum(rect => rect.Width * rect.Height));

        var json = layout.ToEvent(1)["windows"]!.AsArray();
        Assert.False(json[0]!.AsObject().ContainsKey("visibleRegion"));
        Assert.Equal(2, json[1]!["visibleRegion"]!.AsArray().Count);
        Assert.Equal(236, (int?)json[1]!["visibleRegion"]![0]!["height"]);
    }

    [Fact]
    public void AWindowPartlyOffTheDisplayReportsWhatIsOnIt()
    {
        var scan = new[] { new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(-100, 50, 800, 600), true) };
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };

        var window = WindowLayoutComposer.Compose(scan, tracked, Display, null).Windows[0];

        Assert.False(window.FullyVisible);
        Assert.Equal(new[] { new WindowRect(0, 50, 700, 600) }, window.VisibleRegion);
    }

    [Fact]
    public void AHiddenOrWhollyCoveredWindowShowsNothing()
    {
        var scan = new[]
        {
            new WindowLayoutEntry("hwnd:00000002", 2, new WindowRect(0, 0, 1000, 800), true),
            new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(100, 100, 400, 300), true),
            new WindowLayoutEntry("hwnd:00000003", 3, new WindowRect(1200, 100, 400, 300), false)
        };
        var tracked = new Dictionary<string, string?>
        {
            ["hwnd:00000001"] = null, ["hwnd:00000002"] = null, ["hwnd:00000003"] = null
        };

        var layout = WindowLayoutComposer.Compose(scan, tracked, Display, null);

        Assert.Empty(layout.Windows[1].VisibleRegion!);
        Assert.Empty(layout.Windows[2].VisibleRegion!);
    }

    [Fact]
    public void AnotherAppWindowOfTheSameProcessCoversButItsPopupsDoNot()
    {
        var scan = new[]
        {
            // A menu the lower window owns, a second window of the same program, then the first window.
            new WindowLayoutEntry("hwnd:00000003", 7, new WindowRect(150, 150, 200, 300), true),
            new WindowLayoutEntry("hwnd:00000002", 7, new WindowRect(600, 300, 800, 600), true),
            new WindowLayoutEntry("hwnd:00000001", 7, new WindowRect(100, 100, 800, 600), true)
        };
        var tracked = new Dictionary<string, string?>
        {
            ["hwnd:00000001"] = null, ["hwnd:00000002"] = null, ["hwnd:00000003"] = "hwnd:00000001"
        };

        var first = WindowLayoutComposer.Compose(scan, tracked, Display, null).Windows[2];

        Assert.False(first.FullyVisible);
        // Only the second window is cut out; the menu's pixels belong in the first.
        Assert.Equal(800 * 600 - 364 * 464, first.VisibleRegion!.Sum(rect => rect.Width * rect.Height));
    }

    [Fact]
    public void AWindowUnderTooManyPiecesReportsNoneOfThem()
    {
        var scan = new List<WindowLayoutEntry>();
        // A grid of small windows of other programs over one large window, far enough apart that the
        // margins left out around them do not join up.
        for (var index = 0; index < 9; index++)
        {
            scan.Add(new WindowLayoutEntry(
                $"hwnd:000001{index:X2}", 100 + index, new WindowRect(250 + index % 3 * 400, 250 + index / 3 * 250, 60, 60), true));
        }
        scan.Add(new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(50, 50, 1500, 950), true));
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };

        var window = WindowLayoutComposer.Compose(scan, tracked, Display, null).Windows[0];

        Assert.False(window.FullyVisible);
        Assert.Empty(window.VisibleRegion!);
    }

    [Fact]
    public void SubtractingLeavesPiecesThatDoNotOverlap()
    {
        var pieces = WindowLayoutComposer.Subtract(
            new[] { new WindowRect(0, 0, 100, 100) }, new WindowRect(40, 40, 20, 20));

        Assert.Equal(4, pieces.Count);
        Assert.Equal(100 * 100 - 20 * 20, pieces.Sum(rect => rect.Width * rect.Height));
        for (var a = 0; a < pieces.Count; a++)
        {
            for (var b = a + 1; b < pieces.Count; b++)
            {
                Assert.Null(WindowLayoutComposer.Intersection(pieces[a], pieces[b]));
            }
        }
        // A hole that misses changes nothing.
        Assert.Single(WindowLayoutComposer.Subtract(new[] { new WindowRect(0, 0, 100, 100) }, new WindowRect(200, 0, 10, 10)));
    }

    [Fact]
    public void StreamerScansSlowerOnceNothingHasMovedForASecond()
    {
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };
        var frame = new WindowRect(0, 0, 800, 600);
        var streamer = new WindowLayoutStreamer(
            () => tracked,
            () => new WindowLayoutScan(new[] { new WindowLayoutEntry("hwnd:00000001", 1, frame, true) }, Display, null),
            inputDesktopIsSecure: () => false);

        // Nothing tracked yet as far as the streamer knows.
        Assert.Equal(WindowLayoutStreamer.IdleInterval, streamer.CurrentInterval);

        void Scan() => streamer.NoteScan(changed: streamer.NextEvent() is not null);

        Scan();
        Assert.Equal(WindowLayoutStreamer.ActiveInterval, streamer.CurrentInterval);
        for (var scan = 0; scan < WindowLayoutStreamer.UnchangedScansBeforeSettled; scan++)
        {
            Scan();
        }
        Assert.Equal(WindowLayoutStreamer.SettledInterval, streamer.CurrentInterval);

        // A move brings the fast pace straight back.
        frame = new WindowRect(40, 0, 800, 600);
        Scan();
        Assert.Equal(WindowLayoutStreamer.ActiveInterval, streamer.CurrentInterval);
    }
}
