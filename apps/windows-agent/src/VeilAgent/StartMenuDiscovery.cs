using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Runtime.Versioning;
using System.Text;
using Windows.Management.Deployment;

namespace Veil.Agent;

/// <summary>
/// Reads the Windows Start menu: shortcuts under both Programs folders and the packaged apps the package
/// manager lists for the signed-in user. The filtering rules live in <see cref="StartMenuCatalog"/>, where
/// tests can reach them without Windows.
/// </summary>
internal static class StartMenuDiscovery
{
    private const int MaxPath = 32_767;

    /// <summary>
    /// Discovers the Start menu and extracts every icon before returning, so the first <c>app.list</c> after a
    /// discovery finds them cached instead of extracting dozens of icons while the host waits.
    /// </summary>
    public static IReadOnlyList<WindowsAppDescriptor> DiscoverWithIcons()
    {
        if (!OperatingSystem.IsWindows())
        {
            return [];
        }

        var stopwatch = Stopwatch.StartNew();
        var shortcutApps = StartMenuCatalog.FromShortcuts(DiscoverShortcuts(), File.Exists);
        var packagedApps = StartMenuCatalog.FromPackagedApps(DiscoverPackagedApps());
        var apps = StartMenuCatalog.Combine(shortcutApps, packagedApps);
        foreach (var app in apps)
        {
            _ = StartMenuCatalog.IconPngBase64(app);
        }

        Console.WriteLine(
            $"StartMenuCatalog: {shortcutApps.Count} shortcut apps and {packagedApps.Count} packaged apps in {stopwatch.ElapsedMilliseconds} ms."
        );
        return apps;
    }

    private static IEnumerable<StartMenuShortcut> DiscoverShortcuts()
    {
        // All users first, then this user: Windows shows both merged, and a shortcut in both lists once.
        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
            Environment.GetFolderPath(Environment.SpecialFolder.Programs)
        };
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true };
        foreach (var root in roots.Where(root => root.Length > 0 && Directory.Exists(root)))
        {
            foreach (var shortcutPath in Directory.EnumerateFiles(root, "*.lnk", options))
            {
                if (TryReadShortcut(root, shortcutPath) is { } shortcut)
                {
                    yield return shortcut;
                }
            }
        }
    }

    /// <summary>The name Explorer and the Start menu show, which desktop.ini localizes.</summary>
    private static string? ShellDisplayName(string path)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        var info = new ShFileInfo();
        return SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf<ShFileInfo>(), ShgfiDisplayName) != IntPtr.Zero
            && !string.IsNullOrWhiteSpace(info.DisplayName)
            ? info.DisplayName
            : null;
    }

    /// <summary>Each folder between Programs and the shortcut, by its shown name, joined with <c>/</c>.</summary>
    private static string? FolderDisplayName(string root, string shortcutPath)
    {
        if (StartMenuCatalog.FolderFor(root, shortcutPath) is not { } relative)
        {
            return null;
        }
        var current = root.TrimEnd('\\');
        var names = new List<string>();
        foreach (var segment in relative.Split('/'))
        {
            current = current + "\\" + segment;
            names.Add(ShellDisplayName(current) ?? segment);
        }
        return string.Join("/", names);
    }

    private const uint ShgfiDisplayName = 0x000000200;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShFileInfo
    {
        public IntPtr Icon;
        public int IconIndex;
        public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string TypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHGetFileInfo(string path, uint attributes, ref ShFileInfo info, uint size, uint flags);

    private static StartMenuShortcut? TryReadShortcut(string root, string shortcutPath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        object? instance = null;
        try
        {
            // IShellLinkW reads the .lnk the way Explorer does, without starting a script host. Resolve() is not
            // called: it searches the disk for a moved target and can show UI.
            instance = Activator.CreateInstance(Type.GetTypeFromCLSID(ShellLinkClassId, throwOnError: true)!);
            var link = (IShellLinkW)instance!;
            ((IPersistFile)instance!).Load(shortcutPath, 0);

            var target = new StringBuilder(MaxPath);
            link.GetPath(target, target.Capacity, IntPtr.Zero, 0);
            var arguments = new StringBuilder(MaxPath);
            link.GetArguments(arguments, arguments.Capacity);
            var workingDirectory = new StringBuilder(MaxPath);
            link.GetWorkingDirectory(workingDirectory, workingDirectory.Capacity);

            var targetPath = Environment.ExpandEnvironmentVariables(target.ToString());
            if (TryResolveInstallerShortcut(shortcutPath) is { } installedPath)
            {
                // An advertised (Windows Installer) shortcut, as older Office versions make. Its plain target is
                // an icon file in %WINDIR%\Installer, which is an .exe that opens nothing.
                targetPath = installedPath;
            }

            if (targetPath.Length == 0)
            {
                return null;
            }

            return new StartMenuShortcut(
                ProgramsRoot: root,
                ShortcutPath: shortcutPath,
                TargetPath: targetPath,
                Arguments: arguments.ToString(),
                WorkingDirectory: Environment.ExpandEnvironmentVariables(workingDirectory.ToString()),
                Publisher: CompanyName(targetPath),
                DisplayName: ShellDisplayName(shortcutPath),
                FolderDisplayName: FolderDisplayName(root, shortcutPath)
            );
        }
        catch (Exception error) when (error is COMException or InvalidCastException or ArgumentException or IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"StartMenuCatalog: skipped {shortcutPath}. {error.GetType().Name}: {error.Message}");
            return null;
        }
        finally
        {
            if (instance is not null && OperatingSystem.IsWindows())
            {
                Marshal.ReleaseComObject(instance);
            }
        }
    }

    private static string? TryResolveInstallerShortcut(string shortcutPath)
    {
        try
        {
            var productCode = new StringBuilder(39);
            var featureId = new StringBuilder(39);
            var componentCode = new StringBuilder(39);
            if (MsiGetShortcutTarget(shortcutPath, productCode, featureId, componentCode) != 0
                || componentCode.Length == 0)
            {
                return null;
            }

            uint length = MaxPath;
            var path = new StringBuilder((int)length);
            return MsiGetComponentPath(productCode.ToString(), componentCode.ToString(), path, ref length) == InstallStateLocal
                ? path.ToString()
                : null;
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    private static string CompanyName(string targetPath)
    {
        try
        {
            return File.Exists(targetPath) ? FileVersionInfo.GetVersionInfo(targetPath).CompanyName?.Trim() ?? string.Empty : string.Empty;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return string.Empty;
        }
    }

    private static IEnumerable<StartMenuPackagedApp> DiscoverPackagedApps()
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041))
        {
            return [];
        }

        try
        {
            return DiscoverPackagedAppsCore();
        }
        catch (Exception error) when (error is COMException or UnauthorizedAccessException or InvalidOperationException)
        {
            Console.Error.WriteLine($"StartMenuCatalog: could not list packages. {error.GetType().Name}: {error.Message}");
            return [];
        }
    }

    [SupportedOSPlatform("windows10.0.19041.0")]
    private static List<StartMenuPackagedApp> DiscoverPackagedAppsCore()
    {
        var entries = new List<StartMenuPackagedApp>();
        // An empty user security id means the user this process runs as, which needs no administrator rights.
        foreach (var package in new PackageManager().FindPackagesForUser(string.Empty))
        {
            try
            {
                // Frameworks, resource packs, and bundles have no app of their own. A package that is being
                // serviced, tampered with, or is otherwise not OK cannot be activated either.
                if (package.IsFramework || package.IsResourcePackage || package.IsBundle || !package.Status.VerifyIsOK())
                {
                    continue;
                }

                // GetAppListEntriesAsync leaves out apps whose manifest hides them from the Start menu
                // (AppListEntry="none"), such as system hosts and background components.
                var publisher = package.PublisherDisplayName ?? string.Empty;
                foreach (var entry in package.GetAppListEntriesAsync().AsTask().GetAwaiter().GetResult())
                {
                    entries.Add(new StartMenuPackagedApp(
                        DisplayName: entry.DisplayInfo?.DisplayName ?? string.Empty,
                        AppUserModelId: entry.AppUserModelId ?? string.Empty,
                        Publisher: publisher
                    ));
                }
            }
            catch (Exception error) when (error is COMException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
            {
                Console.Error.WriteLine(
                    $"StartMenuCatalog: skipped package {SafePackageName(package)}. {error.GetType().Name}: {error.Message}"
                );
            }
        }

        return entries;
    }

    [SupportedOSPlatform("windows10.0.19041.0")]
    private static string SafePackageName(Windows.ApplicationModel.Package package)
    {
        try
        {
            return package.Id.FullName;
        }
        catch (Exception error) when (error is COMException)
        {
            return "(unknown)";
        }
    }

    private const int InstallStateLocal = 3;

    private static readonly Guid ShellLinkClassId = new("00021401-0000-0000-C000-000000000046");

    [DllImport("msi.dll", CharSet = CharSet.Unicode, EntryPoint = "MsiGetShortcutTargetW")]
    private static extern uint MsiGetShortcutTarget(
        string shortcutPath,
        StringBuilder productCode,
        StringBuilder featureId,
        StringBuilder componentCode
    );

    [DllImport("msi.dll", CharSet = CharSet.Unicode, EntryPoint = "MsiGetComponentPathW")]
    private static extern int MsiGetComponentPath(string product, string component, StringBuilder path, ref uint length);

    // https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishelllinkw
    [ComImport]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int maxLength, IntPtr findData, uint flags);
        void GetIDList(out IntPtr idList);
        void SetIDList(IntPtr idList);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int maxLength);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder directory, int maxLength);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments, int maxLength);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int showCommand);
        void SetShowCmd(int showCommand);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder iconPath, int maxLength, out int iconIndex);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string iconPath, int iconIndex);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string relativePath, uint reserved);
        void Resolve(IntPtr hwnd, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
    }
}
