namespace Veil.Agent;

public sealed record WindowRect(int X, int Y, int Width, int Height);

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
