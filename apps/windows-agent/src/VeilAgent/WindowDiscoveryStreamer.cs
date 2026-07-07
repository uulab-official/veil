using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Periodically scans for windows belonging to already-launched apps that the launch flow didn't
/// see (a second document window, a Save-As dialog, a second instance of the same app), and
/// broadcasts <c>window.created</c> for each newly discovered one. Also prunes windows the host was
/// never told closed (the user closed them directly on the guest rather than through
/// <c>window.close.request</c>), broadcasting <c>window.closed</c> for each -- this also prevents a
/// stale tracked id from masking a genuinely new window if Win32 reuses its HWND. The host already
/// tracks mirrored windows by <c>windowId</c>, not <c>appId</c>, so no host-side change is needed to
/// display newly discovered windows.
/// </summary>
public sealed class WindowDiscoveryStreamer
{
    private readonly AgentSession session;
    private readonly IWindowsDesktop desktop;
    private readonly TimeSpan interval;

    public WindowDiscoveryStreamer(AgentSession session, IWindowsDesktop desktop, TimeSpan? interval = null)
    {
        this.session = session;
        this.desktop = desktop;
        this.interval = interval ?? TimeSpan.FromSeconds(2);
    }

    public async Task StreamAsync(
        Func<JsonObject, CancellationToken, Task> onEvent,
        CancellationToken cancellationToken
    )
    {
        using var timer = new PeriodicTimer(interval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            await PruneClosedWindowsAsync(onEvent, cancellationToken);
            await DiscoverNewWindowsAsync(onEvent, cancellationToken);
        }
    }

    private async Task PruneClosedWindowsAsync(
        Func<JsonObject, CancellationToken, Task> onEvent,
        CancellationToken cancellationToken
    )
    {
        var trackedApps = SnapshotTrackedApps();
        foreach (var (_, knownWindowIds) in trackedApps)
        {
            foreach (var windowId in knownWindowIds)
            {
                bool stillOpen;
                try
                {
                    stillOpen = desktop.IsWindowStillOpen(windowId);
                }
                catch (Exception error) when (error is not OperationCanceledException)
                {
                    // A transient per-window check failure must not permanently kill discovery for
                    // the rest of the agent's process lifetime, matching the fallback pattern used
                    // throughout this streamer and ClipboardTextStreamer/WindowFrameStreamer.
                    Console.Error.WriteLine(
                        $"WindowDiscoveryStreamer: transient open-check failure for {windowId}. {error.GetType().Name}: {error.Message}"
                    );
                    continue;
                }

                if (stillOpen)
                {
                    continue;
                }

                var closedEvent = session.TryUntrackClosedWindow(windowId);
                if (closedEvent is not null)
                {
                    await onEvent(closedEvent, cancellationToken);
                }
            }
        }
    }

    private async Task DiscoverNewWindowsAsync(
        Func<JsonObject, CancellationToken, Task> onEvent,
        CancellationToken cancellationToken
    )
    {
        var trackedApps = SnapshotTrackedApps();
        foreach (var (app, knownWindowIds) in trackedApps)
        {
            IReadOnlyList<LaunchedWindow> discovered;
            try
            {
                discovered = desktop.DiscoverAdditionalWindows(app, knownWindowIds);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                // A transient EnumWindows/process-inspection failure must not permanently kill
                // discovery for the rest of the agent's process lifetime -- matches the fallback
                // pattern ClipboardTextStreamer and WindowFrameStreamer already use for their own
                // per-tick failures.
                Console.Error.WriteLine(
                    $"WindowDiscoveryStreamer: transient discovery failure for {app.Id}. {error.GetType().Name}: {error.Message}"
                );
                continue;
            }

            foreach (var window in discovered)
            {
                var createdEvent = session.TryTrackDiscoveredWindow(app, window);
                if (createdEvent is not null)
                {
                    await onEvent(createdEvent, cancellationToken);
                }
            }
        }
    }

    private IReadOnlyList<(WindowsAppDescriptor App, IReadOnlySet<string> KnownWindowIds)> SnapshotTrackedApps()
    {
        try
        {
            return session.SnapshotTrackedAppsForDiscovery();
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"WindowDiscoveryStreamer: failed to snapshot tracked apps. {error.GetType().Name}: {error.Message}"
            );
            return Array.Empty<(WindowsAppDescriptor, IReadOnlySet<string>)>();
        }
    }
}
