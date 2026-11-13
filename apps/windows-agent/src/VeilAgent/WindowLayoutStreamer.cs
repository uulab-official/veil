using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Sends <c>window.layout</c> whenever a tracked window moves, resizes, changes z-order, or gains or loses
/// full visibility, so the host can crop each window out of the guest framebuffer instead of receiving
/// captured frames. It also says when the secure desktop takes the display (<see cref="InputDesktop"/>). See docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md.
/// </summary>
/// <remarks>
/// It polls rather than hooking WinEvents: a scan of the top-level windows takes well under a
/// millisecond, needs no message loop, and the comparison sends nothing while the layout holds still.
/// The fast interval only runs while windows are tracked and something moved within the last second,
/// under a 1 ms timer resolution so the 8 ms interval is not rounded up to Windows' 15.6 ms tick.
/// </remarks>
public sealed class WindowLayoutStreamer
{
    public static readonly TimeSpan ActiveInterval = TimeSpan.FromMilliseconds(8);
    /// <summary>
    /// The pace once nothing has moved for a second. Windows do not move by themselves, so the fast pace
    /// only earns its cost while something is moving; the first change after a pause is seen at most this
    /// much later, well inside the time the host waits for a moved window to settle.
    /// </summary>
    public static readonly TimeSpan SettledInterval = TimeSpan.FromMilliseconds(33);
    public static readonly TimeSpan IdleInterval = TimeSpan.FromMilliseconds(250);
    /// <summary>Scans without a change, at the fast pace, before the settled pace: one second's worth.</summary>
    public const int UnchangedScansBeforeSettled = 125;

    private readonly Func<IReadOnlyDictionary<string, string?>> trackedOwners;
    private readonly Func<WindowLayoutScan?> scan;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private readonly Func<bool> inputDesktopIsSecure;
    private int sequence;
    private int unchangedScans;
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
        Func<TimeSpan, CancellationToken, Task>? delay = null,
        Func<bool>? inputDesktopIsSecure = null)
    {
        this.trackedOwners = trackedOwners;
        this.scan = scan ?? WindowLayoutScanner.Scan;
        this.delay = delay ?? Task.Delay;
        this.inputDesktopIsSecure = inputDesktopIsSecure ?? InputDesktop.IsSecure;
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
                NoteScan(changed: layoutEvent is not null);
                EnforceTaskbar();

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

                await delay(CurrentInterval, cancellationToken);
            }
        }
        finally
        {
            timerResolution?.Dispose();
        }
    }

    /// <summary>Counts scans that found nothing new, for <see cref="CurrentInterval"/>.</summary>
    internal void NoteScan(bool changed)
    {
        if (changed)
        {
            unchangedScans = 0;
        }
        else if (unchangedScans < UnchangedScansBeforeSettled)
        {
            unchangedScans += 1;
        }
    }

    /// <summary>How long to wait before the next scan.</summary>
    internal TimeSpan CurrentInterval =>
        lastSent is null
            ? IdleInterval
            : unchangedScans >= UnchangedScansBeforeSettled ? SettledInterval : ActiveInterval;

    private long lastTaskbarCheck;

    /// <summary>Keeps the taskbar hidden while the host hides the desktop; checked a few times a second.</summary>
    private void EnforceTaskbar()
    {
        var now = Environment.TickCount64;
        if (now - lastTaskbarCheck < 250)
        {
            return;
        }
        lastTaskbarCheck = now;
        try
        {
            TaskbarVisibility.Enforce(FramebufferCropRegistry.HidesDesktop());
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine($"WindowLayoutStreamer: taskbar update failed. {error.GetType().Name}: {error.Message}");
        }
    }

    /// <summary>The next <c>window.layout</c> to send, or null when nothing changed.</summary>
    internal JsonObject? NextEvent()
    {
        IReadOnlyDictionary<string, string?> owners;
        WindowLayoutScan? current;
        bool secureDesktop;
        try
        {
            owners = trackedOwners();
            secureDesktop = inputDesktopIsSecure();
            // A prompt can come up with no window tracked, as when the app being opened asks for
            // administrator rights before it shows anything, so the secure desktop is reported either way.
            current = owners.Count == 0 && !secureDesktop ? null : scan();
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

        var layout = WindowLayoutComposer.Compose(
            current.ZOrdered, owners, current.Display, current.ForegroundWindowId, secureDesktop);
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
