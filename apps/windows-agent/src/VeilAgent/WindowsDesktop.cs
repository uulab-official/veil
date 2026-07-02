using System.Diagnostics;

namespace Veil.Agent;

public sealed class WindowsDesktop : IWindowsDesktop
{
    public async Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "notepad.exe",
            UseShellExecute = true
        }) ?? throw new InvalidOperationException("Could not start notepad.exe.");

        for (var attempt = 0; attempt < 50; attempt += 1)
        {
            cancellationToken.ThrowIfCancellationRequested();
            process.Refresh();

            if (process.MainWindowHandle != IntPtr.Zero)
            {
                var title = string.IsNullOrWhiteSpace(process.MainWindowTitle)
                    ? "Untitled - Notepad"
                    : process.MainWindowTitle;

                return new LaunchedWindow(
                    WindowId: $"hwnd:{process.MainWindowHandle.ToInt64():X8}",
                    ProcessId: process.Id,
                    Title: title,
                    Bounds: new WindowRect(0, 0, 1280, 800),
                    State: "normal",
                    Focused: true
                );
            }

            await Task.Delay(100, cancellationToken);
        }

        throw new TimeoutException("notepad.exe started but no top-level window was discovered.");
    }
}
