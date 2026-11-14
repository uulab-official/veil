using System.Text;
using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public sealed class ClipboardFileExportTests : IDisposable
{
    private static readonly DateTime Now = new(2026, 11, 11, 5, 1, 2, DateTimeKind.Utc);
    private readonly string root = Path.Combine(Path.GetTempPath(), "veil-export-" + Guid.NewGuid().ToString("N"));
    private readonly string share;
    private readonly string sources;

    public ClipboardFileExportTests()
    {
        share = Path.Combine(root, "VeilShared");
        sources = Path.Combine(root, "Documents");
        Directory.CreateDirectory(share);
        Directory.CreateDirectory(sources);
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(root, recursive: true);
        }
        catch (IOException)
        {
        }
    }

    private string Source(string name, string content = "hello")
    {
        var path = Path.Combine(sources, name);
        File.WriteAllText(path, content);
        return path;
    }

    [Fact]
    public void ParsesTheWidePathsExplorerWrites()
    {
        var drop = WindowsClipboardFormatsTestHelper.BuildDropFiles([@"C:\Users\me\a.txt", @"C:\Users\me\b c.pdf"]);

        Assert.Equal([@"C:\Users\me\a.txt", @"C:\Users\me\b c.pdf"], ClipboardFileExport.ParseDropFiles(drop));
    }

    [Fact]
    public void RejectsAnsiAndTruncatedDropBlocks()
    {
        var drop = WindowsClipboardFormatsTestHelper.BuildDropFiles([@"C:\a.txt"]);
        var ansi = (byte[])drop.Clone();
        BitConverter.TryWriteBytes(ansi.AsSpan(16, 4), 0);
        var truncated = drop[..^4];
        var badOffset = (byte[])drop.Clone();
        BitConverter.TryWriteBytes(badOffset.AsSpan(0, 4), 4096u);

        Assert.Null(ClipboardFileExport.ParseDropFiles(ansi));
        Assert.Null(ClipboardFileExport.ParseDropFiles(truncated));
        Assert.Null(ClipboardFileExport.ParseDropFiles(badOffset));
        Assert.Null(ClipboardFileExport.ParseDropFiles(new byte[8]));
    }

    [Fact]
    public void StopsReadingOnceTheSelectionIsTooLong()
    {
        var paths = Enumerable.Range(0, 200).Select(index => $@"C:\f{index}.txt").ToList();
        var parsed = ClipboardFileExport.ParseDropFiles(WindowsClipboardFormatsTestHelper.BuildDropFiles(paths));

        Assert.Equal(ClipboardFileExport.MaxFileCount + 1, parsed!.Count);
    }

    [Fact]
    public void StagesFilesIntoAFreshBatchAndNamesThemRelativeToTheShare()
    {
        var export = new ClipboardFileExport(share);

        var result = export.Stage([Source("budget.xlsx", "numbers"), Source("notes.txt")], Now, "4D5E6F");

        Assert.Null(result.Refusal);
        Assert.Equal(
            [
                @"Veil Clipboard from Windows\20261111-050102-4D5E6F\budget.xlsx",
                @"Veil Clipboard from Windows\20261111-050102-4D5E6F\notes.txt"
            ],
            result.RelativePaths
        );
        var staged = Path.Combine(share, ClipboardFileExport.DirectoryName, "20261111-050102-4D5E6F", "budget.xlsx");
        Assert.Equal("numbers", File.ReadAllText(staged));
    }

    [Fact]
    public void RefusesFoldersLinksDuplicatesAndOversizedSelectionsWithoutStaging()
    {
        var export = new ClipboardFileExport(share);
        var folder = Path.Combine(sources, "Project");
        Directory.CreateDirectory(folder);
        var link = Path.Combine(sources, "link.txt");
        File.CreateSymbolicLink(link, Source("target.txt"));
        var otherFolder = Path.Combine(root, "Other");
        Directory.CreateDirectory(otherFolder);
        var duplicate = Path.Combine(otherFolder, "NOTES.TXT");
        File.WriteAllText(duplicate, "x");

        Assert.Contains("folder", export.Stage([Source("a.txt"), folder], Now, "000001").Refusal);
        Assert.Contains("link", export.Stage([link], Now, "000002").Refusal);
        Assert.Contains("both named", export.Stage([Source("notes.txt"), duplicate], Now, "000003").Refusal);
        Assert.Contains(
            "More than",
            export.Stage(Enumerable.Repeat(Source("a.txt"), ClipboardFileExport.MaxFileCount + 1).ToList(), Now, "000004").Refusal
        );

        // Nothing was staged for any refusal, so the host is never told about part of a selection.
        var staging = Path.Combine(share, ClipboardFileExport.DirectoryName);
        Assert.False(Directory.Exists(staging) && Directory.EnumerateFileSystemEntries(staging).Any());
    }

    [Fact]
    public void RefusesTotalsAboveTheCapBeforeCopying()
    {
        var export = new ClipboardFileExport(share);
        var large = Path.Combine(sources, "large.bin");
        using (var stream = File.Create(large))
        {
            stream.SetLength(ClipboardFileExport.MaxTotalBytes + 1);
        }

        Assert.Contains("exceed", export.Stage([large], Now, "000005").Refusal);
        Assert.False(Directory.Exists(Path.Combine(share, ClipboardFileExport.DirectoryName, "20261111-050102-000005")));
    }

    [Fact]
    public void RefusesWhenTheShareFolderIsMissing()
    {
        var export = new ClipboardFileExport(Path.Combine(root, "missing"));

        Assert.Contains("does not exist", export.Stage([Source("a.txt")], Now, "000006").Refusal);
    }

    [Fact]
    public void KeepsOnlyTheNewestBatchesAndLeavesOtherFoldersAlone()
    {
        var export = new ClipboardFileExport(share);
        var staging = Path.Combine(share, ClipboardFileExport.DirectoryName);
        Directory.CreateDirectory(Path.Combine(staging, "Keep me"));
        for (var second = 0; second < 5; second += 1)
        {
            Assert.Null(export.Stage([Source("a.txt")], Now.AddSeconds(second), "ABCDEF").Refusal);
        }

        var remaining = Directory.GetDirectories(staging).Select(Path.GetFileName).Order(StringComparer.Ordinal).ToArray();
        Assert.Equal(["20261111-050104-ABCDEF", "20261111-050105-ABCDEF", "20261111-050106-ABCDEF", "Keep me"], remaining);
    }

    [Fact]
    public void RecognisesFilesAHostPastePlacedInTheShare()
    {
        var export = new ClipboardFileExport(@"C:\VeilShared");

        Assert.True(export.IsVeilStaged([@"C:\VeilShared\Veil Clipboard\20261105-140102-1A2B3C\report.pdf"]));
        Assert.True(export.IsVeilStaged([@"c:\veilshared\veil clipboard from windows\x\a.txt"]));
        Assert.False(export.IsVeilStaged([@"C:\VeilShared\report.pdf", @"C:\Users\me\Veil Clipboard\a.txt"]));
    }

    [Fact]
    public async Task StreamerStagesAnExplorerCopyOnceAndPrefersFilesOverText()
    {
        var source = Source("budget.xlsx");
        var desktop = new FileDropDesktop { Paths = [source], Text = source, SequenceNumber = 7 };
        var streamer = new ClipboardTextStreamer(
            desktop,
            interval: TimeSpan.FromMilliseconds(5),
            fileExport: new ClipboardFileExport(share),
            utcNow: () => Now
        );

        var broadcasts = await CollectAsync(streamer, ticks: 6);

        var message = Assert.Single(broadcasts);
        Assert.Equal("clipboard.files.set", message["type"]!.GetValue<string>());
        Assert.Equal("guest", message["origin"]!.GetValue<string>());
        Assert.Equal(1, message["sequence"]!.GetValue<int>());
        Assert.Equal("VeilShared", message["shareName"]!.GetValue<string>());
        var relativePath = Assert.Single(message["relativePaths"]!.AsArray())!.GetValue<string>();
        Assert.StartsWith(@"Veil Clipboard from Windows\20261111-050102-", relativePath);
        Assert.EndsWith(@"\budget.xlsx", relativePath);
    }

    [Fact]
    public async Task StreamerDoesNotEchoAHostPasteBackToTheHost()
    {
        var hostPasted = Path.Combine(share, "Veil Clipboard", "20261105-140102-1A2B3C");
        Directory.CreateDirectory(hostPasted);
        var file = Path.Combine(hostPasted, "report.pdf");
        File.WriteAllText(file, "pdf");
        var desktop = new FileDropDesktop { Paths = [file], SequenceNumber = 3 };
        var streamer = new ClipboardTextStreamer(
            desktop,
            interval: TimeSpan.FromMilliseconds(5),
            fileExport: new ClipboardFileExport(share)
        );

        Assert.Empty(await CollectAsync(streamer, ticks: 4));
    }

    [Fact]
    public async Task StreamerWithoutAnExportIgnoresFilesAndSendsText()
    {
        var desktop = new FileDropDesktop { Paths = [Source("a.txt")], Text = "plain text", SequenceNumber = 1 };
        var streamer = new ClipboardTextStreamer(desktop, interval: TimeSpan.FromMilliseconds(5));

        var message = Assert.Single(await CollectAsync(streamer, ticks: 4));
        Assert.Equal("clipboard.text.set", message["type"]!.GetValue<string>());
    }

    private static async Task<List<JsonObject>> CollectAsync(ClipboardTextStreamer streamer, int ticks)
    {
        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(ticks * 5 + 200));
        try
        {
            await streamer.StreamAsync(
                (message, _) =>
                {
                    broadcasts.Add(message);
                    return Task.CompletedTask;
                },
                cancellation.Token
            );
        }
        catch (OperationCanceledException)
        {
        }

        return broadcasts;
    }

    private sealed class FileDropDesktop : IWindowsDesktop
    {
        public IReadOnlyList<string>? Paths { get; set; }
        public string? Text { get; set; }
        public uint SequenceNumber { get; set; }

        public bool IsClipboardFileDropAvailable() => Paths is not null;

        public Task<IReadOnlyList<string>?> GetClipboardFileDropAsync(CancellationToken cancellationToken) =>
            Task.FromResult(Paths);

        public uint GetClipboardSequenceNumber() => SequenceNumber;

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult(Text);

        public bool TryConsumeHostClipboardEcho(string text) => false;

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) =>
            throw new NotSupportedException();

        public bool IsWindowStillOpen(string windowId) => throw new NotSupportedException();

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}

/// <summary>Builds DROPFILES the way <c>WindowsClipboardFormats.BuildDropFiles</c> does, without Win32.</summary>
internal static class WindowsClipboardFormatsTestHelper
{
    public static byte[] BuildDropFiles(IReadOnlyList<string> paths)
    {
        var names = new StringBuilder();
        foreach (var path in paths)
        {
            names.Append(path).Append('\0');
        }

        names.Append('\0');
        var nameBytes = Encoding.Unicode.GetBytes(names.ToString());
        var drop = new byte[20 + nameBytes.Length];
        BitConverter.TryWriteBytes(drop.AsSpan(0, 4), 20u);
        BitConverter.TryWriteBytes(drop.AsSpan(16, 4), 1);
        Buffer.BlockCopy(nameBytes, 0, drop, 20, nameBytes.Length);
        return drop;
    }
}
