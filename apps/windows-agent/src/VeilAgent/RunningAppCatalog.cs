using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// Finds the app a window on the desktop belongs to. A window of an app in the catalog is reported under
/// that app. Any other window gets an app made from its program, so every Windows window has an app on the
/// Mac, as every window has a taskbar button in Windows.
/// </summary>
public static class RunningAppCatalog
{
    /// <summary>
    /// Ids of apps known only from a window start with this, so they cannot collide with the built-in
    /// <c>winapp_</c> ids or the Start menu's <c>start_</c> ids.
    /// </summary>
    public const string IdPrefix = "proc_";

    // The frame UWP apps are shown in. Its own name says nothing about the app inside.
    private const string FrameHostProcessName = "ApplicationFrameHost";

    /// <summary>
    /// The catalog app the window belongs to, or null. A packaged app is matched by AppUserModelID first,
    /// because its window can belong to ApplicationFrameHost.exe. Then the program's full path, then its file
    /// name, which is all the built-in apps declare.
    /// </summary>
    public static WindowsAppDescriptor? Match(DiscoveredAppWindow window, IReadOnlyList<WindowsAppDescriptor> apps)
    {
        if (window.AppUserModelId is { Length: > 0 } aumid)
        {
            var packaged = apps.FirstOrDefault(app =>
                string.Equals(app.LaunchAumid, aumid, StringComparison.OrdinalIgnoreCase)
                || string.Equals(app.AppUserModelId, aumid, StringComparison.OrdinalIgnoreCase));
            if (packaged is not null)
            {
                return packaged;
            }
        }

        if (string.Equals(window.ProcessName, FrameHostProcessName, StringComparison.OrdinalIgnoreCase))
        {
            // An unknown UWP app: matching by program would call every one of them the same app.
            return null;
        }

        if (window.ExecutablePath is { Length: > 0 } path)
        {
            var sameProgram = apps
                .Where(app => string.Equals(app.Executable, path, StringComparison.OrdinalIgnoreCase))
                // Several shortcuts can start one program with different arguments. The plain one is the app.
                .OrderBy(app => string.IsNullOrEmpty(app.ShortcutArguments) ? 0 : 1)
                .FirstOrDefault();
            if (sameProgram is not null)
            {
                return sameProgram;
            }
        }

        if (window.ProcessName.Length == 0)
        {
            return null;
        }

        return apps
            .Where(app => app.LaunchAumid is null && WindowsDesktop.CandidateProcessNames(app).Any(
                name => string.Equals(name, window.ProcessName, StringComparison.OrdinalIgnoreCase)))
            .OrderBy(app => string.IsNullOrEmpty(app.ShortcutArguments) ? 0 : 1)
            .FirstOrDefault();
    }

    /// <summary>
    /// An app for a window that matches nothing in the catalog. The id depends only on the program, so every
    /// window of the program is the same app and a Mac launcher made for it keeps working.
    /// </summary>
    /// <param name="fileDescription">
    /// Reads the name Windows shows for a program, its version resource's file description. Null when there
    /// is none.
    /// </param>
    public static WindowsAppDescriptor Describe(DiscoveredAppWindow window, Func<string, string?> fileDescription)
    {
        var isFrameHost = string.Equals(window.ProcessName, FrameHostProcessName, StringComparison.OrdinalIgnoreCase);
        var aumid = string.IsNullOrWhiteSpace(window.AppUserModelId) ? null : window.AppUserModelId;
        var key = aumid
            ?? (isFrameHost ? null : window.ExecutablePath)
            ?? (window.ProcessName.Length > 0 && !isFrameHost ? window.ProcessName : window.Window.Title);
        var id = StableId(key);
        var described = isFrameHost || window.ExecutablePath is null ? null : fileDescription(window.ExecutablePath)?.Trim();
        var name = !string.IsNullOrEmpty(described)
            ? described
            : isFrameHost || window.ProcessName.Length == 0 ? window.Window.Title : window.ProcessName;

        return new WindowsAppDescriptor(
            Id: id,
            Name: name,
            Executable: window.ExecutablePath ?? window.ProcessName + ".exe",
            Publisher: string.Empty,
            IconId: "icon_" + id,
            WindowDiscoveryTimeoutOverride: StartMenuCatalog.WindowDiscoveryTimeout,
            AppUserModelId: aumid,
            LaunchAumid: aumid
        );
    }

    /// <summary>Whether the id names an app known only from a window.</summary>
    public static bool IsRunningAppId(string? appId) =>
        appId is not null && appId.StartsWith(IdPrefix, StringComparison.Ordinal);

    internal static string StableId(string key)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(key.ToLowerInvariant()));
        return IdPrefix + Convert.ToHexString(hash, 0, 8).ToLowerInvariant();
    }

    /// <summary>The program's file description, as Task Manager and the taskbar show it.</summary>
    internal static string? FileDescription(string executablePath)
    {
        try
        {
            return FileVersionInfo.GetVersionInfo(executablePath).FileDescription;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return null;
        }
    }
}
