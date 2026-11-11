using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class GuestStateSyncTests
{
    private sealed class FakeClock : IGuestClock
    {
        public bool IsWindows { get; init; } = true;
        public DateTimeOffset UtcNow { get; init; }
        public bool CanSetTime { get; init; }
        public bool PrivilegeNotHeld { get; init; } = true;
        public bool TaskAvailable { get; init; }
        public DateTimeOffset? SetTo { get; private set; }
        public int TaskStarts { get; private set; }

        public bool TrySetSystemTime(DateTimeOffset utc, out bool privilegeNotHeld, out string? error)
        {
            if (CanSetTime)
            {
                SetTo = utc;
                privilegeNotHeld = false;
                error = null;
                return true;
            }

            privilegeNotHeld = PrivilegeNotHeld;
            error = "SeSystemtimePrivilege unavailable (Win32 error 1300)";
            return false;
        }

        public bool TryStartResyncTask(out string? error)
        {
            TaskStarts++;
            error = TaskAvailable ? null : "schtasks /Run exited 1: ERROR: The system cannot find the file specified.";
            return TaskAvailable;
        }
    }

    private sealed class FakeThemeStore : IWindowsThemeStore
    {
        public bool IsWindows { get; init; } = true;
        public bool? Apps { get; set; }
        public bool? System { get; set; }
        public bool IgnoreWrites { get; init; }
        public int Writes { get; private set; }
        public int Broadcasts { get; private set; }

        public (bool? AppsUseLightTheme, bool? SystemUsesLightTheme) Read() => (Apps, System);

        public void Write(bool useLightTheme)
        {
            Writes++;
            if (!IgnoreWrites)
            {
                Apps = useLightTheme;
                System = useLightTheme;
            }
        }

        public bool BroadcastThemeChange()
        {
            Broadcasts++;
            return true;
        }
    }

    private static readonly DateTimeOffset HostUtc = new(2026, 11, 11, 9, 30, 0, TimeSpan.Zero);

    private static JsonObject TimeRequest(string hostUtc = "2026-11-11T09:30:00.000Z", string reason = "vm-resume") => new()
    {
        ["type"] = MessageTypes.TimeSyncRequest,
        ["requestId"] = "req_time_sync",
        ["protocolVersion"] = 1,
        ["hostUtc"] = hostUtc,
        ["reason"] = reason
    };

    [Fact]
    public void SmallSkewIsReportedInSyncWithoutTouchingTheClock()
    {
        var clock = new FakeClock { UtcNow = HostUtc.AddMilliseconds(-800), CanSetTime = true };

        var status = new GuestTimeSync(clock).Handle(TimeRequest());

        Assert.Equal("in-sync", status["outcome"]!.GetValue<string>());
        Assert.Equal("none", status["method"]!.GetValue<string>());
        Assert.Equal(800, status["skewMilliseconds"]!.GetValue<long>());
        Assert.Null(clock.SetTo);
        Assert.Equal(0, clock.TaskStarts);
    }

    [Fact]
    public void StaleClockIsSetFromHostWhenThePrivilegeIsAvailable()
    {
        var before = new DateTimeOffset(2026, 11, 10, 22, 12, 41, 118, TimeSpan.Zero);
        var clock = new FakeClock { UtcNow = before, CanSetTime = true };

        var status = new GuestTimeSync(clock).Handle(TimeRequest());

        Assert.Equal("corrected", status["outcome"]!.GetValue<string>());
        Assert.Equal("set-system-time", status["method"]!.GetValue<string>());
        Assert.Equal(40638882, status["skewMilliseconds"]!.GetValue<long>());
        Assert.Equal("2026-11-10T22:12:41.118Z", status["guestUtcBefore"]!.GetValue<string>());
        Assert.Equal(HostUtc, clock.SetTo);
        Assert.False(status["requiresElevation"]!.GetValue<bool>());
    }

    [Fact]
    public void LimitedTokenFallsBackToTheResyncTaskAndDoesNotClaimACorrection()
    {
        var clock = new FakeClock { UtcNow = HostUtc.AddHours(-3), TaskAvailable = true };

        var status = new GuestTimeSync(clock).Handle(TimeRequest());

        Assert.Equal("resync-requested", status["outcome"]!.GetValue<string>());
        Assert.Equal("resync-task", status["method"]!.GetValue<string>());
        Assert.Equal("wait-for-network-time", status["recommendedAction"]!.GetValue<string>());
        Assert.Equal(1, clock.TaskStarts);
    }

    [Fact]
    public void LimitedTokenWithoutTheTaskAsksForAnElevatedInstall()
    {
        var clock = new FakeClock { UtcNow = HostUtc.AddHours(3) };

        var status = new GuestTimeSync(clock).Handle(TimeRequest());

        Assert.Equal("failed", status["outcome"]!.GetValue<string>());
        Assert.True(status["requiresElevation"]!.GetValue<bool>());
        Assert.Equal("install-time-sync-task-elevated", status["recommendedAction"]!.GetValue<string>());
        Assert.True(status["skewMilliseconds"]!.GetValue<long>() < 0);
        Assert.Contains("ahead of", status["message"]!.GetValue<string>());
    }

    [Theory]
    [InlineData("2026-11-11T18:30:00+09:00", "vm-resume")]
    [InlineData("yesterday", "vm-resume")]
    [InlineData("1970-01-01T00:00:00Z", "vm-resume")]
    [InlineData("2026-11-11T09:30:00Z", "because")]
    public void ImplausibleRequestsAreRefusedWithoutTouchingTheClock(string hostUtc, string reason)
    {
        var clock = new FakeClock { UtcNow = HostUtc.AddHours(-3), CanSetTime = true, TaskAvailable = true };

        var status = new GuestTimeSync(clock).Handle(TimeRequest(hostUtc, reason));

        Assert.Equal("invalid-request", status["outcome"]!.GetValue<string>());
        Assert.Null(clock.SetTo);
        Assert.Equal(0, clock.TaskStarts);
    }

    [Fact]
    public void NonWindowsAgentReportsUnsupported()
    {
        var status = new GuestTimeSync(new FakeClock { IsWindows = false, UtcNow = HostUtc }).Handle(TimeRequest());

        Assert.False(status["isSupported"]!.GetValue<bool>());
        Assert.Equal("unsupported", status["outcome"]!.GetValue<string>());
        Assert.Equal("none", status["method"]!.GetValue<string>());
    }

    [Fact]
    public void DarkThemeWritesBothValuesAndBroadcastsOnce()
    {
        var store = new FakeThemeStore { Apps = true, System = true };

        var status = new GuestAppearanceSync(store).Apply("dark")!;

        Assert.True(status["changed"]!.GetValue<bool>());
        Assert.True(status["broadcast"]!.GetValue<bool>());
        Assert.False(status["appsUseLightTheme"]!.GetValue<bool>());
        Assert.False(status["systemUsesLightTheme"]!.GetValue<bool>());
        Assert.Equal(1, store.Writes);
        Assert.Equal(1, store.Broadcasts);
    }

    [Fact]
    public void MatchingThemeSkipsTheWriteAndTheBroadcast()
    {
        var store = new FakeThemeStore { Apps = false, System = false };

        var status = new GuestAppearanceSync(store).Apply("dark")!;

        Assert.False(status["changed"]!.GetValue<bool>());
        Assert.False(status["broadcast"]!.GetValue<bool>());
        Assert.Equal(0, store.Writes);
        Assert.Equal(0, store.Broadcasts);
    }

    [Fact]
    public void HalfMatchingThemeIsStillRewritten()
    {
        var store = new FakeThemeStore { Apps = true, System = false };

        var status = new GuestAppearanceSync(store).Apply("light")!;

        Assert.True(status["changed"]!.GetValue<bool>());
        Assert.True(status["systemUsesLightTheme"]!.GetValue<bool>());
    }

    [Fact]
    public void WriteThatDidNotTakeEffectThrowsRatherThanReportingSuccess()
    {
        var store = new FakeThemeStore { Apps = true, System = true, IgnoreWrites = true };

        Assert.Throws<InvalidOperationException>(() => new GuestAppearanceSync(store).Apply("dark"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("auto")]
    [InlineData("Dark")]
    public void UnknownThemeIsRejected(string? theme)
    {
        Assert.Null(new GuestAppearanceSync(new FakeThemeStore()).Apply(theme));
    }

    [Fact]
    public async Task SessionRoutesTimeSyncAndAdvertisesTheCapability()
    {
        var session = NewSession(
            new FakeClock { UtcNow = HostUtc, CanSetTime = true },
            new FakeThemeStore()
        );

        var health = Assert.Single((await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        })).DirectReplies);
        Assert.True(health["capabilities"]!["timeSync"]!.GetValue<bool>());
        Assert.True(health["capabilities"]!["appearanceSync"]!.GetValue<bool>());

        var response = Assert.Single((await session.HandleAsync(TimeRequest())).DirectReplies);
        Assert.Equal(MessageTypes.TimeSyncResponse, response["type"]!.GetValue<string>());
        Assert.Equal("req_time_sync", response["requestId"]!.GetValue<string>());
        Assert.Equal("in-sync", response["timeSync"]!["outcome"]!.GetValue<string>());
    }

    [Fact]
    public async Task SessionRoutesAppearanceAndMapsFailuresToStructuredErrors()
    {
        var session = NewSession(new FakeClock { UtcNow = HostUtc }, new FakeThemeStore { Apps = true, System = true });

        var response = Assert.Single((await session.HandleAsync(AppearanceRequest("dark"))).DirectReplies);
        Assert.Equal(MessageTypes.AppearanceSetResponse, response["type"]!.GetValue<string>());
        Assert.Equal("dark", response["appearance"]!["theme"]!.GetValue<string>());

        var invalid = Assert.Single((await session.HandleAsync(AppearanceRequest("sepia"))).DirectReplies);
        Assert.Equal("invalid_message", invalid["code"]!.GetValue<string>());

        var stuck = NewSession(new FakeClock { UtcNow = HostUtc }, new FakeThemeStore { Apps = true, System = true, IgnoreWrites = true });
        var failed = Assert.Single((await stuck.HandleAsync(AppearanceRequest("dark"))).DirectReplies);
        Assert.Equal("appearance_set_failed", failed["code"]!.GetValue<string>());
    }

    private static JsonObject AppearanceRequest(string theme) => new()
    {
        ["type"] = MessageTypes.AppearanceSetRequest,
        ["requestId"] = "req_appearance_set",
        ["protocolVersion"] = 1,
        ["theme"] = theme
    };

    private static AgentSession NewSession(IGuestClock clock, IWindowsThemeStore store) => new(
        new NoOpWindowsDesktop(),
        new NoOpFrameCapture(),
        timeSync: new GuestTimeSync(clock),
        appearanceSync: new GuestAppearanceSync(store)
    );

    private sealed class NoOpWindowsDesktop : IWindowsDesktop
    {
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => false;

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
