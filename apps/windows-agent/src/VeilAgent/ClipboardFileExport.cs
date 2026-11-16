using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Veil.Agent;

/// <summary>What staging one Windows file selection for the host produced.</summary>
/// <param name="RelativePaths">Share-relative paths with Windows separators, or null when refused.</param>
/// <param name="Refusal">Why nothing was staged, for the agent log. Null on success.</param>
public sealed record ClipboardFileStageResult(IReadOnlyList<string>? RelativePaths, string? Refusal)
{
    public static ClipboardFileStageResult Refused(string reason) => new(null, reason);
}

/// <summary>
/// Guest-to-host file copy: stages the files an Explorer Copy put on the clipboard inside the shared folder,
/// so the host can copy them out. See docs/protocol.md "Clipboard Files", "Guest to host".
/// </summary>
/// <remarks>
/// The guest only ever names files inside its own share. The host decides where they land on the Mac and
/// re-checks every bound, so these checks exist to keep the guest from staging what the host will refuse,
/// not as the trust boundary.
/// </remarks>
public sealed class ClipboardFileExport
{
    public const string DirectoryName = "Veil Clipboard from Windows";
    public const int MaxFileCount = 64;
    public const long MaxTotalBytes = 512L * 1024 * 1024;
    public const int RetainedBatchCount = 3;

    /// <summary>A <c>DROPFILES</c> block holding 64 long paths is far below this.</summary>
    public const int MaxDropFilesBytes = 1024 * 1024;

    private const int DropFilesHeaderSize = 20;
    private static readonly Regex BatchName = new("^[0-9]{8}-[0-9]{6}-[0-9A-F]{6}$", RegexOptions.CultureInvariant);

    private readonly string shareRoot;

    public ClipboardFileExport(string shareRoot)
    {
        this.shareRoot = shareRoot;
    }

    /// <summary>
    /// Reads the wide paths out of a <c>DROPFILES</c> block. Returns at most <see cref="MaxFileCount"/> + 1
    /// entries, enough for staging to refuse an over-long selection without reading all of it. Null for a
    /// malformed or ANSI block; every current Windows source writes wide paths.
    /// </summary>
    public static IReadOnlyList<string>? ParseDropFiles(byte[] drop)
    {
        if (drop.Length < DropFilesHeaderSize)
        {
            return null;
        }

        var offset = BitConverter.ToUInt32(drop, 0);
        var isWide = BitConverter.ToInt32(drop, 16) != 0;
        if (!isWide || offset < DropFilesHeaderSize || offset >= drop.Length)
        {
            return null;
        }

        var paths = new List<string>();
        var start = (int)offset;
        var position = start;
        while (position + 1 < drop.Length)
        {
            var unit = BitConverter.ToUInt16(drop, position);
            if (unit != 0)
            {
                position += 2;
                continue;
            }

            if (position == start)
            {
                return paths;
            }

            paths.Add(Encoding.Unicode.GetString(drop, start, position - start));
            if (paths.Count > MaxFileCount)
            {
                return paths;
            }

            position += 2;
            start = position;
        }

        // No terminating empty string: the block was cut short.
        return null;
    }

    /// <summary>
    /// True when any path is inside one of Veil's own clipboard folders in the share. Those are the files a
    /// host paste just placed there, and sending them back would echo the host's own paste.
    /// </summary>
    public bool IsVeilStaged(IReadOnlyList<string> paths)
    {
        var root = Normalize(shareRoot).TrimEnd('\\');
        var hostFolder = root + "\\" + ClipboardFilePaths.DirectoryName + "\\";
        var guestFolder = root + "\\" + DirectoryName + "\\";
        return paths.Any(path =>
        {
            var normalized = Normalize(path);
            return normalized.StartsWith(hostFolder, StringComparison.OrdinalIgnoreCase)
                || normalized.StartsWith(guestFolder, StringComparison.OrdinalIgnoreCase);
        });
    }

    /// <summary>
    /// Copies the selection into <c>&lt;share&gt;\Veil Clipboard from Windows\&lt;batch&gt;\</c>. Every
    /// source is checked before anything is copied, and a failed copy removes the batch, so the host is
    /// never told about part of a selection.
    /// </summary>
    public ClipboardFileStageResult Stage(IReadOnlyList<string> sourcePaths, DateTime utcNow, string batchSuffix)
    {
        if (sourcePaths.Count == 0)
        {
            return ClipboardFileStageResult.Refused("The clipboard file list is empty.");
        }

        if (sourcePaths.Count > MaxFileCount)
        {
            return ClipboardFileStageResult.Refused($"More than {MaxFileCount} files were copied.");
        }

        if (!Directory.Exists(shareRoot))
        {
            return ClipboardFileStageResult.Refused($"The shared folder {shareRoot} does not exist.");
        }

        var batch = $"{utcNow:yyyyMMdd-HHmmss}-{batchSuffix}";
        if (!BatchName.IsMatch(batch))
        {
            return ClipboardFileStageResult.Refused("The batch name is malformed.");
        }

        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var relativePaths = new List<string>(sourcePaths.Count);
        long totalBytes = 0;
        foreach (var source in sourcePaths)
        {
            var name = LastComponent(source);
            var info = new FileInfo(source);
            if (!info.Exists || (info.Attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
            {
                // FileInfo.Exists is false for a folder, which is how a copied folder lands here.
                return ClipboardFileStageResult.Refused($"{name} is a folder or link. Only files are copied to the Mac.");
            }

            if (!ClipboardFilePaths.IsSafeComponent(name))
            {
                return ClipboardFileStageResult.Refused($"{name} is not a file name the Mac copy accepts.");
            }

            if (!names.Add(name))
            {
                return ClipboardFileStageResult.Refused($"Two copied files are both named {name}.");
            }

            totalBytes += info.Length;
            if (totalBytes > MaxTotalBytes)
            {
                return ClipboardFileStageResult.Refused($"The copied files exceed {MaxTotalBytes / (1024 * 1024)} MiB.");
            }

            var relativePath = $"{DirectoryName}\\{batch}\\{name}";
            if (relativePath.Length > ClipboardFilePaths.MaxRelativePathLength)
            {
                return ClipboardFileStageResult.Refused($"{name} is too long to stage.");
            }

            relativePaths.Add(relativePath);
        }

        var stagingDirectory = Path.Combine(shareRoot, DirectoryName);
        var batchDirectory = Path.Combine(stagingDirectory, batch);
        try
        {
            Directory.CreateDirectory(batchDirectory);
            long copiedBytes = 0;
            foreach (var source in sourcePaths)
            {
                var destination = Path.Combine(batchDirectory, LastComponent(source));
                File.Copy(source, destination, overwrite: false);
                // A file that grew between the size check and the copy must not push the batch over the cap.
                copiedBytes += new FileInfo(destination).Length;
                if (copiedBytes > MaxTotalBytes)
                {
                    throw new IOException($"The copied files grew past {MaxTotalBytes / (1024 * 1024)} MiB while copying.");
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            TryDelete(batchDirectory);
            return ClipboardFileStageResult.Refused($"Staging failed: {error.Message}");
        }

        PruneBatches(stagingDirectory);
        return new ClipboardFileStageResult(relativePaths, null);
    }

    public static string RandomBatchSuffix() => Random.Shared.Next(0, 0x1000000).ToString("X6");

    /// <summary>The broadcast for a staged selection. Shape and rules match the host-origin message.</summary>
    public static JsonObject GuestEvent(int sequence, IReadOnlyList<string> relativePaths)
    {
        var paths = new JsonArray();
        foreach (var path in relativePaths)
        {
            paths.Add(path);
        }

        return new JsonObject
        {
            ["type"] = MessageTypes.ClipboardFilesSet,
            ["requestId"] = $"evt_clipboard_{sequence}",
            ["origin"] = "guest",
            ["sequence"] = sequence,
            ["shareName"] = SharedFolderProbe.DefaultShareName,
            ["relativePaths"] = paths
        };
    }

    /// <summary>Deletes all but the newest batches, touching only folders whose names Veil generates.</summary>
    private static void PruneBatches(string stagingDirectory)
    {
        string[] batches;
        try
        {
            batches = Directory.GetDirectories(stagingDirectory)
                .Where(path => BatchName.IsMatch(Path.GetFileName(path)))
                .OrderBy(path => Path.GetFileName(path), StringComparer.Ordinal)
                .ToArray();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return;
        }

        foreach (var batch in batches.Take(Math.Max(0, batches.Length - RetainedBatchCount)))
        {
            TryDelete(batch);
        }
    }

    private static void TryDelete(string directory)
    {
        try
        {
            Directory.Delete(directory, recursive: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"ClipboardFileExport: could not remove {directory}. {error.Message}");
        }
    }

    private static string Normalize(string path) => path.Replace('/', '\\');

    /// <summary>The file name after either separator, so the rule is the same whichever OS runs the tests.</summary>
    private static string LastComponent(string path)
    {
        var index = path.LastIndexOfAny(['\\', '/']);
        return index < 0 ? path : path[(index + 1)..];
    }
}
