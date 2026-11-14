using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace Veil.Agent;

/// <summary>A drive letter's mapping, as Windows reports it.</summary>
public interface IDriveMapper
{
    /// <summary>The UNC path mapped to <paramref name="drive"/> (for example <c>M:</c>), or null when none.</summary>
    string? RemoteNameOf(string drive);
    /// <summary>Whether a local volume (not a network mapping) already uses the letter.</summary>
    bool IsLocalVolume(string drive);
    /// <summary>Maps the drive and returns null, or a message saying why not.</summary>
    string? Map(string drive, string uncPath);
    string? Unmap(string drive);
    void SetLabel(string uncPath, string label);
}

/// <summary>
/// Mounts the Mac folder Veil serves over WebDAV as a drive letter (<c>host.folder.mount.request</c>).
/// </summary>
/// <remarks>
/// Mapped through <c>WNetAddConnection2</c> rather than <c>net use</c>, so nothing the host sends reaches a
/// command line. The WebDAV redirector (WebClient service) handles <c>\\host@port\path</c> names:
/// <see href="https://learn.microsoft.com/windows/win32/api/winnetwk/nf-winnetwk-wnetaddconnection2w"/>.
/// </remarks>
public sealed class HostFolderMount
{
    public const string HostAddress = "10.0.2.2";
    private static readonly Regex TokenPattern = new("^[A-Za-z0-9_-]{16,128}$", RegexOptions.CultureInvariant);
    private readonly IDriveMapper mapper;

    public HostFolderMount(IDriveMapper? mapper = null)
    {
        this.mapper = mapper ?? new WindowsDriveMapper();
    }

    public static bool IsValidDriveLetter(string? letter) =>
        letter is { Length: 1 } && letter[0] is >= 'D' and <= 'Z';

    public static bool IsValidToken(string? token) => token is not null && TokenPattern.IsMatch(token);

    public static string UncPath(int port, string token) => $@"\\{HostAddress}@{port}\{token}";

    /// <summary>Only Veil's own WebDAV mappings are ever replaced or removed.</summary>
    public static bool IsVeilMapping(string? remote) =>
        remote is not null && remote.StartsWith($@"\\{HostAddress}@", StringComparison.OrdinalIgnoreCase);

    public (bool IsMounted, string? UncPath, string? Message) Mount(int port, string token, string driveLetter, string label)
    {
        var drive = driveLetter + ":";
        var unc = UncPath(port, token);
        var current = mapper.RemoteNameOf(drive);
        if (string.Equals(current, unc, StringComparison.OrdinalIgnoreCase))
        {
            mapper.SetLabel(unc, label);
            return (true, unc, null);
        }

        if (current is not null)
        {
            if (!IsVeilMapping(current))
            {
                return (false, null, $"{drive} is already mapped to {current}.");
            }
            // An earlier Veil run served the folder at another port and token.
            if (mapper.Unmap(drive) is { } unmapError)
            {
                return (false, null, unmapError);
            }
        }
        else if (mapper.IsLocalVolume(drive))
        {
            return (false, null, $"{drive} is a local drive.");
        }

        if (mapper.Map(drive, unc) is { } error)
        {
            return (false, null, error);
        }
        mapper.SetLabel(unc, label);
        return (true, unc, null);
    }

    public (bool IsMounted, string? Message) Unmount(string driveLetter)
    {
        var drive = driveLetter + ":";
        var current = mapper.RemoteNameOf(drive);
        if (current is null)
        {
            return (false, null);
        }
        if (!IsVeilMapping(current))
        {
            return (true, $"{drive} is mapped to {current}, which Veil did not create.");
        }
        return mapper.Unmap(drive) is { } error ? (true, error) : (false, null);
    }
}

internal sealed class WindowsDriveMapper : IDriveMapper
{
    private const int ResourcetypeDisk = 1;
    private const int NoError = 0;

    public string? RemoteNameOf(string drive)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        var buffer = new StringBuilder(1024);
        var length = buffer.Capacity;
        return WNetGetConnection(drive, buffer, ref length) == NoError ? buffer.ToString() : null;
    }

    public bool IsLocalVolume(string drive) =>
        OperatingSystem.IsWindows() && Directory.Exists(drive + "\\") && RemoteNameOf(drive) is null;

    public string? Map(string drive, string uncPath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return "Mapping a drive needs Windows.";
        }
        var resource = new NetResource { Type = ResourcetypeDisk, LocalName = drive, RemoteName = uncPath };
        // No CONNECT_UPDATE_PROFILE: the port and token change every time Veil starts, so a mapping restored at
        // the next sign-in would point nowhere.
        var result = WNetAddConnection2(ref resource, null, null, 0);
        return result == NoError ? null : $"Windows could not map {drive} to {uncPath} (error {result}). Is the WebClient service available?";
    }

    public string? Unmap(string drive)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        var result = WNetCancelConnection2(drive, 0, true);
        return result == NoError ? null : $"Windows could not remove {drive} (error {result}).";
    }

    public void SetLabel(string uncPath, string label)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }
        // Explorer names a network drive from MountPoints2, keyed by the UNC path with \ as #.
        var key = @"Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\" + uncPath.Replace('\\', '#');
        using var registryKey = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(key);
        registryKey?.SetValue("_LabelFromReg", label);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NetResource
    {
        public int Scope;
        public int Type;
        public int DisplayType;
        public int Usage;
        public string? LocalName;
        public string? RemoteName;
        public string? Comment;
        public string? Provider;
    }

    [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
    private static extern int WNetAddConnection2(ref NetResource resource, string? password, string? userName, int flags);

    [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
    private static extern int WNetCancelConnection2(string name, int flags, bool force);

    [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
    private static extern int WNetGetConnection(string localName, StringBuilder remoteName, ref int length);
}
