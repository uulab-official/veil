using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Keeps the Windows IME of the foreground window in the mode the host asked for (<c>input.ime.set</c>).
/// </summary>
/// <remarks>
/// On a Mac, Korean and English switch with the macOS input source. Windows kept its own IME state, so keys
/// the Mac sent as English came out as jamo. The mode is applied through the window's default IME window,
/// which works across processes:
/// <see href="https://learn.microsoft.com/windows/win32/intl/wm-ime-control"/>. It is applied again when
/// another window comes to the foreground, because each window keeps its own IME state.
/// </remarks>
public static class GuestImeMode
{
    public const string Native = "native";
    public const string Alphanumeric = "alphanumeric";
    /// <summary>Stop setting the IME: the user switches it, with the Hangul key the host passes through.</summary>
    public const string Unmanaged = "unmanaged";

    private const uint WmImeControl = 0x0283;
    private const int ImcGetConversionMode = 0x0001;
    private const int ImcSetConversionMode = 0x0002;
    private const int ImcGetOpenStatus = 0x0005;
    private const int ImcSetOpenStatus = 0x0006;
    internal const int ImeCmodeNative = 0x0001;
    private const uint SmtoAbortIfHung = 0x0002;
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(150);

    private static readonly object Gate = new();
    private static string? requestedMode;
    private static IntPtr appliedWindow;
    private static string? appliedMode;
    private static bool watching;

    /// <summary>What the last apply saw, for <c>input.ime.set</c>'s reply: whether reading back worked.</summary>
    public static (bool? OpenBefore, bool? OpenAfter, int? ConversionAfter, string? WindowClass, bool? HangulToggledBefore, bool? HangulToggledAfter) LastApply { get; private set; }

    public static bool IsValid(string? mode) => mode is Native or Alphanumeric or Unmanaged;

    /// <summary>Records the mode and applies it to the foreground window now and to each later one.</summary>
    public static void Set(string mode)
    {
        lock (Gate)
        {
            requestedMode = mode == Unmanaged ? null : mode;
            appliedMode = null;
            if (!watching && OperatingSystem.IsWindows())
            {
                watching = true;
                _ = Task.Run(WatchForegroundAsync);
            }
        }
        ApplyIfNeeded();
    }

    /// <summary>The conversion mode that keeps every other bit, such as full-width for Japanese.</summary>
    internal static int ConversionMode(int current, string mode) =>
        mode == Native ? current | ImeCmodeNative : current & ~ImeCmodeNative;

    private static async Task WatchForegroundAsync()
    {
        while (true)
        {
            await Task.Delay(PollInterval);
            try
            {
                ApplyIfNeeded();
            }
            catch (Exception error)
            {
                Console.Error.WriteLine($"IME mode apply failed: {error.Message}");
            }
        }
    }

    private static void ApplyIfNeeded()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        string? mode;
        IntPtr foreground;
        lock (Gate)
        {
            mode = requestedMode;
            foreground = GetForegroundWindow();
            if (mode is null || foreground == IntPtr.Zero || (foreground == appliedWindow && mode == appliedMode))
            {
                return;
            }
            appliedWindow = foreground;
            appliedMode = mode;
        }

        var imeWindow = ImmGetDefaultIMEWnd(foreground);
        if (imeWindow == IntPtr.Zero)
        {
            return;
        }

        // IMC_SETOPENSTATUS reliably switches Win32 windows, which is what Veil types its own commands into.
        // TSF apps such as the Windows 11 Notepad keep their own state and only appear to follow it, and no
        // cross-process read of their state was reliable, so the host does not use this for them: the user
        // switches with the Hangul key the host passes through.
        var open = mode == Native;
        var openBefore = ReadOpenStatus(imeWindow);
        var toggledBefore = ReadHangulToggle(foreground);
        SendMessageTimeout(imeWindow, WmImeControl, (IntPtr)ImcSetOpenStatus, (IntPtr)(open ? 1 : 0), SmtoAbortIfHung, 100, out _);
        if (SendMessageTimeout(imeWindow, WmImeControl, (IntPtr)ImcGetConversionMode, IntPtr.Zero, SmtoAbortIfHung, 100, out var current) != IntPtr.Zero)
        {
            var next = ConversionMode((int)current, mode!);
            if (next != (int)current)
            {
                SendMessageTimeout(imeWindow, WmImeControl, (IntPtr)ImcSetConversionMode, (IntPtr)next, SmtoAbortIfHung, 100, out _);
            }
        }

        int? conversionAfter = SendMessageTimeout(imeWindow, WmImeControl, (IntPtr)ImcGetConversionMode, IntPtr.Zero, SmtoAbortIfHung, 100, out var after) != IntPtr.Zero
            ? (int)after
            : null;
        var className = new System.Text.StringBuilder(128);
        GetClassName(foreground, className, className.Capacity);
        LastApply = (openBefore, ReadOpenStatus(imeWindow), conversionAfter, className.ToString(), toggledBefore, ReadHangulToggle(foreground));
    }

    private const int VkHangul = 0x15;

    /// <summary>The VK_HANGUL toggle bit in the foreground thread's keyboard state.</summary>
    private static bool? ReadHangulToggle(IntPtr foreground)
    {
        var current = GetCurrentThreadId();
        var target = GetWindowThreadProcessId(foreground, out _);
        var attached = target != 0 && target != current && AttachThreadInput(current, target, true);
        try
        {
            var state = new byte[256];
            return GetKeyboardState(state) ? (state[VkHangul] & 1) != 0 : null;
        }
        finally
        {
            if (attached)
            {
                AttachThreadInput(current, target, false);
            }
        }
    }

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint attach, uint attachTo, bool doAttach);

    [DllImport("user32.dll")]
    private static extern bool GetKeyboardState(byte[] state);

    private static bool? ReadOpenStatus(IntPtr imeWindow) =>
        SendMessageTimeout(imeWindow, WmImeControl, (IntPtr)ImcGetOpenStatus, IntPtr.Zero, SmtoAbortIfHung, 100, out var open) != IntPtr.Zero
            ? open != IntPtr.Zero
            : null;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("imm32.dll")]
    private static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
}
