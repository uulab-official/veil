using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;

namespace Veil.Agent;

public sealed class WindowsDesktop : IWindowsDesktop
{
    private const uint WM_CLOSE = 0x0010;

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
                    Hwnd: process.MainWindowHandle,
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

    public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(windowId, out var hwnd))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(PostMessage(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero));
    }

    private static bool TryParseWindowId(string windowId, out IntPtr hwnd)
    {
        hwnd = IntPtr.Zero;
        const string prefix = "hwnd:";

        if (!windowId.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var hex = windowId[prefix.Length..];
        if (!long.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var value))
        {
            return false;
        }

        hwnd = new IntPtr(value);
        return hwnd != IntPtr.Zero;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
