using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using Windows.Foundation;
using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

namespace Veil.Agent;

public sealed class WindowsUserNotificationListener : IWindowsNotificationListener
{
    private static readonly TimeSpan AccessRetryInterval = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan SyncInterval = TimeSpan.FromSeconds(30);

    private readonly UserNotificationListener listener;
    private readonly ConcurrentDictionary<uint, byte> deliveredIds = new();
    private readonly SemaphoreSlim syncSignal = new(0);

    public WindowsUserNotificationListener(UserNotificationListener? listener = null)
    {
        this.listener = listener ?? UserNotificationListener.Current;
    }

    public async IAsyncEnumerable<WindowsNotification> ListenAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken
    )
    {
        using var timer = new PeriodicTimer(SyncInterval);
        TypedEventHandler<UserNotificationListener, UserNotificationChangedEventArgs>? handler = (_, _) =>
        {
            try
            {
                syncSignal.Release();
            }
            catch (SemaphoreFullException)
            {
                // Multiple Windows notification events can coalesce into the next sync pass.
            }
        };
        listener.NotificationChanged += handler;

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (listener.GetAccessStatus() != UserNotificationListenerAccessStatus.Allowed)
                {
                    await Task.Delay(AccessRetryInterval, cancellationToken);
                    continue;
                }

                await foreach (var notification in SyncNewNotificationsAsync(cancellationToken))
                {
                    yield return notification;
                }

                var signalTask = syncSignal.WaitAsync(cancellationToken);
                var timerTask = timer.WaitForNextTickAsync(cancellationToken).AsTask();
                var completed = await Task.WhenAny(signalTask, timerTask);
                await completed;
            }
        }
        finally
        {
            listener.NotificationChanged -= handler;
            syncSignal.Dispose();
        }
    }

    private async IAsyncEnumerable<WindowsNotification> SyncNewNotificationsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken
    )
    {
        IReadOnlyList<UserNotification> currentNotifications;
        try
        {
            currentNotifications = await listener.GetNotificationsAsync(NotificationKinds.Toast).AsTask(cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"WindowsUserNotificationListener: failed to sync notifications. {error.GetType().Name}: {error.Message}"
            );
            yield break;
        }

        foreach (var notification in currentNotifications.OrderBy(item => item.CreationTime))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!deliveredIds.TryAdd(notification.Id, 0))
            {
                continue;
            }

            var converted = TryConvert(notification);
            if (converted is not null)
            {
                yield return converted;
            }
        }
    }

    private static WindowsNotification? TryConvert(UserNotification notification)
    {
        try
        {
            var appName = notification.AppInfo.DisplayInfo.DisplayName;
            var sourceAumid = notification.AppInfo.AppUserModelId;
            var toastBinding = notification.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric);
            var textElements = toastBinding?.GetTextElements() ?? [];
            var title = FirstNonEmpty(textElements.Select(element => element.Text)) ?? appName;
            if (string.IsNullOrWhiteSpace(title))
            {
                return null;
            }

            var body = string.Join(
                "\n",
                textElements
                    .Skip(1)
                    .Select(element => element.Text?.Trim())
                    .Where(text => !string.IsNullOrWhiteSpace(text))
            );

            return new WindowsNotification(
                NotificationId: $"toast:{sourceAumid ?? "unknown"}:{notification.Id}",
                AppId: null,
                AppName: string.IsNullOrWhiteSpace(appName) ? null : appName,
                Title: title.Trim(),
                Body: string.IsNullOrWhiteSpace(body) ? null : body,
                ReceivedAt: notification.CreationTime,
                SourceAumid: string.IsNullOrWhiteSpace(sourceAumid) ? null : sourceAumid
            );
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(
                $"WindowsUserNotificationListener: failed to convert notification {notification.Id}. {error.GetType().Name}: {error.Message}"
            );
            return null;
        }
    }

    private static string? FirstNonEmpty(IEnumerable<string?> values) =>
        values.Select(value => value?.Trim()).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
}

public static class WindowsNotificationListenerFactory
{
    public static IWindowsNotificationListener Create(IPackageIdentityProbe packageIdentityProbe)
    {
        if (!OperatingSystem.IsWindows() || !packageIdentityProbe.HasPackageIdentity)
        {
            return new DisabledWindowsNotificationListener();
        }

        return new WindowsUserNotificationListener();
    }
}
