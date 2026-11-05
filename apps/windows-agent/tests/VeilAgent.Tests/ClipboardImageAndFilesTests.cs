using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

/// <summary>
/// Covers clipboard.image.set and clipboard.files.set (docs/protocol.md "Clipboard Image" and
/// "Clipboard Files"): the bounds, the hash-based echo suppression, and path containment.
/// </summary>
public class ClipboardImageAndFilesTests
{
    // The 2x2 PNG from harness/protocol-fixtures/clipboard.image.set.*.json.
    private const string PngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=";
    private const string PngSha256 = "d28c139bba718d60154960eaca75535a5cc5b59fe2153e998a29251e8e5f4667";
    private static readonly byte[] Png = Convert.FromBase64String(PngBase64);

    private static JsonObject HostImage(Action<JsonObject>? edit = null)
    {
        var message = new JsonObject
        {
            ["type"] = MessageTypes.ClipboardImageSet,
            ["requestId"] = "req_clipboard_7",
            ["origin"] = "host",
            ["sequence"] = 7,
            ["format"] = "png",
            ["width"] = 2,
            ["height"] = 2,
            ["byteLength"] = Png.Length,
            ["sha256"] = PngSha256,
            ["pngBase64"] = PngBase64
        };
        edit?.Invoke(message);
        return message;
    }

    private static JsonObject HostFiles(params string[] relativePaths) => new()
    {
        ["type"] = MessageTypes.ClipboardFilesSet,
        ["requestId"] = "req_clipboard_8",
        ["origin"] = "host",
        ["sequence"] = 8,
        ["shareName"] = "VeilShared",
        ["relativePaths"] = new JsonArray(relativePaths.Select(path => (JsonNode?)JsonValue.Create(path)).ToArray())
    };

    [Fact]
    public void ParsesTheFixtureImage()
    {
        var (image, rejection) = ClipboardImageMessage.Parse(HostImage());

        Assert.Null(rejection);
        Assert.NotNull(image);
        Assert.Equal(Png, image!.Png);
        Assert.Equal(PngSha256, image.Sha256);
    }

    [Theory]
    [InlineData("sha256", "0000000000000000000000000000000000000000000000000000000000000000", "invalid_message")]
    [InlineData("width", 3, "invalid_message")]
    [InlineData("byteLength", 75, "invalid_message")]
    [InlineData("format", "jpeg", "invalid_message")]
    [InlineData("byteLength", ClipboardImageMessage.MaxPngBytes + 1, "clipboard_image_too_large")]
    [InlineData("width", 16_385, "clipboard_image_too_large")]
    public void RejectsImagesThatDisagreeWithTheirBytesOrBounds(string field, object value, string expectedCode)
    {
        var message = HostImage(edit => edit[field] = value switch
        {
            int number => JsonValue.Create(number),
            string text => JsonValue.Create(text),
            _ => throw new ArgumentException("unsupported test value")
        });

        var (image, rejection) = ClipboardImageMessage.Parse(message);

        Assert.Null(image);
        Assert.Equal(expectedCode, rejection?.Code);
    }

    [Fact]
    public void RejectsAPixelCountAboveTheBoundEvenWithinTheDimensionBound()
    {
        Assert.True(ClipboardImageMessage.DimensionsAllowed(8_192, 4_096));
        Assert.False(ClipboardImageMessage.DimensionsAllowed(16_384, 16_384));
    }

    [Fact]
    public void TrimsAllocationPaddingAfterTheIendChunk()
    {
        var padded = Png.Concat(new byte[16]).ToArray();

        Assert.Equal(Png, ClipboardImageMessage.TrimToPngEnd(padded));
        Assert.Equal(PngSha256, ClipboardImageMessage.Sha256Hex(ClipboardImageMessage.TrimToPngEnd(padded)));
    }

    [Fact]
    public async Task AcknowledgesAHostImageAfterWritingIt()
    {
        var desktop = new ClipboardRecordingDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(HostImage());

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.Equal("req_clipboard_7", ack["requestId"]!.GetValue<string>());
        Assert.Equal(Png, Assert.Single(desktop.WrittenImages));
    }

    [Fact]
    public async Task DoesNotWriteATamperedHostImage()
    {
        var desktop = new ClipboardRecordingDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(HostImage(edit => edit["sha256"] = new string('a', 64)));

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal("invalid_message", error["code"]!.GetValue<string>());
        Assert.Empty(desktop.WrittenImages);
    }

    [Fact]
    public async Task ReportsAClipboardImageWriteFailure()
    {
        var desktop = new ClipboardRecordingDesktop { ImageWriteError = new InvalidOperationException("OpenClipboard failed.") };
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(HostImage());

        Assert.Equal("clipboard_image_failed", Assert.Single(replies.DirectReplies)["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task PlacesSharedFolderFilesResolvedUnderTheGuestShare()
    {
        var desktop = new ClipboardRecordingDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(HostFiles(@"Veil Clipboard\20261105-140102-1A2B3C\report.pdf"));

        Assert.Equal(MessageTypes.OperationAck, Assert.Single(replies.DirectReplies)["type"]!.GetValue<string>());
        var paths = Assert.Single(desktop.WrittenFileLists);
        Assert.Equal(new[] { @"C:\VeilShared\Veil Clipboard\20261105-140102-1A2B3C\report.pdf" }, paths);
    }

    [Theory]
    [InlineData(@"Veil Clipboard\..\..\Windows\win.ini")]
    [InlineData(@"C:\Windows\win.ini")]
    [InlineData(@"Veil Clipboard\batch\file.txt:secret")]
    [InlineData(@"Veil Clipboard\batch\CON.txt")]
    [InlineData(@"Other\file.txt")]
    [InlineData(@"Veil Clipboard\\file.txt")]
    [InlineData("Veil Clipboard/batch/file.txt")]
    public async Task RejectsFilePathsThatEscapeTheClipboardFolder(string relativePath)
    {
        var desktop = new ClipboardRecordingDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(HostFiles(relativePath));

        Assert.Equal("invalid_shared_file_path", Assert.Single(replies.DirectReplies)["code"]!.GetValue<string>());
        Assert.Empty(desktop.WrittenFileLists);
    }

    [Fact]
    public async Task RejectsTheWholePasteWhenOneFileIsMissing()
    {
        var desktop = new ClipboardRecordingDesktop { MissingFileName = "gone.txt" };
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(HostFiles(
            @"Veil Clipboard\20261105-140102-1A2B3C\here.txt",
            @"Veil Clipboard\20261105-140102-1A2B3C\gone.txt"
        ));

        Assert.Equal("invalid_shared_file_path", Assert.Single(replies.DirectReplies)["code"]!.GetValue<string>());
        Assert.Empty(desktop.WrittenFileLists);
    }

    [Fact]
    public async Task RejectsGuestOriginFiles()
    {
        var session = new AgentSession(new ClipboardRecordingDesktop(), new NoOpFrameCapture());
        var message = HostFiles(@"Veil Clipboard\batch\file.txt");
        message["origin"] = "guest";

        var replies = await session.HandleAsync(message);

        Assert.Equal("invalid_message", Assert.Single(replies.DirectReplies)["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task HealthAdvertisesImageAndFileClipboards()
    {
        var session = new AgentSession(new ClipboardRecordingDesktop(), new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var capabilities = Assert.Single(replies.DirectReplies)["capabilities"]!;
        Assert.True(capabilities["clipboardImage"]!.GetValue<bool>());
        Assert.True(capabilities["clipboardFiles"]!.GetValue<bool>());
    }

    [Fact]
    public async Task StreamsAGuestImageOnceAndSharesTheTextSequence()
    {
        var desktop = new ClipboardRecordingDesktop();
        desktop.ClipboardScript.Enqueue(("first text", null, 1));
        desktop.ClipboardScript.Enqueue((null, Png, 2));
        // Windows bumped its sequence number for an identical re-set; the hash must stop a second broadcast.
        desktop.ClipboardScript.Enqueue((null, Png, 3));
        desktop.ClipboardScript.Enqueue(("first text", null, 4));

        var broadcasts = await CollectBroadcastsAsync(desktop, expected: 3);

        Assert.Equal(
            new[] { MessageTypes.ClipboardTextSet, MessageTypes.ClipboardImageSet, MessageTypes.ClipboardTextSet },
            broadcasts.Select(message => message["type"]!.GetValue<string>())
        );
        Assert.Equal(new[] { 1, 2, 3 }, broadcasts.Select(message => message["sequence"]!.GetValue<int>()));
        Assert.Equal(PngSha256, broadcasts[1]["sha256"]!.GetValue<string>());
        Assert.Equal("guest", broadcasts[1]["origin"]!.GetValue<string>());
    }

    [Fact]
    public async Task DoesNotEchoAnImageTheHostJustWrote()
    {
        var desktop = new ClipboardRecordingDesktop { HostImageEchoSha256 = PngSha256 };
        desktop.ClipboardScript.Enqueue((null, Png, 1));
        desktop.ClipboardScript.Enqueue(("after the echo", null, 2));

        var broadcasts = await CollectBroadcastsAsync(desktop, expected: 1);

        var only = Assert.Single(broadcasts);
        Assert.Equal(MessageTypes.ClipboardTextSet, only["type"]!.GetValue<string>());
    }

    [Fact]
    public void BuildsAWideDropFilesBlock()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var drop = WindowsClipboardFormats.BuildDropFiles([@"C:\VeilShared\a.txt"]);

        Assert.Equal(20u, BitConverter.ToUInt32(drop, 0));
        Assert.Equal(1, BitConverter.ToInt32(drop, 16));
        Assert.Equal("C:\\VeilShared\\a.txt\0\0", System.Text.Encoding.Unicode.GetString(drop, 20, drop.Length - 20));
    }

    [Fact]
    public void ConvertsBetweenPngAndDib()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var dib = ClipboardBitmapConverter.PngToDib(Png);
        Assert.Equal(2, BitConverter.ToInt32(dib, 4));

        var png = ClipboardBitmapConverter.DibToPng(dib);
        Assert.NotNull(png);
        Assert.True(ClipboardImageMessage.TryReadDimensions(png!, out var width, out var height));
        Assert.Equal((2, 2), (width, height));
    }

    private static async Task<List<JsonObject>> CollectBroadcastsAsync(ClipboardRecordingDesktop desktop, int expected)
    {
        var streamer = new ClipboardTextStreamer(desktop, interval: TimeSpan.FromMilliseconds(5));
        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        try
        {
            await streamer.StreamAsync(
                (message, _) =>
                {
                    broadcasts.Add(message);
                    if (broadcasts.Count >= expected && desktop.ClipboardScript.Count == 0)
                    {
                        cancellation.Cancel();
                    }

                    return Task.CompletedTask;
                },
                cancellation.Token
            );
        }
        catch (OperationCanceledException)
        {
            // Expected: the test cancels once the script has played out.
        }

        return broadcasts;
    }

    /// <summary>
    /// Plays a scripted clipboard: each tick the current entry's text and image are what Windows holds, and
    /// the entry advances when the sequence number is read after its text.
    /// </summary>
    private sealed class ClipboardRecordingDesktop : IWindowsDesktop
    {
        public Queue<(string? Text, byte[]? Png, uint Sequence)> ClipboardScript { get; } = new();
        public List<byte[]> WrittenImages { get; } = [];
        public List<IReadOnlyList<string>> WrittenFileLists { get; } = [];
        public Exception? ImageWriteError { get; init; }
        public string? MissingFileName { get; init; }
        public string? HostImageEchoSha256 { get; set; }
        private (string? Text, byte[]? Png, uint Sequence) current;

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken)
        {
            if (ClipboardScript.Count > 0)
            {
                current = ClipboardScript.Dequeue();
            }

            return Task.FromResult(current.Text);
        }

        public uint GetClipboardSequenceNumber() => current.Sequence;

        public Task<byte[]?> GetClipboardImagePngAsync(CancellationToken cancellationToken) =>
            Task.FromResult(current.Png);

        public Task SetClipboardImagePngAsync(byte[] png, string sha256, CancellationToken cancellationToken)
        {
            if (ImageWriteError is not null)
            {
                throw ImageWriteError;
            }

            WrittenImages.Add(png);
            return Task.CompletedTask;
        }

        public bool TryConsumeHostClipboardImageEcho(string sha256)
        {
            if (HostImageEchoSha256 != sha256)
            {
                return false;
            }

            HostImageEchoSha256 = null;
            return true;
        }

        public Task SetClipboardFilesAsync(IReadOnlyList<string> fullPaths, CancellationToken cancellationToken)
        {
            WrittenFileLists.Add(fullPaths);
            return Task.CompletedTask;
        }

        public bool IsRegularSharedFile(string fullPath) =>
            MissingFileName is null || !fullPath.EndsWith(MissingFileName, StringComparison.Ordinal);

        public bool TryConsumeHostClipboardEcho(string text) => false;

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => false;

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(false);

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(false);

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(false);

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(false);
    }

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            Task.FromException<WindowFrame>(new NotSupportedException());
    }
}
