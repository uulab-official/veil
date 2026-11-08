using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Keeps the Windows display on while at least one window is being mirrored to the Mac.
/// </summary>
/// <remarks>
/// With the guest display powered off, DWM stops composing: XAML apps such as Paint never redraw after a
/// resize, so <c>PrintWindow</c> keeps returning the old client area under a resized title bar and the
/// stream reports the window as unchanged. The host shows that guest window on the Mac, so Windows'
/// own display idle timer must not apply while it does.
/// See https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate.
/// </remarks>
public sealed class DisplayKeepAwake
{
    private readonly object gate = new();
    private readonly Action<bool> setDisplayRequired;
    private int holds;

    /// <param name="setDisplayRequired">
    /// Called with true when the first hold starts and false when the last one ends.
    /// </param>
    public DisplayKeepAwake(Action<bool> setDisplayRequired)
    {
        this.setDisplayRequired = setDisplayRequired;
    }

    /// <summary>A keep-awake that does nothing, for tests and non-Windows hosts.</summary>
    public static DisplayKeepAwake None { get; } = new(_ => { });

    public static DisplayKeepAwake CreateForWindows() =>
        OperatingSystem.IsWindows() ? new DisplayKeepAwake(new ExecutionStateThread().Set) : None;

    public IDisposable Hold()
    {
        lock (gate)
        {
            holds += 1;
            if (holds == 1)
            {
                setDisplayRequired(true);
            }
        }

        return new Releaser(this);
    }

    private void Release()
    {
        lock (gate)
        {
            holds -= 1;
            if (holds == 0)
            {
                setDisplayRequired(false);
            }
        }
    }

    private sealed class Releaser(DisplayKeepAwake owner) : IDisposable
    {
        private int disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0)
            {
                owner.Release();
            }
        }
    }

    /// <summary>
    /// Owns the execution state on one long-lived thread. <c>ES_CONTINUOUS</c> state belongs to the
    /// calling thread, and the frame streams run on pool threads that come and go.
    /// </summary>
    private sealed class ExecutionStateThread
    {
        private const uint ES_CONTINUOUS = 0x80000000;
        private const uint ES_SYSTEM_REQUIRED = 0x00000001;
        private const uint ES_DISPLAY_REQUIRED = 0x00000002;

        private readonly BlockingCollection<bool> requests = new();

        public ExecutionStateThread()
        {
            var thread = new Thread(Run) { IsBackground = true, Name = "Veil display keep-awake" };
            thread.Start();
        }

        public void Set(bool displayRequired) => requests.Add(displayRequired);

        private void Run()
        {
            foreach (var displayRequired in requests.GetConsumingEnumerable())
            {
                var flags = displayRequired
                    ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
                    : ES_CONTINUOUS;
                if (SetThreadExecutionState(flags) == 0)
                {
                    Console.Error.WriteLine($"SetThreadExecutionState(0x{flags:X8}) failed.");
                }
            }
        }

        [DllImport("kernel32.dll")]
        private static extern uint SetThreadExecutionState(uint esFlags);
    }
}
