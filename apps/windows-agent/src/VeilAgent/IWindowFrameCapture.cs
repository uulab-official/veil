namespace Veil.Agent;

public interface IWindowFrameCapture
{
    Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken);

    /// <summary>
    /// Captures a frame, or reports that the window's pixels are byte-for-byte unchanged.
    /// </summary>
    /// <remarks>
    /// Declared with a default implementation so existing capture implementations and test doubles keep
    /// working: they simply always report a change, which is the pre-existing behavior of encoding and
    /// sending every tick. Only an implementation that can compare against the previous pixel buffer
    /// should override this.
    /// </remarks>
    async Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
        LaunchedWindow window,
        int sequence,
        CancellationToken cancellationToken
    ) => WindowFrameCaptureResult.Changed(await CaptureFrameAsync(window, sequence, cancellationToken));

    /// <summary>
    /// Captures a frame, optionally skipping the full-surface encode when only a tile is needed.
    /// </summary>
    /// <remarks>
    /// Default ignores <paramref name="includeFullFrame"/> and always produces a full frame, which is the
    /// pre-existing behavior for implementations that cannot compute a changed region.
    /// </remarks>
    Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
        LaunchedWindow window,
        int sequence,
        bool includeFullFrame,
        CancellationToken cancellationToken
    ) => CaptureFrameResultAsync(window, sequence, cancellationToken);

    /// <summary>
    /// Releases any per-window state retained for change detection.
    /// </summary>
    /// <remarks>
    /// Without this an implementation that retains a previous full-window pixel buffer would hold it for
    /// the rest of the agent process's lifetime after the window closed. Also guarantees a restarted
    /// stream begins with a full frame rather than comparing against a previous session's pixels.
    /// No-op by default for implementations that keep no state.
    /// </remarks>
    void ForgetWindow(string windowId)
    {
    }
}
