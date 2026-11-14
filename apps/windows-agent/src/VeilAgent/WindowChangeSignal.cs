using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Wakes the layout scan as soon as Windows moves, resizes, shows, hides, restacks, or activates a
/// top-level window, instead of waiting for the next poll.
/// </summary>
/// <remarks>
/// The scan runs every 8 ms while something moves and every 33 ms once the layout has been still. A move
/// Windows makes by itself, such as snapping or an app placing its own window, was seen up to 33 ms late,
/// and in that gap the host could already hold a guest picture with the window at its new place while
/// cropping the old one: the desktop showed through the Mac window. WinEvents arrive as the window
/// manager makes the change, before the next frame is presented
/// (<see href="https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwineventhook"/>).
///
/// Out-of-context hooks are delivered to the thread that set them, which therefore runs a message loop
/// of its own. Polling stays as the fallback: a missed or unavailable hook only costs the old delay.
/// </remarks>
public sealed class WindowChangeSignal : IDisposable
{
    private readonly object gate = new();
    private TaskCompletionSource signal = NewSource();
    private Thread? thread;
    private uint threadId;
    // Held so the delegate the hooks call is not collected while they are set.
    private WinEventDelegate? callback;

    /// <summary>Starts listening on Windows; elsewhere it never signals.</summary>
    public static WindowChangeSignal Start()
    {
        var instance = new WindowChangeSignal();
        if (OperatingSystem.IsWindows())
        {
            instance.StartHooks();
        }
        return instance;
    }

    /// <summary>Completes at the next window change after this call, or when cancelled.</summary>
    public Task WaitAsync(CancellationToken cancellationToken)
    {
        Task pending;
        lock (gate)
        {
            pending = signal.Task;
        }
        return pending.WaitAsync(cancellationToken);
    }

    /// <summary>Wakes every waiter; also used by tests.</summary>
    public void Raise()
    {
        TaskCompletionSource fired;
        lock (gate)
        {
            fired = signal;
            signal = NewSource();
        }
        fired.TrySetResult();
    }

    /// <summary>Whether a WinEvent names a change to a top-level window's placement or visibility.</summary>
    public static bool IsWindowChange(int idObject, int idChild, bool isTopLevel) =>
        idObject == ObjidWindow && idChild == ChildidSelf && isTopLevel;

    private static TaskCompletionSource NewSource() =>
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private void StartHooks()
    {
        var ready = new ManualResetEventSlim();
        thread = new Thread(() => Run(ready)) { IsBackground = true, Name = "Veil window change hooks" };
        thread.Start();
        ready.Wait(TimeSpan.FromSeconds(2));
    }

    private void Run(ManualResetEventSlim ready)
    {
        threadId = GetCurrentThreadId();
        callback = OnWinEvent;
        // Foreground through minimize-end: activation, move/size start and end, minimize and restore.
        var systemHook = SetWinEventHook(EventSystemForeground, EventSystemMinimizeEnd, 0, callback, 0, 0, WineventOutofcontext | WineventSkipownprocess);
        // Show through location change: show, hide, reorder, and every move or resize.
        var objectHook = SetWinEventHook(EventObjectShow, EventObjectLocationchange, 0, callback, 0, 0, WineventOutofcontext | WineventSkipownprocess);
        ready.Set();
        if (systemHook == 0 && objectHook == 0)
        {
            Console.Error.WriteLine("WindowChangeSignal: no WinEvent hook could be set; layout falls back to polling.");
            return;
        }

        try
        {
            while (GetMessage(out var message, 0, 0, 0) > 0)
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
        }
        finally
        {
            if (systemHook != 0)
            {
                UnhookWinEvent(systemHook);
            }
            if (objectHook != 0)
            {
                UnhookWinEvent(objectHook);
            }
        }
    }

    private void OnWinEvent(nint hook, uint eventType, nint hwnd, int idObject, int idChild, uint eventThread, uint eventTime)
    {
        if (hwnd == 0)
        {
            return;
        }
        if (IsWindowChange(idObject, idChild, GetAncestor(hwnd, GaRoot) == hwnd))
        {
            Raise();
        }
    }

    public void Dispose()
    {
        if (threadId != 0)
        {
            PostThreadMessage(threadId, WmQuit, 0, 0);
        }
    }

    private const uint EventSystemForeground = 0x0003;
    private const uint EventSystemMinimizeEnd = 0x0017;
    private const uint EventObjectShow = 0x8002;
    private const uint EventObjectLocationchange = 0x800B;
    private const uint WineventOutofcontext = 0x0000;
    private const uint WineventSkipownprocess = 0x0002;
    private const int ObjidWindow = 0;
    private const int ChildidSelf = 0;
    private const uint GaRoot = 2;
    private const uint WmQuit = 0x0012;

    private delegate void WinEventDelegate(nint hook, uint eventType, nint hwnd, int idObject, int idChild, uint eventThread, uint eventTime);

    [StructLayout(LayoutKind.Sequential)]
    private struct Msg
    {
        public nint Hwnd;
        public uint Message;
        public nint WParam;
        public nint LParam;
        public uint Time;
        public int PointX;
        public int PointY;
        public uint Private;
    }

    [DllImport("user32.dll")]
    private static extern nint SetWinEventHook(uint eventMin, uint eventMax, nint module, WinEventDelegate callback, uint processId, uint threadId, uint flags);

    [DllImport("user32.dll")]
    private static extern bool UnhookWinEvent(nint hook);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out Msg message, nint hwnd, uint filterMin, uint filterMax);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref Msg message);

    [DllImport("user32.dll")]
    private static extern nint DispatchMessage(ref Msg message);

    [DllImport("user32.dll")]
    private static extern bool PostThreadMessage(uint threadId, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern nint GetAncestor(nint hwnd, uint flags);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
}
