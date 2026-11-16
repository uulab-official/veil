using System.Collections.Concurrent;

namespace Veil.Agent;

/// <summary>
/// Remembers when each window's rectangle last changed, so capture can avoid screen copies right after.
/// </summary>
/// <remarks>
/// Desktop Duplication and screen copies read what DWM last composed, which lags a move or resize: copying
/// the new rectangle out of that image shows the desktop behind wherever the window has not been redrawn
/// yet, and a growing Paint window brought its Mac mirror a band of Windows desktop. Until the rectangle
/// holds for <see cref="SettleMilliseconds"/>, capture asks the window to draw itself (PrintWindow).
/// </remarks>
public sealed class WindowGeometrySettling
{
    public const long SettleMilliseconds = 300;

    private readonly ConcurrentDictionary<string, (WindowRect Outer, long ChangedAt)> states = new();

    /// <summary>True while the window's rectangle changed less than the settle time ago.</summary>
    public bool IsSettling(string windowId, WindowRect outer, long nowMilliseconds)
    {
        if (states.TryGetValue(windowId, out var state))
        {
            if (state.Outer == outer)
            {
                return nowMilliseconds - state.ChangedAt < SettleMilliseconds;
            }

            states[windowId] = (outer, nowMilliseconds);
            return true;
        }

        // The first capture has nothing stale to show.
        states[windowId] = (outer, nowMilliseconds - SettleMilliseconds);
        return false;
    }

    public void Forget(string windowId) => states.TryRemove(windowId, out _);
}
