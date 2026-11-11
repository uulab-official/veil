using System.Security.Cryptography;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// Where <see cref="AgentSession"/> gets the Start menu apps it lists after its built-in apps.
/// </summary>
/// <remarks>
/// An interface so tests can hand the session a fixed list. Discovery itself only runs on Windows.
/// </remarks>
public interface IStartMenuCatalogSource
{
    /// <summary>
    /// The cached Start menu apps. Waits at most <paramref name="maxWait"/> for a discovery that is still
    /// running and has never finished, and returns an empty list when that wait runs out.
    /// </summary>
    Task<IReadOnlyList<WindowsAppDescriptor>> GetAppsAsync(TimeSpan maxWait, CancellationToken cancellationToken);
}

/// <summary>
/// One <c>.lnk</c> file found under a Start menu Programs folder, with its resolved target.
/// </summary>
internal sealed record StartMenuShortcut(
    string ProgramsRoot,
    string ShortcutPath,
    string TargetPath,
    string Arguments,
    string? WorkingDirectory,
    string Publisher,
    // The names Explorer shows, localized through desktop.ini (명령 프롬프트 for Command Prompt.lnk). Null off
    // Windows or when Windows has none; the file names are used then.
    string? DisplayName = null,
    string? FolderDisplayName = null
);

/// <summary>
/// One Start menu entry of a packaged (Store or inbox) app.
/// </summary>
internal sealed record StartMenuPackagedApp(string DisplayName, string AppUserModelId, string Publisher);

/// <summary>
/// Every app the Windows Start menu shows, so the Mac can offer a Start menu of its own.
/// </summary>
/// <remarks>
/// Discovery reads every shortcut and asks the package manager about every installed package, which takes
/// seconds. It runs in the background, and its result is kept and reused. A new discovery starts at most every
/// <see cref="DefaultRefreshInterval"/>, when someone asks for the list. Callers never wait longer than they
/// choose: a caller that arrives before the first discovery finishes gets an empty list.
/// </remarks>
public sealed class StartMenuCatalog : IStartMenuCatalogSource
{
    public static readonly TimeSpan DefaultRefreshInterval = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Ids start with this, so they cannot collide with the built-in <c>winapp_</c> ids.
    /// </summary>
    public const string IdPrefix = "start_";

    /// <summary>
    /// Start menu icons are smaller than the built-in apps' 256 px. Dozens of apps each send their icon in the
    /// one <c>app.list.response</c>, and the host refuses WebSocket messages over 32 MiB.
    /// </summary>
    internal const int IconSize = 128;

    /// <summary>
    /// Third-party apps can take a long time to show their first window, often behind a splash screen. The
    /// built-in apps' 5 second default would report a working launch as failed.
    /// </summary>
    internal static readonly TimeSpan WindowDiscoveryTimeout = TimeSpan.FromSeconds(15);

    private static readonly string[] ExcludedWords = ["uninstall", "제거", "readme", "help", "website"];

    private readonly Func<IReadOnlyList<WindowsAppDescriptor>> discover;
    private readonly TimeSpan refreshInterval;
    private readonly Func<DateTimeOffset> now;
    private readonly object gate = new();
    private IReadOnlyList<WindowsAppDescriptor>? cached;
    private DateTimeOffset? lastStarted;
    private Task running = Task.CompletedTask;

    public StartMenuCatalog(
        Func<IReadOnlyList<WindowsAppDescriptor>>? discover = null,
        TimeSpan? refreshInterval = null,
        Func<DateTimeOffset>? now = null
    )
    {
        this.discover = discover ?? StartMenuDiscovery.DiscoverWithIcons;
        this.refreshInterval = refreshInterval ?? DefaultRefreshInterval;
        this.now = now ?? (() => DateTimeOffset.UtcNow);
    }

    /// <summary>
    /// Starts a discovery unless one is running or the last one started less than the refresh interval ago.
    /// Returns the running discovery.
    /// </summary>
    public Task StartRefresh()
    {
        lock (gate)
        {
            if (!running.IsCompleted)
            {
                return running;
            }

            var current = now();
            if (lastStarted is { } started && current - started < refreshInterval)
            {
                return running;
            }

            lastStarted = current;
            running = Task.Run(Refresh);
            return running;
        }
    }

    public async Task<IReadOnlyList<WindowsAppDescriptor>> GetAppsAsync(
        TimeSpan maxWait,
        CancellationToken cancellationToken
    )
    {
        var refresh = StartRefresh();
        if (Volatile.Read(ref cached) is { } snapshot)
        {
            // A stale list is better than a slow one; the refresh replaces it for the next request.
            return snapshot;
        }

        if (!refresh.IsCompleted)
        {
            await Task.WhenAny(refresh, Task.Delay(maxWait, cancellationToken));
            cancellationToken.ThrowIfCancellationRequested();
        }

        return Volatile.Read(ref cached) ?? [];
    }

    private void Refresh()
    {
        try
        {
            Volatile.Write(ref cached, discover());
        }
        catch (Exception error)
        {
            // Keep the previous list. The next request after the refresh interval tries again.
            Console.Error.WriteLine($"StartMenuCatalog: discovery failed. {error.GetType().Name}: {error.Message}");
        }
    }

    /// <summary>
    /// An id that stays the same across agent restarts and reinstalls of the same app, so a Mac launcher made
    /// for it keeps working. It only uses characters the host accepts in an app id (letters, digits, <c>_</c>).
    /// </summary>
    internal static string StableId(string key)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(key.ToLowerInvariant()));
        return IdPrefix + Convert.ToHexString(hash, 0, 8).ToLowerInvariant();
    }

    internal static string ShortcutKey(string targetPath, string arguments) =>
        string.IsNullOrWhiteSpace(arguments) ? targetPath.Trim() : $"{targetPath.Trim()} {arguments.Trim()}";

    /// <summary>
    /// Uninstallers, readmes, help files, and website links share the Start menu folder of the app they belong
    /// to, but nobody opens them as an app. Inno Setup uninstallers are named <c>unins000.exe</c>.
    /// </summary>
    internal static bool IsExcludedShortcut(string name, string targetPath)
    {
        var targetName = WindowsFileName(targetPath);
        return targetName.StartsWith("unins", StringComparison.OrdinalIgnoreCase)
            || ExcludedWords.Any(word =>
                name.Contains(word, StringComparison.OrdinalIgnoreCase)
                || targetName.Contains(word, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// The shortcut's folder relative to Programs, with <c>/</c> between nested folders. Null for a shortcut
    /// directly in Programs or outside it.
    /// </summary>
    internal static string? FolderFor(string programsRoot, string shortcutPath)
    {
        var root = NormalizeSeparators(programsRoot).TrimEnd('\\') + "\\";
        var path = NormalizeSeparators(shortcutPath);
        if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var segments = path[root.Length..].Split('\\', StringSplitOptions.RemoveEmptyEntries);
        return segments.Length <= 1 ? null : string.Join("/", segments[..^1]);
    }

    /// <summary>
    /// Turns shortcuts into apps. Only shortcuts to an existing <c>.exe</c> are kept: a shortcut to a document,
    /// a folder, a Control Panel item, or an <c>.msc</c> console does not open a window the agent can follow.
    /// The same program reached from both the all-users and the per-user Start menu is listed once.
    /// </summary>
    internal static IReadOnlyList<WindowsAppDescriptor> FromShortcuts(
        IEnumerable<StartMenuShortcut> shortcuts,
        Func<string, bool> fileExists
    )
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var apps = new List<WindowsAppDescriptor>();
        foreach (var shortcut in shortcuts)
        {
            var fileName = WindowsFileNameWithoutExtension(shortcut.ShortcutPath);
            var name = string.IsNullOrWhiteSpace(shortcut.DisplayName) ? fileName : shortcut.DisplayName.Trim();
            var target = shortcut.TargetPath.Trim();
            if (name.Length == 0
                || !target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                || IsExcludedShortcut(fileName, target)
                || IsExcludedShortcut(name, target)
                || !fileExists(target))
            {
                continue;
            }

            var key = ShortcutKey(target, shortcut.Arguments);
            if (!seen.Add(key))
            {
                continue;
            }

            var id = StableId(key);
            apps.Add(new WindowsAppDescriptor(
                Id: id,
                Name: name,
                Executable: target,
                Publisher: shortcut.Publisher,
                IconId: "icon_" + id,
                WindowDiscoveryTimeoutOverride: WindowDiscoveryTimeout,
                ShortcutArguments: string.IsNullOrWhiteSpace(shortcut.Arguments) ? null : shortcut.Arguments.Trim(),
                WorkingDirectory: string.IsNullOrWhiteSpace(shortcut.WorkingDirectory) ? null : shortcut.WorkingDirectory,
                Folder: shortcut.FolderDisplayName ?? FolderFor(shortcut.ProgramsRoot, shortcut.ShortcutPath)
            ));
        }

        return apps;
    }

    /// <summary>
    /// Turns packaged app entries into apps. A name the package manager could not resolve comes back as an
    /// <c>ms-resource:</c> reference, which would show up on the Mac as gibberish.
    /// </summary>
    internal static IReadOnlyList<WindowsAppDescriptor> FromPackagedApps(IEnumerable<StartMenuPackagedApp> entries)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var apps = new List<WindowsAppDescriptor>();
        foreach (var entry in entries)
        {
            var name = entry.DisplayName?.Trim() ?? string.Empty;
            var aumid = entry.AppUserModelId?.Trim() ?? string.Empty;
            if (name.Length == 0
                || aumid.Length == 0
                || name.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase)
                || !seen.Add(aumid))
            {
                continue;
            }

            var id = StableId(aumid);
            apps.Add(new WindowsAppDescriptor(
                Id: id,
                Name: name,
                // What the user would type in Run or Explorer to open it; exePath has no real executable to show.
                Executable: ShellItemIcon.AppsFolderPath(aumid),
                Publisher: entry.Publisher,
                IconId: "icon_" + id,
                WindowDiscoveryTimeoutOverride: WindowDiscoveryTimeout,
                AppUserModelId: aumid,
                LaunchAumid: aumid
            ));
        }

        return apps;
    }

    /// <summary>
    /// Shortcut and packaged apps together, sorted by name the way the Start menu's All list is.
    /// </summary>
    internal static IReadOnlyList<WindowsAppDescriptor> Combine(
        IEnumerable<WindowsAppDescriptor> shortcutApps,
        IEnumerable<WindowsAppDescriptor> packagedApps
    )
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return shortcutApps
            .Concat(packagedApps)
            .Where(app => seen.Add(app.Id))
            .OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
    }

    /// <summary>
    /// Drops catalog entries that are a built-in app: Notepad, Calculator, and Paint are also in the Start
    /// menu, and listing them twice would give the Mac two launchers that open the same windows.
    /// </summary>
    internal static IReadOnlyList<WindowsAppDescriptor> WithoutBuiltIns(
        IReadOnlyList<WindowsAppDescriptor> builtIns,
        IEnumerable<WindowsAppDescriptor> catalog
    )
    {
        var builtInAumids = builtIns
            .Select(app => app.AppUserModelId)
            .OfType<string>()
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var builtInExecutables = builtIns
            .SelectMany(app => (app.AlternateExecutables ?? []).Append(app.Executable))
            .Select(WindowsFileNameWithoutExtension)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        return catalog
            .Where(app => !(
                app.LaunchAumid is { } aumid
                    ? builtInAumids.Contains(aumid)
                    : builtInExecutables.Contains(WindowsFileNameWithoutExtension(app.Executable))
            ))
            .ToArray();
    }

    /// <summary>
    /// The icon for a catalog entry, extracted once per id. A packaged app's icon comes from its AppUserModelID
    /// only: its <c>exePath</c> is a shell path, not a file.
    /// </summary>
    internal static string? IconPngBase64(WindowsAppDescriptor app) =>
        WindowsAppIconExtractor.ExtractIconPngBase64(
            app.Id,
            app.AppUserModelId,
            app.LaunchAumid is null ? [app.Executable] : [],
            IconSize
        );

    // Windows paths are handled as strings here rather than through System.IO.Path, which on the Mac where the
    // tests run does not treat a backslash as a separator.
    private static string NormalizeSeparators(string path) => path.Replace('/', '\\');

    internal static string WindowsFileName(string path)
    {
        var normalized = NormalizeSeparators(path);
        return normalized[(normalized.LastIndexOf('\\') + 1)..];
    }

    internal static string WindowsFileNameWithoutExtension(string path)
    {
        var fileName = WindowsFileName(path);
        var dot = fileName.LastIndexOf('.');
        return dot <= 0 ? fileName : fileName[..dot];
    }
}
