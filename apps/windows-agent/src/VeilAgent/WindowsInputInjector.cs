using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Delivers mirrored-window input to Windows as real input through <c>SendInput</c>.
/// </summary>
/// <remarks>
/// Input used to be posted as window messages to the top-level HWND. Modern apps such as Paint and Notepad
/// draw their content in XAML or DirectComposition child surfaces that only take input from the system input
/// queue, so posted clicks, drags, and keys never reached them: the window could be moved and resized from
/// the Mac, but nothing inside it responded. Posted <c>WM_MOUSEMOVE</c> also carried no button state, so no
/// drag could work even in classic apps. <c>SendInput</c> goes through the same path as a physical mouse and
/// keyboard on the guest. It moves only the guest's own cursor; the Mac pointer is never touched.
/// See https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput.
/// </remarks>
internal static class WindowsInputInjector
{
    internal const uint INPUT_MOUSE = 0;
    internal const uint INPUT_KEYBOARD = 1;

    internal const uint MOUSEEVENTF_MOVE = 0x0001;
    internal const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    internal const uint MOUSEEVENTF_LEFTUP = 0x0004;
    internal const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    internal const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    internal const uint MOUSEEVENTF_WHEEL = 0x0800;
    internal const uint MOUSEEVENTF_HWHEEL = 0x01000;
    internal const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    internal const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

    internal const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    internal const uint KEYEVENTF_KEYUP = 0x0002;
    internal const uint KEYEVENTF_UNICODE = 0x0004;

    private const int WheelDelta = 120;
    private const int VK_CONTROL = 0x11;
    private const int VK_SHIFT = 0x10;
    private const int VK_MENU = 0x12;

    /// <summary>
    /// Keys that live on the extended part of the keyboard. Without the extended flag, an arrow key arrives
    /// as its numeric keypad twin and does something else once Num Lock is on.
    /// </summary>
    private static readonly HashSet<int> ExtendedVirtualKeys =
    [
        0x21, 0x22, 0x23, 0x24, // Page Up, Page Down, End, Home
        0x25, 0x26, 0x27, 0x28, // arrows
        0x2D, 0x2E,             // Insert, Delete
        0x5B, 0x5C, 0x5D,       // Windows keys, Apps
        0x6F,                   // keypad divide
        0x90,                   // Num Lock
        0xA3, 0xA5              // right Ctrl, right Alt
    ];

    /// <summary>The mouse button flags for a protocol mouse event, or null for an unknown event.</summary>
    internal static uint? MouseButtonFlags(string inputEvent) => inputEvent switch
    {
        "leftDown" => MOUSEEVENTF_LEFTDOWN,
        "leftUp" => MOUSEEVENTF_LEFTUP,
        "rightDown" => MOUSEEVENTF_RIGHTDOWN,
        "rightUp" => MOUSEEVENTF_RIGHTUP,
        "move" => 0,
        "scroll" => MOUSEEVENTF_WHEEL,
        _ => null
    };

    /// <summary>
    /// Converts a screen pixel to the 0...65535 range absolute mouse input uses across the virtual desktop.
    /// </summary>
    internal static (int X, int Y) NormalizeToVirtualDesktop(
        int screenX,
        int screenY,
        int virtualLeft,
        int virtualTop,
        int virtualWidth,
        int virtualHeight,
        int maximum = 65535
    )
    {
        int Normalize(int value, int origin, int extent)
        {
            if (extent <= 1)
            {
                return 0;
            }
            var clamped = Math.Clamp(value - origin, 0, extent - 1);
            return (int)Math.Round(clamped * (double)maximum / (extent - 1), MidpointRounding.AwayFromZero);
        }

        return (Normalize(screenX, virtualLeft, virtualWidth), Normalize(screenY, virtualTop, virtualHeight));
    }

    internal static bool IsExtendedKey(int virtualKey) => ExtendedVirtualKeys.Contains(virtualKey);

    internal static IEnumerable<int> ModifierVirtualKeys(IReadOnlyList<string> modifiers)
    {
        foreach (var modifier in modifiers)
        {
            switch (modifier)
            {
                case "ctrl":
                    yield return VK_CONTROL;
                    break;
                case "shift":
                    yield return VK_SHIFT;
                    break;
                case "alt":
                    yield return VK_MENU;
                    break;
            }
        }
    }

    /// <summary>
    /// The key events for one protocol key event: modifiers go down before the key and come up after it, so
    /// Ctrl+Z arrives as Ctrl down, Z down, and on key-up Z up, Ctrl up.
    /// </summary>
    internal static IReadOnlyList<(int VirtualKey, bool KeyUp)> KeySequence(
        string inputEvent,
        int virtualKey,
        IReadOnlyList<string> modifiers
    )
    {
        var modifierKeys = ModifierVirtualKeys(modifiers).ToArray();
        return inputEvent switch
        {
            "keyDown" => modifierKeys.Select(key => (key, false)).Append((virtualKey, false)).ToArray(),
            "keyUp" => new[] { (virtualKey, true) }.Concat(modifierKeys.Reverse().Select(key => (key, true))).ToArray(),
            _ => []
        };
    }

    /// <summary>
    /// Brings the target window forward and onto its monitor so real input lands on it.
    /// </summary>
    /// <remarks>
    /// Real input goes to whatever is under the guest cursor or has keyboard focus, so the window has to be
    /// in front. A window hanging off the edge of the guest display would also have clicks clamped to the
    /// screen edge, so one that fits is moved fully onto its monitor's work area; its position inside the
    /// guest is invisible on the Mac. A minimized window is restored, but a maximized one is left maximized.
    /// </remarks>
    public static bool PrepareTarget(IntPtr hwnd)
    {
        if (!IsWindow(hwnd))
        {
            return false;
        }

        if (IsIconic(hwnd))
        {
            ShowWindow(hwnd, SW_RESTORE);
        }

        KeepOnWorkArea(hwnd);
        BringToForeground(hwnd);
        return true;
    }

    /// <summary>
    /// Moves a window that reaches past its monitor's work area back inside it. Besides keeping input
    /// targets reachable, this keeps a mirrored window off the taskbar and the display edge, so the host
    /// can crop it from the guest framebuffer (<c>window.layout</c>'s <c>fullyVisible</c>).
    /// </summary>
    internal static void KeepOnWorkArea(IntPtr hwnd)
    {
        if (IsZoomed(hwnd) || !GetWindowRect(hwnd, out var rect))
        {
            return;
        }

        var monitorInfo = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), ref monitorInfo))
        {
            return;
        }

        var work = monitorInfo.Work;
        var (left, top) = PlaceWithin(
            rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top,
            work.Left, work.Top, work.Right - work.Left, work.Bottom - work.Top
        );
        if (left != rect.Left || top != rect.Top)
        {
            SetWindowPos(hwnd, IntPtr.Zero, left, top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
    }

    /// <summary>
    /// The top-left that keeps a window inside an area, or its current one when it already fits or is too
    /// large to fit, in which case the top-left stays visible.
    /// </summary>
    internal static (int Left, int Top) PlaceWithin(
        int left, int top, int width, int height,
        int areaLeft, int areaTop, int areaWidth, int areaHeight
    )
    {
        static int Fit(int start, int length, int areaStart, int areaLength) =>
            length > areaLength
                ? Math.Max(Math.Min(start, areaStart), areaStart)
                : Math.Clamp(start, areaStart, areaStart + areaLength - length);

        return (Fit(left, width, areaLeft, areaWidth), Fit(top, height, areaTop, areaHeight));
    }

    /// <summary>
    /// Windows refuses <c>SetForegroundWindow</c> from a process that did not receive the last input, which
    /// the agent never does. Attaching to the current foreground thread's input state lifts that for the call.
    /// </summary>
    private static void BringToForeground(IntPtr hwnd)
    {
        var foreground = GetForegroundWindow();
        if (foreground == hwnd)
        {
            return;
        }

        var currentThread = GetCurrentThreadId();
        var foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, out _);
        var attached = foregroundThread != 0
            && foregroundThread != currentThread
            && AttachThreadInput(currentThread, foregroundThread, true);
        try
        {
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached)
            {
                AttachThreadInput(currentThread, foregroundThread, false);
            }
        }
    }

    /// <param name="pointer">
    /// Where the cursor went, in the host tablet's absolute range. QEMU's USB tablet keeps reporting the last
    /// position it was given, which snaps the guest cursor back from wherever SendInput put it; the host
    /// moves the tablet to this position so the two agree.
    /// </param>
    public static bool SendMouse(IntPtr hwnd, WindowMouseInput input, out GuestPointerPosition? pointer)
    {
        pointer = null;
        if (MouseButtonFlags(input.Event) is not { } buttonFlags
            || WindowGeometry.Read(hwnd) is not { } geometry)
        {
            return false;
        }

        // Frames are captured from the visible frame's top-left in physical pixels, and the host maps
        // clicks into that same bitmap, so the visible frame is the right origin here.
        var screenX = geometry.Visible.X + input.X;
        var screenY = geometry.Visible.Y + input.Y;
        var virtualLeft = GetSystemMetrics(SM_XVIRTUALSCREEN);
        var virtualTop = GetSystemMetrics(SM_YVIRTUALSCREEN);
        var virtualWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        var virtualHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        var (x, y) = NormalizeToVirtualDesktop(screenX, screenY, virtualLeft, virtualTop, virtualWidth, virtualHeight);
        var (tabletX, tabletY) = NormalizeToVirtualDesktop(
            screenX, screenY, virtualLeft, virtualTop, virtualWidth, virtualHeight,
            GuestPointerPosition.MaximumAbsolute
        );

        var inputs = new List<NativeInput>();
        var modifierKeys = input.Event.EndsWith("Down", StringComparison.Ordinal)
            ? ModifierVirtualKeys(input.Modifiers).ToArray()
            : [];
        inputs.AddRange(modifierKeys.Select(key => KeyboardInput((ushort)key, 0, keyUp: false)));
        if (input.Event == "scroll")
        {
            // Trackpads send many small deltas; Windows accepts wheel amounts below one notch and scrolls
            // smoothly by them. A vertical and a horizontal component go as separate wheel events.
            var steps = ScrollSteps(input.DeltaX, input.DeltaY);
            for (var index = 0; index < steps.Count; index++)
            {
                var (flags, amount) = steps[index];
                inputs.Add(MouseEvent(x, y, (index == 0 ? MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK : 0) | flags, amount));
            }
        }
        else
        {
            inputs.Add(MouseEvent(x, y, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK | buttonFlags, 0));
        }
        inputs.AddRange(modifierKeys.Reverse().Select(key => KeyboardInput((ushort)key, 0, keyUp: true)));
        if (!Send(inputs))
        {
            return false;
        }
        pointer = new GuestPointerPosition(tabletX, tabletY);
        return true;
    }

    /// <summary>
    /// The wheel events for a scroll: vertical then horizontal, each only when non-zero, and one notch up when
    /// the host sent no amounts at all.
    /// </summary>
    internal static IReadOnlyList<(uint Flags, int Amount)> ScrollSteps(int deltaX, int deltaY)
    {
        if (deltaX == 0 && deltaY == 0)
        {
            return [(MOUSEEVENTF_WHEEL, WheelDelta)];
        }

        var steps = new List<(uint, int)>(2);
        if (deltaY != 0)
        {
            steps.Add((MOUSEEVENTF_WHEEL, deltaY));
        }
        if (deltaX != 0)
        {
            steps.Add((MOUSEEVENTF_HWHEEL, deltaX));
        }
        return steps;
    }

    private static NativeInput MouseEvent(int x, int y, uint flags, int wheelAmount) => new()
    {
        Type = INPUT_MOUSE,
        Union = new InputUnion
        {
            Mouse = new MouseInput
            {
                X = x,
                Y = y,
                MouseData = unchecked((uint)wheelAmount),
                Flags = flags
            }
        }
    };

    public static bool SendKey(WindowKeyInput input)
    {
        var sequence = KeySequence(input.Event, input.WindowsVirtualKey, input.Modifiers);
        return sequence.Count > 0
            && Send(sequence.Select(step => KeyboardInput((ushort)step.VirtualKey, 0, step.KeyUp)).ToList());
    }

    /// <summary>
    /// Committed text, including Hangul and anything outside the virtual-key map, typed as Unicode key events,
    /// one per UTF-16 code unit as Windows expects for surrogate pairs.
    /// </summary>
    public static bool SendText(string text)
    {
        var inputs = new List<NativeInput>(text.Length * 2);
        foreach (var codeUnit in text)
        {
            inputs.Add(KeyboardInput(0, codeUnit, keyUp: false, unicode: true));
            inputs.Add(KeyboardInput(0, codeUnit, keyUp: true, unicode: true));
        }
        return Send(inputs);
    }

    private static NativeInput KeyboardInput(ushort virtualKey, ushort scanCode, bool keyUp, bool unicode = false)
    {
        var flags = (keyUp ? KEYEVENTF_KEYUP : 0)
            | (unicode ? KEYEVENTF_UNICODE : 0)
            | (!unicode && IsExtendedKey(virtualKey) ? KEYEVENTF_EXTENDEDKEY : 0);
        return new NativeInput
        {
            Type = INPUT_KEYBOARD,
            Union = new InputUnion
            {
                Keyboard = new KeyboardInputData
                {
                    VirtualKey = virtualKey,
                    ScanCode = scanCode,
                    Flags = flags
                }
            }
        };
    }

    private static bool Send(List<NativeInput> inputs)
    {
        if (inputs.Count == 0)
        {
            return false;
        }

        var array = inputs.ToArray();
        var sent = SendInput((uint)array.Length, array, Marshal.SizeOf<NativeInput>());
        if (sent != array.Length)
        {
            Console.Error.WriteLine(
                $"SendInput delivered {sent} of {array.Length} events (error {Marshal.GetLastWin32Error()})."
            );
            return false;
        }
        return true;
    }

    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeInput
    {
        public uint Type;
        public InputUnion Union;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInputData Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    /// <remarks>
    /// Every field is blittable on purpose. With a <c>char</c> here the struct needed marshaling, and the
    /// marshaler copies each overlapping union member in turn, so this all-zero keyboard member was written
    /// over the mouse member and every mouse event reached Windows as a no-op that SendInput still counted
    /// as delivered.
    /// </remarks>
    [StructLayout(LayoutKind.Sequential)]
    internal struct KeyboardInputData
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private const int SW_RESTORE = 9;
    private const uint MONITOR_DEFAULTTONEAREST = 2;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint attach, uint attachTo, bool doAttach);

    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, NativeInput[] inputs, int size);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out NativeRect rect);
}
