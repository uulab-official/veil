using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

/// <summary>
/// Covers the operation.ack contract for the messages the host used to send fire-and-forget.
/// Failures keep the error shape, so one host read of "one reply frame" covers both outcomes.
/// </summary>
public class AgentSessionOperationAckTests
{
    [Fact]
    public async Task AcknowledgesASuccessfulMouseInput()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputMouse,
            ["requestId"] = "req_mouse",
            ["windowId"] = "hwnd:00000010",
            ["event"] = "leftDown",
            ["x"] = 20,
            ["y"] = 30,
            ["modifiers"] = new JsonArray()
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.Equal("req_mouse", ack["requestId"]!.GetValue<string>());
        Assert.True(ack["accepted"]!.GetValue<bool>());
        Assert.Null(ack["pointer"]);
    }

    [Fact]
    public async Task ReportsWhereTheCursorWentSoTheHostCanMoveItsTablet()
    {
        var desktop = new ConfigurableWindowsDesktop { InjectedPointer = new GuestPointerPosition(16384, 8192) };
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputMouse,
            ["requestId"] = "req_mouse_pointer",
            ["windowId"] = "hwnd:00000010",
            ["event"] = "move",
            ["x"] = 20,
            ["y"] = 30,
            ["modifiers"] = new JsonArray()
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(16384, ack["pointer"]!["x"]!.GetValue<int>());
        Assert.Equal(8192, ack["pointer"]!["y"]!.GetValue<int>());
    }

    [Fact]
    public async Task AcknowledgesASuccessfulKeyInput()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputKey,
            ["requestId"] = "req_key",
            ["windowId"] = "hwnd:00000010",
            ["event"] = "keyDown",
            ["key"] = "c",
            ["windowsVirtualKey"] = 67,
            ["modifiers"] = new JsonArray("ctrl")
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.True(ack["accepted"]!.GetValue<bool>());
    }

    [Fact]
    public async Task AcknowledgesASuccessfulTextInput()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputText,
            ["requestId"] = "req_text",
            ["windowId"] = "hwnd:00000010",
            ["text"] = "안녕하세요"
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.True(ack["accepted"]!.GetValue<bool>());
    }

    [Fact]
    public async Task AcknowledgesAHostClipboardWrite()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.ClipboardTextSet,
            ["requestId"] = "req_clipboard",
            ["origin"] = "host",
            ["sequence"] = 1,
            ["text"] = "hello from macOS"
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.True(ack["accepted"]!.GetValue<bool>());
    }

    [Fact]
    public async Task KeepsTheClipboardEchoSilent()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.ClipboardTextSet,
            ["requestId"] = "req_echo",
            ["origin"] = "guest",
            ["sequence"] = 2,
            ["text"] = "copied inside windows"
        });

        Assert.Empty(replies.DirectReplies);
    }

    [Fact]
    public async Task AcknowledgesAFrameStreamSubscribeWithTheWindowStreamStarted()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.WindowFrameSubscribe,
            ["requestId"] = "req_frame_subscribe",
            ["windowId"] = "hwnd:00000010",
            ["format"] = "png"
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.True(ack["accepted"]!.GetValue<bool>());
        Assert.Equal("hwnd:00000010", replies.StreamWindow?.WindowId);
    }

    [Fact]
    public async Task AcknowledgesAFrameStreamUnsubscribe()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.WindowFrameUnsubscribe,
            ["requestId"] = "req_frame_unsubscribe",
            ["windowId"] = "hwnd:00000010"
        });

        var ack = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());
        Assert.True(ack["accepted"]!.GetValue<bool>());
        Assert.Equal("hwnd:00000010", replies.StopStreamWindowId);
    }

    [Fact]
    public async Task ReportsARejectedMouseInputAsInputMouseFailed()
    {
        var desktop = new ConfigurableWindowsDesktop { MouseResult = false };
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputMouse,
            ["requestId"] = "req_mouse_dead",
            ["windowId"] = "hwnd:00000010",
            ["event"] = "leftDown",
            ["x"] = 20,
            ["y"] = 30,
            ["modifiers"] = new JsonArray()
        });

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("input_mouse_failed", error["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task ReportsARejectedTextInputAsInputTextFailed()
    {
        var desktop = new ConfigurableWindowsDesktop { TextResult = false };
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputText,
            ["requestId"] = "req_text_dead",
            ["windowId"] = "hwnd:00000010",
            ["text"] = "hello"
        });

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("input_text_failed", error["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task ReportsARejectedKeyInputAsInputKeyFailed()
    {
        var desktop = new ConfigurableWindowsDesktop { KeyResult = false };
        var session = new AgentSession(desktop, new NoOpFrameCapture());
        await LaunchNotepadAsync(session);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputKey,
            ["requestId"] = "req_key_dead",
            ["windowId"] = "hwnd:00000010",
            ["event"] = "keyDown",
            ["key"] = "c",
            ["windowsVirtualKey"] = 67,
            ["modifiers"] = new JsonArray()
        });

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.Error, error["type"]!.GetValue<string>());
        Assert.Equal("input_key_failed", error["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task AdvertisesTheOperationAcksCapabilityInHealth()
    {
        var desktop = new ConfigurableWindowsDesktop();
        var session = new AgentSession(desktop, new NoOpFrameCapture());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var health = Assert.Single(replies.DirectReplies);
        Assert.True(health["capabilities"]!["operationAcks"]!.GetValue<bool>());
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

    private sealed class ConfigurableWindowsDesktop : IWindowsDesktop
    {
        public bool MouseResult { get; init; } = true;
        public bool KeyResult { get; init; } = true;
        public bool TextResult { get; init; } = true;

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

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(MouseResult);

        public GuestPointerPosition? InjectedPointer { get; init; }

        public GuestPointerPosition? LastInjectedPointer => InjectedPointer;

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(KeyResult);

        public Task<bool> SendTextInputAsync(WindowTextInput input, CancellationToken cancellationToken) => Task.FromResult(TextResult);

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
