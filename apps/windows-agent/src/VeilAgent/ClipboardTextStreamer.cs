using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class ClipboardTextStreamer
{
    private readonly IWindowsDesktop desktop;
    private readonly TimeSpan interval;
    private int sequence;
    private string? lastBroadcastText;

    public ClipboardTextStreamer(IWindowsDesktop desktop, TimeSpan? interval = null)
    {
        this.desktop = desktop;
        this.interval = interval ?? TimeSpan.FromMilliseconds(500);
    }

    public async Task StreamAsync(
        Func<JsonObject, CancellationToken, Task> onClipboardText,
        CancellationToken cancellationToken
    )
    {
        using var timer = new PeriodicTimer(interval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var text = await desktop.GetClipboardTextAsync(cancellationToken);
            if (text is null || text == lastBroadcastText)
            {
                continue;
            }

            if (desktop.TryConsumeHostClipboardEcho(text))
            {
                lastBroadcastText = text;
                continue;
            }

            sequence += 1;
            lastBroadcastText = text;
            await onClipboardText(ClipboardTextEvent(sequence, text), cancellationToken);
        }
    }

    private static JsonObject ClipboardTextEvent(int sequence, string text) => new()
    {
        ["type"] = MessageTypes.ClipboardTextSet,
        ["requestId"] = $"evt_clipboard_{sequence}",
        ["origin"] = "guest",
        ["sequence"] = sequence,
        ["text"] = text
    };
}
