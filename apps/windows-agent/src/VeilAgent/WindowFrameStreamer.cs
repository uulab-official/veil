namespace Veil.Agent;

public sealed class WindowFrameStreamer
{
    private static readonly TimeSpan CaptureTimeout = TimeSpan.FromSeconds(2);
    private readonly IWindowFrameCapture capture;
    private readonly TimeSpan? fixedInterval;
    private readonly Func<WindowFrameStreamCadence> cadenceFactory;

    public WindowFrameStreamer(
        IWindowFrameCapture capture,
        TimeSpan? interval = null,
        Func<WindowFrameStreamCadence>? cadenceFactory = null
    )
    {
        this.capture = capture;
        fixedInterval = interval;
        this.cadenceFactory = cadenceFactory ?? (() => new WindowFrameStreamCadence());
    }

    public async Task StreamAsync(
        LaunchedWindow window,
        int firstSequence,
        Func<WindowFrame, CancellationToken, Task> onFrame,
        CancellationToken cancellationToken,
        Func<int, CancellationToken, Task>? onUnchanged = null
    )
    {
        var sequence = firstSequence;
        var cadence = cadenceFactory();
        using var timer = new PeriodicTimer(fixedInterval ?? cadence.CurrentInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var result = await TryCaptureFrameAsync(window, sequence, cancellationToken);
            if (result is null)
            {
                Retune(timer, cadence, changed: false);
                continue;
            }

            if (result.IsUnchanged)
            {
                if (onUnchanged is not null)
                {
                    await onUnchanged(sequence, cancellationToken);
                }

                Retune(timer, cadence, changed: false);
                continue;
            }

            await onFrame(result.Frame!, cancellationToken);
            sequence += 1;
            Retune(timer, cadence, changed: true);
        }
    }

    public void ForgetWindow(string windowId) => capture.ForgetWindow(windowId);

    private void Retune(PeriodicTimer timer, WindowFrameStreamCadence cadence, bool changed)
    {
        var next = cadence.Next(changed);
        if (fixedInterval is null)
        {
            timer.Period = next;
        }
    }

    private async Task<WindowFrameCaptureResult?> TryCaptureFrameAsync(
        LaunchedWindow window,
        int sequence,
        CancellationToken cancellationToken
    )
    {
        try
        {
            return await capture
                .CaptureFrameResultAsync(window, sequence, cancellationToken)
                .WaitAsync(CaptureTimeout, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(
                $"Frame stream capture failed for {window.WindowId}; waiting for the next real frame. {error.GetType().Name}: {error.Message}"
            );
            return null;
        }
    }
}
