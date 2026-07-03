using Veil.Agent;

var endpoint = AgentEndpoint.FromEnvironment();
using var instanceGuard = SingleInstanceGuard.TryAcquire(endpoint);
if (!instanceGuard.HasOwnership)
{
    Console.WriteLine($"Veil Windows Agent is already running for {endpoint.WebSocketUrl} ({instanceGuard.MutexName}).");
    return;
}

var desktop = new WindowsDesktop();
var capture = new GdiWindowFrameCapture();
var streamer = new WindowFrameStreamer(capture);
var clipboardStreamer = new ClipboardTextStreamer(desktop);
var session = new AgentSession(desktop, capture);
var server = new WebSocketAgentServer(endpoint, session, streamer, clipboardStreamer);

Console.WriteLine($"Veil Windows Agent listening on {endpoint.WebSocketUrl}");
await server.RunAsync();
