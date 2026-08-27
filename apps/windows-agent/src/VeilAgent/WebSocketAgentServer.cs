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
    private readonly ConcurrentDictionary<Guid, WebSocket> clients = new();
    /// <summary>
    /// Connections that asked for the binary frame channel. Kept separate from <see cref="clients"/> so
    /// frames never share a connection with control messages and input.
    /// </summary>
    private readonly ConcurrentDictionary<Guid, WebSocket> frameChannelClients = new();
    private readonly ConcurrentDictionary<string, CancellationTokenSource> frameStreamsByWindowId = new();
    private CancellationTokenSource? clipboardStreamCancellation;
    private CancellationTokenSource? windowDiscoveryStreamCancellation;
    private CancellationTokenSource? notificationStreamCancellation;

    public WebSocketAgentServer(
        AgentEndpoint endpoint,
        AgentSession session,
        WindowFrameStreamer frameStreamer,
        ClipboardTextStreamer clipboardTextStreamer,
        WindowDiscoveryStreamer windowDiscoveryStreamer,
        WindowsNotificationStreamer? notificationStreamer = null
    )
    {
        this.endpoint = endpoint;
        this.session = session;
        this.frameStreamer = frameStreamer;
        this.clipboardTextStreamer = clipboardTextStreamer;
        this.windowDiscoveryStreamer = windowDiscoveryStreamer;
        this.notificationStreamer = notificationStreamer ?? new WindowsNotificationStreamer(new DisabledWindowsNotificationListener());
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        using var listener = new TcpListener(endpoint.ListenAddress, endpoint.Port);
        listener.Start();
        StartClipboardStream(cancellationToken);
        StartWindowDiscoveryStream(cancellationToken);
        StartNotificationStream(cancellationToken);

        while (!cancellationToken.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await listener.AcceptTcpClientAsync(cancellationToken);
            }
            catch (SocketException error) when (IsTransientAcceptSocketError(error.SocketErrorCode))
            {
                // A client can reset the connection while Windows is accepting it. This happens
                // with short-lived TCP probes and must not terminate the long-running agent.
                Console.Error.WriteLine(
                    $"WebSocketAgentServer: ignoring transient accept failure {error.SocketErrorCode}."
                );
                continue;
            }
            _ = Task.Run(() => HandleClientAsync(client, cancellationToken), cancellationToken);
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

            clients[clientId] = socket;

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

                    foreach (var reply in replies.SerializeDirectReplies())
                    {
                        await SendTextAsync(socket, reply, cancellationToken);
                    }

                    foreach (var broadcast in replies.SerializeBroadcastEvents())
                    {
                        await BroadcastTextAsync(broadcast, cancellationToken);
                    }

                    if (replies.StreamWindow is not null)
                    {
                        StartFrameStream(replies.StreamWindow, replies.NextFrameSequence, cancellationToken);
                    }

                    if (replies.StopStreamWindowId is not null)
                    {
                        StopFrameStream(replies.StopStreamWindowId);
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

    private void StartFrameStream(LaunchedWindow window, int firstSequence, CancellationToken serverCancellationToken)
    {
        if (frameStreamsByWindowId.TryRemove(window.WindowId, out var existing))
        {
            existing.Cancel();
            existing.Dispose();
        }

        // A restarted stream must begin with a full frame. Comparing against the previous session's
        // pixels could suppress the very first frame the host is waiting for.
        frameStreamer.ForgetWindow(window.WindowId);

        var streamCancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
        frameStreamsByWindowId[window.WindowId] = streamCancellation;

        _ = Task.Run(async () =>
        {
            try
            {
                await frameStreamer.StreamAsync(
                    window,
                    firstSequence,
                    async (result, token) => await BroadcastFrameAsync(result, token),
                    streamCancellation.Token,
                    // Liveness only. Without this the host would read an idle window as broken capture
                    // and escalate the stream, which is what previously forced a full-window PNG encode
                    // several times a second for a window nobody was touching.
                    async (sequence, token) => await BroadcastTextAsync(
                        AgentReplies.SerializeUnchangedFrame(window.WindowId, sequence),
                        token
                    ),
                    // Skips the full-surface encode entirely in the normal case, where the only subscriber
                    // is on the binary frame channel.
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
                frameStreamsByWindowId.TryRemove(window.WindowId, out _);
                // Covers every exit path -- unsubscribe, cancellation, and unexpected failure -- so the
                // retained full-window comparison buffer cannot outlive the stream that created it.
                frameStreamer.ForgetWindow(window.WindowId);
                streamCancellation.Dispose();
            }
        }, streamCancellation.Token);
    }

    private void StopFrameStream(string windowId)
    {
        if (frameStreamsByWindowId.TryRemove(windowId, out var existing))
        {
            existing.Cancel();
            existing.Dispose();
        }

        // Releases the retained comparison buffer. Without this a closed window's full-size pixel buffer
        // would be held for the rest of the agent process's lifetime.
        frameStreamer.ForgetWindow(windowId);
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
