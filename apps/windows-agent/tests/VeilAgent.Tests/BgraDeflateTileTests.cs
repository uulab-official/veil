using System.IO.Compression;
using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class BgraDeflateTileTests
{
    [Fact]
    public void DeflatesExactlyTheChangedRectangleRowByRow()
    {
        // A 4x3 surface whose bytes are their own index, so any row or offset mistake shows up.
        var pixels = Enumerable.Range(0, 4 * 3 * 4).Select(index => (byte)index).ToArray();
        var rect = new WindowFrameTileRect(1, 1, 2, 2);

        var payload = Convert.FromBase64String(GdiWindowFrameCapture.EncodeRegionBgraDeflate(pixels, 4, rect));
        using var inflater = new DeflateStream(new MemoryStream(payload), CompressionMode.Decompress);
        using var inflated = new MemoryStream();
        inflater.CopyTo(inflated);

        var expected = new byte[16];
        Array.Copy(pixels, (1 * 4 + 1) * 4, expected, 0, 8);
        Array.Copy(pixels, (2 * 4 + 1) * 4, expected, 8, 8);
        Assert.Equal(expected, inflated.ToArray());
    }

    [Fact]
    public void WritesTheTilePayloadFormatIntoTheFrameMessage()
    {
        var tile = new WindowFrameTile("hwnd:1", 7, 4, 3, 1, false, new WindowFrameTileRect(1, 1, 2, 2),
            Convert.ToBase64String(new byte[] { 1, 2, 3 }), FrameChannelCodec.BgraDeflateFormat);

        var message = FrameChannelCodec.Encode(tile);

        Assert.Equal(FrameChannelCodec.BgraDeflateFormat, message[4]);
    }

    [Fact]
    public async Task UsesDeflatedTilesOnlyForHostsThatAskForThem()
    {
        var capture = new RecordingCapture();
        var session = new AgentSession(new SingleWindowDesktop(), capture);
        await session.HandleAsync(new JsonObject { ["type"] = MessageTypes.AppLaunchRequest, ["requestId"] = "r1", ["appId"] = "winapp_notepad" });

        await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.WindowFrameSubscribe, ["requestId"] = "r2", ["windowId"] = "hwnd:00000010", ["tileFormat"] = "bgra-deflate"
        });
        await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.WindowFrameSubscribe, ["requestId"] = "r3", ["windowId"] = "hwnd:00000010"
        });

        Assert.Equal(new[] { FrameChannelCodec.BgraDeflateFormat, FrameChannelCodec.PngFormat }, capture.Formats);
    }

    private sealed class RecordingCapture : IWindowFrameCapture
    {
        public List<byte> Formats { get; } = [];
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public void SetTileFormat(string windowId, byte format) => Formats.Add(format);
    }

    private sealed class SingleWindowDesktop : IWindowsDesktop
    {
        private static readonly LaunchedWindow Window = new("hwnd:00000010", 0x10, 4912, "Untitled - Notepad", new WindowRect(10, 10, 640, 480), "normal", true);
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) => Task.FromResult(Window);
        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) => Task.FromResult(Window);
        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) => Task.FromResult(Window);
        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];
        public bool IsWindowStillOpen(string windowId) => true;
        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task<bool> SendTextInputAsync(WindowTextInput input, CancellationToken cancellationToken) => Task.FromResult(true);
        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);
        public bool TryConsumeHostClipboardEcho(string text) => false;
    }
}
