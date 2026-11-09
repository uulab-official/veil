using System.Collections.Concurrent;
using System.Drawing;
using System.Drawing.Imaging;

namespace Veil.Agent;

/// <summary>
/// Resolves an app catalog entry's real Windows icon (the .exe's associated icon, not a generic
/// placeholder) once per app and caches the encoded result -- <see cref="AgentSession"/>
/// rebuilds the app list response on every <c>app.list.request</c>, and icons never change at
/// runtime, so re-extracting on every request would be wasted work. Cached by app id (not by
/// executable name) so callers can pass alternate executable names for packaged apps without
/// affecting the cache key.
/// </summary>
public static class WindowsAppIconExtractor
{
    private static readonly ConcurrentDictionary<string, string?> Cache = new(StringComparer.OrdinalIgnoreCase);

    public static string? ExtractIconPngBase64(string cacheKey, IEnumerable<string> executableCandidates) =>
        ExtractIconPngBase64(cacheKey, appUserModelId: null, executableCandidates);

    /// <summary>
    /// Prefers the shell's large icon: a packaged app's logo from its AppUserModelID, then an executable's
    /// largest icon. <see cref="Icon.ExtractAssociatedIcon"/> is the last resort; its 32 px image looks
    /// blurry in the Mac Dock, and for an execution alias stub it is a generic window.
    /// </summary>
    public static string? ExtractIconPngBase64(
        string cacheKey,
        string? appUserModelId,
        IEnumerable<string> executableCandidates
    ) =>
        Cache.GetOrAdd(cacheKey, _ => TryExtractIconPngBase64(appUserModelId, executableCandidates.ToArray()));

    private static string? TryExtractIconPngBase64(string? appUserModelId, string[] executableCandidates)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        if (appUserModelId is not null
            && ShellItemIcon.TryGetPng(ShellItemIcon.AppsFolderPath(appUserModelId)) is { } packagedIcon)
        {
            return Convert.ToBase64String(packagedIcon);
        }

        var resolvedPaths = executableCandidates
            .Select(ResolveExecutablePath)
            .OfType<string>()
            .ToArray();
        foreach (var resolvedPath in resolvedPaths)
        {
            if (ShellItemIcon.TryGetPng(resolvedPath) is { } shellIcon)
            {
                return Convert.ToBase64String(shellIcon);
            }
        }

        foreach (var resolvedPath in resolvedPaths)
        {
            try
            {
                using var icon = Icon.ExtractAssociatedIcon(resolvedPath);
                if (icon is null)
                {
                    continue;
                }

                using var bitmap = icon.ToBitmap();
                using var stream = new MemoryStream();
                bitmap.Save(stream, ImageFormat.Png);
                return Convert.ToBase64String(stream.ToArray());
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                Console.Error.WriteLine(
                    $"WindowsAppIconExtractor: failed to extract an icon from {resolvedPath}. {error.GetType().Name}: {error.Message}"
                );
            }
        }

        Console.Error.WriteLine(
            $"WindowsAppIconExtractor: could not resolve or extract an icon from any of [{string.Join(", ", executableCandidates)}]; falling back to no icon."
        );
        return null;
    }

    private static string? ResolveExecutablePath(string executable)
    {
        if (Path.IsPathRooted(executable)) {
            return File.Exists(executable) ? executable : null;
        }

        // Bare filenames (e.g. "calc.exe") rely on Process.Start(UseShellExecute: true)'s own PATH
        // resolution at launch time -- Icon.ExtractAssociatedIcon does not replicate that, it only
        // resolves relative to the current working directory. The built-in catalog's bare names all
        // live in System32, so check there directly before falling back to PATH and then the working
        // directory. Some inbox apps (e.g. mspaint.exe on recent Windows 11 builds) are packaged apps
        // whose System32 entry was removed in favor of an execution-alias stub under
        // "%LOCALAPPDATA%\Microsoft\WindowsApps", which only PATH search will find.
        var systemCandidate = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), executable);
        if (File.Exists(systemCandidate))
        {
            return systemCandidate;
        }

        var pathCandidate = ResolveFromPathEnvironmentVariable(executable);
        if (pathCandidate is not null)
        {
            return pathCandidate;
        }

        return File.Exists(executable) ? Path.GetFullPath(executable) : null;
    }

    private static string? ResolveFromPathEnvironmentVariable(string executable)
    {
        var pathVariable = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathVariable))
        {
            return null;
        }

        foreach (var directory in pathVariable.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(directory, executable);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }
}
