namespace Veil.Agent;

/// <summary>
/// Retains the most recent captured pixels for each actively streamed window.
/// </summary>
internal sealed class WindowFrameChangeTracker
{
    private readonly Dictionary<string, byte[]> previousPixelsByWindowId = new();
    private readonly object gate = new();

    public bool HasChanged(string windowId, ReadOnlySpan<byte> pixels)
    {
        lock (gate)
        {
            if (previousPixelsByWindowId.TryGetValue(windowId, out var previous)
                && pixels.SequenceEqual(previous))
            {
                return false;
            }

            previousPixelsByWindowId[windowId] = pixels.ToArray();
            return true;
        }
    }

    public void Forget(string windowId)
    {
        lock (gate)
        {
            previousPixelsByWindowId.Remove(windowId);
        }
    }
}
