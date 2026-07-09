using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentSessionHealthTests
{
    private sealed class FakePackageIdentityProbe : IPackageIdentityProbe
    {
        public FakePackageIdentityProbe(bool hasPackageIdentity)
        {
            HasPackageIdentity = hasPackageIdentity;
        }

        public bool HasPackageIdentity { get; }
    }

    private sealed class NoOpWindowsDesktop : IWindowsDesktop
    {
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => false;

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task HealthResponseReportsInjectedPackageIdentityState(bool hasPackageIdentity)
    {
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(hasPackageIdentity)
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.AgentHealthResponse, response["type"]!.GetValue<string>());
        Assert.Equal(hasPackageIdentity, response["capabilities"]!["packageIdentity"]!.GetValue<bool>());
    }

    [Fact]
    public void WindowsPackageIdentityProbeReturnsFalseOutsideWindows()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        Assert.False(new WindowsPackageIdentityProbe().HasPackageIdentity);
    }
}
