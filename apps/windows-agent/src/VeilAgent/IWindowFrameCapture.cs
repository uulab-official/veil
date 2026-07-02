namespace Veil.Agent;

public interface IWindowFrameCapture
{
    Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken);
}
