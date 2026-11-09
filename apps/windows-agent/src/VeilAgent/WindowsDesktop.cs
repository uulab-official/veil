using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace Veil.Agent;

public sealed class WindowsDesktop : IWindowsDesktop
{
    private const uint WM_CLOSE = 0x0010;
    private const uint WM_KEYDOWN = 0x0100;
    private const uint WM_KEYUP = 0x0101;

    /// <summary>
    /// Matches the host-side bound. One message becomes one posted window message, so an unbounded
    /// payload would flood the target window's queue.
    /// </summary>
    internal const int MaxTextInputUtf16Length = 4096;
    private const uint CDS_FULLSCREEN = 0x00000004;
    private const int DISP_CHANGE_SUCCESSFUL = 0;
    private const int DISP_CHANGE_BADMODE = -2;
    private const int ENUM_CURRENT_SETTINGS = -1;
    private const uint DM_PELSWIDTH = 0x00080000;
    private const uint DM_PELSHEIGHT = 0x00100000;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_NOOWNERZORDER = 0x0200;
    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;
    private readonly object clipboardGate = new();
    private string? lastHostClipboardText;
    private int lastHostClipboardSequence;
    private string? lastHostClipboardImageSha256;

    public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken)
    {
        return LaunchAppAsync(
            new WindowsAppDescriptor(
                Id: "winapp_notepad",
                Name: "Notepad",
                Executable: "notepad.exe",
                Publisher: "Microsoft",
                IconId: "icon_notepad"
            ),
            cancellationToken
        );
    }

    public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
        LaunchAppCoreAsync(app, arguments: null, cancellationToken);

    public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
        LaunchAppCoreAsync(app, arguments: $"\"{filePath}\"", cancellationToken);

    /// <summary>
    /// Starts an app in the user's profile folder. Inheriting the agent's folder pinned it as the
    /// app's current directory, so an open Paint blocked tools updates from replacing that folder.
    /// </summary>
    internal static ProcessStartInfo AppStartInfo(WindowsAppDescriptor app, string? arguments) => new()
    {
        FileName = app.Executable,
        Arguments = arguments ?? string.Empty,
        UseShellExecute = true,
        WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    };

    private async Task<LaunchedWindow> LaunchAppCoreAsync(WindowsAppDescriptor app, string? arguments, CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        var existingWindowHandles = SnapshotAppWindowHandles(app);
        using var process = Process.Start(AppStartInfo(app, arguments))
            ?? throw new InvalidOperationException($"Could not start {app.Executable}.");

        var discoveryAttempts = (int)(app.WindowDiscoveryTimeout.TotalMilliseconds / 100);
        for (var attempt = 0; attempt < discoveryAttempts; attempt += 1)
        {
            cancellationToken.ThrowIfCancellationRequested();
            process.Refresh();

            if (process.MainWindowHandle != IntPtr.Zero)
            {
                return CreateLaunchedWindow(process.MainWindowHandle, process.Id, process.MainWindowTitle, app.Name);
            }

            if (TryFindTopLevelWindow(app, process.Id, existingWindowHandles, out var launched))
            {
                return launched;
            }

            await Task.Delay(100, cancellationToken);
        }

        throw new TimeoutException($"{app.Executable} started but no top-level window was discovered.");
    }

    public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds)
    {
        if (!OperatingSystem.IsWindows())
        {
            return Array.Empty<LaunchedWindow>();
        }

        var discovered = new List<LaunchedWindow>();
        EnumWindows((hwnd, unused) =>
        {
            if (!IsWindowVisible(hwnd))
            {
                return true;
            }

            if (knownWindowIds.Contains(FormatWindowId(hwnd)))
            {
                return true;
            }

            _ = GetWindowThreadProcessId(hwnd, out var windowProcessId);
            if (!DoesProcessMatchApp(windowProcessId, app))
            {
                return true;
            }

            discovered.Add(CreateLaunchedWindow(hwnd, (int)windowProcessId, GetWindowTitle(hwnd), app.Name));
            return true;
        }, IntPtr.Zero);

        return discovered;
    }

    /// <summary>
    /// Whether a previously tracked window still exists on the desktop -- used by
    /// <see cref="WindowDiscoveryStreamer"/> to prune windows the host was never told about closing
    /// (the user clicked the window's own close button rather than going through
    /// <c>window.close.request</c>). Pruning stale entries also prevents a subtle bug: Win32 reuses
    /// HWND values after a window is destroyed, and windowId is derived purely from the hwnd, so an
    /// un-pruned stale id would make a genuinely new window with a reused hwnd look "already known"
    /// and never get reported.
    /// </summary>
    public bool IsWindowStillOpen(string windowId)
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        return TryParseWindowId(windowId, out var hwnd) && IsWindow(hwnd);
    }

    private static string FormatWindowId(IntPtr hwnd) => $"hwnd:{hwnd.ToInt64():X8}";

    private static HashSet<IntPtr> SnapshotAppWindowHandles(WindowsAppDescriptor app)
    {
        var handles = new HashSet<IntPtr>();
        EnumWindows((hwnd, unused) =>
        {
            if (!IsWindowVisible(hwnd))
            {
                return true;
            }

            _ = GetWindowThreadProcessId(hwnd, out var windowProcessId);
            if (DoesProcessMatchApp(windowProcessId, app))
            {
                handles.Add(hwnd);
            }

            return true;
        }, IntPtr.Zero);

        return handles;
    }

    private static bool TryFindTopLevelWindow(
        WindowsAppDescriptor app,
        int launchedProcessId,
        HashSet<IntPtr> existingWindowHandles,
        out LaunchedWindow launched
    )
    {
        var candidates = new List<WindowCandidate>();
        EnumWindows((hwnd, unused) =>
        {
            if (!IsWindowVisible(hwnd))
            {
                return true;
            }

            _ = GetWindowThreadProcessId(hwnd, out var windowProcessId);
            var title = GetWindowTitle(hwnd);
            var matchesProcess = windowProcessId == launchedProcessId;
            var matchesExecutable = DoesProcessMatchApp(windowProcessId, app);
            var matchesTitle = !string.IsNullOrWhiteSpace(title)
                && title.Contains(app.Name, StringComparison.OrdinalIgnoreCase);

            if (matchesProcess || matchesExecutable || matchesTitle)
            {
                candidates.Add(new WindowCandidate(
                    Hwnd: hwnd,
                    ProcessId: (int)windowProcessId,
                    Title: title,
                    IsNewWindow: !existingWindowHandles.Contains(hwnd),
                    MatchesLaunchedProcess: matchesProcess,
                    MatchesExecutable: matchesExecutable,
                    MatchesTitle: matchesTitle
                ));
            }

            return true;
        }, IntPtr.Zero);

        var candidate = candidates
            .OrderByDescending(candidate => candidate.IsNewWindow)
            .ThenByDescending(candidate => candidate.MatchesLaunchedProcess)
            .ThenByDescending(candidate => candidate.MatchesExecutable)
            .ThenByDescending(candidate => candidate.MatchesTitle)
            .FirstOrDefault();

        if (candidate is null)
        {
            launched = null!;
            return false;
        }

        launched = CreateLaunchedWindow(candidate.Hwnd, candidate.ProcessId, candidate.Title, app.Name);
        return true;
    }

    internal static bool DoesProcessMatchApp(uint processId, WindowsAppDescriptor app)
    {
        try
        {
            using var process = Process.GetProcessById((int)processId);
            var candidateExecutables = (app.AlternateExecutables ?? [])
                .Append(app.Executable)
                .Select(Path.GetFileNameWithoutExtension);
            return candidateExecutables.Any(
                candidate => string.Equals(process.ProcessName, candidate, StringComparison.OrdinalIgnoreCase)
            );
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (Win32Exception)
        {
            return false;
        }
    }

    private static LaunchedWindow CreateLaunchedWindow(IntPtr hwnd, int processId, string? title, string fallbackTitle)
    {
        var resolvedTitle = string.IsNullOrWhiteSpace(title)
            ? fallbackTitle
            : title;

        var owner = GetWindow(hwnd, GW_OWNER);
        return new LaunchedWindow(
            WindowId: FormatWindowId(hwnd),
            Hwnd: hwnd,
            ProcessId: processId,
            Title: resolvedTitle,
            Bounds: GetWindowBounds(hwnd),
            State: "normal",
            Focused: true,
            IsPopup: IsPopup(GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64(), hasOwner: owner != IntPtr.Zero),
            OwnerWindowId: owner == IntPtr.Zero ? null : FormatWindowId(owner)
        );
    }

    /// <summary>
    /// An owned window with no title bar. Dialogs such as Save As keep theirs and stay ordinary windows, and
    /// an unowned window without one is an app's main window drawing its own title bar, like Paint's.
    /// </summary>
    internal static bool IsPopup(long style, bool hasOwner) => hasOwner && (style & WS_CAPTION) != WS_CAPTION;

    private const int GW_OWNER = 4;
    private const int GWL_STYLE = -16;
    private const long WS_CAPTION = 0x00C00000;

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

    private static string GetWindowTitle(IntPtr hwnd)
    {
        var length = GetWindowTextLength(hwnd);
        if (length <= 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(length + 1);
        _ = GetWindowText(hwnd, builder, builder.Capacity);
        return builder.ToString();
    }

    private static WindowRect GetWindowBounds(IntPtr hwnd)
    {
        if (GetWindowRect(hwnd, out var rect))
        {
            // GetWindowRect returns real physical pixels now that the process is Per-Monitor-V2 DPI
            // aware (see ProcessDpiAwareness), but window.created/window.updated's bounds are a
            // pre-existing wire contract the host's WindowsAppWindowPlacement sizing heuristics
            // already assume are ~96-DPI-equivalent "logical" units. Normalize by the window's real
            // scale here so bounds keeps reporting what it always has, decoupled from
            // GdiWindowFrameCapture's separate real-DPI-scale capture path.
            var scale = GdiWindowFrameCapture.GetWindowScale(hwnd);
            return new WindowRect(
                (int)Math.Round(rect.Left / scale),
                (int)Math.Round(rect.Top / scale),
                Math.Max(1, (int)Math.Round((rect.Right - rect.Left) / scale)),
                Math.Max(1, (int)Math.Round((rect.Bottom - rect.Top) / scale))
            );
        }

        return new WindowRect(0, 0, 1280, 800);
    }

    public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(windowId, out var hwnd))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(PostMessage(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero));
    }

    public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(windowId, out var hwnd))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(EnsureWindowReadyForInput(hwnd));
    }

    public Task<WindowRect?> ResizeWindowAsync(WindowResizeInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (input.Width < 320
            || input.Width > 8_192
            || input.Height < 320
            || input.Height > 8_192
            || (long)input.Width * input.Height > 32_000_000)
        {
            return Task.FromResult<WindowRect?>(null);
        }

        if (!TryParseWindowId(input.WindowId, out var hwnd)
            || !IsWindow(hwnd)
            || !GetWindowRect(hwnd, out var currentRect))
        {
            return Task.FromResult<WindowRect?>(null);
        }

        var scale = GdiWindowFrameCapture.GetWindowScale(hwnd);
        var physicalWidth = Math.Max(1, (int)Math.Round(input.Width * scale, MidpointRounding.AwayFromZero));
        var physicalHeight = Math.Max(1, (int)Math.Round(input.Height * scale, MidpointRounding.AwayFromZero));
        var accepted = SetWindowPos(
            hwnd,
            IntPtr.Zero,
            currentRect.Left,
            currentRect.Top,
            physicalWidth,
            physicalHeight,
            SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER
        );

        return Task.FromResult<WindowRect?>(accepted ? GetWindowBounds(hwnd) : null);
    }

    public Task<DisplayResizeResult?> ResizeDisplayAsync(DisplayResizeInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (input.Width < 640
            || input.Width > 3_840
            || input.Height < 640
            || input.Height > 3_840
            || (long)input.Width * input.Height > 8_294_400)
        {
            return Task.FromResult<DisplayResizeResult?>(null);
        }

        var mode = new NativeDevMode
        {
            dmSize = (ushort)Marshal.SizeOf<NativeDevMode>(),
            dmDeviceName = string.Empty,
            dmFormName = string.Empty
        };
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode))
        {
            return Task.FromResult<DisplayResizeResult?>(null);
        }

        mode.dmPelsWidth = (uint)input.Width;
        mode.dmPelsHeight = (uint)input.Height;
        mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;

        var result = ChangeDisplaySettingsEx(
            null,
            ref mode,
            IntPtr.Zero,
            CDS_FULLSCREEN,
            IntPtr.Zero
        );
        // The VirtIO GPU driver lists one custom size beside its fixed modes. QEMU normally sets it to
        // this size first; when it did not, replace it through the driver. Other adapters keep the
        // first answer.
        if (result == DISP_CHANGE_BADMODE && VirtioGpuDisplay.TrySetCustomMode(input.Width, input.Height))
        {
            result = ChangeDisplaySettingsEx(
                null,
                ref mode,
                IntPtr.Zero,
                CDS_FULLSCREEN,
                IntPtr.Zero
            );

            // Measured on viogpudo 0.1.302: while Windows runs on the custom mode, Windows keeps the
            // old custom size until another mode is committed, so going from one custom size to the
            // next needs one listed mode in between. The covering mode keeps windows from being
            // squeezed onto a smaller desktop during that step.
            if (result == DISP_CHANGE_BADMODE
                && TryFindListedModeCovering(input.Width, input.Height, out var listedMode))
            {
                ChangeDisplaySettingsEx(null, ref listedMode, IntPtr.Zero, CDS_FULLSCREEN, IntPtr.Zero);
                result = ChangeDisplaySettingsEx(
                    null,
                    ref mode,
                    IntPtr.Zero,
                    CDS_FULLSCREEN,
                    IntPtr.Zero
                );
            }
        }

        if (result != DISP_CHANGE_SUCCESSFUL)
        {
            return Task.FromResult<DisplayResizeResult?>(null);
        }

        return Task.FromResult<DisplayResizeResult?>(new DisplayResizeResult(input.Width, input.Height));
    }

    /// <summary>
    /// The smallest listed mode of the primary display that is at least <paramref name="width"/> x
    /// <paramref name="height"/>, or the largest listed mode when none covers it. Never the target itself.
    /// </summary>
    private static bool TryFindListedModeCovering(int width, int height, out NativeDevMode listedMode)
    {
        listedMode = default;
        NativeDevMode? covering = null;
        NativeDevMode? largest = null;
        var candidate = new NativeDevMode
        {
            dmSize = (ushort)Marshal.SizeOf<NativeDevMode>(),
            dmDeviceName = string.Empty,
            dmFormName = string.Empty
        };
        for (var index = 0; EnumDisplaySettings(null, index, ref candidate); index++)
        {
            var candidateWidth = (int)candidate.dmPelsWidth;
            var candidateHeight = (int)candidate.dmPelsHeight;
            var area = (long)candidateWidth * candidateHeight;
            if ((candidateWidth != width || candidateHeight != height)
                && candidateWidth <= 3_840
                && candidateHeight <= 3_840)
            {
                if (candidateWidth >= width
                    && candidateHeight >= height
                    && (covering is null || area < (long)covering.Value.dmPelsWidth * covering.Value.dmPelsHeight))
                {
                    covering = candidate;
                }

                if (largest is null || area > (long)largest.Value.dmPelsWidth * largest.Value.dmPelsHeight)
                {
                    largest = candidate;
                }
            }
        }

        var chosen = covering ?? largest;
        if (chosen is null)
        {
            return false;
        }

        listedMode = chosen.Value;
        listedMode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
        return true;
    }

    public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(input.WindowId, out var hwnd)
            || WindowsInputInjector.MouseButtonFlags(input.Event) is null)
        {
            return Task.FromResult(false);
        }

        if (!EnsureWindowReadyForInput(hwnd))
        {
            return Task.FromResult(false);
        }

        var applied = WindowsInputInjector.SendMouse(hwnd, input, out var pointer);
        if (applied)
        {
            LastInjectedPointer = pointer;
        }
        return Task.FromResult(applied);
    }

    public GuestPointerPosition? LastInjectedPointer { get; private set; }

    public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(input.WindowId, out var hwnd)
            || !TryResolveKeyMessage(input.Event, out var message))
        {
            return Task.FromResult(false);
        }

        if (!EnsureWindowReadyForInput(hwnd))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(WindowsInputInjector.SendKey(input));
    }

    public Task<bool> SendTextInputAsync(WindowTextInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        if (!TryParseWindowId(input.WindowId, out var hwnd) || input.Text.Length == 0)
        {
            return Task.FromResult(false);
        }

        if (input.Text.Length > MaxTextInputUtf16Length)
        {
            return Task.FromResult(false);
        }

        if (!EnsureWindowReadyForInput(hwnd))
        {
            return Task.FromResult(false);
        }

        return Task.FromResult(WindowsInputInjector.SendText(input.Text));
    }

    public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(() =>
        {
            SetClipboardUnicodeText(text);
            lock (clipboardGate)
            {
                lastHostClipboardText = text;
                lastHostClipboardSequence += 1;
            }
        }, cancellationToken);
    }

    public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(GetClipboardUnicodeText, cancellationToken);
    }

    public bool TryConsumeHostClipboardEcho(string text)
    {
        lock (clipboardGate)
        {
            if (lastHostClipboardSequence <= 0 || lastHostClipboardText != text)
            {
                return false;
            }

            lastHostClipboardText = null;
            return true;
        }
    }

    public uint GetClipboardSequenceNumber() =>
        OperatingSystem.IsWindows() ? WindowsClipboardFormats.SequenceNumber() : 0;

    public Task<byte[]?> GetClipboardImagePngAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(WindowsClipboardFormats.ReadImagePng, cancellationToken);
    }

    public Task SetClipboardImagePngAsync(byte[] png, string sha256, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(() =>
        {
            // Recorded before the write: the clipboard watcher runs concurrently and could otherwise read the
            // new image before its hash is known and broadcast it back to the host as a guest copy.
            lock (clipboardGate)
            {
                lastHostClipboardImageSha256 = sha256;
            }

            try
            {
                WindowsClipboardFormats.WriteImage(png);
            }
            catch
            {
                lock (clipboardGate)
                {
                    lastHostClipboardImageSha256 = null;
                }

                throw;
            }
        }, cancellationToken);
    }

    public bool TryConsumeHostClipboardImageEcho(string sha256)
    {
        lock (clipboardGate)
        {
            if (lastHostClipboardImageSha256 != sha256)
            {
                return false;
            }

            lastHostClipboardImageSha256 = null;
            return true;
        }
    }

    public Task SetClipboardFilesAsync(IReadOnlyList<string> fullPaths, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("The Veil Windows agent must run inside Windows.");
        }

        return Task.Run(() => WindowsClipboardFormats.WriteFileDrop(fullPaths), cancellationToken);
    }

    private static bool TryParseWindowId(string windowId, out IntPtr hwnd)
    {
        hwnd = IntPtr.Zero;
        const string prefix = "hwnd:";

        if (!windowId.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var hex = windowId[prefix.Length..];
        if (!long.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var value))
        {
            return false;
        }

        hwnd = new IntPtr(value);
        return hwnd != IntPtr.Zero;
    }



    private static bool TryResolveKeyMessage(string eventName, out uint message)
    {
        message = eventName switch
        {
            "keyDown" => WM_KEYDOWN,
            "keyUp" => WM_KEYUP,
            _ => 0
        };

        return message != 0;
    }

    private static bool EnsureWindowReadyForInput(IntPtr hwnd)
    {
        return WindowsInputInjector.PrepareTarget(hwnd);
    }


    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out NativeRect lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        uint flags
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumDisplaySettings(
        string? lpszDeviceName,
        int modeNum,
        ref NativeDevMode devMode
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int ChangeDisplaySettingsEx(
        string? lpszDeviceName,
        ref NativeDevMode devMode,
        IntPtr hwnd,
        uint dwflags,
        IntPtr lParam
    );

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeDevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    private static void SetClipboardUnicodeText(string text)
    {
        OpenClipboardWithRetry();
        IntPtr handle = IntPtr.Zero;
        try
        {
            if (!EmptyClipboard())
            {
                ThrowLastWin32Error("EmptyClipboard failed.");
            }

            var bytes = Encoding.Unicode.GetBytes(text + "\0");
            handle = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes.Length);
            if (handle == IntPtr.Zero)
            {
                ThrowLastWin32Error("GlobalAlloc failed for clipboard text.");
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                ThrowLastWin32Error("GlobalLock failed for clipboard text.");
            }

            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }

            if (SetClipboardData(CF_UNICODETEXT, handle) == IntPtr.Zero)
            {
                ThrowLastWin32Error("SetClipboardData failed for clipboard text.");
            }

            handle = IntPtr.Zero;
        }
        finally
        {
            CloseClipboard();
            if (handle != IntPtr.Zero)
            {
                _ = GlobalFree(handle);
            }
        }
    }

    private static string? GetClipboardUnicodeText()
    {
        OpenClipboardWithRetry();
        try
        {
            if (!IsClipboardFormatAvailable(CF_UNICODETEXT))
            {
                return null;
            }

            var handle = GetClipboardData(CF_UNICODETEXT);
            if (handle == IntPtr.Zero)
            {
                return null;
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                return Marshal.PtrToStringUni(pointer);
            }
            finally
            {
                _ = GlobalUnlock(handle);
            }
        }
        finally
        {
            CloseClipboard();
        }
    }

    private static void OpenClipboardWithRetry()
    {
        for (var attempt = 0; attempt < 10; attempt += 1)
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                return;
            }

            Thread.Sleep(25);
        }

        ThrowLastWin32Error("OpenClipboard failed.");
    }

    private static void ThrowLastWin32Error(string message)
    {
        throw new Win32Exception(Marshal.GetLastWin32Error(), message);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsClipboardFormatAvailable(uint format);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private sealed record WindowCandidate(
        IntPtr Hwnd,
        int ProcessId,
        string Title,
        bool IsNewWindow,
        bool MatchesLaunchedProcess,
        bool MatchesExecutable,
        bool MatchesTitle
    );
}
