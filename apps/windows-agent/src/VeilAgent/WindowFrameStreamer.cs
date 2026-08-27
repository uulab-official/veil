namespace Veil.Agent;

public sealed class WindowFrameStreamer
{
    private static readonly TimeSpan CaptureTimeout = TimeSpan.FromSeconds(2);
    private readonly IWindowFrameCapture capture;
    private readonly TimeSpan? fixedInterval;
    private readonly Func<WindowFrameStreamCadence> cadenceFactory;

    /// <param name="interval">
    /// When supplied, the stream ticks on this fixed interval and never backs off. Kept for tests and
    /// for callers that need a deterministic cadence; production uses the adaptive cadence instead.
    /// </param>
    public WindowFrameStreamer(
        IWindowFrameCapture capture,
        TimeSpan? interval = null,
        Func<WindowFrameStreamCadence>? cadenceFactory = null
    )
    {
        this.capture = capture;
        this.fixedInterval = interval;
        this.cadenceFactory = cadenceFactory ?? (() => new WindowFrameStreamCadence());
    }

    /// <param name="onUnchanged">
    /// Invoked instead of <paramref name="onFrame"/> when the window's pixels did not change. Sending a
    /// liveness heartbeat here is what allows the guest to skip the encode: without it the host cannot
    /// distinguish an idle window from broken capture, and would escalate the stream into subscription
    /// restart, capture recovery, and app reopen.
    /// </param>
    /// <param name="needsFullFrame">
    /// Asked once per tick. Returns whether a legacy JSON subscriber exists, so the full-surface encode is
    /// paid for only when something is actually listening on that path.
    /// </param>
    public async Task StreamAsync(
        LaunchedWindow window,
        int firstSequence,
        Func<WindowFrameCaptureResult, CancellationToken, Task> onFrame,
        CancellationToken cancellationToken,
        Func<int, CancellationToken, Task>? onUnchanged = null,
        Func<bool>? needsFullFrame = null
    )
    {
        var sequence = firstSequence;
        var cadence = cadenceFactory();
        // `PeriodicTimer.Period` is settable on .NET 8, so the adaptive cadence can retune the same timer
        // instead of allocating a new one per tick.
        using var timer = new PeriodicTimer(fixedInterval ?? cadence.CurrentInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var result = await TryCaptureFrameAsync(
                window,
                sequence,
                needsFullFrame?.Invoke() ?? true,
                cancellationToken
            );
            if (result is null)
            {
                // Transient capture failure. Treated as "no change" for cadence purposes, but never
                // reported as a heartbeat: the host must still be able to see a stream that has stopped
                // producing anything at all.
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

            await onFrame(result, cancellationToken);
            sequence += 1;
            Retune(timer, cadence, changed: true);
        }
    }

    private void Retune(PeriodicTimer timer, WindowFrameStreamCadence cadence, bool changed)
    {
        var next = cadence.Next(changed);
        if (fixedInterval is null)
        {
            timer.Period = next;
        }
    }

    /// <summary>
    /// Releases change-detection state for a window whose stream has stopped.
    /// </summary>
    public void ForgetWindow(string windowId) => capture.ForgetWindow(windowId);

    private async Task<WindowFrameCaptureResult?> TryCaptureFrameAsync(
        LaunchedWindow window,
        int sequence,
        bool includeFullFrame,
        CancellationToken cancellationToken
    )
    {
        try
        {
            return await capture
                .CaptureFrameResultAsync(window, sequence, includeFullFrame, cancellationToken)
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
