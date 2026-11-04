using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using Veil.Agent;

namespace VeilAgent.Tests;

public class WebSocketFrameStreamLifecycleTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);
    private const string WindowId = "hwnd:00000010";

    [Fact]
    public async Task LaunchPublishesMetadataBeforeStartingTheContinuousStream()
    {
        await using var harness = await ServerHarness.StartAsync();
        var start = new CaptureStep();
        harness.Capture.BlockNextForget = start;
        var launch = harness.RequestAsync(MessageTypes.AppLaunchRequest);
        try
        {
            await start.Cancelled.Task.WaitAsync(Timeout);
            var response = await launch.WaitAsync(TimeSpan.FromSeconds(1));
            Assert.Equal(MessageTypes.AppLaunchResponse, response["type"]!.GetValue<string>());
        }
        finally
        {
            start.Release.Set();
        }
    }

    [Theory]
    [InlineData(MessageTypes.WindowFrameSubscribe)]
    [InlineData(MessageTypes.WindowFrameUnsubscribe)]
    public async Task AcknowledgesStreamChangesOnlyAfterPreviousStreamFinishes(string operation)
    {
        await using var harness = await ServerHarness.StartAsync();
        await harness.RequestAsync(MessageTypes.WindowFrameSubscribe);
        var previous = await harness.Capture.NextAsync();

        var change = harness.RequestAsync(operation);
        await previous.Cancelled.Task.WaitAsync(Timeout);
        // Cancellation is explicitly gated inside capture. This timeout observes the absence of an
        // acknowledgement while cleanup is blocked; elapsed time does not arrange the race.
        await Assert.ThrowsAsync<TimeoutException>(() => change.WaitAsync(TimeSpan.FromMilliseconds(150)));
        previous.Release.Set();

        var acknowledgement = await change.WaitAsync(Timeout);
        Assert.Equal(MessageTypes.OperationAck, acknowledgement["type"]!.GetValue<string>());
        Assert.True(acknowledgement["accepted"]!.GetValue<bool>());
        Assert.False(harness.Capture.ForgotWhileCapturing);

        if (operation == MessageTypes.WindowFrameSubscribe)
        {
            var replacement = await harness.Capture.NextAsync();
            var stop = harness.RequestAsync(MessageTypes.WindowFrameUnsubscribe);
            await replacement.Cancelled.Task.WaitAsync(Timeout);
            replacement.Release.Set();
            await stop.WaitAsync(Timeout);
            Assert.False(harness.Capture.ForgotWhileCapturing);
        }
    }

    [Fact]
    public async Task ServerShutdownDrainsActiveFrameCaptureBeforeReturning()
    {
        await using var harness = await ServerHarness.StartAsync();
        await harness.RequestAsync(MessageTypes.WindowFrameSubscribe);
        var capture = await harness.Capture.NextAsync();

        harness.Cancellation.Cancel();
        await capture.Cancelled.Task.WaitAsync(Timeout);
        var completed = Task.WhenAny(harness.ServerTask);
        await Assert.ThrowsAsync<TimeoutException>(() => completed.WaitAsync(TimeSpan.FromMilliseconds(150)));
        capture.Release.Set();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => harness.ServerTask.WaitAsync(Timeout));
        Assert.False(harness.Capture.ForgotWhileCapturing);
        Assert.True(harness.Capture.ForgetCount >= 2);
    }

    private sealed class CaptureStep
    {
        public TaskCompletionSource Cancelled { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public ManualResetEventSlim Release { get; } = new();
    }

    private sealed class ControlledCapture : IWindowFrameCapture
    {
        private readonly Channel<CaptureStep> captures = Channel.CreateUnbounded<CaptureStep>();
        private readonly List<CaptureStep> allCaptures = [];
        private int activeCaptures;
        private int forgetCount;
        private int forgotWhileCapturing;
        private bool releasing;

        public bool ForgotWhileCapturing => Volatile.Read(ref forgotWhileCapturing) != 0;
        public int ForgetCount => Volatile.Read(ref forgetCount);
        public CaptureStep? BlockNextForget { get; set; }

        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            Task.FromResult(new WindowFrame(window.WindowId, "frame_initial", sequence, "png", 1, 1, 1, "AA=="));

        public Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
            LaunchedWindow window, int sequence, bool includeFullFrame, CancellationToken cancellationToken)
        {
            var step = new CaptureStep();
            lock (allCaptures)
            {
                allCaptures.Add(step);
                if (releasing) step.Release.Set();
            }

            Interlocked.Increment(ref activeCaptures);
            using var registration = cancellationToken.Register(() => step.Cancelled.TrySetResult());
            captures.Writer.TryWrite(step);
            try
            {
                // Models a synchronous/native capture that has started but cannot yet unwind.
                if (!step.Release.Wait(Timeout)) throw new TimeoutException("Test did not release capture.");
                cancellationToken.ThrowIfCancellationRequested();
                return Task.FromResult(WindowFrameCaptureResult.Unchanged(sequence));
            }
            finally
            {
                Interlocked.Decrement(ref activeCaptures);
            }
        }

        public void ForgetWindow(string windowId)
        {
            if (BlockNextForget is { } block)
            {
                BlockNextForget = null;
                block.Cancelled.TrySetResult();
                if (!block.Release.Wait(Timeout)) throw new TimeoutException("Test did not release stream startup.");
            }
            if (Volatile.Read(ref activeCaptures) != 0) Interlocked.Exchange(ref forgotWhileCapturing, 1);
            Interlocked.Increment(ref forgetCount);
        }

        public Task<CaptureStep> NextAsync() => captures.Reader.ReadAsync().AsTask().WaitAsync(Timeout);

        public void ReleaseAll()
        {
            lock (allCaptures)
            {
                releasing = true;
                foreach (var step in allCaptures) step.Release.Set();
            }
        }
    }

    private sealed class ServerHarness : IAsyncDisposable
    {
        public ControlledCapture Capture { get; } = new();
        public CancellationTokenSource Cancellation { get; } = new();
        public Task ServerTask { get; private set; } = Task.CompletedTask;
        private Uri address = null!;

        public static async Task<ServerHarness> StartAsync()
        {
            var harness = new ServerHarness();
            using var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            var port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            var endpoint = new AgentEndpoint("127.0.0.1", port);
            harness.address = new Uri(endpoint.WebSocketUrl);
            var desktop = new TestDesktop();
            var session = new AgentSession(desktop, harness.Capture);
            await session.HandleAsync(new JsonObject
            {
                ["type"] = MessageTypes.AppLaunchRequest,
                ["requestId"] = "launch",
                ["appId"] = "winapp_notepad"
            });
            var server = new WebSocketAgentServer(endpoint, session,
                new WindowFrameStreamer(harness.Capture, TimeSpan.FromMilliseconds(1)),
                new ClipboardTextStreamer(desktop), new WindowDiscoveryStreamer(session, desktop));
            harness.ServerTask = server.RunAsync(harness.Cancellation.Token);
            return harness;
        }

        public async Task<JsonObject> RequestAsync(string type)
        {
            using var timeout = new CancellationTokenSource(Timeout);
            using var socket = new ClientWebSocket();
            await socket.ConnectAsync(address, timeout.Token);
            var request = new JsonObject
            {
                ["type"] = type,
                ["requestId"] = Guid.NewGuid().ToString(),
                ["appId"] = "winapp_notepad",
                ["windowId"] = WindowId,
                ["format"] = "png"
            };
            await socket.SendAsync(System.Text.Encoding.UTF8.GetBytes(request.ToJsonString()),
                WebSocketMessageType.Text, true, timeout.Token);
            var buffer = new byte[8192];
            var result = await socket.ReceiveAsync(buffer, timeout.Token);
            var response = JsonNode.Parse(buffer.AsSpan(0, result.Count))!.AsObject();
            if (type == MessageTypes.AppLaunchRequest)
            {
                result = await socket.ReceiveAsync(buffer, timeout.Token);
                var window = JsonNode.Parse(buffer.AsSpan(0, result.Count))!.AsObject();
                Assert.Equal(MessageTypes.WindowCreated, window["type"]!.GetValue<string>());
            }
            return response;
        }

        public async ValueTask DisposeAsync()
        {
            Cancellation.Cancel();
            Capture.ReleaseAll();
            try { await ServerTask.WaitAsync(Timeout); }
            catch (OperationCanceledException) { }
            Cancellation.Dispose();
        }
    }

    private sealed class TestDesktop : IWindowsDesktop
    {
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            Task.FromResult(new LaunchedWindow(WindowId, 0x10, 123, "Notepad", new WindowRect(0, 0, 1, 1), "normal", true));
        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) => LaunchAppAsync(app, cancellationToken);
        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];
        public bool IsWindowStillOpen(string windowId) => windowId == WindowId;
        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);
        public bool TryConsumeHostClipboardEcho(string text) => false;
    }
}
