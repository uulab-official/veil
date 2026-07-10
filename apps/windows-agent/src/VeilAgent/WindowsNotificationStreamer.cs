using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class WindowsNotificationStreamer
{
    private readonly IWindowsNotificationListener listener;
    private readonly HashSet<string> deliveredNotificationIds = new(StringComparer.Ordinal);

    public WindowsNotificationStreamer(IWindowsNotificationListener listener)
    {
        this.listener = listener;
    }

    public async Task StreamAsync(
        Func<JsonObject, CancellationToken, Task> onNotification,
        CancellationToken cancellationToken
    )
    {
        await foreach (var notification in listener.ListenAsync(cancellationToken))
        {
            if (!TryAccept(notification))
            {
                continue;
            }

            await onNotification(notification.ToProtocolEvent(), cancellationToken);
        }
    }

    private bool TryAccept(WindowsNotification notification)
    {
        if (string.IsNullOrWhiteSpace(notification.NotificationId)
            || string.IsNullOrWhiteSpace(notification.Title))
        {
            return false;
        }

        return deliveredNotificationIds.Add(notification.NotificationId);
    }
}

public sealed class DisabledWindowsNotificationListener : IWindowsNotificationListener
{
    public async IAsyncEnumerable<WindowsNotification> ListenAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken
    )
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromMinutes(10), cancellationToken);
        }

        yield break;
    }
}
