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

        Assert.Equal(TimeSpan.FromMilliseconds(33), cadence.Next(changed: true));
        Assert.False(cadence.IsIdle);
    }

    [Fact]
    public void IdleIntervalStaysInsideTheHostStaleThreshold()
    {
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
}
