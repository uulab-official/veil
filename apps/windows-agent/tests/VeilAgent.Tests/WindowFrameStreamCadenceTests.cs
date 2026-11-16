using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowFrameStreamCadenceTests
{
    private static WindowFrameStreamCadence MakeCadence(int unchangedTicksBeforeIdle = 3) =>
        new(
            activeInterval: TimeSpan.FromMilliseconds(33),
            idleInterval: TimeSpan.FromMilliseconds(250),
            unchangedTicksBeforeIdle: unchangedTicksBeforeIdle
        );

    [Fact]
    public void WakesFromIdleToTheActiveRate()
    {
        var cadence = MakeCadence(unchangedTicksBeforeIdle: 1);
        cadence.Next(changed: false);
        Assert.True(cadence.IsIdle);

        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Wake());
        Assert.False(cadence.IsIdle);
    }

    [Fact]
    public void StartsAtTheActiveRate()
    {
        var cadence = MakeCadence();

        Assert.False(cadence.IsIdle);
        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.CurrentInterval);
    }

    [Fact]
    public void StaysActiveWhileContentKeepsChanging()
    {
        var cadence = MakeCadence();

        for (var tick = 0; tick < 10; tick++)
        {
            Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Next(changed: true));
        }

        Assert.False(cadence.IsIdle);
    }

    [Fact]
    public void BacksOffOnlyAfterTheUnchangedThreshold()
    {
        var cadence = MakeCadence(unchangedTicksBeforeIdle: 3);

        // A brief pause between keystrokes must not cost the user a lag spike on the next change, so the
        // first unchanged ticks stay at the active rate.
        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Next(changed: false));
        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Next(changed: false));
        Assert.Equal(TimeSpan.FromMilliseconds(250), cadence.Next(changed: false));
        Assert.True(cadence.IsIdle);
    }

    [Fact]
    public void SnapsBackToActiveOnTheFirstChange()
    {
        var cadence = MakeCadence(unchangedTicksBeforeIdle: 2);
        cadence.Next(changed: false);
        cadence.Next(changed: false);
        Assert.True(cadence.IsIdle);

        // Ramping back up gradually would make the first interaction after a pause feel sluggish.
        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Next(changed: true));
        Assert.False(cadence.IsIdle);
    }

    [Fact]
    public void IdleIntervalStaysWellInsideTheHostStaleThreshold()
    {
        // The host marks a stream stale after 5 seconds without liveness. Backing off must never itself
        // trip recovery, so the idle interval needs a wide margin.
        Assert.True(WindowFrameStreamCadence.DefaultIdleInterval < TimeSpan.FromSeconds(1));
        Assert.True(WindowFrameStreamCadence.DefaultActiveInterval < WindowFrameStreamCadence.DefaultIdleInterval);
    }

    [Fact]
    public void DoesNotOverflowTheUnchangedCounterWhileIdleForALongTime()
    {
        var cadence = MakeCadence(unchangedTicksBeforeIdle: 2);

        for (var tick = 0; tick < 10_000; tick++)
        {
            cadence.Next(changed: false);
        }

        Assert.True(cadence.IsIdle);
        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Next(changed: true));
    }

    [Fact]
    public void TheFineTimerIsHeldOnlyForFastTicks()
    {
        // The count of holders is shared by every stream in the process, so only this lease is looked at.
        using var lease = new TimerResolutionLease();

        lease.SetInterval(WindowFrameStreamCadence.DefaultActiveInterval);
        Assert.True(lease.IsHeld);
        lease.SetInterval(TimeSpan.FromMilliseconds(1));
        Assert.True(lease.IsHeld);

        // A still window, sampled four times a second or once a second, lets it go.
        lease.SetInterval(WindowFrameStreamCadence.DefaultIdleInterval);
        Assert.False(lease.IsHeld);
        lease.SetInterval(FramebufferCropRegistry.CroppedInterval);
        Assert.False(lease.IsHeld);

        lease.SetInterval(WindowLayoutStreamer.ActiveInterval);
        Assert.True(lease.IsHeld);
        // The layout scan's settled pace does not need it either.
        lease.SetInterval(WindowLayoutStreamer.SettledInterval);
        Assert.False(lease.IsHeld);

        lease.SetInterval(WindowLayoutStreamer.ActiveInterval);
        lease.Dispose();
        Assert.False(lease.IsHeld);
    }
}
