using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>One top-level window as the layout scan saw it, in z-order (topmost first).</summary>
public sealed record WindowLayoutEntry(
    string WindowId,
    int ProcessId,
    // The visible frame (DWMWA_EXTENDED_FRAME_BOUNDS), as everywhere else in the protocol.
    WindowRect Frame,
    // Visible, not minimized, and not cloaked: the window draws on the framebuffer.
    bool IsShown,
    // False for a shown window that cannot hide another window's pixels: one pixel across, as the helper
    // windows File Explorer and other programs keep, or layered with zero opacity.
    bool CoversPixels = true
);

/// <summary>A tracked window's place on the guest display.</summary>
public sealed record WindowLayoutWindow(
    string WindowId,
    string? OwnerWindowId,
    WindowRect Frame,
    int ZOrder,
    bool IsForeground,
    bool IsShown,
    bool FullyVisible
);

/// <summary>Where every tracked window sits on the guest display; see <c>window.layout</c> in docs/protocol.md.</summary>
public sealed record WindowLayout(WindowRect Display, IReadOnlyList<WindowLayoutWindow> Windows)
{
    public JsonObject ToEvent(int sequence)
    {
        var windows = new JsonArray();
        foreach (var window in Windows)
        {
            windows.Add(new JsonObject
            {
                ["windowId"] = window.WindowId,
                ["ownerWindowId"] = window.OwnerWindowId,
                ["frame"] = Rect(window.Frame),
                ["zOrder"] = window.ZOrder,
                ["isForeground"] = window.IsForeground,
                ["isShown"] = window.IsShown,
                ["fullyVisible"] = window.FullyVisible
            });
        }

        return new JsonObject
        {
            ["type"] = MessageTypes.WindowLayout,
            ["sequence"] = sequence,
            ["display"] = Rect(Display),
            ["windows"] = windows
        };
    }

    private static JsonObject Rect(WindowRect rect) => new()
    {
        ["x"] = rect.X,
        ["y"] = rect.Y,
        ["width"] = rect.Width,
        ["height"] = rect.Height
    };
}

/// <summary>
/// Turns a z-ordered scan of top-level windows into the layout of the tracked ones.
/// </summary>
/// <remarks>
/// A tracked window is <c>fullyVisible</c> when the host can take its pixels straight from the guest
/// framebuffer: it is shown, lies inside the display, and no shown window of another process above it
/// overlaps it. Windows of the same process above it (its menus, tooltips, dialogs) do not count, since
/// their pixels are what the user should see there anyway. Neither do windows that draw nothing over it
/// (<see cref="WindowLayoutEntry.CoversPixels"/>): one of those above the window in use sent it back to
/// captured frames, which are slower and include the Windows border.
/// </remarks>
public static class WindowLayoutComposer
{
    public static WindowLayout Compose(
        IReadOnlyList<WindowLayoutEntry> zOrdered,
        IReadOnlyDictionary<string, string?> trackedOwners,
        WindowRect display,
        string? foregroundWindowId)
    {
        var windows = new List<WindowLayoutWindow>();
        for (var index = 0; index < zOrdered.Count; index++)
        {
            var entry = zOrdered[index];
            if (!trackedOwners.TryGetValue(entry.WindowId, out var owner))
            {
                continue;
            }

            var fullyVisible = entry.IsShown && Contains(display, entry.Frame);
            for (var above = 0; fullyVisible && above < index; above++)
            {
                var other = zOrdered[above];
                if (other.IsShown
                    && other.CoversPixels
                    && other.ProcessId != entry.ProcessId
                    && Intersects(other.Frame, entry.Frame))
                {
                    fullyVisible = false;
                }
            }

            windows.Add(new WindowLayoutWindow(
                entry.WindowId,
                owner,
                entry.Frame,
                windows.Count,
                entry.WindowId == foregroundWindowId,
                entry.IsShown,
                fullyVisible));
        }

        return new WindowLayout(display, windows);
    }

    internal static bool Contains(WindowRect outer, WindowRect inner) =>
        inner.X >= outer.X
        && inner.Y >= outer.Y
        && inner.X + inner.Width <= outer.X + outer.Width
        && inner.Y + inner.Height <= outer.Y + outer.Height;

    /// <summary>
    /// Whether a shown window of this size and opacity can hide pixels of a window beneath it.
    /// </summary>
    /// <param name="layeredOpacity">
    /// The opacity of a layered window that sets one for the whole window, 0 to 255, or null for any other
    /// window.
    /// </param>
    public static bool CoversPixels(WindowRect frame, byte? layeredOpacity) =>
        frame.Width > 1 && frame.Height > 1 && layeredOpacity != 0;

    internal static bool Intersects(WindowRect a, WindowRect b) =>
        a.X < b.X + b.Width && b.X < a.X + a.Width && a.Y < b.Y + b.Height && b.Y < a.Y + a.Height;
}
