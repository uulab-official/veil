using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Hides the Windows pointer while a host is connected.
/// </summary>
/// <remarks>
/// The Mac pointer is always shown over mirrored windows and the desktop view. The VirtIO GPU display draws
/// the Windows pointer into the guest framebuffer, so once the host crops windows out of that framebuffer
/// (<c>window.layout</c>) a second, lagging pointer appeared in them, and stayed behind where the Mac pointer
/// last left the window. Parallels hides the guest pointer in Coherence the same way. The Magnification
/// API hides every pointer shape, including app cursors such as Paint's brush, and Windows restores it
/// when the agent process ends:
/// <see href="https://learn.microsoft.com/windows/win32/api/magnification/nf-magnification-magshowsystemcursor"/>.
/// </remarks>
public static class GuestCursorVisibility
{
    private static readonly object Gate = new();
    private static int connectedHosts;
    private static bool initialized;

    public static IDisposable HostConnected()
    {
        lock (Gate)
        {
            if (connectedHosts++ == 0)
            {
                Apply(show: false);
            }
        }

        return new Disconnect();
    }

    private static void Apply(bool show)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        try
        {
            if (!initialized)
            {
                initialized = MagInitialize();
            }
            if (initialized && !MagShowSystemCursor(show))
            {
                Console.Error.WriteLine($"GuestCursorVisibility: MagShowSystemCursor({show}) failed.");
            }
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            Console.Error.WriteLine($"GuestCursorVisibility: unavailable. {error.Message}");
        }
    }

    private sealed class Disconnect : IDisposable
    {
        private int disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) != 0)
            {
                return;
            }

            lock (Gate)
            {
                if (--connectedHosts == 0)
                {
                    Apply(show: true);
                }
            }
        }
    }

    [DllImport("magnification.dll")]
    private static extern bool MagInitialize();

    [DllImport("magnification.dll")]
    private static extern bool MagShowSystemCursor(bool showCursor);
}
