using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Hides the Windows taskbar while the host shows apps as their own Mac windows.
/// </summary>
/// <remarks>
/// The host crops each app out of the guest display. The taskbar is a topmost window along the bottom of
/// that display, so an app window reaching down there was covered by it and fell back to captured frames,
/// and the taskbar is part of the Windows desktop Coherence is meant to hide. Parallels hides it the
/// same way. The windows are only hidden, not removed, so the work area and the user's taskbar settings
/// stay as they are, and <see cref="Enforce"/> shows them again once the host stops asking (desktop view,
/// a host that went away) or the agent exits.
/// </remarks>
public static class TaskbarVisibility
{
    private static readonly string[] TaskbarClasses = { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" };
    private static readonly object Gate = new();
    private static bool hidden;
    private static bool exitHookInstalled;

    /// <summary>Hides or shows the taskbars to match <paramref name="hide"/>; cheap enough to call often.</summary>
    public static void Enforce(bool hide)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        lock (Gate)
        {
            if (hide && !exitHookInstalled)
            {
                AppDomain.CurrentDomain.ProcessExit += (_, _) => Enforce(false);
                exitHookInstalled = true;
            }
            if (!hide && !hidden)
            {
                return;
            }

            foreach (var taskbar in FindTaskbars())
            {
                // Explorer shows the taskbar again after it restarts and for some shell events, so this
                // re-hides whatever is visible rather than remembering handles.
                if (hide && IsWindowVisible(taskbar))
                {
                    ShowWindow(taskbar, SW_HIDE);
                }
                else if (!hide && !IsWindowVisible(taskbar))
                {
                    ShowWindow(taskbar, SW_SHOWNOACTIVATE);
                }
            }
            hidden = hide;
        }
    }

    private static IEnumerable<nint> FindTaskbars()
    {
        foreach (var className in TaskbarClasses)
        {
            var window = FindWindowEx(0, 0, className, null);
            while (window != 0)
            {
                yield return window;
                window = FindWindowEx(0, window, className, null);
            }
        }
    }

    private const int SW_HIDE = 0;
    private const int SW_SHOWNOACTIVATE = 4;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint FindWindowEx(nint parent, nint childAfter, string className, string? windowName);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(nint hwnd, int command);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(nint hwnd);
}
