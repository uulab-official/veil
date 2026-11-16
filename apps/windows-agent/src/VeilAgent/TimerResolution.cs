using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Raises the Windows timer resolution to 1 ms while any window is streaming.
/// </summary>
/// <remarks>
/// Windows wakes timers on its default 15.6 ms tick, so a stream asking for 8 ms between captures got 15.6
/// or 31 ms instead, which alone held mirrored windows near 30 frames a second. Since Windows 10 version 2004
/// the setting applies to this process only:
/// <see href="https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod"/>.
/// Reference counted, so it is released when the last stream stops.
/// </remarks>
public static class TimerResolution
{
    private static readonly object Gate = new();
    private static int holders;

    public static IDisposable Hold()
    {
        lock (Gate)
        {
            if (holders++ == 0 && OperatingSystem.IsWindows())
            {
                _ = timeBeginPeriod(1);
            }
        }

        return new Release();
    }

    private sealed class Release : IDisposable
    {
        private int released;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref released, 1) != 0)
            {
                return;
            }

            lock (Gate)
            {
                if (--holders == 0 && OperatingSystem.IsWindows())
                {
                    _ = timeEndPeriod(1);
                }
            }
        }
    }

    [DllImport("winmm.dll")]
    private static extern uint timeBeginPeriod(uint period);

    [DllImport("winmm.dll")]
    private static extern uint timeEndPeriod(uint period);
}

/// <summary>
/// One stream's share of the 1 ms timer resolution, taken only while the stream ticks fast.
/// </summary>
/// <remarks>
/// Streams used to hold the resolution for as long as they ran. A window that sits still is sampled once
/// a second, and its stream kept Windows ticking a thousand times a second all the same, for every window
/// open, which keeps the guest's processors from resting.
/// </remarks>
internal sealed class TimerResolutionLease : IDisposable
{
    /// <summary>Waits at least this long are fine on Windows' own 15.6 ms tick.</summary>
    public static readonly TimeSpan CoarseEnough = TimeSpan.FromMilliseconds(30);

    private IDisposable? held;

    public bool IsHeld => held is not null;

    /// <summary>Holds the resolution for a stream waiting this long between ticks, or lets it go.</summary>
    public void SetInterval(TimeSpan interval) => Set(interval < CoarseEnough);

    public void Set(bool needed)
    {
        if (needed && held is null)
        {
            held = TimerResolution.Hold();
        }
        else if (!needed && held is not null)
        {
            held.Dispose();
            held = null;
        }
    }

    public void Dispose() => Set(false);
}
