using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowDiscoveryStreamerTests
{
    private sealed class ScriptedWindowsDesktop : IWindowsDesktop
    {
        private readonly LaunchedWindow launchedWindow;
        private readonly Queue<IReadOnlyList<LaunchedWindow>> discoveryScript;
        private readonly HashSet<string> closedWindowIds;
        public int LaunchAppCallCount { get; private set; }
        public List<IReadOnlySet<string>> DiscoveryKnownWindowIds { get; } = [];

        public ScriptedWindowsDesktop(
            LaunchedWindow launchedWindow,
            Queue<IReadOnlyList<LaunchedWindow>> discoveryScript,
            IEnumerable<string>? closedWindowIds = null
        )
        {
            this.launchedWindow = launchedWindow;
            this.discoveryScript = discoveryScript;
            this.closedWindowIds = closedWindowIds is null ? [] : new HashSet<string>(closedWindowIds);
        }

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken)
        {
            LaunchAppCallCount += 1;
            return Task.FromResult(launchedWindow);
        }

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            Task.FromResult(launchedWindow);

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds)
        {
            DiscoveryKnownWindowIds.Add(new HashSet<string>(knownWindowIds));
            return discoveryScript.Count == 0 ? Array.Empty<LaunchedWindow>() : discoveryScript.Dequeue();
        }

        // Every window is "still open" unless the test explicitly scripts it as closed -- keeps the
        // pruning pass a no-op for tests that are only exercising discovery.
        public bool IsWindowStillOpen(string windowId) => !closedWindowIds.Contains(windowId);

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

    private sealed class ConcurrentLaunchWindowsDesktop : IWindowsDesktop
    {
        private readonly LaunchedWindow window;
        private int windowIsVisible;
        private int launchAppCallCount;

        public ConcurrentLaunchWindowsDesktop(LaunchedWindow window)
        {
            this.window = window;
        }

        public int LaunchAppCallCount => Volatile.Read(ref launchAppCallCount);

        public async Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref launchAppCallCount);
            await Task.Delay(TimeSpan.FromMilliseconds(50), cancellationToken);
            Volatile.Write(ref windowIsVisible, 1);
            return window;
        }

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            LaunchAppAsync(new WindowsAppDescriptor("winapp_notepad", "Notepad", "notepad.exe", "Microsoft", "icon_notepad"), cancellationToken);

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) =>
            Volatile.Read(ref windowIsVisible) == 1 ? [window] : Array.Empty<LaunchedWindow>();

        public bool IsWindowStillOpen(string windowId) => Volatile.Read(ref windowIsVisible) == 1;

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

    private static LaunchedWindow Window(string windowId) => new(
        WindowId: windowId,
        Hwnd: 0,
        ProcessId: 4242,
        Title: "Untitled",
        Bounds: new WindowRect(0, 0, 640, 480),
        State: "normal",
        Focused: true
    );

    private static async Task<AgentSession> LaunchNotepadAsync(IWindowsDesktop desktop, IWindowFrameCapture capture)
    {
        var session = new AgentSession(desktop, capture);
        var request = new JsonObject
        {
            ["type"] = "app.launch.request",
            ["requestId"] = "req_launch",
            ["appId"] = "winapp_notepad"
        };

        await session.HandleAsync(request);
        return session;
    }

    [Fact]
    public async Task KeepsLaunchAndWindowTrackingWhenInitialCaptureFails()
    {
        var launched = Window("hwnd:00000001");
        var desktop = new ScriptedWindowsDesktop(launched, new Queue<IReadOnlyList<LaunchedWindow>>());
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        var request = new JsonObject
        {
            ["type"] = "app.launch.request",
            ["requestId"] = "req_launch",
            ["appId"] = "winapp_notepad"
        };

        var replies = await session.HandleAsync(request);

        Assert.Equal(2, replies.DirectReplies.Count);
        Assert.Equal("app.launch.response", replies.DirectReplies[0]["type"]!.GetValue<string>());
        Assert.Equal("window.created", replies.DirectReplies[1]["type"]!.GetValue<string>());
        Assert.Empty(replies.BroadcastEvents);
        Assert.Equal(launched, replies.StreamWindow);
        Assert.Equal(1, replies.NextFrameSequence);
    }

    [Fact]
    public async Task RestoreReusesAnExistingWindowAndSuppressesDuplicateDiscovery()
    {
        var existingFocusedWindow = Window("hwnd:00000001");
        var existingBackgroundWindow = Window("hwnd:00000002") with { Focused = false };
        var desktop = new ScriptedWindowsDesktop(
            Window("hwnd:new"),
            new Queue<IReadOnlyList<LaunchedWindow>>([
                [existingFocusedWindow, existingBackgroundWindow],
                [existingBackgroundWindow]
            ])
        );
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = "app.launch.request",
            ["requestId"] = "req_restore",
            ["appId"] = "winapp_notepad",
            ["reuseExistingWindow"] = true
        });

        Assert.Equal(0, desktop.LaunchAppCallCount);
        Assert.Equal(existingFocusedWindow.WindowId, replies.DirectReplies[1]["windowId"]!.GetValue<string>());

        var streamer = new WindowDiscoveryStreamer(session, desktop, interval: TimeSpan.FromMilliseconds(5));
        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(40));
        var streamTask = streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        Assert.Empty(broadcasts);
        Assert.Contains(desktop.DiscoveryKnownWindowIds, knownWindowIds =>
            knownWindowIds.Count == 2
            && knownWindowIds.Contains(existingFocusedWindow.WindowId)
            && knownWindowIds.Contains(existingBackgroundWindow.WindowId)
        );
    }

    [Fact]
    public async Task ConcurrentReuseRequestsLaunchOneWindowsAppProcess()
    {
        var window = Window("hwnd:00000001");
        var desktop = new ConcurrentLaunchWindowsDesktop(window);
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        static JsonObject Request(string requestId) => new()
        {
            ["type"] = "app.launch.request",
            ["requestId"] = requestId,
            ["appId"] = "winapp_notepad",
            ["reuseExistingWindow"] = true
        };

        var firstRequest = session.HandleAsync(Request("req_launch_1"));
        await Task.Delay(TimeSpan.FromMilliseconds(5));
        var secondRequest = session.HandleAsync(Request("req_launch_2"));
        var replies = await Task.WhenAll(firstRequest, secondRequest);

        Assert.Equal(1, desktop.LaunchAppCallCount);
        Assert.All(replies, reply =>
            Assert.Equal(window.WindowId, reply.DirectReplies[1]["windowId"]!.GetValue<string>())
        );
    }

    [Fact]
    public async Task BroadcastsWindowCreatedForANewlyDiscoveredWindow()
    {
        // Regression test for Phase 3 (multi-window discovery): a second Notepad window opened
        // after the initial launch (e.g. a second document) must surface as its own window.created
        // event without depending on another app.launch.request.
        var firstWindow = Window("hwnd:00000001");
        var secondWindow = Window("hwnd:00000002");

        var discoveryScript = new Queue<IReadOnlyList<LaunchedWindow>>();
        discoveryScript.Enqueue([secondWindow]);

        var desktop = new ScriptedWindowsDesktop(firstWindow, discoveryScript);
        var session = await LaunchNotepadAsync(desktop, new NoOpFrameCapture());
        var streamer = new WindowDiscoveryStreamer(session, desktop, interval: TimeSpan.FromMilliseconds(5));

        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var createdEvent = Assert.Single(broadcasts);
        Assert.Equal("window.created", createdEvent["type"]!.GetValue<string>());
        Assert.Equal("hwnd:00000002", createdEvent["windowId"]!.GetValue<string>());
        Assert.Equal("winapp_notepad", createdEvent["appId"]!.GetValue<string>());
    }

    [Fact]
    public async Task DoesNotReannounceAWindowAlreadyTracked()
    {
        // If the guest's own EnumWindows scan races a launch/close and reports the same window id
        // twice, the streamer must not broadcast window.created for it a second time.
        var firstWindow = Window("hwnd:00000001");
        var secondWindow = Window("hwnd:00000002");

        var discoveryScript = new Queue<IReadOnlyList<LaunchedWindow>>();
        discoveryScript.Enqueue([secondWindow]);
        discoveryScript.Enqueue([secondWindow]);

        var desktop = new ScriptedWindowsDesktop(firstWindow, discoveryScript);
        var session = await LaunchNotepadAsync(desktop, new NoOpFrameCapture());
        var streamer = new WindowDiscoveryStreamer(session, desktop, interval: TimeSpan.FromMilliseconds(5));

        var broadcastCount = 0;
        using var cancellation = new CancellationTokenSource();
        cancellation.CancelAfter(TimeSpan.FromMilliseconds(60));

        var streamTask = streamer.StreamAsync(
            (_, _) =>
            {
                broadcastCount += 1;
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        Assert.Equal(1, broadcastCount);
    }

    [Fact]
    public async Task PrunesAndBroadcastsWindowClosedForAWindowClosedDirectlyOnTheGuest()
    {
        // Regression test for a gap the review caught: if the user closes a mirrored window by
        // clicking its own close button (not via window.close.request), the tracked entry must be
        // pruned -- otherwise it stays tracked forever, and Win32's HWND reuse could later make a
        // genuinely new window look "already known" and never get reported.
        var firstWindow = Window("hwnd:00000001");
        var desktop = new ScriptedWindowsDesktop(
            firstWindow,
            new Queue<IReadOnlyList<LaunchedWindow>>(),
            closedWindowIds: [firstWindow.WindowId]
        );
        var session = await LaunchNotepadAsync(desktop, new NoOpFrameCapture());
        var streamer = new WindowDiscoveryStreamer(session, desktop, interval: TimeSpan.FromMilliseconds(5));

        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var closedEvent = Assert.Single(broadcasts);
        Assert.Equal("window.closed", closedEvent["type"]!.GetValue<string>());
        Assert.Equal("hwnd:00000001", closedEvent["windowId"]!.GetValue<string>());
    }

    [Fact]
    public async Task TransientDiscoveryFailureDoesNotStopTheStream()
    {
        var firstWindow = Window("hwnd:00000001");
        var secondWindow = Window("hwnd:00000002");

        var desktop = new ThrowingThenSucceedingDesktop(firstWindow, secondWindow);
        var session = await LaunchNotepadAsync(desktop, new NoOpFrameCapture());
        var streamer = new WindowDiscoveryStreamer(session, desktop, interval: TimeSpan.FromMilliseconds(5));

        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var createdEvent = Assert.Single(broadcasts);
        Assert.Equal("hwnd:00000002", createdEvent["windowId"]!.GetValue<string>());
    }

    private sealed class ThrowingThenSucceedingDesktop : IWindowsDesktop
    {
        private readonly LaunchedWindow launchedWindow;
        private readonly LaunchedWindow discoveredWindow;
        private bool hasThrown;

        public ThrowingThenSucceedingDesktop(LaunchedWindow launchedWindow, LaunchedWindow discoveredWindow)
        {
            this.launchedWindow = launchedWindow;
            this.discoveredWindow = discoveredWindow;
        }

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            Task.FromResult(launchedWindow);

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            Task.FromResult(launchedWindow);

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds)
        {
            if (!hasThrown)
            {
                hasThrown = true;
                throw new InvalidOperationException("transient EnumWindows failure");
            }

            return [discoveredWindow];
        }

        public bool IsWindowStillOpen(string windowId) => true;

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
}
