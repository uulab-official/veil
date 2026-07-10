using Veil.Agent;

ProcessDpiAwareness.EnablePerMonitorV2();

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
var packageIdentityProbe = new WindowsPackageIdentityProbe();
var session = new AgentSession(desktop, capture, packageIdentityProbe);
var windowDiscoveryStreamer = new WindowDiscoveryStreamer(session, desktop);
var notificationStreamer = new WindowsNotificationStreamer(WindowsNotificationListenerFactory.Create(packageIdentityProbe));
var server = new WebSocketAgentServer(endpoint, session, streamer, clipboardStreamer, windowDiscoveryStreamer, notificationStreamer);

Console.WriteLine($"Veil Windows Agent listening on {endpoint.WebSocketUrl}");
await server.RunAsync();
