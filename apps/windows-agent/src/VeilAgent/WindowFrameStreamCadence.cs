namespace Veil.Agent;

/// <summary>
/// Chooses how often to sample a window's pixels.
/// </summary>
/// <remarks>
/// The streamer used to tick on a fixed 250 ms timer, which is a hard 4 frames-per-second ceiling no
/// matter how responsive the guest could be. Sampling can now be much faster, because an unchanged
/// tick costs a capture plus a vectorized buffer comparison rather than a full-window PNG encode.
///
/// Sampling still backs off while a window is static, so an untouched window does not burn guest CPU on
/// <c>PrintWindow</c> forever. The idle interval must stay well inside the host's stale threshold, or
/// backing off would itself trip stream recovery.
///
/// Pure state machine with no timer or clock inside it, so the transitions are unit testable.
/// </remarks>
public sealed class WindowFrameStreamCadence
{
    public static readonly TimeSpan DefaultActiveInterval = TimeSpan.FromMilliseconds(33);
    public static readonly TimeSpan DefaultIdleInterval = TimeSpan.FromMilliseconds(250);

    /// <summary>
    /// Unchanged ticks tolerated at the active rate before backing off.
    /// </summary>
    /// <remarks>
    /// Small enough that a genuinely idle window drops to the cheap rate quickly, large enough that a
    /// pause between keystrokes does not cost the user a visible lag spike on the next change.
    /// </remarks>
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

    /// <summary>
    /// Records a tick outcome and returns the interval to wait before the next one.
    /// </summary>
    public TimeSpan Next(bool changed)
    {
        if (changed)
        {
            // Any change snaps straight back to the active rate. Ramping back up gradually would make
            // the first interaction after a pause feel sluggish.
            consecutiveUnchangedTicks = 0;
        }
        else if (consecutiveUnchangedTicks < unchangedTicksBeforeIdle)
        {
            consecutiveUnchangedTicks += 1;
        }

        return CurrentInterval;
    }
}
