using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentSessionOperationAcknowledgementTests
{
    private const string WindowId = "hwnd:0003029A";

    private sealed class ScriptedWindowsDesktop : IWindowsDesktop
    {
        public bool MouseInputAccepted { get; init; } = true;
        public bool KeyInputAccepted { get; init; } = true;

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            Task.FromResult(new LaunchedWindow(
                WindowId,
                Hwnd: 0,
                ProcessId: 4912,
                Title: "Untitled - Notepad",
                Bounds: new WindowRect(10, 10, 1280, 800),
                State: "normal",
                Focused: true
            ));

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            LaunchAppAsync(new WindowsAppDescriptor("winapp_notepad", "Notepad", "notepad.exe", "Microsoft", "icon_notepad"), cancellationToken);

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => windowId == WindowId;

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(true);

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) =>
            Task.FromResult(MouseInputAccepted);

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) =>
            Task.FromResult(KeyInputAccepted);

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Fact]
    public async Task AcknowledgesSuccessfulMouseInputWithRequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(MouseRequest("leftDown", "req_mouse_1"));

        var reply = Assert.Single(replies.DirectReplies);
        Assert.Equal("operation.response", reply["type"]!.GetValue<string>());
        Assert.Equal("req_mouse_1", reply["requestId"]!.GetValue<string>());
        Assert.Equal("input.mouse", reply["operation"]!.GetValue<string>());
        Assert.True(reply["accepted"]!.GetValue<bool>());
    }

    [Fact]
    public async Task AcknowledgesSuccessfulKeyInputWithRequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(KeyRequest("req_key_1"));

        AssertOperationAccepted(Assert.Single(replies.DirectReplies), "req_key_1", MessageTypes.InputKey);
    }

    [Fact]
    public async Task AcknowledgesSuccessfulHostClipboardSetWithRequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(ClipboardRequest("host", "req_clipboard_1"));

        AssertOperationAccepted(Assert.Single(replies.DirectReplies), "req_clipboard_1", MessageTypes.ClipboardTextSet);
    }

    [Fact]
    public async Task AcknowledgesSuccessfulFrameSubscribeWithRequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(FrameSubscriptionRequest(MessageTypes.WindowFrameSubscribe, "req_subscribe_1"));

        AssertOperationAccepted(Assert.Single(replies.DirectReplies), "req_subscribe_1", MessageTypes.WindowFrameSubscribe);
    }

    [Fact]
    public async Task AcknowledgesSuccessfulFrameUnsubscribeWithRequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(FrameSubscriptionRequest(MessageTypes.WindowFrameUnsubscribe, "req_unsubscribe_1"));

        AssertOperationAccepted(Assert.Single(replies.DirectReplies), "req_unsubscribe_1", MessageTypes.WindowFrameUnsubscribe);
    }

    [Theory]
    [MemberData(nameof(LegacyOperationRequests))]
    public async Task KeepsLegacyOperationsWithoutRequestIdsSilent(JsonObject request)
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(request);

        Assert.Empty(replies.DirectReplies);
    }

    [Fact]
    public async Task KeepsMouseMoveSilentEvenWhenItHasARequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(MouseRequest("move", "req_mouse_move_1"));

        Assert.Empty(replies.DirectReplies);
    }

    [Fact]
    public async Task KeepsRejectedMouseMoveSilent()
    {
        var session = await CreateTrackedSessionAsync(mouseInputAccepted: false);

        var replies = await session.HandleAsync(MouseRequest("move", "req_mouse_move_2"));

        Assert.Empty(replies.DirectReplies);
    }

    [Fact]
    public async Task KeepsGuestOriginClipboardSilentEvenWhenItHasARequestId()
    {
        var session = await CreateTrackedSessionAsync();

        var replies = await session.HandleAsync(ClipboardRequest("guest", "req_guest_clipboard_1"));

        Assert.Empty(replies.DirectReplies);
    }

    [Fact]
    public async Task ReturnsMouseRejectedErrorWhenTheDesktopRejectsNonMoveInput()
    {
        var session = await CreateTrackedSessionAsync(mouseInputAccepted: false);

        var replies = await session.HandleAsync(MouseRequest("leftDown", "req_mouse_rejected"));

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("req_mouse_rejected", error["requestId"]!.GetValue<string>());
        Assert.Equal("input_mouse_rejected", error["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task ReturnsKeyRejectedErrorWhenTheDesktopRejectsInput()
    {
        var session = await CreateTrackedSessionAsync(keyInputAccepted: false);

        var replies = await session.HandleAsync(KeyRequest("req_key_rejected"));

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("req_key_rejected", error["requestId"]!.GetValue<string>());
        Assert.Equal("input_key_rejected", error["code"]!.GetValue<string>());
    }

    public static IEnumerable<object[]> LegacyOperationRequests()
    {
        yield return [MouseRequest("leftDown")];
        yield return [KeyRequest()];
        yield return [ClipboardRequest("host")];
        yield return [FrameSubscriptionRequest(MessageTypes.WindowFrameSubscribe)];
        yield return [FrameSubscriptionRequest(MessageTypes.WindowFrameUnsubscribe)];
    }

    private static async Task<AgentSession> CreateTrackedSessionAsync(bool mouseInputAccepted = true, bool keyInputAccepted = true)
    {
        var session = new AgentSession(
            new ScriptedWindowsDesktop
            {
                MouseInputAccepted = mouseInputAccepted,
                KeyInputAccepted = keyInputAccepted
            },
            new NoOpFrameCapture()
        );

        await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AppLaunchRequest,
            ["requestId"] = "req_launch_notepad",
            ["appId"] = "winapp_notepad"
        });

        return session;
    }

    private static JsonObject MouseRequest(string eventName, string? requestId = null) => new()
    {
        ["type"] = MessageTypes.InputMouse,
        ["requestId"] = requestId,
        ["windowId"] = WindowId,
        ["event"] = eventName,
        ["x"] = 20,
        ["y"] = 30,
        ["modifiers"] = new JsonArray()
    };

    private static JsonObject KeyRequest(string? requestId = null) => new()
    {
        ["type"] = MessageTypes.InputKey,
        ["requestId"] = requestId,
        ["windowId"] = WindowId,
        ["event"] = "keyDown",
        ["key"] = "V",
        ["windowsVirtualKey"] = 86,
        ["modifiers"] = new JsonArray("ctrl")
    };

    private static JsonObject ClipboardRequest(string origin, string? requestId = null) => new()
    {
        ["type"] = MessageTypes.ClipboardTextSet,
        ["requestId"] = requestId,
        ["origin"] = origin,
        ["sequence"] = 1,
        ["text"] = "hello from macOS"
    };

    private static JsonObject FrameSubscriptionRequest(string type, string? requestId = null) => new()
    {
        ["type"] = type,
        ["requestId"] = requestId,
        ["windowId"] = WindowId
    };

    private static void AssertOperationAccepted(JsonObject reply, string requestId, string operation)
    {
        Assert.Equal(MessageTypes.OperationResponse, reply["type"]!.GetValue<string>());
        Assert.Equal(requestId, reply["requestId"]!.GetValue<string>());
        Assert.Equal(operation, reply["operation"]!.GetValue<string>());
        Assert.True(reply["accepted"]!.GetValue<bool>());
    }
}
