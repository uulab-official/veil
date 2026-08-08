namespace Veil.Agent;

/// <summary>
/// Selects an active or idle interval from capture outcomes without owning a timer or clock.
/// </summary>
public sealed class WindowFrameStreamCadence
{
    public static readonly TimeSpan DefaultActiveInterval = TimeSpan.FromMilliseconds(33);
    public static readonly TimeSpan DefaultIdleInterval = TimeSpan.FromMilliseconds(250);
    public const int DefaultUnchangedTicksBeforeIdle = 15;

    private readonly TimeSpan activeInterval;
    private readonly TimeSpan idleInterval;
    private readonly int unchangedTicksBeforeIdle;
    private int consecutiveUnchangedTicks;

    public WindowFrameStreamCadence(
        TimeSpan? activeInterval = null,
        TimeSpan? idleInterval = null,
        int unchangedTicksBeforeIdle = DefaultUnchangedTicksBeforeIdle
    )
    {
        this.activeInterval = activeInterval ?? DefaultActiveInterval;
        this.idleInterval = idleInterval ?? DefaultIdleInterval;
        this.unchangedTicksBeforeIdle = Math.Max(1, unchangedTicksBeforeIdle);
    }

    public bool IsIdle => consecutiveUnchangedTicks >= unchangedTicksBeforeIdle;

    public TimeSpan CurrentInterval => IsIdle ? idleInterval : activeInterval;

    public TimeSpan Next(bool changed)
    {
        if (changed)
        {
            consecutiveUnchangedTicks = 0;
        }
        else if (consecutiveUnchangedTicks < unchangedTicksBeforeIdle)
        {
            consecutiveUnchangedTicks += 1;
        }

        return CurrentInterval;
    }
}
