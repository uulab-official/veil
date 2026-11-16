using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class WebSocketAgentServerTests
{
    private sealed class BroadcastDesktop : IWindowsDesktop
    {
        public string? ClipboardText { get; set; }

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
            Task.FromResult(ClipboardText);

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Theory]
    [InlineData(SocketError.ConnectionAborted)]
    [InlineData(SocketError.ConnectionReset)]
    [InlineData(SocketError.Interrupted)]
    public void KeepsTheAgentListenerAliveAfterTransientAcceptFailures(SocketError error)
    {
        Assert.True(WebSocketAgentServer.IsTransientAcceptSocketError(error));
    }

    [Fact]
    public void DoesNotTreatPermanentAcceptFailuresAsTransient()
    {
        Assert.False(WebSocketAgentServer.IsTransientAcceptSocketError(SocketError.AccessDenied));
    }

    [Fact]
    public async Task KeepsBroadcastEventsOffRequestConnections()
    {
        var port = ReserveLoopbackPort();
        var endpoint = new AgentEndpoint("127.0.0.1", port);
        var desktop = new BroadcastDesktop();
        var capture = new NoOpFrameCapture();
        var session = new AgentSession(desktop, capture);
        var server = new WebSocketAgentServer(
            endpoint,
            session,
            new WindowFrameStreamer(capture),
            new ClipboardTextStreamer(desktop, TimeSpan.FromMilliseconds(20)),
            new WindowDiscoveryStreamer(session, desktop, TimeSpan.FromMilliseconds(20))
        );
        using var serverCancellation = new CancellationTokenSource();
        var serverTask = server.RunAsync(serverCancellation.Token);

        using var eventSocket = new ClientWebSocket();
        using var requestSocket = new ClientWebSocket();
        try
        {
            await eventSocket.ConnectAsync(new Uri(endpoint.WebSocketUrl), CancellationToken.None);
            await requestSocket.ConnectAsync(new Uri(endpoint.WebSocketUrl), CancellationToken.None);

            var request = Encoding.UTF8.GetBytes("{\"type\":\"agent.health.request\",\"requestId\":\"req_health\"}");
            await requestSocket.SendAsync(request, WebSocketMessageType.Text, true, CancellationToken.None);
            var health = await ReceiveJsonAsync(requestSocket, CancellationToken.None);
            Assert.Equal(MessageTypes.AgentHealthResponse, health["type"]!.GetValue<string>());

            desktop.ClipboardText = "event-channel-only";
            using var eventTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            var clipboard = await ReceiveJsonAsync(eventSocket, eventTimeout.Token);
            Assert.Equal(MessageTypes.ClipboardTextSet, clipboard["type"]!.GetValue<string>());

            using var requestTimeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(300));
            await Assert.ThrowsAnyAsync<OperationCanceledException>(
                () => ReceiveJsonAsync(requestSocket, requestTimeout.Token)
            );
        }
        finally
        {
            serverCancellation.Cancel();
            eventSocket.Abort();
            requestSocket.Abort();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => serverTask);
        }
    }

    [Fact]
    public async Task RefusesAWebSocketOpenedByAWebPage()
    {
        var port = ReserveLoopbackPort();
        var endpoint = new AgentEndpoint("127.0.0.1", port);
        var desktop = new BroadcastDesktop();
        var capture = new NoOpFrameCapture();
        var session = new AgentSession(desktop, capture);
        var server = new WebSocketAgentServer(
            endpoint,
            session,
            new WindowFrameStreamer(capture),
            new ClipboardTextStreamer(desktop, TimeSpan.FromMilliseconds(20)),
            new WindowDiscoveryStreamer(session, desktop, TimeSpan.FromMilliseconds(20))
        );
        using var serverCancellation = new CancellationTokenSource();
        var serverTask = server.RunAsync(serverCancellation.Token);

        // A browser sends the page's origin with every WebSocket handshake.
        using var pageSocket = new ClientWebSocket();
        pageSocket.Options.SetRequestHeader("Origin", "https://example.com");
        using var hostSocket = new ClientWebSocket();
        try
        {
            await Assert.ThrowsAsync<WebSocketException>(
                () => pageSocket.ConnectAsync(new Uri(endpoint.WebSocketUrl), CancellationToken.None)
            );

            await hostSocket.ConnectAsync(new Uri(endpoint.WebSocketUrl), CancellationToken.None);
            Assert.Equal(WebSocketState.Open, hostSocket.State);
        }
        finally
        {
            serverCancellation.Cancel();
            pageSocket.Abort();
            hostSocket.Abort();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => serverTask);
        }
    }

    [Fact]
    public void TellsAWebPageFromTheHostByItsOriginHeader()
    {
        var page = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["origin"] = "null" };
        var host = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["Upgrade"] = "websocket" };

        Assert.True(WebSocketAgentServer.IsFromWebPage(page));
        Assert.False(WebSocketAgentServer.IsFromWebPage(host));
    }

    private static int ReserveLoopbackPort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }

    private static async Task<JsonObject> ReceiveJsonAsync(ClientWebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        using var payload = new MemoryStream();
        WebSocketReceiveResult result;
        do
        {
            result = await socket.ReceiveAsync(buffer, cancellationToken);
            payload.Write(buffer, 0, result.Count);
        } while (!result.EndOfMessage);

        return JsonNode.Parse(payload.ToArray())!.AsObject();
    }
}
