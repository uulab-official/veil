using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Sends <c>window.layout</c> whenever a tracked window moves, resizes, changes z-order, or gains or loses
/// full visibility, so the host can crop each window out of the guest framebuffer instead of receiving
/// captured frames. See docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md.
/// </summary>
/// <remarks>
/// It polls rather than hooking WinEvents: a scan of the top-level windows takes well under a
/// millisecond, needs no message loop, and the comparison sends nothing while the layout holds still.
/// The fast interval only runs while windows are tracked, under a 1 ms timer resolution so the 8 ms
/// interval is not rounded up to Windows' 15.6 ms tick.
/// </remarks>
public sealed class WindowLayoutStreamer
{
    public static readonly TimeSpan ActiveInterval = TimeSpan.FromMilliseconds(8);
    public static readonly TimeSpan IdleInterval = TimeSpan.FromMilliseconds(250);

    private readonly Func<IReadOnlyDictionary<string, string?>> trackedOwners;
    private readonly Func<WindowLayoutScan?> scan;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private int sequence;
    private string? lastSent;
    private JsonObject? lastEvent;

    public WindowLayoutStreamer(
        AgentSession session,
        Func<WindowLayoutScan?>? scan = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
        : this(session.SnapshotTrackedWindowOwners, scan, delay)
    {
    }

    internal WindowLayoutStreamer(
        Func<IReadOnlyDictionary<string, string?>> trackedOwners,
        Func<WindowLayoutScan?>? scan = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        this.trackedOwners = trackedOwners;
        this.scan = scan ?? WindowLayoutScanner.Scan;
        this.delay = delay ?? Task.Delay;
    }

    public async Task StreamAsync(Func<JsonObject, CancellationToken, Task> onEvent, CancellationToken cancellationToken)
    {
        IDisposable? timerResolution = null;
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var layoutEvent = NextEvent();
                if (layoutEvent is not null)
                {
                    await onEvent(layoutEvent, cancellationToken);
                }

                var active = lastSent is not null;
                if (active && timerResolution is null)
                {
                    timerResolution = TimerResolution.Hold();
                }
                else if (!active && timerResolution is not null)
                {
                    timerResolution.Dispose();
                    timerResolution = null;
                }

                await delay(active ? ActiveInterval : IdleInterval, cancellationToken);
            }
        }
        finally
        {
            timerResolution?.Dispose();
        }
    }

    /// <summary>The next <c>window.layout</c> to send, or null when nothing changed.</summary>
    internal JsonObject? NextEvent()
    {
        IReadOnlyDictionary<string, string?> owners;
        WindowLayoutScan? current;
        try
        {
            owners = trackedOwners();
            current = owners.Count == 0 ? null : scan();
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            // One failed scan must not stop layout for the rest of the agent's life.
            Console.Error.WriteLine($"WindowLayoutStreamer: scan failed. {error.GetType().Name}: {error.Message}");
            return null;
        }

        if (current is null)
        {
            if (lastSent is null)
            {
                return null;
            }

            // The last tracked window went away: say so once, with an empty layout.
            lastSent = null;
            var empty = new WindowLayout(new WindowRect(0, 0, 0, 0), Array.Empty<WindowLayoutWindow>()).ToEvent(++sequence);
            Volatile.Write(ref lastEvent, null);
            return empty;
        }

        var layout = WindowLayoutComposer.Compose(current.ZOrdered, owners, current.Display, current.ForegroundWindowId);
        var key = layout.ToEvent(0).ToJsonString();
        if (key == lastSent)
        {
            return null;
        }

        lastSent = key;
        var layoutEvent = layout.ToEvent(++sequence);
        Volatile.Write(ref lastEvent, layoutEvent);
        return layoutEvent;
    }

    /// <summary>The layout most recently sent, for a host that connects after it; null with no windows.</summary>
    public JsonObject? CurrentEvent() => Volatile.Read(ref lastEvent)?.DeepClone().AsObject();
}
