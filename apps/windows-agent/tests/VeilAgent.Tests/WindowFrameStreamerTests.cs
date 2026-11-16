using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowFrameStreamerTests
{
    private sealed class FailsOnceCapture : IWindowFrameCapture
    {
        private int attempts;

        public Task<WindowFrame> CaptureFrameAsync(
            LaunchedWindow window,
            int sequence,
            CancellationToken cancellationToken
        )
        {
            if (Interlocked.Increment(ref attempts) == 1)
            {
                throw new InvalidOperationException("PrintWindow failed");
            }

            return Task.FromResult(new WindowFrame(
                window.WindowId,
                $"frame_{sequence:000000}",
                sequence,
                "png",
                640,
                480,
                1,
                "real-frame"
            ));
        }
    }

    private sealed class UnchangedCapture : IWindowFrameCapture
    {
        private int captures;

        public int Captures => Volatile.Read(ref captures);

        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
            LaunchedWindow window,
            int sequence,
            bool includeFullFrame,
            CancellationToken cancellationToken
        )
        {
            Interlocked.Increment(ref captures);
            return Task.FromResult(WindowFrameCaptureResult.Unchanged(sequence));
        }
    }

    [Fact]
    public async Task WakingAnIdleStreamCapturesWithoutWaitingOutTheIdleInterval()
    {
        var window = new LaunchedWindow("hwnd:00000002", 0, 4242, "Paint", new WindowRect(0, 0, 640, 480), "normal", true);
        var capture = new UnchangedCapture();
        // Idle after one unchanged tick, and idle long enough that only a wake can explain a second capture.
        var streamer = new WindowFrameStreamer(
            capture,
            cadenceFactory: () => new WindowFrameStreamCadence(
                activeInterval: TimeSpan.FromMilliseconds(20),
                idleInterval: TimeSpan.FromSeconds(30),
                unchangedTicksBeforeIdle: 1
            )
        );
        using var cancellation = new CancellationTokenSource();
        var streamTask = streamer.StreamAsync(window, 1, (_, _) => Task.CompletedTask, cancellation.Token);

        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (capture.Captures < 1 && DateTime.UtcNow < deadline)
        {
            await Task.Delay(5);
        }
        await Task.Delay(100);
        var capturesWhileIdle = capture.Captures;

        streamer.Wake(window.WindowId);
        deadline = DateTime.UtcNow.AddSeconds(5);
        while (capture.Captures == capturesWhileIdle && DateTime.UtcNow < deadline)
        {
            await Task.Delay(5);
        }

        Assert.True(capture.Captures > capturesWhileIdle, "A wake should trigger a capture well before the 30 s idle tick.");
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);
    }

    [Fact]
    public async Task SkipsFailedCapturesUntilARealFrameIsAvailable()
    {
        var window = new LaunchedWindow(
            "hwnd:00000001",
            0,
            4242,
            "Untitled - Notepad",
            new WindowRect(0, 0, 640, 480),
            "normal",
            true
        );
        var streamer = new WindowFrameStreamer(new FailsOnceCapture(), TimeSpan.FromMilliseconds(5));
        var received = new List<WindowFrameCaptureResult>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            window,
            firstSequence: 1,
            (result, _) =>
            {
                received.Add(result);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var result = Assert.Single(received);
        Assert.NotNull(result.Frame);
        var frame = result.Frame!;
        Assert.Equal(1, frame.Sequence);
        Assert.Equal("real-frame", frame.EncodedData);
    }
    [Fact]
    public async Task HoldsTheDisplayOnOnlyWhileAStreamRuns()
    {
        var window = new LaunchedWindow(
            "hwnd:00000001",
            0,
            4242,
            "Untitled - Paint",
            new WindowRect(0, 0, 640, 480),
            "normal",
            true
        );
        var states = new List<bool>();
        var keepAwake = new DisplayKeepAwake(states.Add);
        var streamer = new WindowFrameStreamer(
            new FailsOnceCapture(),
            TimeSpan.FromMilliseconds(5),
            keepAwake: keepAwake
        );
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            window,
            firstSequence: 1,
            (_, _) =>
            {
                Assert.Equal(new[] { true }, states);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);
        Assert.Equal(new[] { true, false }, states);
    }

    [Fact]
    public void KeepsTheDisplayOnUntilTheLastHoldEnds()
    {
        var states = new List<bool>();
        var keepAwake = new DisplayKeepAwake(states.Add);

        var first = keepAwake.Hold();
        var second = keepAwake.Hold();
        first.Dispose();
        first.Dispose();
        Assert.Equal(new[] { true }, states);

        second.Dispose();
        Assert.Equal(new[] { true, false }, states);
    }

    [Fact]
    public async Task SendsHeartbeatsWithoutCapturingWhileTheSecureDesktopIsUp()
    {
        var window = new LaunchedWindow("hwnd:00000003", 0, 4242, "Setup", new WindowRect(0, 0, 640, 480), "normal", true);
        var capture = new UnchangedCapture();
        var secure = true;
        var streamer = new WindowFrameStreamer(
            capture,
            TimeSpan.FromMilliseconds(5),
            inputDesktopIsSecure: () => Volatile.Read(ref secure)
        );
        var heartbeats = 0;
        using var cancellation = new CancellationTokenSource();
        var streamTask = streamer.StreamAsync(
            window,
            1,
            (_, _) => Task.CompletedTask,
            cancellation.Token,
            onUnchanged: (_, _) =>
            {
                Interlocked.Increment(ref heartbeats);
                return Task.CompletedTask;
            }
        );

        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (Volatile.Read(ref heartbeats) < 3 && DateTime.UtcNow < deadline)
        {
            await Task.Delay(5);
        }

        Assert.True(Volatile.Read(ref heartbeats) >= 3);
        Assert.Equal(0, capture.Captures);

        // Capturing resumes when the prompt is answered.
        Volatile.Write(ref secure, false);
        while (capture.Captures < 1 && DateTime.UtcNow < deadline)
        {
            await Task.Delay(5);
        }

        Assert.True(capture.Captures >= 1);
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);
    }
}
