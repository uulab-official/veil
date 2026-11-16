using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentSessionDisplayResizeTests
{
    [Fact]
    public async Task ForwardsAValidDesktopResizeToTheWindowsDisplay()
    {
        var desktop = new RecordingWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.DisplayResizeRequest,
            ["requestId"] = "req_display_resize",
            ["width"] = 1920,
            ["height"] = 1080
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.DisplayResizeResponse, response["type"]!.GetValue<string>());
        Assert.True(response["accepted"]!.GetValue<bool>());
        Assert.Equal(1920, desktop.LastWidth);
        Assert.Equal(1080, desktop.LastHeight);
    }

    [Theory]
    [InlineData(639, 900)]
    [InlineData(3841, 900)]
    [InlineData(1920, 4321)]
    public async Task RejectsUnsafeDesktopSizesBeforeCallingWindows(int width, int height)
    {
        var desktop = new RecordingWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.DisplayResizeRequest,
            ["requestId"] = "req_display_resize_invalid",
            ["width"] = width,
            ["height"] = height
        });

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("invalid_message", error["code"]!.GetValue<string>());
        Assert.Null(desktop.LastWidth);
        Assert.Null(desktop.LastHeight);
    }

    internal sealed class RecordingWindowsDesktop : IWindowsDesktop
    {
        public int? LastWidth { get; private set; }
        public int? LastHeight { get; private set; }

        public Task<DisplayResizeResult?> ResizeDisplayAsync(DisplayResizeInput input, CancellationToken cancellationToken)
        {
            LastWidth = input.Width;
            LastHeight = input.Height;
            return Task.FromResult<DisplayResizeResult?>(new DisplayResizeResult(input.Width, input.Height));
        }

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

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    internal sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            Task.FromException<WindowFrame>(new NotSupportedException());
    }
}
