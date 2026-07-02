using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;

namespace Veil.Agent;

public sealed class WindowsDesktop : IWindowsDesktop
{
    private const uint WM_CLOSE = 0x0010;
    private const uint WM_MOUSEMOVE = 0x0200;
    private const uint WM_LBUTTONDOWN = 0x0201;
    private const uint WM_LBUTTONUP = 0x0202;
    private const uint WM_RBUTTONDOWN = 0x0204;
    private const uint WM_RBUTTONUP = 0x0205;
    private const uint WM_MOUSEWHEEL = 0x020A;
    private const int MK_LBUTTON = 0x0001;
    private const int MK_RBUTTON = 0x0002;
    private const int WHEEL_DELTA = 120;

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

    public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(input.WindowId, out var hwnd)
            || !TryResolveMouseMessage(input, out var message, out var wParam, out var lParam))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(PostMessage(hwnd, message, wParam, lParam));
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

    private static bool TryResolveMouseMessage(
        WindowMouseInput input,
        out uint message,
        out IntPtr wParam,
        out IntPtr lParam
    )
    {
        message = input.Event switch
        {
            "leftDown" => WM_LBUTTONDOWN,
            "leftUp" => WM_LBUTTONUP,
            "rightDown" => WM_RBUTTONDOWN,
            "rightUp" => WM_RBUTTONUP,
            "move" => WM_MOUSEMOVE,
            "scroll" => WM_MOUSEWHEEL,
            _ => 0
        };

        if (message == 0)
        {
            wParam = IntPtr.Zero;
            lParam = IntPtr.Zero;
            return false;
        }

        wParam = input.Event switch
        {
            "leftDown" => new IntPtr(MK_LBUTTON),
            "rightDown" => new IntPtr(MK_RBUTTON),
            "scroll" => new IntPtr(WHEEL_DELTA << 16),
            _ => IntPtr.Zero
        };
        lParam = MakeLParam(input.X, input.Y);
        return true;
    }

    private static IntPtr MakeLParam(int x, int y)
    {
        var packed = (y & 0xFFFF) << 16 | (x & 0xFFFF);
        return new IntPtr(packed);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
