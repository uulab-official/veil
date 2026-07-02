namespace Veil.Agent;

public sealed class BootstrapPngFrameCapture : IWindowFrameCapture
{
    private const string OnePixelPng =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=";

    public Task<WindowFrame> CaptureFirstFrameAsync(LaunchedWindow window, CancellationToken cancellationToken)
    {
        return Task.FromResult(new WindowFrame(
            WindowId: window.WindowId,
            FrameId: "frame_000001",
            Sequence: 1,
            Format: "png",
            Width: 1,
            Height: 1,
            Scale: 1,
            EncodedData: OnePixelPng
        ));
    }
}
