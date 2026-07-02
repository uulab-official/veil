namespace Veil.Agent;

public interface IWindowFrameCapture
{
    Task<WindowFrame> CaptureFirstFrameAsync(LaunchedWindow window, CancellationToken cancellationToken);
}
