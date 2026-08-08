namespace Veil.Agent;

public interface IWindowFrameCapture
{
    Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken);

    async Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
        LaunchedWindow window,
        int sequence,
        CancellationToken cancellationToken
    ) => WindowFrameCaptureResult.Changed(
        await CaptureFrameAsync(window, sequence, cancellationToken)
    );

    void ForgetWindow(string windowId)
    {
    }
}
