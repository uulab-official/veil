using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Declares the agent process as Per-Monitor-V2 DPI aware. Without this, Windows treats an
/// unaware process as running at a virtualized 96 DPI and silently scales every GetWindowRect/
/// PrintWindow result to match -- <see cref="GdiWindowFrameCapture"/> would capture a blurry,
/// upscaled bitmap even from a window that's actually rendering crisply at a higher DPI, and
/// GetDpiForWindow would always report 96 regardless of the window's real scale.
/// </summary>
public static class ProcessDpiAwareness
{
    private static readonly nint DpiAwarenessContextPerMonitorAwareV2 = -4;

    public static void EnablePerMonitorV2()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        try
        {
            // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 requires Windows 10 version 1703 or later
            // per https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setprocessdpiawarenesscontext --
            // on an older build this call fails and the agent still runs, just without accurate
            // DPI-aware capture.
            _ = SetProcessDpiAwarenessContext(DpiAwarenessContextPerMonitorAwareV2);
        }
        catch (EntryPointNotFoundException)
        {
            Console.Error.WriteLine(
                "ProcessDpiAwareness: SetProcessDpiAwarenessContext is unavailable on this Windows build; frame capture will use virtualized 96 DPI."
            );
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetProcessDpiAwarenessContext(nint dpiAwarenessContext);
}
