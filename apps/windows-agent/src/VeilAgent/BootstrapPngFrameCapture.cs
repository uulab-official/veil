namespace Veil.Agent;

public sealed class BootstrapPngFrameCapture : IWindowFrameCapture
{
    private const string OnePixelPng =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=";

    public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken)
    {
        return Task.FromResult(new WindowFrame(
            WindowId: window.WindowId,
            FrameId: $"frame_{sequence:000000}",
            Sequence: sequence,
            Format: "png",
            Width: 1,
            Height: 1,
            // Scale is meaningless for this synthetic 1x1 placeholder (it isn't a real capture of
            // any window's actual DPI), so it's left at 1 rather than querying GetWindowScale.
            Scale: 1,
            EncodedData: OnePixelPng
        ));
    }
}
