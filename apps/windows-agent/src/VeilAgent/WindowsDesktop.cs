using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

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
    private const uint WM_KEYDOWN = 0x0100;
    private const uint WM_KEYUP = 0x0101;
    private const int MK_LBUTTON = 0x0001;
    private const int MK_RBUTTON = 0x0002;
    private const int WHEEL_DELTA = 120;
    private const int SW_RESTORE = 9;
    private const int VK_CONTROL = 0x11;
    private const int VK_SHIFT = 0x10;
    private const int VK_MENU = 0x12;
    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;
    private readonly object clipboardGate = new();
    private string? lastHostClipboardText;
    private int lastHostClipboardSequence;

    public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken)
    {
        return LaunchAppAsync(
            new WindowsAppDescriptor(
                Id: "winapp_notepad",
                Name: "Notepad",
                Executable: "notepad.exe",
                Publisher: "Microsoft",
                IconId: "icon_notepad"
            ),
            cancellationToken
        );
    }

    public async Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        var existingWindowHandles = SnapshotAppWindowHandles(app);
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = app.Executable,
            UseShellExecute = true
        }) ?? throw new InvalidOperationException($"Could not start {app.Executable}.");

        var discoveryAttempts = (int)(app.WindowDiscoveryTimeout.TotalMilliseconds / 100);
        for (var attempt = 0; attempt < discoveryAttempts; attempt += 1)
        {
            cancellationToken.ThrowIfCancellationRequested();
            process.Refresh();

            if (process.MainWindowHandle != IntPtr.Zero)
            {
                return CreateLaunchedWindow(process.MainWindowHandle, process.Id, process.MainWindowTitle, app.Name);
            }

            if (TryFindTopLevelWindow(app, process.Id, existingWindowHandles, out var launched))
            {
                return launched;
            }

            await Task.Delay(100, cancellationToken);
        }

        throw new TimeoutException($"{app.Executable} started but no top-level window was discovered.");
    }

    private static HashSet<IntPtr> SnapshotAppWindowHandles(WindowsAppDescriptor app)
    {
        var handles = new HashSet<IntPtr>();
        EnumWindows((hwnd, unused) =>
        {
            if (!IsWindowVisible(hwnd))
            {
                return true;
            }

            _ = GetWindowThreadProcessId(hwnd, out var windowProcessId);
            if (DoesProcessMatchApp(windowProcessId, app))
            {
                handles.Add(hwnd);
            }

            return true;
        }, IntPtr.Zero);

        return handles;
    }

    private static bool TryFindTopLevelWindow(
        WindowsAppDescriptor app,
        int launchedProcessId,
        HashSet<IntPtr> existingWindowHandles,
        out LaunchedWindow launched
    )
    {
        var candidates = new List<WindowCandidate>();
        EnumWindows((hwnd, unused) =>
        {
            if (!IsWindowVisible(hwnd))
            {
                return true;
            }

            _ = GetWindowThreadProcessId(hwnd, out var windowProcessId);
            var title = GetWindowTitle(hwnd);
            var matchesProcess = windowProcessId == launchedProcessId;
            var matchesExecutable = DoesProcessMatchApp(windowProcessId, app);
            var matchesTitle = !string.IsNullOrWhiteSpace(title)
                && title.Contains(app.Name, StringComparison.OrdinalIgnoreCase);

            if (matchesProcess || matchesExecutable || matchesTitle)
            {
                candidates.Add(new WindowCandidate(
                    Hwnd: hwnd,
                    ProcessId: (int)windowProcessId,
                    Title: title,
                    IsNewWindow: !existingWindowHandles.Contains(hwnd),
                    MatchesLaunchedProcess: matchesProcess,
                    MatchesExecutable: matchesExecutable,
                    MatchesTitle: matchesTitle
                ));
            }

            return true;
        }, IntPtr.Zero);

        var candidate = candidates
            .OrderByDescending(candidate => candidate.IsNewWindow)
            .ThenByDescending(candidate => candidate.MatchesLaunchedProcess)
            .ThenByDescending(candidate => candidate.MatchesExecutable)
            .ThenByDescending(candidate => candidate.MatchesTitle)
            .FirstOrDefault();

        if (candidate is null)
        {
            launched = null!;
            return false;
        }

        launched = CreateLaunchedWindow(candidate.Hwnd, candidate.ProcessId, candidate.Title, app.Name);
        return true;
    }

    internal static bool DoesProcessMatchApp(uint processId, WindowsAppDescriptor app)
    {
        try
        {
            using var process = Process.GetProcessById((int)processId);
            var candidateExecutables = (app.AlternateExecutables ?? [])
                .Append(app.Executable)
                .Select(Path.GetFileNameWithoutExtension);
            return candidateExecutables.Any(
                candidate => string.Equals(process.ProcessName, candidate, StringComparison.OrdinalIgnoreCase)
            );
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (Win32Exception)
        {
            return false;
        }
    }

    private static LaunchedWindow CreateLaunchedWindow(IntPtr hwnd, int processId, string? title, string fallbackTitle)
    {
        var resolvedTitle = string.IsNullOrWhiteSpace(title)
            ? fallbackTitle
            : title;

        return new LaunchedWindow(
            WindowId: $"hwnd:{hwnd.ToInt64():X8}",
            Hwnd: hwnd,
            ProcessId: processId,
            Title: resolvedTitle,
            Bounds: GetWindowBounds(hwnd),
            State: "normal",
            Focused: true
        );
    }

    private static string GetWindowTitle(IntPtr hwnd)
    {
        var length = GetWindowTextLength(hwnd);
        if (length <= 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(length + 1);
        _ = GetWindowText(hwnd, builder, builder.Capacity);
        return builder.ToString();
    }

    private static WindowRect GetWindowBounds(IntPtr hwnd)
    {
        if (GetWindowRect(hwnd, out var rect))
        {
            return new WindowRect(
                rect.Left,
                rect.Top,
                Math.Max(1, rect.Right - rect.Left),
                Math.Max(1, rect.Bottom - rect.Top)
            );
        }

        return new WindowRect(0, 0, 1280, 800);
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

    public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken)
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

        return Task.FromResult(EnsureWindowReadyForInput(hwnd));
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

        if (!EnsureWindowReadyForInput(hwnd))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(PostMessage(hwnd, message, wParam, lParam));
    }

    public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(input.WindowId, out var hwnd)
            || !TryResolveKeyMessage(input.Event, out var message))
        {
            return Task.FromResult(false);
        }

        if (!EnsureWindowReadyForInput(hwnd))
        {
            return Task.FromResult(false);
        }

        var accepted = true;
        if (message == WM_KEYDOWN)
        {
            foreach (var modifierVirtualKey in ModifierVirtualKeys(input.Modifiers))
            {
                accepted &= PostMessage(hwnd, WM_KEYDOWN, new IntPtr(modifierVirtualKey), IntPtr.Zero);
            }
        }

        accepted &= PostMessage(hwnd, message, new IntPtr(input.WindowsVirtualKey), IntPtr.Zero);

        if (message == WM_KEYUP)
        {
            foreach (var modifierVirtualKey in ModifierVirtualKeys(input.Modifiers).Reverse())
            {
                accepted &= PostMessage(hwnd, WM_KEYUP, new IntPtr(modifierVirtualKey), IntPtr.Zero);
            }
        }

        return Task.FromResult(accepted);
    }

    public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(() =>
        {
            SetClipboardUnicodeText(text);
            lock (clipboardGate)
            {
                lastHostClipboardText = text;
                lastHostClipboardSequence += 1;
            }
        }, cancellationToken);
    }

    public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(GetClipboardUnicodeText, cancellationToken);
    }

    public bool TryConsumeHostClipboardEcho(string text)
    {
        lock (clipboardGate)
        {
            if (lastHostClipboardSequence <= 0 || lastHostClipboardText != text)
            {
                return false;
            }

            lastHostClipboardText = null;
            return true;
        }
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

    private static bool TryResolveKeyMessage(string eventName, out uint message)
    {
        message = eventName switch
        {
            "keyDown" => WM_KEYDOWN,
            "keyUp" => WM_KEYUP,
            _ => 0
        };

        return message != 0;
    }

    private static bool EnsureWindowReadyForInput(IntPtr hwnd)
    {
        if (!IsWindow(hwnd))
        {
            return false;
        }

        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
        SetFocus(hwnd);
        return true;
    }

    private static IEnumerable<int> ModifierVirtualKeys(IReadOnlyList<string> modifiers)
    {
        foreach (var modifier in modifiers)
        {
            switch (modifier)
            {
                case "ctrl":
                    yield return VK_CONTROL;
                    break;
                case "shift":
                    yield return VK_SHIFT;
                    break;
                case "alt":
                    yield return VK_MENU;
                    break;
            }
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetFocus(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out NativeRect lpRect);

    private static void SetClipboardUnicodeText(string text)
    {
        OpenClipboardWithRetry();
        IntPtr handle = IntPtr.Zero;
        try
        {
            if (!EmptyClipboard())
            {
                ThrowLastWin32Error("EmptyClipboard failed.");
            }

            var bytes = Encoding.Unicode.GetBytes(text + "\0");
            handle = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
            if (handle == IntPtr.Zero)
            {
                ThrowLastWin32Error("GlobalAlloc failed for clipboard text.");
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                ThrowLastWin32Error("GlobalLock failed for clipboard text.");
            }

            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }

            if (SetClipboardData(CF_UNICODETEXT, handle) == IntPtr.Zero)
            {
                ThrowLastWin32Error("SetClipboardData failed for clipboard text.");
            }

            handle = IntPtr.Zero;
        }
        finally
        {
            CloseClipboard();
            if (handle != IntPtr.Zero)
            {
                _ = GlobalFree(handle);
            }
        }
    }

    private static string? GetClipboardUnicodeText()
    {
        OpenClipboardWithRetry();
        try
        {
            if (!IsClipboardFormatAvailable(CF_UNICODETEXT))
            {
                return null;
            }

            var handle = GetClipboardData(CF_UNICODETEXT);
            if (handle == IntPtr.Zero)
            {
                return null;
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                return Marshal.PtrToStringUni(pointer);
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }
        }
        finally
        {
            CloseClipboard();
        }
    }

    private static void OpenClipboardWithRetry()
    {
        for (var attempt = 0; attempt < 10; attempt += 1)
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                return;
            }

            Thread.Sleep(25);
        }

        ThrowLastWin32Error("OpenClipboard failed.");
    }

    private static void ThrowLastWin32Error(string message)
    {
        throw new Win32Exception(Marshal.GetLastWin32Error(), message);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsClipboardFormatAvailable(uint format);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private sealed record WindowCandidate(
        IntPtr Hwnd,
        int ProcessId,
        string Title,
        bool IsNewWindow,
        bool MatchesLaunchedProcess,
        bool MatchesExecutable,
        bool MatchesTitle
    );
}
