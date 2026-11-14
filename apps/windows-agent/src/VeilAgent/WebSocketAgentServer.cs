using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class WebSocketAgentServer
{
    private readonly AgentEndpoint endpoint;
    private readonly AgentSession session;
    private readonly WindowFrameStreamer frameStreamer;
    private readonly ClipboardTextStreamer clipboardTextStreamer;
    private readonly WindowDiscoveryStreamer windowDiscoveryStreamer;
    private readonly WindowsNotificationStreamer notificationStreamer;
    private readonly WindowLayoutStreamer? windowLayoutStreamer;
    private readonly ConcurrentDictionary<Guid, WebSocket> clients = new();
    /// <summary>
    /// Connections that asked for the binary frame channel. Kept separate from <see cref="clients"/> so
    /// frames never share a connection with control messages and input.
    /// </summary>
    private readonly ConcurrentDictionary<Guid, WebSocket> frameChannelClients = new();
    private readonly ConcurrentDictionary<string, FrameStream> frameStreamsByWindowId = new();
    private readonly SemaphoreSlim frameStreamChanges = new(1, 1);
    private CancellationTokenSource? clipboardStreamCancellation;
    private CancellationTokenSource? windowDiscoveryStreamCancellation;
    private CancellationTokenSource? notificationStreamCancellation;
    private CancellationTokenSource? windowLayoutStreamCancellation;

    public WebSocketAgentServer(
        AgentEndpoint endpoint,
        AgentSession session,
        WindowFrameStreamer frameStreamer,
        ClipboardTextStreamer clipboardTextStreamer,
        WindowDiscoveryStreamer windowDiscoveryStreamer,
        WindowsNotificationStreamer? notificationStreamer = null,
        WindowLayoutStreamer? windowLayoutStreamer = null
    )
    {
        this.endpoint = endpoint;
        this.session = session;
        this.frameStreamer = frameStreamer;
        this.clipboardTextStreamer = clipboardTextStreamer;
        this.windowDiscoveryStreamer = windowDiscoveryStreamer;
        this.notificationStreamer = notificationStreamer ?? new WindowsNotificationStreamer(new DisabledWindowsNotificationListener());
        this.windowLayoutStreamer = windowLayoutStreamer;
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        using var listener = new TcpListener(endpoint.ListenAddress, endpoint.Port);
        listener.Start();
        StartClipboardStream(cancellationToken);
        StartWindowDiscoveryStream(cancellationToken);
        StartNotificationStream(cancellationToken);
        StartWindowLayoutStream(cancellationToken);

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                TcpClient client;
                try
                {
                    client = await listener.AcceptTcpClientAsync(cancellationToken);
                }
                catch (SocketException error) when (IsTransientAcceptSocketError(error.SocketErrorCode))
                {
                    // A client reset during accept must not terminate the long-running agent.
                    Console.Error.WriteLine(
                        $"WebSocketAgentServer: ignoring transient accept failure {error.SocketErrorCode}."
                    );
                    continue;
                }
                _ = Task.Run(() => HandleClientAsync(client, cancellationToken), cancellationToken);
            }
        }
        finally
        {
            await StopAllFrameStreamsAsync();
        }
    }

    internal static bool IsTransientAcceptSocketError(SocketError error) => error is
        SocketError.ConnectionAborted or
        SocketError.ConnectionReset or
        SocketError.Interrupted;

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        try
        {
            await HandleClientCoreAsync(client, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            // A single malformed message or connection error must not vanish silently -- this is a
            // fire-and-forget Task.Run, so an unhandled exception here would otherwise just fault the
            // task and disconnect the client with no diagnostic trace anywhere.
            Console.Error.WriteLine(
                $"WebSocketAgentServer: client handling failed. {error.GetType().Name}: {error.Message}"
            );
        }
    }

    private async Task HandleClientCoreAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        {
            var stream = client.GetStream();
            var accepted = await AcceptWebSocketAsync(stream, cancellationToken);
            if (accepted is null)
            {
                return;
            }

            using var socket = accepted.Socket;
            var clientId = Guid.NewGuid();

            if (accepted.IsFrameChannel)
            {
                await ServeFrameChannelAsync(clientId, socket, cancellationToken);
                return;
            }

            // Layouts go out only on change, so a host that connects later starts from the current one.
            // Sent before the socket joins the broadcast list, where nothing else can write to it yet.
            if (windowLayoutStreamer?.CurrentEvent() is { } currentLayout)
            {
                await SendTextAsync(socket, currentLayout.ToJsonString(ProtocolJson.Options), cancellationToken);
            }

            clients[clientId] = socket;
            using var hostCursor = GuestCursorVisibility.HostConnected();

            try
            {
                while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
                {
                    var requestText = await ReceiveTextAsync(socket, cancellationToken);
                    if (requestText is null)
                    {
                        break;
                    }

                    // Connections that send RPC requests are short-lived request channels. Keep
                    // background window, frame, clipboard, and notification events on the passive
                    // event channel so they cannot be counted as replies to an unrelated request.
                    clients.TryRemove(clientId, out _);

                    var request = JsonNode.Parse(requestText)?.AsObject()
                        ?? new JsonObject { ["type"] = "invalid" };
                    var replies = await session.HandleAsync(request, cancellationToken);

                    // A success reply confirms the lifecycle mutation. Complete it first, even if
                    // the request connection disappears before the acknowledgement can be sent.
                    var startsSubscription = request["type"]?.GetValue<string>() == MessageTypes.WindowFrameSubscribe;
                    if (startsSubscription && replies.StreamWindow is not null)
                    {
                        await StartFrameStreamAsync(replies.StreamWindow, replies.NextFrameSequence, cancellationToken);
                    }

                    if (replies.StopStreamWindowId is not null)
                    {
                        await StopFrameStreamAsync(replies.StopStreamWindowId, cancellationToken);
                    }

                    foreach (var reply in replies.SerializeDirectReplies())
                    {
                        await SendTextAsync(socket, reply, cancellationToken);
                    }

                    foreach (var broadcast in replies.SerializeBroadcastEvents())
                    {
                        await BroadcastTextAsync(broadcast, cancellationToken);
                    }

                    // Launch replies establish window metadata before the initial frame and live
                    // stream. Otherwise a static window's only full frame can precede its host mirror.
                    if (!startsSubscription && replies.StreamWindow is not null)
                    {
                        await StartFrameStreamAsync(replies.StreamWindow, replies.NextFrameSequence, cancellationToken);
                    }
                }
            }
            finally
            {
                clients.TryRemove(clientId, out _);
            }
        }
    }

    /// <summary>
    /// Request path a client uses to ask for the binary frame channel.
    /// </summary>
    /// <remarks>
    /// Routing by path rather than changing behavior for every connection is what keeps this additive: a
    /// host that never opens this path keeps receiving JSON frames exactly as before.
    /// </remarks>
    public const string FrameChannelPath = "/frames";

    internal static string RequestPath(string requestLine)
    {
        var parts = requestLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2)
        {
            return "/";
        }

        var target = parts[1];
        var queryIndex = target.IndexOf('?');
        var path = queryIndex >= 0 ? target[..queryIndex] : target;
        return path.Length == 0 ? "/" : path;
    }

    internal static bool IsFrameChannelPath(string path) =>
        string.Equals(path.TrimEnd('/'), FrameChannelPath.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);

    private static async Task<AcceptedWebSocket?> AcceptWebSocketAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var requestText = await ReadHttpUpgradeRequestAsync(stream, cancellationToken);
        if (requestText is null)
        {
            return null;
        }

        var lines = requestText.Split("\r\n", StringSplitOptions.None);
        if (lines.Length == 0 || !lines[0].StartsWith("GET ", StringComparison.OrdinalIgnoreCase))
        {
            await WriteHttpResponseAsync(stream, "400 Bad Request", "Expected a WebSocket GET request.", cancellationToken);
            return null;
        }

        var requestPath = RequestPath(lines[0]);

        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in lines.Skip(1))
        {
            var separatorIndex = line.IndexOf(':');
            if (separatorIndex <= 0)
            {
                continue;
            }

            headers[line[..separatorIndex].Trim()] = line[(separatorIndex + 1)..].Trim();
        }

        if (IsFromWebPage(headers))
        {
            await WriteHttpResponseAsync(stream, "403 Forbidden", "Web pages may not connect to the Veil agent.", cancellationToken);
            return null;
        }

        if (!AgentAccessToken.IsAuthorized(headers, AgentAccessToken.Expected))
        {
            await WriteHttpResponseAsync(stream, "401 Unauthorized", "This connection did not present the Veil agent token.", cancellationToken);
            return null;
        }

        if (!HeaderContainsToken(headers, "Connection", "Upgrade")
            || !HeaderEquals(headers, "Upgrade", "websocket")
            || !headers.TryGetValue("Sec-WebSocket-Key", out var key)
            || string.IsNullOrWhiteSpace(key))
        {
            await WriteHttpResponseAsync(stream, "426 Upgrade Required", "WebSocket upgrade required.", cancellationToken);
            return null;
        }

        var accept = ComputeWebSocketAccept(key);
        var response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Connection: Upgrade\r\n" +
            "Upgrade: websocket\r\n" +
            $"Sec-WebSocket-Accept: {accept}\r\n" +
            "\r\n";
        var responseBytes = Encoding.ASCII.GetBytes(response);
        await stream.WriteAsync(responseBytes, cancellationToken);
        var socket = WebSocket.CreateFromStream(
            stream,
            isServer: true,
            subProtocol: null,
            keepAliveInterval: TimeSpan.FromSeconds(30)
        );
        return new AcceptedWebSocket(socket, IsFrameChannelPath(requestPath));
    }

    /// <summary>
    /// Whether the handshake comes from a page in a web browser. The agent's port is forwarded to
    /// 127.0.0.1 on the Mac, and any page open in a browser there may open a WebSocket to it. Without this
    /// such a page could type into Windows, start programs, and read the clipboard.
    /// </summary>
    /// <remarks>
    /// A browser adds <c>Origin</c> to every WebSocket handshake and a page cannot remove it
    /// (<see href="https://www.rfc-editor.org/rfc/rfc6455#section-10.2">RFC 6455, section 10.2</see>). The
    /// Veil host does not send one. This does not stop another program on the Mac, which can leave the
    /// header out; `AgentAccessToken` keeps those out when the machine carries a token.
    /// </remarks>
    internal static bool IsFromWebPage(IReadOnlyDictionary<string, string> headers) =>
        headers.ContainsKey("Origin");

    private sealed record AcceptedWebSocket(WebSocket Socket, bool IsFrameChannel);

    private static async Task<string?> ReadHttpUpgradeRequestAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        using var request = new MemoryStream();

        while (request.Length < 32768)
        {
            var count = await stream.ReadAsync(buffer, cancellationToken);
            if (count == 0)
            {
                return null;
            }

            request.Write(buffer, 0, count);
            var text = Encoding.ASCII.GetString(request.ToArray());
            if (text.Contains("\r\n\r\n", StringComparison.Ordinal))
            {
                return text[..text.IndexOf("\r\n\r\n", StringComparison.Ordinal)];
            }
        }

        await WriteHttpResponseAsync(stream, "431 Request Header Fields Too Large", "Request headers are too large.", cancellationToken);
        return null;
    }

    private static async Task WriteHttpResponseAsync(NetworkStream stream, string status, string body, CancellationToken cancellationToken)
    {
        var bodyBytes = Encoding.UTF8.GetBytes(body);
        var header =
            $"HTTP/1.1 {status}\r\n" +
            "Connection: close\r\n" +
            "Content-Type: text/plain; charset=utf-8\r\n" +
            $"Content-Length: {bodyBytes.Length}\r\n" +
            "\r\n";
        var headerBytes = Encoding.ASCII.GetBytes(header);
        await stream.WriteAsync(headerBytes.Concat(bodyBytes).ToArray(), cancellationToken);
    }

    private static bool HeaderEquals(Dictionary<string, string> headers, string name, string expected)
    {
        return headers.TryGetValue(name, out var actual)
            && string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static bool HeaderContainsToken(Dictionary<string, string> headers, string name, string expected)
    {
        return headers.TryGetValue(name, out var actual)
            && actual.Split(',').Any(token => string.Equals(token.Trim(), expected, StringComparison.OrdinalIgnoreCase));
    }

    private static string ComputeWebSocketAccept(string key)
    {
        var bytes = Encoding.ASCII.GetBytes(key.Trim() + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
        return Convert.ToBase64String(SHA1.HashData(bytes));
    }

    private void StartClipboardStream(CancellationToken serverCancellationToken)
    {
        if (clipboardStreamCancellation is not null)
        {
            return;
        }

        var streamCancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
        clipboardStreamCancellation = streamCancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                await clipboardTextStreamer.StreamAsync(
                    async (message, token) => await BroadcastTextAsync(message.ToJsonString(ProtocolJson.Options), token),
                    streamCancellation.Token
                );
            }
            catch (OperationCanceledException)
            {
                // Expected when the agent shuts down.
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(
                    $"WebSocketAgentServer: clipboard stream stopped unexpectedly. {error.GetType().Name}: {error.Message}"
                );
            }
        }, streamCancellation.Token);
    }

    private void StartWindowDiscoveryStream(CancellationToken serverCancellationToken)
    {
        if (windowDiscoveryStreamCancellation is not null)
        {
            return;
        }

        var streamCancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
        windowDiscoveryStreamCancellation = streamCancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                await windowDiscoveryStreamer.StreamAsync(
                    async (message, token) => await BroadcastTextAsync(message.ToJsonString(ProtocolJson.Options), token),
                    streamCancellation.Token
                );
            }
            catch (OperationCanceledException)
            {
                // Expected when the agent shuts down.
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(
                    $"WebSocketAgentServer: window discovery stream stopped unexpectedly. {error.GetType().Name}: {error.Message}"
                );
            }
        }, streamCancellation.Token);
    }

    private void StartWindowLayoutStream(CancellationToken serverCancellationToken)
    {
        if (windowLayoutStreamer is null || windowLayoutStreamCancellation is not null)
        {
            return;
        }

        var streamCancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
        windowLayoutStreamCancellation = streamCancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                await windowLayoutStreamer.StreamAsync(
                    async (message, token) => await BroadcastTextAsync(message.ToJsonString(ProtocolJson.Options), token),
                    streamCancellation.Token
                );
            }
            catch (OperationCanceledException)
            {
                // Expected when the agent shuts down.
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(
                    $"WebSocketAgentServer: window layout stream stopped unexpectedly. {error.GetType().Name}: {error.Message}"
                );
            }
        }, streamCancellation.Token);
    }

    private void StartNotificationStream(CancellationToken serverCancellationToken)
    {
        if (notificationStreamCancellation is not null)
        {
            return;
        }

        var streamCancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
        notificationStreamCancellation = streamCancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                await notificationStreamer.StreamAsync(
                    async (message, token) => await BroadcastTextAsync(message.ToJsonString(ProtocolJson.Options), token),
                    streamCancellation.Token
                );
            }
            catch (OperationCanceledException)
            {
                // Expected when the agent shuts down.
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(
                    $"WebSocketAgentServer: notification stream stopped unexpectedly. {error.GetType().Name}: {error.Message}"
                );
            }
        }, streamCancellation.Token);
    }

    /// <summary>
    /// Holds a frame-channel connection open and lets the frame broadcaster write binary frames to it.
    /// </summary>
    /// <remarks>
    /// The frame channel is send-only. It reads solely to observe a close, so a client cannot use it to
    /// issue requests, and frames on it cannot be mistaken for replies to anything.
    /// </remarks>
    private async Task ServeFrameChannelAsync(Guid clientId, WebSocket socket, CancellationToken cancellationToken)
    {
        frameChannelClients[clientId] = socket;
        try
        {
            var buffer = new byte[256];
            while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
            {
                var result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    break;
                }
            }
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"WebSocketAgentServer: frame channel client disconnected. {error.GetType().Name}: {error.Message}"
            );
        }
        finally
        {
            frameChannelClients.TryRemove(clientId, out _);
        }
    }

    /// <summary>
    /// Sends one captured frame to whichever channel each client subscribed on.
    /// </summary>
    /// <remarks>
    /// Frame-channel clients get raw bytes, which is the whole point: no base64 inflation, no JSON parse
    /// on the host, and no large frame sitting in front of an input message on the control connection.
    /// Control-channel clients keep receiving the JSON form so a host that does not open the frame
    /// channel is unaffected.
    ///
    /// The JSON form is built only when a control-channel client actually exists, so the common case of a
    /// host using the frame channel pays nothing for the legacy path.
    /// </remarks>
    private async Task BroadcastFrameAsync(WindowFrameCaptureResult result, CancellationToken cancellationToken)
    {
        if (!frameChannelClients.IsEmpty && result.Tile is not null)
        {
            byte[]? message = null;
            try
            {
                message = FrameChannelCodec.Encode(result.Tile);
            }
            catch (Exception error)
            {
                // Encoding is pure and should not fail, but a silent drop here would look like a frozen
                // window with no trace of why.
                Console.Error.WriteLine(
                    $"WebSocketAgentServer: failed to encode frame for the binary channel. {error.GetType().Name}: {error.Message}"
                );
            }

            if (message is not null)
            {
                foreach (var pair in frameChannelClients)
                {
                    if (pair.Value.State != WebSocketState.Open)
                    {
                        frameChannelClients.TryRemove(pair.Key, out _);
                        continue;
                    }

                    try
                    {
                        await pair.Value.SendAsync(
                            new ArraySegment<byte>(message),
                            WebSocketMessageType.Binary,
                            endOfMessage: true,
                            cancellationToken
                        );
                    }
                    catch (Exception error) when (error is not OperationCanceledException)
                    {
                        frameChannelClients.TryRemove(pair.Key, out _);
                        Console.Error.WriteLine(
                            $"WebSocketAgentServer: dropping frame channel client after a send failure. {error.GetType().Name}: {error.Message}"
                        );
                    }
                }
            }
        }

        // Legacy JSON subscribers always receive a self-contained full-surface frame. Tiles are only
        // meaningful to a client that composites them, and that client is on the binary channel.
        if (!clients.IsEmpty && result.Frame is not null)
        {
            await BroadcastTextAsync(AgentReplies.SerializeFrame(result.Frame), cancellationToken);
        }
    }

    private async Task BroadcastTextAsync(string text, CancellationToken cancellationToken)
    {
        foreach (var pair in clients)
        {
            var socket = pair.Value;
            if (socket.State != WebSocketState.Open)
            {
                clients.TryRemove(pair.Key, out _);
                continue;
            }

            await SendTextAsync(socket, text, cancellationToken);
        }
    }

    private async Task StartFrameStreamAsync(LaunchedWindow window, int firstSequence, CancellationToken serverCancellationToken)
    {
        await frameStreamChanges.WaitAsync(serverCancellationToken);
        try
        {
            await StopFrameStreamCoreAsync(window.WindowId);
            serverCancellationToken.ThrowIfCancellationRequested();

            var stream = new FrameStream(serverCancellationToken);
            frameStreamsByWindowId[window.WindowId] = stream;
            // Always run the delegate, including when cancellation wins before scheduling, so its
            // finally block releases both comparison state and the linked cancellation source.
            stream.Completion = Task.Run(() => RunFrameStreamAsync(window, firstSequence, stream));
        }
        finally
        {
            frameStreamChanges.Release();
        }
    }

    private async Task RunFrameStreamAsync(LaunchedWindow window, int firstSequence, FrameStream stream)
    {
        try
        {
            await frameStreamer.StreamAsync(
                window,
                firstSequence,
                async (result, token) => await BroadcastFrameAsync(result, token),
                stream.Token,
                // Liveness only. Without this the host would read an idle window as broken capture
                // and escalate the stream, forcing repeated full-window PNG encodes for idle content.
                async (sequence, token) => await BroadcastTextAsync(
                    AgentReplies.SerializeUnchangedFrame(window.WindowId, sequence),
                    token
                ),
                // Skip the full-surface encode when only binary frame-channel clients are listening.
                () => !clients.IsEmpty
            );
        }
        catch (OperationCanceledException)
        {
            // Expected when the agent shuts down or the same HWND stream is replaced.
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(
                $"WebSocketAgentServer: frame stream for {window.WindowId} stopped unexpectedly. {error.GetType().Name}: {error.Message}"
            );
        }
        finally
        {
            // Replacement waits for this task. Release pixels before relinquishing ownership,
            // and only remove this stream's entry, never another subscription for the same HWND.
            frameStreamer.ForgetWindow(window.WindowId);
            ((ICollection<KeyValuePair<string, FrameStream>>)frameStreamsByWindowId)
                .Remove(new(window.WindowId, stream));
            stream.Dispose();
        }
    }

    private async Task StopFrameStreamAsync(string windowId, CancellationToken cancellationToken)
    {
        await frameStreamChanges.WaitAsync(cancellationToken);
        try
        {
            await StopFrameStreamCoreAsync(windowId);
        }
        finally
        {
            frameStreamChanges.Release();
        }
    }

    private async Task StopFrameStreamCoreAsync(string windowId)
    {
        if (frameStreamsByWindowId.TryGetValue(windowId, out var existing))
        {
            existing.Cancel();
            await existing.Completion;
        }

        // A restarted stream always begins without the previous subscription's comparison buffer.
        frameStreamer.ForgetWindow(windowId);
    }

    private async Task StopAllFrameStreamsAsync()
    {
        await frameStreamChanges.WaitAsync();
        try
        {
            var streams = frameStreamsByWindowId.Values.ToArray();
            foreach (var stream in streams) stream.Cancel();
            await Task.WhenAll(streams.Select(stream => stream.Completion));
        }
        finally
        {
            frameStreamChanges.Release();
        }
    }

    private sealed class FrameStream : IDisposable
    {
        private readonly CancellationTokenSource cancellation;
        private readonly object gate = new();
        private bool disposed;

        public FrameStream(CancellationToken serverCancellationToken)
        {
            cancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
            Token = cancellation.Token;
        }

        public CancellationToken Token { get; }
        public Task Completion { get; set; } = Task.CompletedTask;

        public void Cancel()
        {
            lock (gate)
            {
                if (!disposed) cancellation.Cancel();
            }
        }

        public void Dispose()
        {
            lock (gate)
            {
                if (disposed) return;
                disposed = true;
                cancellation.Dispose();
            }
        }
    }

    private static async Task<string?> ReceiveTextAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        using var stream = new MemoryStream();

        while (true)
        {
            var result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                return null;
            }

            stream.Write(buffer, 0, result.Count);
            if (result.EndOfMessage)
            {
                return Encoding.UTF8.GetString(stream.ToArray());
            }
        }
    }

    private static Task SendTextAsync(WebSocket socket, string text, CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        return socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, endOfMessage: true, cancellationToken);
    }
}
