using System.Runtime.InteropServices;
using System.Text;

namespace Veil.Agent;

/// <summary>What Windows says about one top-level window, enough to decide whether it is an app's window.</summary>
public sealed record TopLevelWindowFacts(
    bool Visible,
    bool Minimized,
    bool Cloaked,
    bool HasOwner,
    bool ToolWindow,
    bool AppWindow,
    bool NoActivate,
    string ClassName,
    string Title,
    string ProcessName
);

/// <summary>
/// An app window found on the desktop that nothing launched through the agent: opened from inside Windows,
/// by another app, or before the agent started.
/// </summary>
public sealed record DiscoveredAppWindow(
    LaunchedWindow Window,
    string ProcessName,
    // Null when Windows does not let the agent read it, as for an elevated process.
    string? ExecutablePath,
    // Set for a packaged app, whose window can belong to ApplicationFrameHost.exe.
    string? AppUserModelId
);

/// <summary>
/// Which top-level windows are an app's own windows, as opposed to parts of the Windows shell. The rule is
/// the one the taskbar and Alt+Tab use, plus the shell's own windows that pass it.
/// </summary>
public static class AppWindowRules
{
    // The desktop, the taskbar, and the shell's flyouts. Start, Search, and the notification center are
    // Windows.UI.Core.CoreWindow windows; Task View and the snap layouts are XAML island hosts.
    private static readonly HashSet<string> ShellClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "NotifyIconOverflowWindow",
        "TopLevelWindowForOverflowXamlIsland",
        "XamlExplorerHostIslandWindow",
        "Windows.UI.Core.CoreWindow",
        "ApplicationManager_ImmersiveShellWindow",
        "MultitaskingViewFrame",
        "ForegroundStaging",
        "EdgeUiInputTopWndClass",
        "Shell_InputSwitchTopLevelWindow",
        "LockScreenBackstopFrame",
        "TaskListThumbnailWnd"
    };

    // Shell processes whose windows pass the Alt+Tab rule while they are showing: the touch keyboard and
    // emoji panel, Start, Search, the notification center, and the lock screen.
    private static readonly HashSet<string> ShellProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "TextInputHost",
        "StartMenuExperienceHost",
        "SearchHost",
        "SearchApp",
        "ShellExperienceHost",
        "ShellHost",
        "LockApp",
        "LogonUI"
    };

    /// <summary>Whether the window is part of the Windows shell rather than an app.</summary>
    public static bool IsShellWindow(string className, string processName) =>
        ShellClasses.Contains(className) || ShellProcesses.Contains(processName);

    /// <summary>
    /// Whether the window should get a Mac window of its own. Minimized windows are left out: they have no
    /// frame to show until they are restored.
    /// </summary>
    public static bool IsAppWindow(TopLevelWindowFacts facts)
    {
        if (!facts.Visible || facts.Minimized || facts.Cloaked)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(facts.Title) || IsShellWindow(facts.ClassName, facts.ProcessName))
        {
            return false;
        }

        // WS_EX_APPWINDOW puts a window on the taskbar whatever else is set. Without it, tool windows,
        // owned windows, and windows that never take focus are not apps' main windows.
        return facts.AppWindow || (!facts.ToolWindow && !facts.HasOwner && !facts.NoActivate);
    }
}

/// <summary>Finds every app window on the Windows desktop.</summary>
internal static class DesktopAppWindowScanner
{
    /// <summary>
    /// App windows not in <paramref name="knownWindowIds"/>, front to back. The agent's own windows are
    /// left out.
    /// </summary>
    public static IReadOnlyList<DiscoveredAppWindow> Scan(
        IReadOnlySet<string> knownWindowIds,
        Func<nint, int, string, LaunchedWindow> createWindow
    )
    {
        var found = new List<DiscoveredAppWindow>();
        var ownProcessId = (uint)Environment.ProcessId;
        _ = EnumWindows((hwnd, unused) =>
        {
            // Checked first: most top-level windows are hidden helper windows.
            if (!IsWindowVisible(hwnd) || knownWindowIds.Contains(WindowId(hwnd)))
            {
                return true;
            }

            _ = GetWindowThreadProcessId(hwnd, out var processId);
            if (processId == 0 || processId == ownProcessId)
            {
                return true;
            }

            var executablePath = ExecutablePath(processId);
            var processName = executablePath is null
                ? ProcessNameFallback(processId)
                : Path.GetFileNameWithoutExtension(executablePath);
            var title = Title(hwnd);
            var facts = Facts(hwnd, title, processName);
            if (!AppWindowRules.IsAppWindow(facts))
            {
                return true;
            }

            found.Add(new DiscoveredAppWindow(
                Window: createWindow(hwnd, (int)processId, title),
                ProcessName: processName,
                ExecutablePath: executablePath,
                AppUserModelId: PackagedAppActivation.AppUserModelIdForWindow(hwnd, processId)
            ));
            return true;
        }, IntPtr.Zero);

        return found;
    }

    /// <summary>
    /// Whether a visible window of an app that already has a tracked window is worth reporting: another app
    /// window, or a window one of them owns, such as a dialog, a menu, or a tooltip. Programs also keep
    /// unowned helper windows visible, File Explorer several of one pixel, which are neither.
    /// </summary>
    public static bool IsAppOrOwnedWindow(nint hwnd)
    {
        if (!OperatingSystem.IsWindows())
        {
            return true;
        }

        var facts = Facts(hwnd, Title(hwnd), string.Empty);
        if (facts.Minimized || facts.Cloaked || AppWindowRules.IsShellWindow(facts.ClassName, string.Empty))
        {
            return false;
        }

        return facts.HasOwner || AppWindowRules.IsAppWindow(facts);
    }

    /// <summary>
    /// Whether a window could be the one an app launch opened. Like <see cref="IsAppOrOwnedWindow"/>, but a
    /// main window may not have its title yet when it first appears, so an untitled window counts when it is
    /// large enough to be one. File Explorer's untitled helper windows are one pixel.
    /// </summary>
    public static bool IsLaunchCandidate(nint hwnd)
    {
        if (!OperatingSystem.IsWindows() || IsAppOrOwnedWindow(hwnd))
        {
            return true;
        }

        var facts = Facts(hwnd, UntitledPlaceholder, string.Empty);
        return AppWindowRules.IsAppWindow(facts)
            && GetWindowRect(hwnd, out var rect)
            && rect.Right - rect.Left >= MinimumUntitledSide
            && rect.Bottom - rect.Top >= MinimumUntitledSide;
    }

    private const string UntitledPlaceholder = "-";
    private const int MinimumUntitledSide = 64;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out NativeRect rect);

    private static TopLevelWindowFacts Facts(nint hwnd, string title, string processName)
    {
        var extendedStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        return new TopLevelWindowFacts(
            Visible: IsWindowVisible(hwnd),
            Minimized: IsIconic(hwnd),
            Cloaked: DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out var cloaked, sizeof(int)) == 0 && cloaked != 0,
            HasOwner: GetWindow(hwnd, GW_OWNER) != IntPtr.Zero,
            ToolWindow: (extendedStyle & WS_EX_TOOLWINDOW) != 0,
            AppWindow: (extendedStyle & WS_EX_APPWINDOW) != 0,
            NoActivate: (extendedStyle & WS_EX_NOACTIVATE) != 0,
            ClassName: ClassName(hwnd),
            Title: title,
            ProcessName: processName
        );
    }

    /// <summary>The window's class, for telling shell windows from an app's.</summary>
    public static string ClassName(nint hwnd)
    {
        if (!OperatingSystem.IsWindows())
        {
            return string.Empty;
        }

        var builder = new StringBuilder(256);
        return GetClassName(hwnd, builder, builder.Capacity) > 0 ? builder.ToString() : string.Empty;
    }

    /// <summary>
    /// The process's image path. PROCESS_QUERY_LIMITED_INFORMATION is granted for elevated and protected
    /// processes that <c>Process.MainModule</c> cannot open.
    /// </summary>
    public static string? ExecutablePath(uint processId)
    {
        var process = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (process == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var capacity = 1024u;
            var builder = new StringBuilder((int)capacity);
            return QueryFullProcessImageName(process, 0, builder, ref capacity) ? builder.ToString() : null;
        }
        finally
        {
            _ = CloseHandle(process);
        }
    }

    private static string ProcessNameFallback(uint processId)
    {
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException)
        {
            return string.Empty;
        }
    }

    private static string Title(nint hwnd)
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

    private static string WindowId(nint hwnd) => $"hwnd:{hwnd.ToInt64():X8}";

    private const int GW_OWNER = 4;
    private const int GWL_EXSTYLE = -20;
    private const long WS_EX_TOOLWINDOW = 0x00000080;
    private const long WS_EX_APPWINDOW = 0x00040000;
    private const long WS_EX_NOACTIVATE = 0x08000000;
    private const int DWMWA_CLOAKED = 14;
    private const uint ProcessQueryLimitedInformation = 0x1000;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);

    [DllImport("kernel32.dll")]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref uint size);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
}
