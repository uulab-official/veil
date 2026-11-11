using System.Text.Json.Nodes;
using Veil.Agent;
namespace VeilAgent.Tests;

public sealed class GuestImeModeTests
{
    [Fact]
    public void NativeSetsOnlyTheNativeBit()
    {
        // Japanese hiragana is native + full-shape (0x9); English full-shape (0x8) keeps full-shape.
        Assert.Equal(0x9, GuestImeMode.ConversionMode(0x8, GuestImeMode.Native));
        Assert.Equal(0x8, GuestImeMode.ConversionMode(0x9, GuestImeMode.Alphanumeric));
        Assert.Equal(0x0, GuestImeMode.ConversionMode(0x1, GuestImeMode.Alphanumeric));
    }

    [Fact]
    public async Task AppliesAValidModeAndAcknowledgesIt()
    {
        var applied = new List<string>();
        var session = new AgentSession(new IdleDesktop(), new NoCapture(), imeModeSink: applied.Add);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputImeSet,
            ["requestId"] = "req_ime",
            ["mode"] = "alphanumeric"
        });

        Assert.Equal(MessageTypes.OperationAck, Assert.Single(replies.DirectReplies)["type"]!.GetValue<string>());
        Assert.Equal(["alphanumeric"], applied);
    }

    [Fact]
    public async Task RejectsAnUnknownMode()
    {
        var applied = new List<string>();
        var session = new AgentSession(new IdleDesktop(), new NoCapture(), imeModeSink: applied.Add);

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.InputImeSet,
            ["requestId"] = "req_ime_bad",
            ["mode"] = "hangul"
        });

        Assert.Equal("invalid_message", Assert.Single(replies.DirectReplies)["code"]!.GetValue<string>());
        Assert.Empty(applied);
    }

    private sealed class IdleDesktop : IWindowsDesktop
    {
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) => throw new NotSupportedException();
        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];
        public bool IsWindowStillOpen(string windowId) => false;
        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
