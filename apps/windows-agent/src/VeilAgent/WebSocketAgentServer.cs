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
            using var socket = await AcceptWebSocketAsync(stream, cancellationToken);
            if (socket is null)
            {
                return;
            }

            var clientId = Guid.NewGuid();
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

    private static async Task<WebSocket?> AcceptWebSocketAsync(NetworkStream stream, CancellationToken cancellationToken)
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
        return WebSocket.CreateFromStream(stream, isServer: true, subProtocol: null, keepAliveInterval: TimeSpan.FromSeconds(30));
    }

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

        var streamCancellation = CancellationTokenSource.CreateLinkedTokenSource(serverCancellationToken);
        frameStreamsByWindowId[window.WindowId] = streamCancellation;

        _ = Task.Run(async () =>
        {
            try
            {
                await frameStreamer.StreamAsync(
                    window,
                    firstSequence,
                    async (frame, token) => await BroadcastTextAsync(AgentReplies.SerializeFrame(frame), token),
                    streamCancellation.Token
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
