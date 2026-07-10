using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed record WindowsNotification(
    string NotificationId,
    string? AppId,
    string? AppName,
    string Title,
    string? Body,
    DateTimeOffset ReceivedAt,
    string? SourceAumid
)
{
    public JsonObject ToProtocolEvent() => new()
    {
        ["type"] = MessageTypes.NotificationReceived,
        ["notificationId"] = NotificationId,
        ["appId"] = AppId,
        ["appName"] = AppName,
        ["title"] = Title,
        ["body"] = Body,
        ["receivedAt"] = ReceivedAt.UtcDateTime.ToString("O"),
        ["sourceAumid"] = SourceAumid
    };
}

public interface IWindowsNotificationListener
{
    IAsyncEnumerable<WindowsNotification> ListenAsync(CancellationToken cancellationToken);
}
