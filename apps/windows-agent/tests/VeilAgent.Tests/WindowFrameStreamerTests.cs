using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowFrameStreamerTests
{
    private static readonly LaunchedWindow Window = new(
        "hwnd:00000001",
        0,
        4242,
        "Untitled - Notepad",
        new WindowRect(0, 0, 640, 480),
        "normal",
        true
    );

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

    private sealed class ChangedThenUnchangedCapture : IWindowFrameCapture
    {
        private int attempts;

        public Task<WindowFrame> CaptureFrameAsync(
            LaunchedWindow window,
            int sequence,
            CancellationToken cancellationToken
        ) => throw new NotSupportedException("The result capture path should be used.");

        public Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
            LaunchedWindow window,
            int sequence,
            CancellationToken cancellationToken
        )
        {
            if (Interlocked.Increment(ref attempts) == 1)
            {
                return Task.FromResult(WindowFrameCaptureResult.Changed(new WindowFrame(
                    window.WindowId,
                    $"frame_{sequence:000000}",
                    sequence,
                    "png",
                    640,
                    480,
                    1,
                    "real-frame"
                )));
            }

            return Task.FromResult(WindowFrameCaptureResult.Unchanged(sequence));
        }
    }

    [Fact]
    public async Task SkipsFailedCapturesUntilARealFrameIsAvailable()
    {
        var streamer = new WindowFrameStreamer(new FailsOnceCapture(), TimeSpan.FromMilliseconds(5));
        var received = new List<WindowFrame>();
        var heartbeats = new List<int>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            Window,
            firstSequence: 1,
            (frame, _) =>
            {
                received.Add(frame);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token,
            (sequence, _) =>
            {
                heartbeats.Add(sequence);
                return Task.CompletedTask;
            }
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var frame = Assert.Single(received);
        Assert.Equal(1, frame.Sequence);
        Assert.Equal("real-frame", frame.EncodedData);
        Assert.Empty(heartbeats);
    }

    [Fact]
    public async Task EmitsHeartbeatWithoutResendingAnUnchangedFrame()
    {
        var streamer = new WindowFrameStreamer(
            new ChangedThenUnchangedCapture(),
            TimeSpan.FromMilliseconds(5)
        );
        var received = new List<WindowFrame>();
        var heartbeats = new List<int>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            Window,
            firstSequence: 1,
            (frame, _) =>
            {
                received.Add(frame);
                return Task.CompletedTask;
            },
            cancellation.Token,
            (sequence, _) =>
            {
                heartbeats.Add(sequence);
                cancellation.Cancel();
                return Task.CompletedTask;
            }
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var frame = Assert.Single(received);
        Assert.Equal(1, frame.Sequence);
        Assert.Equal(new[] { 2 }, heartbeats);
    }
}
