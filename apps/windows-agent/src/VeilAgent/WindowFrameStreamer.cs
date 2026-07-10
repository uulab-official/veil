namespace Veil.Agent;

public sealed class WindowFrameStreamer
{
    private static readonly TimeSpan CaptureTimeout = TimeSpan.FromSeconds(2);
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
            var frame = await TryCaptureFrameAsync(window, sequence, cancellationToken);
            if (frame is null)
            {
                continue;
            }

            await onFrame(frame, cancellationToken);
            sequence += 1;
        }
    }

    private async Task<WindowFrame?> TryCaptureFrameAsync(
        LaunchedWindow window,
        int sequence,
        CancellationToken cancellationToken
    )
    {
        try
        {
            return await capture
                .CaptureFrameAsync(window, sequence, cancellationToken)
                .WaitAsync(CaptureTimeout, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"Frame stream capture failed for {window.WindowId}; waiting for the next real frame. {error.GetType().Name}: {error.Message}"
            );
            return null;
        }
    }
}
