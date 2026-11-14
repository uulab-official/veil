namespace Veil.Agent.Tests;

public sealed class WindowChangeSignalTests
{
    private static readonly WindowRect Display = new(0, 0, 1920, 1080);

    [Fact]
    public void OnlyTopLevelWindowChangesCount()
    {
        Assert.True(WindowChangeSignal.IsWindowChange(idObject: 0, idChild: 0, isTopLevel: true));
        // A child control, the caret (-8), or the cursor (-9) moving says nothing about the layout.
        Assert.False(WindowChangeSignal.IsWindowChange(idObject: 0, idChild: 0, isTopLevel: false));
        Assert.False(WindowChangeSignal.IsWindowChange(idObject: -8, idChild: 0, isTopLevel: true));
        Assert.False(WindowChangeSignal.IsWindowChange(idObject: -9, idChild: 0, isTopLevel: true));
        Assert.False(WindowChangeSignal.IsWindowChange(idObject: 0, idChild: 3, isTopLevel: true));
    }

    [Fact]
    public async Task AWaiterWakesOnTheNextChangeOnly()
    {
        using var signal = WindowChangeSignal.Start();
        var first = signal.WaitAsync(CancellationToken.None);
        Assert.False(first.IsCompleted);
        signal.Raise();
        await first.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.False(signal.WaitAsync(CancellationToken.None).IsCompleted);
    }

    [Fact]
    public async Task AWindowChangeScansAgainWithoutWaitingForThePoll()
    {
        using var signal = WindowChangeSignal.Start();
        var scans = 0;
        var secondScan = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var tracked = new Dictionary<string, string?> { ["hwnd:00000001"] = null };
        var streamer = new WindowLayoutStreamer(
            () => tracked,
            () =>
            {
                if (Interlocked.Increment(ref scans) == 2)
                {
                    secondScan.TrySetResult();
                }
                return new WindowLayoutScan(
                    new[] { new WindowLayoutEntry("hwnd:00000001", 1, new WindowRect(0, 0, 800, 600), true) }, Display, null);
            },
            // The poll never comes due; only the change can start the second scan. The short wait that
            // keeps wakes at most one per 4 ms passes at once.
            delay: (interval, token) => interval >= WindowLayoutStreamer.ActiveInterval
                ? Task.Delay(Timeout.Infinite, token)
                : Task.CompletedTask,
            inputDesktopIsSecure: () => false,
            isElevated: _ => false,
            windowChanged: signal.WaitAsync);

        using var cancellation = new CancellationTokenSource();
        var stream = streamer.StreamAsync((_, _) => Task.CompletedTask, cancellation.Token);
        while (Volatile.Read(ref scans) < 1)
        {
            await Task.Delay(10);
        }
        Assert.False(secondScan.Task.IsCompleted);

        signal.Raise();
        await secondScan.Task.WaitAsync(TimeSpan.FromSeconds(5));

        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => stream);
    }
}
