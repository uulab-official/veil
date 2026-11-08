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
}
