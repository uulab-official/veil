using Veil.Agent;

namespace VeilAgent.Tests;

public class PopupWindowEventTests
{
    private static readonly WindowsAppDescriptor Paint = new("winapp_paint", "Paint", "mspaint.exe", "Microsoft", "icon_paint");

    [Theory]
    // Owned, no title bar: Paint's text formatting bar, a menu, a tooltip.
    [InlineData(0x80000000L, true, true)]
    // Owned with a title bar: a Save As dialog stays an ordinary window.
    [InlineData(0x80C80000L, true, false)]
    // Unowned without a title bar: an app main window that draws its own caption.
    [InlineData(0x80000000L, false, false)]
    public void ClassifiesOnlyOwnedCaptionlessWindowsAsPopups(long style, bool hasOwner, bool expected)
    {
        Assert.Equal(expected, WindowsDesktop.IsPopup(style, hasOwner));
    }

    [Fact]
    public void MarksPopupsAndTheirOwnerOnWindowCreated()
    {
        var session = new AgentSession(new NoWindowsDesktop(), new NoFrames());
        var popup = new LaunchedWindow(
            "hwnd:00000020", 0x20, 4912, "팝업 호스트", new WindowRect(40, 120, 942, 84), "normal", false,
            IsPopup: true, OwnerWindowId: "hwnd:00000010"
        );

        var message = session.TryTrackDiscoveredWindow(Paint, popup)!;

        Assert.True(message["popup"]!.GetValue<bool>());
        Assert.Equal("hwnd:00000010", message["ownerWindowId"]!.GetValue<string>());
    }

    [Fact]
    public void AttachesToTheAppWindowRatherThanAPopupAboveIt()
    {
        var popup = new LaunchedWindow("hwnd:00000020", 0x20, 4912, "팝업 호스트", new WindowRect(40, 120, 942, 84), "normal", true, IsPopup: true, OwnerWindowId: "hwnd:00000010");
        var main = new LaunchedWindow("hwnd:00000010", 0x10, 4912, "제목 없음 - 그림판", new WindowRect(0, 0, 1182, 709), "normal", true);

        Assert.Equal("hwnd:00000010", AgentSession.PrimaryWindow([popup, main]).WindowId);
        Assert.Equal("hwnd:00000020", AgentSession.PrimaryWindow([popup]).WindowId);
    }

    [Fact]
    public async Task AnnouncesOpenPopupsWhenReattachingToAnApp()
    {
        var popup = new LaunchedWindow("hwnd:00000020", 0x20, 4912, "팝업 호스트", new WindowRect(40, 120, 942, 84), "normal", true, IsPopup: true, OwnerWindowId: "hwnd:00000010");
        var main = new LaunchedWindow("hwnd:00000010", 0x10, 4912, "제목 없음 - 그림판", new WindowRect(0, 0, 1182, 709), "normal", true);
        var session = new AgentSession(new NoWindowsDesktop([popup, main]), new NoFrames());

        var replies = await session.HandleAsync(new System.Text.Json.Nodes.JsonObject
        {
            ["type"] = MessageTypes.AppLaunchRequest,
            ["requestId"] = "req_reattach",
            ["appId"] = "winapp_paint",
            ["reuseExistingWindow"] = true
        });

        Assert.Equal("hwnd:00000010", replies.StreamWindow!.WindowId);
        var announcedPopup = Assert.Single(replies.BroadcastEvents, message => message["type"]!.GetValue<string>() == MessageTypes.WindowCreated);
        Assert.Equal("hwnd:00000020", announcedPopup["windowId"]!.GetValue<string>());
        Assert.True(announcedPopup["popup"]!.GetValue<bool>());
    }

    [Fact]
    public void LeavesOrdinaryWindowEventsUnchanged()
    {
        var session = new AgentSession(new NoWindowsDesktop(), new NoFrames());
        var window = new LaunchedWindow("hwnd:00000030", 0x30, 4912, "Paint", new WindowRect(0, 0, 800, 600), "normal", true);

        var message = session.TryTrackDiscoveredWindow(Paint, window)!;

        Assert.Null(message["popup"]);
        Assert.Null(message["ownerWindowId"]);
    }

    private sealed class NoFrames : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private sealed class NoWindowsDesktop(IReadOnlyList<LaunchedWindow>? openWindows = null) : IWindowsDesktop
    {
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => openWindows ?? [];
        public bool IsWindowStillOpen(string windowId) => false;
        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> SendTextInputAsync(WindowTextInput input, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);
        public bool TryConsumeHostClipboardEcho(string text) => false;
    }
}
