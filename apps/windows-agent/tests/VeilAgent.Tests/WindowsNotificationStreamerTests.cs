using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowsNotificationStreamerTests
{
    private sealed class FakePackageIdentityProbe : IPackageIdentityProbe
    {
        public FakePackageIdentityProbe(bool hasPackageIdentity)
        {
            HasPackageIdentity = hasPackageIdentity;
        }

        public bool HasPackageIdentity { get; }
    }

    [Fact]
    public async Task BroadcastsWindowsNotificationsAsProtocolEvents()
    {
        var listener = new ScriptedNotificationListener([
            new WindowsNotification(
                NotificationId: "toast:winapp_notepad:0001",
                AppId: "winapp_notepad",
                AppName: "Notepad",
                Title: "Notepad",
                Body: "Autosaved Notes.txt",
                ReceivedAt: DateTimeOffset.Parse("2026-07-10T12:15:00Z"),
                SourceAumid: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"
            )
        ]);
        var streamer = new WindowsNotificationStreamer(listener);

        var broadcasts = new List<JsonObject>();
        await streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                return Task.CompletedTask;
            },
            CancellationToken.None
        );

        var notification = Assert.Single(broadcasts);
        Assert.Equal(MessageTypes.NotificationReceived, notification["type"]!.GetValue<string>());
        Assert.Equal("toast:winapp_notepad:0001", notification["notificationId"]!.GetValue<string>());
        Assert.Equal("winapp_notepad", notification["appId"]!.GetValue<string>());
        Assert.Equal("Notepad", notification["appName"]!.GetValue<string>());
        Assert.Equal("Notepad", notification["title"]!.GetValue<string>());
        Assert.Equal("Autosaved Notes.txt", notification["body"]!.GetValue<string>());
        Assert.Equal("2026-07-10T12:15:00.0000000Z", notification["receivedAt"]!.GetValue<string>());
        Assert.Equal("Microsoft.WindowsNotepad_8wekyb3d8bbwe!App", notification["sourceAumid"]!.GetValue<string>());
    }

    [Fact]
    public async Task DropsDuplicateAndInvalidNotificationEvents()
    {
        var listener = new ScriptedNotificationListener([
            new WindowsNotification(
                NotificationId: "toast:duplicate",
                AppId: null,
                AppName: "Mail",
                Title: "Mail",
                Body: "First",
                ReceivedAt: DateTimeOffset.Parse("2026-07-10T12:15:00Z"),
                SourceAumid: null
            ),
            new WindowsNotification(
                NotificationId: "toast:duplicate",
                AppId: null,
                AppName: "Mail",
                Title: "Mail",
                Body: "Second",
                ReceivedAt: DateTimeOffset.Parse("2026-07-10T12:15:01Z"),
                SourceAumid: null
            ),
            new WindowsNotification(
                NotificationId: "toast:missing-title",
                AppId: null,
                AppName: "Broken",
                Title: "",
                Body: "No title",
                ReceivedAt: DateTimeOffset.Parse("2026-07-10T12:15:02Z"),
                SourceAumid: null
            )
        ]);
        var streamer = new WindowsNotificationStreamer(listener);

        var broadcasts = new List<JsonObject>();
        await streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                return Task.CompletedTask;
            },
            CancellationToken.None
        );

        var notification = Assert.Single(broadcasts);
        Assert.Equal("toast:duplicate", notification["notificationId"]!.GetValue<string>());
        Assert.Equal("First", notification["body"]!.GetValue<string>());
    }

    [Fact]
    public void FactoryKeepsListenerDisabledWithoutPackageIdentity()
    {
        var listener = WindowsNotificationListenerFactory.Create(new FakePackageIdentityProbe(false));

        Assert.IsType<DisabledWindowsNotificationListener>(listener);
    }

    [Fact]
    public void FactoryKeepsListenerDisabledOutsideWindows()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var listener = WindowsNotificationListenerFactory.Create(new FakePackageIdentityProbe(true));

        Assert.IsType<DisabledWindowsNotificationListener>(listener);
    }

    private sealed class ScriptedNotificationListener : IWindowsNotificationListener
    {
        private readonly IReadOnlyList<WindowsNotification> notifications;

        public ScriptedNotificationListener(IReadOnlyList<WindowsNotification> notifications)
        {
            this.notifications = notifications;
        }

        public async IAsyncEnumerable<WindowsNotification> ListenAsync(
            [EnumeratorCancellation] CancellationToken cancellationToken
        )
        {
            foreach (var notification in notifications)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return notification;
            }

            await Task.CompletedTask;
        }
    }
}
