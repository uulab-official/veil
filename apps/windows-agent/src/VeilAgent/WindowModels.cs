namespace Veil.Agent;

public sealed record WindowRect(int X, int Y, int Width, int Height);

public sealed record WindowsAppDescriptor(
    string Id,
    string Name,
    string Executable,
    string Publisher,
    string IconId,
    string[]? AlternateExecutables = null,
    TimeSpan? WindowDiscoveryTimeoutOverride = null
)
{
    /// <summary>
    /// How long <see cref="WindowsDesktop.LaunchAppAsync"/> polls for a top-level window before
    /// giving up. Packaged (MSIX/UWP) apps like Windows 11's Calculator can take noticeably longer
    /// to cold-activate their window than native Win32 apps, so this is overridable per app rather
    /// than a single global constant.
    /// </summary>
    public TimeSpan WindowDiscoveryTimeout => WindowDiscoveryTimeoutOverride ?? TimeSpan.FromSeconds(5);
}

public sealed record LaunchedWindow(
    string WindowId,
    nint Hwnd,
    int ProcessId,
    string Title,
    WindowRect Bounds,
    string State,
    bool Focused
);

public sealed record WindowFrame(
    string WindowId,
    string FrameId,
    int Sequence,
    string Format,
    int Width,
    int Height,
    double Scale,
    string EncodedData
);

/// <summary>
/// Outcome of one successful capture tick: a changed frame or unchanged pixels.
/// </summary>
public sealed record WindowFrameCaptureResult(WindowFrame? Frame, int Sequence)
{
    public bool IsUnchanged => Frame is null;

    public static WindowFrameCaptureResult Changed(WindowFrame frame) => new(frame, frame.Sequence);

    public static WindowFrameCaptureResult Unchanged(int sequence) => new(null, sequence);
}

public sealed record WindowMouseInput(
    string WindowId,
    string Event,
    int X,
    int Y,
    IReadOnlyList<string> Modifiers
);

public sealed record WindowKeyInput(
    string WindowId,
    string Event,
    string Key,
    int WindowsVirtualKey,
    IReadOnlyList<string> Modifiers
);
