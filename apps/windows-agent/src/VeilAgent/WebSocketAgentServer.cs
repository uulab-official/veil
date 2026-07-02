using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class WebSocketAgentServer
{
    private readonly AgentEndpoint endpoint;
    private readonly AgentSession session;
    private readonly ConcurrentDictionary<Guid, WebSocket> clients = new();

    public WebSocketAgentServer(AgentEndpoint endpoint, AgentSession session)
    {
        this.endpoint = endpoint;
        this.session = session;
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        using var listener = new HttpListener();
        listener.Prefixes.Add(endpoint.HttpPrefix);
        listener.Start();

        while (!cancellationToken.IsCancellationRequested)
        {
            var context = await listener.GetContextAsync();
            if (!context.Request.IsWebSocketRequest)
            {
                context.Response.StatusCode = 426;
                context.Response.Close();
                continue;
            }

            _ = Task.Run(() => HandleClientAsync(context, cancellationToken), cancellationToken);
        }
    }

    private async Task HandleClientAsync(HttpListenerContext context, CancellationToken cancellationToken)
    {
        var webSocketContext = await context.AcceptWebSocketAsync(subProtocol: null);
        var socket = webSocketContext.WebSocket;
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
            }
        }
        finally
        {
            clients.TryRemove(clientId, out _);
            socket.Dispose();
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
