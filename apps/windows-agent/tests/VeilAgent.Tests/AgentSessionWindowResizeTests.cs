using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentSessionWindowResizeTests
{
    [Fact]
    public async Task ResizesATrackedWindowAndReturnsTheAppliedBounds()
    {
        var desktop = new RecordingWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.WindowResizeRequest,
            ["requestId"] = "req_resize",
            ["windowId"] = "hwnd:00000010",
            ["width"] = 1440,
            ["height"] = 900
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.WindowResizeResponse, response["type"]!.GetValue<string>());
        Assert.True(response["accepted"]!.GetValue<bool>());
        Assert.Equal(1440, desktop.LastWidth);
        Assert.Equal(900, desktop.LastHeight);
        Assert.Equal(1440, response["bounds"]!["width"]!.GetValue<int>());
        Assert.Equal(900, response["bounds"]!["height"]!.GetValue<int>());
    }

    [Theory]
    [InlineData(319, 900)]
    [InlineData(8_193, 900)]
    [InlineData(4_000, 8_193)]
    public async Task RejectsAnUnsafeSizeBeforeCallingTheDesktop(int width, int height)
    {
        var desktop = new RecordingWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.WindowResizeRequest,
            ["requestId"] = "req_resize_invalid",
            ["windowId"] = "hwnd:00000010",
            ["width"] = width,
            ["height"] = height
        });

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("invalid_message", error["code"]!.GetValue<string>());
        Assert.Null(desktop.LastWidth);
        Assert.Null(desktop.LastHeight);
    }

    private static async Task LaunchNotepadAsync(AgentSession session)
    {
        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AppLaunchRequest,
            ["requestId"] = "req_launch",
            ["appId"] = "winapp_notepad"
        });

        Assert.Contains(replies.DirectReplies, reply => reply["type"]!.GetValue<string>() == MessageTypes.WindowCreated);
    }

    private sealed class RecordingWindowsDesktop : IWindowsDesktop
    {
        public int? LastWidth { get; private set; }
        public int? LastHeight { get; private set; }

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            Task.FromResult(new LaunchedWindow(
                "hwnd:00000010",
                0x10,
                4912,
                "Untitled - Notepad",
                new WindowRect(10, 10, 640, 480),
                "normal",
                true
            ));

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            LaunchAppAsync(app, cancellationToken);

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            LaunchAppAsync(new WindowsAppDescriptor("winapp_notepad", "Notepad", "notepad.exe", "Microsoft", "icon_notepad"), cancellationToken);

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => windowId == "hwnd:00000010";

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);

        public Task<WindowRect?> ResizeWindowAsync(WindowResizeInput input, CancellationToken cancellationToken)
        {
            LastWidth = input.Width;
            LastHeight = input.Height;
            return Task.FromResult<WindowRect?>(new WindowRect(10, 10, input.Width, input.Height));
        }

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(true);

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(true);

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            Task.FromException<WindowFrame>(new NotSupportedException());
    }
}
