namespace Veil.Agent;

public sealed class WindowFrameStreamer
{
    private readonly IWindowFrameCapture capture;
    private readonly TimeSpan interval;

    public WindowFrameStreamer(IWindowFrameCapture capture, TimeSpan? interval = null)
    {
        this.capture = capture;
        this.interval = interval ?? TimeSpan.FromMilliseconds(250);
    }

    public async Task StreamAsync(
        LaunchedWindow window,
        int firstSequence,
        Func<WindowFrame, CancellationToken, Task> onFrame,
        CancellationToken cancellationToken
    )
    {
        var sequence = firstSequence;
        using var timer = new PeriodicTimer(interval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var frame = await capture.CaptureFrameAsync(window, sequence, cancellationToken);
            await onFrame(frame, cancellationToken);
            sequence += 1;
        }
    }
}
