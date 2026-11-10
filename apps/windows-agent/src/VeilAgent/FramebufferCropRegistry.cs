namespace Veil.Agent;

/// <summary>
/// The windows the host currently shows by cropping the guest framebuffer (<c>window.crop.set</c>).
/// </summary>
/// <remarks>
/// Their frame streams keep running, because the host still reads a window's size and scale from its
/// frames, but at <see cref="CroppedInterval"/> instead of up to 120 times a second: the pixels the user
/// sees come from the framebuffer, and capturing them again only took CPU from the guest's own
/// software-rendered drawing. The host repeats the list every few seconds; a list older than
/// <see cref="Lifetime"/> lapses, so a host that went away does not leave windows slowed.
/// </remarks>
public static class FramebufferCropRegistry
{
    public static readonly TimeSpan CroppedInterval = TimeSpan.FromSeconds(1);
    public static readonly TimeSpan Lifetime = TimeSpan.FromSeconds(6);

    private static readonly object Gate = new();
    private static HashSet<string> cropped = new(StringComparer.Ordinal);
    private static long setAt;

    public static void Set(IEnumerable<string> windowIds, long? nowMilliseconds = null)
    {
        var next = windowIds.ToHashSet(StringComparer.Ordinal);
        lock (Gate)
        {
            cropped = next;
            setAt = nowMilliseconds ?? Environment.TickCount64;
        }
    }

    public static bool IsCropped(string windowId, long? nowMilliseconds = null)
    {
        lock (Gate)
        {
            return (nowMilliseconds ?? Environment.TickCount64) - setAt <= (long)Lifetime.TotalMilliseconds
                && cropped.Contains(windowId);
        }
    }

    public static void Clear()
    {
        lock (Gate)
        {
            cropped = new HashSet<string>(StringComparer.Ordinal);
        }
    }
}
