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
    bool FullyVisible,
    // For a window that is not fully visible: the parts of it the display does show, in display pixels.
    // Null for a fully visible window, whose whole frame shows. Empty when none of it shows or the shape
    // has too many pieces to be worth sending.
    IReadOnlyList<WindowRect>? VisibleRegion = null,
    // The window's process runs above the agent, so input the agent injects does not reach it; see
    // <see cref="ProcessElevation"/>.
    bool Elevated = false
);

/// <summary>Where every tracked window sits on the guest display; see <c>window.layout</c> in docs/protocol.md.</summary>
public sealed record WindowLayout(
    WindowRect Display,
    IReadOnlyList<WindowLayoutWindow> Windows,
    // The display shows the Winlogon desktop instead of these windows; see <see cref="InputDesktop"/>.
    bool SecureDesktop = false)
{
    public JsonObject ToEvent(int sequence)
    {
        var windows = new JsonArray();
        foreach (var window in Windows)
        {
            var entry = new JsonObject
            {
                ["windowId"] = window.WindowId,
                ["ownerWindowId"] = window.OwnerWindowId,
                ["frame"] = Rect(window.Frame),
                ["zOrder"] = window.ZOrder,
                ["isForeground"] = window.IsForeground,
                ["isShown"] = window.IsShown,
                ["fullyVisible"] = window.FullyVisible
            };
            if (window.Elevated)
            {
                entry["elevated"] = true;
            }
            if (window.VisibleRegion is { } region)
            {
                var rects = new JsonArray();
                foreach (var rect in region)
                {
                    rects.Add(Rect(rect));
                }
                entry["visibleRegion"] = rects;
            }
            windows.Add(entry);
        }

        return new JsonObject
        {
            ["type"] = MessageTypes.WindowLayout,
            ["sequence"] = sequence,
            ["display"] = Rect(Display),
            ["secureDesktop"] = SecureDesktop,
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
///
/// No window is <c>fullyVisible</c> while the secure desktop is up: the framebuffer then shows a User
/// Account Control prompt or the lock screen where the window was.
/// </remarks>
public static class WindowLayoutComposer
{
    public static WindowLayout Compose(
        IReadOnlyList<WindowLayoutEntry> zOrdered,
        IReadOnlyDictionary<string, string?> trackedOwners,
        WindowRect display,
        string? foregroundWindowId,
        bool secureDesktop = false,
        Func<int, bool>? isElevated = null)
    {
        var windows = new List<WindowLayoutWindow>();
        for (var index = 0; index < zOrdered.Count; index++)
        {
            var entry = zOrdered[index];
            if (!trackedOwners.TryGetValue(entry.WindowId, out var owner))
            {
                continue;
            }

            var fullyVisible = !secureDesktop && entry.IsShown && Contains(display, entry.Frame);
            // What the display shows of the window: its frame on the display, less every window above it
            // that covers pixels, and less the shadow around each of those.
            var visible = !secureDesktop && entry.IsShown && Intersection(entry.Frame, display) is { } onDisplay
                ? new List<WindowRect> { onDisplay }
                : new List<WindowRect>();
            for (var above = 0; above < index && (fullyVisible || visible.Count > 0); above++)
            {
                var other = zOrdered[above];
                if (other.IsShown
                    && other.CoversPixels
                    && Covers(other, entry, trackedOwners)
                    && Intersects(other.Frame, entry.Frame))
                {
                    fullyVisible = false;
                    visible = Subtract(visible, Inflate(other.Frame, ShadowMargin));
                    if (visible.Count > MaximumVisibleRects)
                    {
                        visible.Clear();
                    }
                }
            }

            windows.Add(new WindowLayoutWindow(
                entry.WindowId,
                owner,
                entry.Frame,
                windows.Count,
                entry.WindowId == foregroundWindowId,
                entry.IsShown,
                fullyVisible,
                fullyVisible ? null : visible,
                isElevated?.Invoke(entry.ProcessId) ?? false));
        }

        return new WindowLayout(display, windows, secureDesktop);
    }

    /// <summary>
    /// The most pieces a window's visible part is sent in. A window under many others breaks into more,
    /// and by then little of it shows.
    /// </summary>
    public const int MaximumVisibleRects = 12;

    /// <summary>
    /// How far around a covering window its shadow darkens the window behind. Those pixels are the window
    /// behind with a shadow drawn over it, and cropped into a Mac window they put a dark band next to the
    /// Mac window in front, which casts a shadow of its own there. Measured on Windows 11 at 100% under the
    /// window in front: most of the shadow lies within 45 pixels, and at 48 it still darkens by a tenth,
    /// which shows as a grey step on a light window. It is gone at 63.
    /// </summary>
    public const int ShadowMargin = 64;

    internal static WindowRect Inflate(WindowRect rect, int margin) =>
        new(rect.X - margin, rect.Y - margin, rect.Width + 2 * margin, rect.Height + 2 * margin);

    /// <summary>
    /// Whether a window above another hides that window's pixels, as opposed to being part of it. A window
    /// of another process does. So does a window of the same process that is an app window in its own
    /// right, tracked with no owner: two File Explorer windows are one process, and the lower one used to
    /// count as fully visible and show the upper one's pixels inside it. The process's other windows above
    /// it, its menus, tooltips, and dialogs, belong to what the user should see there.
    /// </summary>
    private static bool Covers(
        WindowLayoutEntry above,
        WindowLayoutEntry below,
        IReadOnlyDictionary<string, string?> trackedOwners) =>
        above.ProcessId != below.ProcessId
        || (trackedOwners.TryGetValue(above.WindowId, out var ownerOfAbove) && ownerOfAbove is null);

    internal static WindowRect? Intersection(WindowRect a, WindowRect b)
    {
        var left = Math.Max(a.X, b.X);
        var top = Math.Max(a.Y, b.Y);
        var right = Math.Min(a.X + a.Width, b.X + b.Width);
        var bottom = Math.Min(a.Y + a.Height, b.Y + b.Height);
        return right > left && bottom > top ? new WindowRect(left, top, right - left, bottom - top) : null;
    }

    /// <summary>Takes a rectangle out of a set of rectangles that do not overlap; neither do the results.</summary>
    internal static List<WindowRect> Subtract(IReadOnlyList<WindowRect> from, WindowRect hole)
    {
        var result = new List<WindowRect>();
        foreach (var rect in from)
        {
            if (Intersection(rect, hole) is not { } cut)
            {
                result.Add(rect);
                continue;
            }

            // A band above the hole, one below it, and what is left on either side between them.
            if (cut.Y > rect.Y)
            {
                result.Add(new WindowRect(rect.X, rect.Y, rect.Width, cut.Y - rect.Y));
            }
            var rectBottom = rect.Y + rect.Height;
            var cutBottom = cut.Y + cut.Height;
            if (cutBottom < rectBottom)
            {
                result.Add(new WindowRect(rect.X, cutBottom, rect.Width, rectBottom - cutBottom));
            }
            if (cut.X > rect.X)
            {
                result.Add(new WindowRect(rect.X, cut.Y, cut.X - rect.X, cut.Height));
            }
            var rectRight = rect.X + rect.Width;
            var cutRight = cut.X + cut.Width;
            if (cutRight < rectRight)
            {
                result.Add(new WindowRect(cutRight, cut.Y, rectRight - cutRight, cut.Height));
            }
        }

        return result;
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
