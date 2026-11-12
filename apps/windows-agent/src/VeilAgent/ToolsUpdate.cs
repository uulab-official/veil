using System.Diagnostics;

namespace Veil.Agent;

/// <summary>A drive that could hold the tools disc: its root, such as <c>H:\</c>, and its volume label.</summary>
public sealed record ToolsUpdateDrive(string Root, string VolumeLabel);

/// <summary>What became of a tools update request.</summary>
public sealed record ToolsUpdateResult(bool Started, string? EntryPoint, string? ErrorCode, string? Message);

/// <summary>
/// Starts the Windows tools update from the disc the host put in the removable drive, so the host does not
/// have to type the command into Windows. Typing clicked a fixed place on the screen and pressed Ctrl+A
/// first, and with apps open it replaced the text of an open Notepad document.
/// </summary>
/// <remarks>
/// The host's request names nothing to run. Only <see cref="EntryPointRelativePath"/> on an optical disc
/// labelled <see cref="VolumeLabel"/> is started, as the agent's own user and without elevation. The host can
/// already attach a disc and type into Windows, so this gives it nothing new. A program inside Windows that
/// mounts its own image with that label gets a script run as the user it already runs as.
/// </remarks>
public sealed class ToolsUpdate
{
    /// <summary>The label the host gives the tools update disc (<c>GuestToolsUpdateMedia.volumeName</c>).</summary>
    public const string VolumeLabel = "VEIL_TOOLS";

    public const string EntryPointRelativePath = @"Veil Guest Agent\U.cmd";

    private readonly Func<IEnumerable<ToolsUpdateDrive>> opticalDrives;
    private readonly Func<string, bool> fileExists;
    private readonly Action<string> start;

    public ToolsUpdate(
        Func<IEnumerable<ToolsUpdateDrive>>? opticalDrives = null,
        Func<string, bool>? fileExists = null,
        Action<string>? start = null
    )
    {
        this.opticalDrives = opticalDrives ?? ReadyOpticalDrives;
        this.fileExists = fileExists ?? File.Exists;
        this.start = start ?? StartHidden;
    }

    /// <summary>The update's entry point on the tools disc, or null when no such disc is in a drive.</summary>
    public string? FindEntryPoint() =>
        opticalDrives()
            .Where(drive => string.Equals(drive.VolumeLabel, VolumeLabel, StringComparison.OrdinalIgnoreCase))
            .Select(drive => EntryPointOn(drive.Root))
            .FirstOrDefault(fileExists);

    /// <summary>Starts the update and returns without waiting: the script stops this agent to replace it.</summary>
    public ToolsUpdateResult Run()
    {
        var entryPoint = FindEntryPoint();
        if (entryPoint is null)
        {
            return new ToolsUpdateResult(
                Started: false,
                EntryPoint: null,
                ErrorCode: "tools_media_missing",
                Message: $"No disc labelled {VolumeLabel} with {EntryPointRelativePath} is in a drive."
            );
        }

        try
        {
            start(entryPoint);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return new ToolsUpdateResult(false, entryPoint, "tools_update_failed", error.Message);
        }

        return new ToolsUpdateResult(true, entryPoint, null, null);
    }

    // Windows paths are joined as strings: on the Mac, where the tests run, Path.Combine uses a slash.
    internal static string EntryPointOn(string root) =>
        (root.EndsWith('\\') ? root : root + "\\") + EntryPointRelativePath;

    private static IEnumerable<ToolsUpdateDrive> ReadyOpticalDrives()
    {
        if (!OperatingSystem.IsWindows())
        {
            return [];
        }

        var drives = new List<ToolsUpdateDrive>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (drive.DriveType == DriveType.CDRom && drive.IsReady)
                {
                    drives.Add(new ToolsUpdateDrive(drive.RootDirectory.FullName, drive.VolumeLabel));
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // A drive whose disc is being changed. The next request sees it.
            }
        }

        return drives;
    }

    /// <summary>
    /// Through the shell, so the script does not inherit the agent's handles: it outlives the agent, and the
    /// new agent needs the port the old one listened on. No window, so the update does not open a console
    /// that would then show up on the Mac as an app window.
    /// </summary>
    private static void StartHidden(string entryPoint)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c \"\"{entryPoint}\"\"",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden
        }) ?? throw new InvalidOperationException("cmd.exe did not start.");
    }
}
