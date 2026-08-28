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

/// <summary>
/// Committed Unicode text for a tracked window.
/// </summary>
/// <remarks>
/// <see cref="WindowKeyInput"/> carries a Windows virtual key, which cannot express characters
/// outside the virtual key map -- every Hangul syllable, kana, and Han character. The macOS host owns
/// the IME and sends only finished text, so this record never carries in-progress composition.
/// </remarks>
public sealed record WindowTextInput(
    string WindowId,
    string Text
);

public sealed record WindowResizeInput(
    string WindowId,
    int Width,
    int Height
);

/// <summary>
/// Outcome of one capture tick: either a frame to send, or proof that nothing changed.
/// </summary>
/// <remarks>
/// The "unchanged" case is what lets the agent stop paying for a full-window PNG encode plus a base64
/// expansion several times a second on a window nobody is touching. The host distinguishes it from
/// broken capture through the <c>window.frame.unchanged</c> heartbeat, so backing off does not trip
/// stream recovery.
/// </remarks>
public sealed record WindowFrameCaptureResult(
    WindowFrame? Frame,
    int Sequence,
    WindowFrameTile? Tile = null
)
{
    public bool IsUnchanged => Frame is null && Tile is null;

    public static WindowFrameCaptureResult Changed(WindowFrame frame) =>
        new(frame, frame.Sequence);

    public static WindowFrameCaptureResult Changed(WindowFrame? frame, WindowFrameTile tile) =>
        new(frame, tile.Sequence, tile);

    public static WindowFrameCaptureResult Unchanged(int sequence) =>
        new(null, sequence);
}

/// <summary>
/// Region of a window surface, in guest pixels, with a top-left origin.
/// </summary>
public sealed record WindowFrameTileRect(
    int X,
    int Y,
    int Width,
    int Height
)
{
    public bool Covers(int surfaceWidth, int surfaceHeight) =>
        X == 0 && Y == 0 && Width == surfaceWidth && Height == surfaceHeight;
}

/// <summary>
/// One frame update: a key frame carrying the whole surface, or a tile carrying only the region that
/// changed since the previous capture.
/// </summary>
/// <remarks>
/// Sending only the changed region is the point. Typing one character in a 1920x1080 window used to
/// re-encode 2 million pixels to deliver a caret and a glyph.
///
/// A key frame's rectangle always covers the whole surface: the host has nothing to composite onto until
/// one arrives, so a partial key frame would leave undefined pixels with no way to detect it.
/// </remarks>
public sealed record WindowFrameTile(
    string WindowId,
    int Sequence,
    int SurfaceWidth,
    int SurfaceHeight,
    double Scale,
    bool IsKeyFrame,
    WindowFrameTileRect Rect,
    string EncodedData
);
