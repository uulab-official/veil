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
        var received = new List<WindowFrame>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            window,
            firstSequence: 1,
            (frame, _) =>
            {
                received.Add(frame);
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        var frame = Assert.Single(received);
        Assert.Equal(1, frame.Sequence);
        Assert.Equal("real-frame", frame.EncodedData);
    }
}
