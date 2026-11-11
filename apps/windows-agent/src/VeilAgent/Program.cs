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
var streamer = new WindowFrameStreamer(capture, keepAwake: DisplayKeepAwake.CreateForWindows());
var clipboardStreamer = new ClipboardTextStreamer(
    desktop,
    fileExport: new ClipboardFileExport(SharedFolderProbe.DefaultGuestDirectoryPath)
);
var packageIdentityProbe = new WindowsPackageIdentityProbe();
var session = new AgentSession(desktop, capture, packageIdentityProbe);
session.WindowActivity = streamer.Wake;
var windowDiscoveryStreamer = new WindowDiscoveryStreamer(session, desktop);
var notificationStreamer = new WindowsNotificationStreamer(WindowsNotificationListenerFactory.Create(packageIdentityProbe));
var windowLayoutStreamer = new WindowLayoutStreamer(session);
var server = new WebSocketAgentServer(endpoint, session, streamer, clipboardStreamer, windowDiscoveryStreamer, notificationStreamer, windowLayoutStreamer);

Console.WriteLine($"Veil Windows Agent listening on {endpoint.WebSocketUrl}");
await server.RunAsync();
