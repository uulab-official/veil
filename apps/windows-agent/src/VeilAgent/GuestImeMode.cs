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
    public static (bool? OpenBefore, bool? OpenAfter, int? ConversionAfter, string? WindowClass) LastApply { get; private set; }

    public static bool IsValid(string? mode) => mode is Native or Alphanumeric;

    /// <summary>Records the mode and applies it to the foreground window now and to each later one.</summary>
    public static void Set(string mode)
    {
        lock (Gate)
        {
            requestedMode = mode;
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

        // Read, then press the Hangul key if it differs. Writing IMC_SETOPENSTATUS changed only the IMM copy of
        // the state in TSF apps such as the Windows 11 Notepad: it read back as changed while typing stayed in
        // the old mode. The key goes through the IME itself, so every app follows it.
        var open = mode == Native;
        var openBefore = ReadOpenStatus(imeWindow);
        if (openBefore is { } before && before != open)
        {
            PressHangulKey();
            Thread.Sleep(30);
        }

        int? conversionAfter = SendMessageTimeout(imeWindow, WmImeControl, (IntPtr)ImcGetConversionMode, IntPtr.Zero, SmtoAbortIfHung, 100, out var after) != IntPtr.Zero
            ? (int)after
            : null;
        var className = new System.Text.StringBuilder(128);
        GetClassName(foreground, className, className.Capacity);
        LastApply = (openBefore, ReadOpenStatus(imeWindow), conversionAfter, className.ToString());
    }

    private const ushort VkHangul = 0x15;
    private const uint KeyeventfKeyup = 0x0002;

    private static void PressHangulKey()
    {
        var inputs = new[]
        {
            KeyboardInput(VkHangul, keyUp: false),
            KeyboardInput(VkHangul, keyUp: true),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
    }

    private static Input KeyboardInput(ushort virtualKey, bool keyUp) => new()
    {
        Type = 1,
        Keyboard = new KeyboardData
        {
            VirtualKey = virtualKey,
            ScanCode = (ushort)MapVirtualKey(virtualKey, 0),
            Flags = keyUp ? KeyeventfKeyup : 0,
        },
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardData
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    /// <summary>INPUT with the keyboard member, padded to the size of the union's largest member (MOUSEINPUT).</summary>
    [StructLayout(LayoutKind.Explicit)]
    private struct Input
    {
        [FieldOffset(0)] public uint Type;
        [FieldOffset(8)] public KeyboardData Keyboard;
        [FieldOffset(8)] private MouseData mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseData
    {
        public int X;
        public int Y;
        public uint MouseData_;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint code, uint mapType);

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
