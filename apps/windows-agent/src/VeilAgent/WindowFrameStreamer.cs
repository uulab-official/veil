namespace Veil.Agent;

public sealed class WindowFrameStreamer
{
    private static readonly TimeSpan CaptureTimeout = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan ImmediateCaptureDelay = TimeSpan.FromMilliseconds(1);
    private readonly IWindowFrameCapture capture;
    private readonly TimeSpan? fixedInterval;
    private readonly Func<WindowFrameStreamCadence> cadenceFactory;
    private readonly DisplayKeepAwake keepAwake;
    private readonly Func<bool> inputDesktopIsSecure;
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, Action> wakers = new();

    /// <param name="interval">
    /// When supplied, the stream ticks on this fixed interval and never backs off. Kept for tests and
    /// for callers that need a deterministic cadence; production uses the adaptive cadence instead.
    /// </param>
    public WindowFrameStreamer(
        IWindowFrameCapture capture,
        TimeSpan? interval = null,
        Func<WindowFrameStreamCadence>? cadenceFactory = null,
        DisplayKeepAwake? keepAwake = null,
        Func<bool>? inputDesktopIsSecure = null
    )
    {
        this.capture = capture;
        this.fixedInterval = interval;
        this.cadenceFactory = cadenceFactory ?? (() => new WindowFrameStreamCadence());
        this.keepAwake = keepAwake ?? DisplayKeepAwake.None;
        this.inputDesktopIsSecure = inputDesktopIsSecure ?? InputDesktop.IsSecure;
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
        // A powered-off display stops apps from redrawing, so a mirrored window would freeze at its
        // last composed pixels.
        using var displayHold = keepAwake.Hold();
        // Held only while this stream ticks fast; see TimerResolutionLease.
        using var timerResolution = new TimerResolutionLease();
        var sequence = firstSequence;
        var cadence = cadenceFactory();
        var cadenceGate = new object();
        // `PeriodicTimer.Period` is settable on .NET 8, so the adaptive cadence can retune the same timer
        // instead of allocating a new one per tick. Setting it also restarts the wait from now, which is
        // what lets `Wake` cut an idle wait short.
        using var timer = new PeriodicTimer(fixedInterval ?? cadence.CurrentInterval);
        timerResolution.SetInterval(timer.Period);
        Action wake = () =>
        {
            lock (cadenceGate)
            {
                cadence.Wake();
                // Capture right away rather than at the next tick: input usually changes the window within a
                // frame, and the tick after this capture returns to the active interval through Retune.
                // A window the host crops from the framebuffer already shows the change there.
                if (fixedInterval is null && !FramebufferCropRegistry.IsCropped(window.WindowId))
                {
                    timer.Period = ImmediateCaptureDelay;
                    timerResolution.SetInterval(timer.Period);
                }
            }
        };
        using var wakeRegistration = RegisterWaker(window.WindowId, wake);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            if (inputDesktopIsSecure())
            {
                // A User Account Control prompt or the lock screen has the display. A screen copy fails
                // there and the window cannot change under the user's hands, so nothing is captured. The
                // heartbeat still goes out: a prompt left unanswered for a minute must not look like a
                // broken stream, which the host answers by restarting capture.
                if (onUnchanged is not null)
                {
                    await onUnchanged(sequence, cancellationToken);
                }

                Retune(timer, timerResolution, cadence, cadenceGate, window.WindowId, changed: false);
                continue;
            }

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
                Retune(timer, timerResolution, cadence, cadenceGate, window.WindowId, changed: false);
                continue;
            }

            if (result.IsUnchanged)
            {
                if (onUnchanged is not null)
                {
                    await onUnchanged(sequence, cancellationToken);
                }

                Retune(timer, timerResolution, cadence, cadenceGate, window.WindowId, changed: false);
                continue;
            }

            await onFrame(result, cancellationToken);
            sequence += 1;
            Retune(timer, timerResolution, cadence, cadenceGate, window.WindowId, changed: true);
        }
    }

    /// <summary>
    /// Moves the window's stream to its active cadence; see <see cref="WindowFrameStreamCadence.Wake"/>.
    /// Does nothing for a window that is not streaming.
    /// </summary>
    public void Wake(string windowId)
    {
        if (wakers.TryGetValue(windowId, out var wake))
        {
            wake();
        }
    }

    private void Retune(
        PeriodicTimer timer,
        TimerResolutionLease timerResolution,
        WindowFrameStreamCadence cadence,
        object cadenceGate,
        string windowId,
        bool changed)
    {
        lock (cadenceGate)
        {
            var next = cadence.Next(changed);
            if (fixedInterval is null)
            {
                timer.Period = FramebufferCropRegistry.IsCropped(windowId) && next < FramebufferCropRegistry.CroppedInterval
                    ? FramebufferCropRegistry.CroppedInterval
                    : next;
            }
            timerResolution.SetInterval(timer.Period);
        }
    }

    /// <summary>
    /// Registers a stream's waker, removed when the stream ends unless a newer stream for the same window
    /// has already replaced it.
    /// </summary>
    private IDisposable RegisterWaker(string windowId, Action wake)
    {
        wakers[windowId] = wake;
        return new WakerRegistration(() => wakers.TryRemove(new KeyValuePair<string, Action>(windowId, wake)));
    }

    private sealed class WakerRegistration(Action unregister) : IDisposable
    {
        public void Dispose() => unregister();
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
