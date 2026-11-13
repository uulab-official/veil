using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class AgentSession
{
    private static readonly TimeSpan InitialFrameCaptureTimeout = TimeSpan.FromSeconds(2);
    private const int MaxDroppedFileBytes = 50 * 1024 * 1024;
    private static readonly TimeSpan DroppedFileCleanupDelay = TimeSpan.FromMinutes(5);
    /// <summary>
    /// How long <c>app.list</c> waits for the first Start menu discovery. Listing the packages can take
    /// several seconds, and the Mac shows its launcher list from this reply.
    /// </summary>
    internal static readonly TimeSpan AppListCatalogWait = TimeSpan.FromSeconds(2);

    /// <summary>
    /// How long <c>app.launch</c> waits for the first Start menu discovery. The host can ask for a Start menu
    /// id it remembers from before the agent restarted, and the user is waiting for that app to open.
    /// </summary>
    internal static readonly TimeSpan AppLaunchCatalogWait = TimeSpan.FromSeconds(10);

    // Listed first, before the Start menu entries, with the ids hosts and Mac launchers already use.
    private static readonly IReadOnlyList<WindowsAppDescriptor> AppCatalog = new[]
    {
        new WindowsAppDescriptor(
            Id: "winapp_notepad",
            Name: "Notepad",
            Executable: "notepad.exe",
            Publisher: "Microsoft",
            IconId: "icon_notepad",
            AppUserModelId: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"
        ),
        new WindowsAppDescriptor(
            Id: "winapp_calculator",
            Name: "Calculator",
            Executable: "calc.exe",
            Publisher: "Microsoft",
            IconId: "icon_calculator",
            // Windows 11 ships calc.exe as a launcher stub for the packaged Calculator app; the
            // top-level window that actually appears belongs to CalculatorApp.exe, a different
            // process than the one Process.Start("calc.exe") returns.
            AlternateExecutables: ["CalculatorApp"],
            // The packaged Calculator app's cold activation can take noticeably longer than the
            // default 5-second discovery budget used by native Win32 apps like Notepad and Paint.
            WindowDiscoveryTimeoutOverride: TimeSpan.FromSeconds(12),
            AppUserModelId: "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App"
        ),
        new WindowsAppDescriptor(
            Id: "winapp_paint",
            Name: "Paint",
            Executable: "mspaint.exe",
            Publisher: "Microsoft",
            IconId: "icon_paint",
            AppUserModelId: "Microsoft.Paint_8wekyb3d8bbwe!App"
        ),
        // The Start menu's File Explorer shortcut names a shell folder, not a program, so the Start menu
        // discovery cannot list it. explorer.exe opens a new window in the shell's own process.
        new WindowsAppDescriptor(
            Id: "winapp_explorer",
            Name: "File Explorer",
            Executable: "explorer.exe",
            Publisher: "Microsoft",
            IconId: "icon_explorer",
            AppUserModelId: "Microsoft.Windows.Explorer"
        )
    };

    private readonly IWindowsDesktop desktop;
    private readonly IWindowFrameCapture capture;
    private readonly IPackageIdentityProbe packageIdentityProbe;
    private readonly ISparsePackageStatusProbe sparsePackageStatusProbe;
    private readonly IWindowsNotificationAccessProbe notificationAccessProbe;
    private readonly IWindowsSharedFolderProbe sharedFolderProbe;
    private readonly IGuestShutdown guestShutdown;
    private readonly DisplayScaleManager displayScale;
    private readonly GuestTimeSync timeSync;
    private readonly GuestAppearanceSync appearanceSync;
    private readonly GuestVisualEffects visualEffects;
    private readonly Action<string> imeModeSink;
    private readonly HostFolderMount hostFolderMount;
    private readonly ToolsUpdate toolsUpdate;
    private readonly IStartMenuCatalogSource startMenu;
    private readonly Dictionary<string, LaunchedWindow> trackedWindowsById = new();
    private readonly Dictionary<string, WindowsAppDescriptor> appByWindowId = new();
    private readonly ConcurrentDictionary<string, SemaphoreSlim> appLaunchGates = new();
    // Apps known only from a window found on the desktop, by id, so app.list and app.launch can find them.
    private readonly ConcurrentDictionary<string, WindowsAppDescriptor> runningApps = new(StringComparer.Ordinal);
    private int launchesInFlight;
    private readonly object trackedWindowsGate = new();

    public AgentSession(
        IWindowsDesktop desktop,
        IWindowFrameCapture capture,
        IPackageIdentityProbe? packageIdentityProbe = null,
        ISparsePackageStatusProbe? sparsePackageStatusProbe = null,
        IWindowsNotificationAccessProbe? notificationAccessProbe = null,
        IWindowsSharedFolderProbe? sharedFolderProbe = null,
        IGuestShutdown? guestShutdown = null,
        DisplayScaleManager? displayScale = null,
        GuestTimeSync? timeSync = null,
        GuestAppearanceSync? appearanceSync = null,
        GuestVisualEffects? visualEffects = null,
        Action<string>? imeModeSink = null,
        HostFolderMount? hostFolderMount = null,
        IStartMenuCatalogSource? startMenu = null,
        ToolsUpdate? toolsUpdate = null
    )
    {
        this.desktop = desktop;
        this.capture = capture;
        this.packageIdentityProbe = packageIdentityProbe ?? new WindowsPackageIdentityProbe();
        this.sparsePackageStatusProbe = sparsePackageStatusProbe ?? new SparsePackageStatusProbe();
        this.notificationAccessProbe = notificationAccessProbe ?? new WindowsNotificationAccessProbe();
        this.sharedFolderProbe = sharedFolderProbe ?? new SharedFolderProbe();
        this.guestShutdown = guestShutdown ?? new WindowsGuestShutdown();
        this.displayScale = displayScale
            ?? new DisplayScaleManager(new WindowsDisplayScaleBackend(), new UserDisplayScaleFile());
        this.timeSync = timeSync ?? new GuestTimeSync();
        this.appearanceSync = appearanceSync ?? new GuestAppearanceSync();
        this.visualEffects = visualEffects ?? new GuestVisualEffects();
        this.imeModeSink = imeModeSink ?? GuestImeMode.Set;
        this.hostFolderMount = hostFolderMount ?? new HostFolderMount();
        this.toolsUpdate = toolsUpdate ?? new ToolsUpdate();
        this.startMenu = startMenu ?? new StartMenuCatalog();
    }

    /// <summary>
    /// Told the window id of every input, resize, or focus request before it is applied, so that window's
    /// frame stream can leave its idle cadence and show the result on the next fast tick.
    /// </summary>
    public Action<string>? WindowActivity { get; set; }

    private static readonly HashSet<string> WindowActivityMessageTypes =
    [
        MessageTypes.InputMouse,
        MessageTypes.InputKey,
        MessageTypes.InputText,
        MessageTypes.WindowResizeRequest,
        MessageTypes.WindowFocusRequest
    ];

    public async Task<AgentReplies> HandleAsync(JsonObject request, CancellationToken cancellationToken = default)
    {
        var type = request["type"]?.GetValue<string>();
        var requestId = request["requestId"]?.GetValue<string>();
        if (type is not null
            && WindowActivityMessageTypes.Contains(type)
            && request["windowId"]?.GetValue<string>() is { Length: > 0 } activeWindowId)
        {
            WindowActivity?.Invoke(activeWindowId);
        }

        try
        {
            return type switch
            {
                MessageTypes.AgentHealthRequest => AgentReplies.Direct(HealthResponse(requestId)),
                MessageTypes.AppListRequest => AgentReplies.Direct(await AppListResponseAsync(requestId, cancellationToken)),
                MessageTypes.AppLaunchRequest => await WhileLaunchingAsync(
                    () => HandleAppLaunchAsync(request, requestId, cancellationToken)),
                MessageTypes.FileOpenRequest => await WhileLaunchingAsync(
                    () => HandleFileOpenAsync(request, requestId, cancellationToken)),
                MessageTypes.SharedFileOpenRequest => await WhileLaunchingAsync(
                    () => HandleSharedFileOpenAsync(request, requestId, cancellationToken)),
                MessageTypes.WindowListRequest => await HandleWindowListAsync(requestId, cancellationToken),
                MessageTypes.WindowFrameSubscribe => HandleWindowFrameSubscribeAsync(request, requestId),
                MessageTypes.WindowFrameUnsubscribe => HandleWindowFrameUnsubscribeAsync(request, requestId),
                MessageTypes.WindowFocusRequest => await HandleWindowFocusAsync(request, requestId, cancellationToken),
                MessageTypes.WindowCloseRequest => await HandleWindowCloseAsync(request, requestId, cancellationToken),
                MessageTypes.WindowResizeRequest => await HandleWindowResizeAsync(request, requestId, cancellationToken),
                MessageTypes.DisplayResizeRequest => await HandleDisplayResizeAsync(request, requestId, cancellationToken),
                MessageTypes.DisplayScaleRequest => HandleDisplayScale(request, requestId),
                MessageTypes.SystemShutdownRequest => HandleSystemShutdown(requestId),
                MessageTypes.FrameCaptureStrategySet => HandleFrameCaptureStrategySet(request, requestId),
                MessageTypes.WindowCropSet => HandleWindowCropSet(request, requestId),
                MessageTypes.WindowMoveRequest => HandleWindowMove(request, requestId),
                MessageTypes.InputMouse => await HandleMouseInputAsync(request, requestId, cancellationToken),
                MessageTypes.InputKey => await HandleKeyInputAsync(request, requestId, cancellationToken),
                MessageTypes.InputText => await HandleTextInputAsync(request, requestId, cancellationToken),
                MessageTypes.InputImeSet => HandleImeSet(request, requestId),
                MessageTypes.ClipboardTextSet => await HandleClipboardTextSetAsync(request, requestId, cancellationToken),
                MessageTypes.ClipboardImageSet => await HandleClipboardImageSetAsync(request, requestId, cancellationToken),
                MessageTypes.ClipboardFilesSet => await HandleClipboardFilesSetAsync(request, requestId, cancellationToken),
                MessageTypes.NotificationListenerRequest => await HandleNotificationListenerRequestAsync(requestId, cancellationToken),
                MessageTypes.SharedFolderRequest => await HandleSharedFolderRequestAsync(request, requestId, cancellationToken),
                MessageTypes.TimeSyncRequest => HandleTimeSyncRequest(request, requestId),
                MessageTypes.AppearanceSetRequest => HandleAppearanceSetRequest(request, requestId),
                MessageTypes.VisualEffectsSetRequest => HandleVisualEffectsSetRequest(request, requestId),
                MessageTypes.ToolsUpdateRequest => HandleToolsUpdate(requestId),
                MessageTypes.HostFolderMountRequest => HandleHostFolderMount(request, requestId),
                MessageTypes.HostFolderUnmountRequest => HandleHostFolderUnmount(request, requestId),
                _ => AgentReplies.Direct(ErrorResponse(requestId, "unknown_message_type", $"Unsupported message type {type}"))
            };
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "handler_failed", error.Message));
        }
    }

    /// <summary>
    /// Starts the tools update from the disc the host inserted. The request carries nothing to run; see
    /// <see cref="ToolsUpdate"/>. Answers before the script stops this agent.
    /// </summary>
    private AgentReplies HandleToolsUpdate(string? requestId)
    {
        var result = toolsUpdate.Run();
        // In the agent's log, since the script that follows stops this process.
        Console.Error.WriteLine(result.Started
            ? $"ToolsUpdate: started {result.EntryPoint}."
            : $"ToolsUpdate: not started. {result.ErrorCode}: {result.Message}");
        if (!result.Started)
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                result.ErrorCode ?? "tools_update_failed",
                result.Message ?? "The tools update could not be started."
            ));
        }

        return AgentReplies.Direct(new JsonObject
        {
            ["type"] = MessageTypes.ToolsUpdateResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["accepted"] = true,
            ["entryPoint"] = result.EntryPoint
        });
    }

    private async Task<AgentReplies> WhileLaunchingAsync(Func<Task<AgentReplies>> launch)
    {
        Interlocked.Increment(ref launchesInFlight);
        try
        {
            return await launch();
        }
        finally
        {
            Interlocked.Decrement(ref launchesInFlight);
        }
    }

    /// <summary>
    /// Announces every app window on the desktop to a host that has just connected: it tracks the windows
    /// nothing has reported yet, then answers with a <c>window.created</c> for each tracked window. Windows
    /// come before the popups they own.
    /// </summary>
    private async Task<AgentReplies> HandleWindowListAsync(string? requestId, CancellationToken cancellationToken)
    {
        if (!IsLaunching)
        {
            foreach (var found in desktop.DiscoverAppWindows(SnapshotTrackedWindowIds()))
            {
                var app = await AppForDiscoveredWindowAsync(found, cancellationToken);
                _ = TryTrackDiscoveredWindow(app, found.Window);
            }
        }

        List<(WindowsAppDescriptor App, LaunchedWindow Window)> tracked;
        lock (trackedWindowsGate)
        {
            tracked = trackedWindowsById.Values
                .Where(window => appByWindowId.ContainsKey(window.WindowId))
                .Select(window => (appByWindowId[window.WindowId], window))
                .ToList();
        }

        // A window that closed since the last discovery pass would get a Mac window with nothing to show.
        var open = tracked
            .Where(pair => desktop.IsWindowStillOpen(pair.Window.WindowId))
            .Select(pair => (pair.App, Window: desktop.CurrentWindow(pair.Window)))
            .OrderBy(pair => pair.Window.IsPopup)
            .ToList();
        var replies = new List<JsonObject>
        {
            new()
            {
                ["type"] = MessageTypes.WindowListResponse,
                ["requestId"] = requestId,
                ["windowIds"] = new JsonArray(open.Select(pair => (JsonNode?)pair.Window.WindowId).ToArray())
            }
        };
        replies.AddRange(open.Select(pair => WindowCreatedEvent(pair.App, pair.Window)));
        return new AgentReplies(replies, Array.Empty<JsonObject>());
    }

    private async Task<AgentReplies> HandleAppLaunchAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var appId = request["appId"]?.GetValue<string>();
        var app = await FindLaunchableAppAsync(appId, cancellationToken);
        if (app is null)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "app_not_found", $"No app exists for id {appId}"));
        }

        var reuseExistingWindow = request["reuseExistingWindow"]?.GetValue<bool>() ?? false;
        var launchGate = appLaunchGates.GetOrAdd(app.Id, _ => new SemaphoreSlim(1, 1));
        LaunchedWindow launched;
        IReadOnlyList<LaunchedWindow> openPopups = [];
        await launchGate.WaitAsync(cancellationToken);
        try
        {
            try
            {
                var existingWindows = reuseExistingWindow
                    ? desktop.DiscoverAdditionalWindows(app, new HashSet<string>())
                    : Array.Empty<LaunchedWindow>();
                if (existingWindows.Count > 0)
                {
                    // An app-first open or reconnect attaches to an existing guest window instead
                    // of opening another instance. Track every matching HWND quietly so discovery
                    // cannot turn old windows into duplicate macOS mirrors after the request.
                    TrackWindows(app, existingWindows);
                    launched = PrimaryWindow(existingWindows);
                    // Popups already open, such as Paint's text formatting bar, belong on the app window the host
                    // is about to show; tracked quietly they would never appear until reopened.
                    openPopups = existingWindows
                        .Where(window => window.IsPopup && window.WindowId != launched.WindowId)
                        .ToArray();
                }
                else
                {
                    launched = await desktop.LaunchAppAsync(app, cancellationToken);
                    TrackWindow(app, launched);
                }
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                return AgentReplies.Direct(ErrorResponse(requestId, "app_launch_failed", error.Message));
            }
        }
        finally
        {
            launchGate.Release();
        }

        var frame = await CaptureInitialFrameOrNilAsync(launched, cancellationToken);

        return new AgentReplies(
            DirectReplies: new List<JsonObject>
            {
                LaunchResponse(requestId, launched.ProcessId),
                WindowCreatedEvent(app, launched)
            },
            BroadcastEvents: (frame is null ? Array.Empty<JsonObject>() : [WindowFrameEvent(frame)])
                .Concat(openPopups.Select(popup => WindowCreatedEvent(app, popup)))
                .ToArray(),
            StreamWindow: launched,
            NextFrameSequence: frame is null ? 1 : 2
        );
    }

    /// <summary>
    /// The window that stands for the app when attaching to one already open: never a popup such as Paint's
    /// text formatting bar, which sits above the app window in z-order. Every discovered window reports
    /// itself focused, so focus alone picked whichever window was on top.
    /// </summary>
    internal static LaunchedWindow PrimaryWindow(IReadOnlyList<LaunchedWindow> windows) =>
        windows.FirstOrDefault(window => !window.IsPopup && window.Focused)
            ?? windows.FirstOrDefault(window => !window.IsPopup)
            ?? windows[0];

    private async Task<AgentReplies> HandleFileOpenAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var appId = request["appId"]?.GetValue<string>();
        var app = AppCatalog.FirstOrDefault(candidate => candidate.Id == appId);
        if (app is null)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "app_not_found", $"No app exists for id {appId}"));
        }

        var fileName = request["fileName"]?.GetValue<string>();
        if (!TryResolveSafeFileName(fileName, out var safeFileName))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_file_name",
                "fileName must be a non-empty file name with no path separators or traversal."
            ));
        }

        var contentBase64 = request["contentBase64"]?.GetValue<string>();
        byte[] fileBytes;
        try
        {
            fileBytes = Convert.FromBase64String(contentBase64 ?? string.Empty);
        }
        catch (FormatException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "file_decode_failed", "contentBase64 was not valid base64."));
        }

        if (fileBytes.Length == 0)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "file_decode_failed", "Decoded file content was empty."));
        }

        if (fileBytes.Length > MaxDroppedFileBytes)
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "file_too_large",
                $"File exceeds the {MaxDroppedFileBytes} byte limit for drag-and-drop."
            ));
        }

        string filePath;
        try
        {
            filePath = WriteDroppedFile(safeFileName, fileBytes);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "file_write_failed", error.Message));
        }

        LaunchedWindow launched;
        try
        {
            launched = await desktop.LaunchAppWithFileAsync(app, filePath, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "file_open_failed", error.Message));
        }

        TrackWindow(app, launched);
        var frame = await CaptureInitialFrameOrNilAsync(launched, cancellationToken);

        return new AgentReplies(
            DirectReplies: new List<JsonObject>
            {
                FileOpenResponse(requestId, accepted: true, launched.ProcessId),
                WindowCreatedEvent(app, launched)
            },
            BroadcastEvents: frame is null ? Array.Empty<JsonObject>() : [WindowFrameEvent(frame)],
            StreamWindow: launched,
            NextFrameSequence: frame is null ? 1 : 2
        );
    }

    private async Task<AgentReplies> HandleSharedFileOpenAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var appId = request["appId"]?.GetValue<string>();
        var app = AppCatalog.FirstOrDefault(candidate => candidate.Id == appId);
        if (app is null)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "app_not_found", $"No app exists for id {appId}"));
        }

        var fileName = request["fileName"]?.GetValue<string>();
        if (!TryResolveSafeFileName(fileName, out var safeFileName))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_file_name",
                "fileName must be a non-empty file name with no path separators or traversal."
            ));
        }

        var guestPath = request["guestPath"]?.GetValue<string>();
        if (!TryResolveSharedFilePath(guestPath, safeFileName, out var resolvedPath))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_shared_file_path",
                $"guestPath must point to {SharedFolderProbe.DefaultGuestDirectoryPath} and match fileName."
            ));
        }

        if (!File.Exists(resolvedPath))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "shared_file_missing",
                "The file is not present in the shared folder. Copy it again and retry."
            ));
        }

        LaunchedWindow launched;
        try
        {
            launched = await desktop.LaunchAppWithFileAsync(app, resolvedPath, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "file_open_failed", error.Message));
        }

        TrackWindow(app, launched);
        var frame = await CaptureInitialFrameOrNilAsync(launched, cancellationToken);

        return new AgentReplies(
            DirectReplies: new List<JsonObject>
            {
                FileOpenResponse(requestId, accepted: true, launched.ProcessId),
                WindowCreatedEvent(app, launched)
            },
            BroadcastEvents: frame is null ? Array.Empty<JsonObject>() : [WindowFrameEvent(frame)],
            StreamWindow: launched,
            NextFrameSequence: frame is null ? 1 : 2
        );
    }

    /// <summary>
    /// Only a bare file name is accepted -- no directory separators, no parent-directory traversal.
    /// The host must never be able to steer where inside the guest filesystem a dropped file ends up
    /// beyond the fixed, agent-controlled drop directory <see cref="WriteDroppedFile"/> writes into.
    /// </summary>
    // Windows reserves these names for device files regardless of extension -- "CON.txt" still
    // resolves to the CON device, not a regular file. Path.GetInvalidFileNameChars() does not catch
    // this, so it needs its own check.
    private static readonly HashSet<string> ReservedWindowsDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    private static bool TryResolveSafeFileName(string? fileName, out string safeFileName)
    {
        safeFileName = string.Empty;
        if (string.IsNullOrWhiteSpace(fileName))
        {
            return false;
        }

        var candidate = fileName.Trim();
        if (candidate.IndexOfAny(['\\', '/']) >= 0 || candidate == "." || candidate == "..")
        {
            return false;
        }

        if (candidate.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
        {
            return false;
        }

        if (ReservedWindowsDeviceNames.Contains(Path.GetFileNameWithoutExtension(candidate)))
        {
            return false;
        }

        safeFileName = candidate;
        return true;
    }

    private static bool TryResolveSharedFilePath(
        string? guestPath,
        string safeFileName,
        out string resolvedPath
    )
    {
        resolvedPath = string.Empty;
        if (string.IsNullOrWhiteSpace(guestPath)
            || guestPath.Contains("..", StringComparison.Ordinal)
            || guestPath.Contains('/', StringComparison.Ordinal))
        {
            return false;
        }

        // Keep this comparison in Windows path syntax even when the agent's unit tests run on macOS.
        // `Path.GetFullPath` follows the host OS rules and would treat `C:\VeilShared\...` as a
        // relative Unix path, accidentally making a valid guest path fail before the live guest sees it.
        var root = SharedFolderProbe.DefaultGuestDirectoryPath.TrimEnd('\\') + "\\";
        var candidate = guestPath.Trim();
        var lastSeparator = candidate.LastIndexOf('\\');
        var candidateFileName = lastSeparator >= 0 ? candidate[(lastSeparator + 1)..] : string.Empty;
        if (!candidate.StartsWith(root, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(candidateFileName, safeFileName, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        resolvedPath = candidate;
        return true;
    }

    private static string WriteDroppedFile(string fileName, byte[] content)
    {
        var dropDirectory = Path.Combine(Path.GetTempPath(), "VeilDroppedFiles", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dropDirectory);
        var filePath = Path.Combine(dropDirectory, fileName);
        File.WriteAllBytes(filePath, content);
        ScheduleDropDirectoryCleanup(dropDirectory);
        return filePath;
    }

    /// <summary>
    /// Dropped files are never referenced again once the launched app has opened them, so leaving
    /// them in place forever would let repeated drag-and-drop use slowly fill the guest's disk with
    /// orphaned copies (up to <see cref="MaxDroppedFileBytes"/> each). Deletes the per-request drop
    /// directory after a delay long enough for the launched app to have read the file, regardless of
    /// whether the launch itself succeeds.
    /// </summary>
    private static void ScheduleDropDirectoryCleanup(string dropDirectory)
    {
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(DroppedFileCleanupDelay);
                Directory.Delete(dropDirectory, recursive: true);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                Console.Error.WriteLine(
                    $"AgentSession: failed to clean up dropped file directory {dropDirectory}. {error.GetType().Name}: {error.Message}"
                );
            }
        });
    }

    private async Task<WindowFrame?> CaptureInitialFrameOrNilAsync(
        LaunchedWindow launched,
        CancellationToken cancellationToken
    )
    {
        try
        {
            return await capture
                .CaptureFrameAsync(launched, sequence: 1, cancellationToken)
                .WaitAsync(InitialFrameCaptureTimeout, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"Initial frame capture failed for {launched.WindowId}; waiting for the live frame stream. {error.GetType().Name}: {error.Message}"
            );
            return null;
        }
    }

    private AgentReplies HandleWindowFrameSubscribeAsync(JsonObject request, string? requestId)
    {
        var windowId = request["windowId"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "window.frame.subscribe requires windowId."));
        }

        if (!TryGetTrackedWindow(windowId, out var window))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_not_tracked", $"No tracked window exists for id {windowId}."));
        }

        // A host that can decode them asks for deflated BGRA tiles; any other value, or none, keeps PNG.
        capture.SetTileFormat(
            windowId,
            request["tileFormat"]?.GetValue<string>() == FrameChannelCodec.BgraDeflateFormatName
                ? FrameChannelCodec.BgraDeflateFormat
                : FrameChannelCodec.PngFormat
        );

        return new AgentReplies(
            // The ack is a direct reply so a host that waits for exactly one frame reads it before
            // the stream's first frame arrives on the broadcast side.
            DirectReplies: new[] { OperationAck(requestId) },
            BroadcastEvents: Array.Empty<JsonObject>(),
            StreamWindow: window,
            NextFrameSequence: 1
        );
    }

    private AgentReplies HandleWindowFrameUnsubscribeAsync(JsonObject request, string? requestId)
    {
        var windowId = request["windowId"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "window.frame.unsubscribe requires windowId."));
        }

        return new AgentReplies(
            DirectReplies: new[] { OperationAck(requestId) },
            BroadcastEvents: Array.Empty<JsonObject>(),
            StopStreamWindowId: windowId
        );
    }

    private async Task<AgentReplies> HandleWindowFocusAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var windowId = request["windowId"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "window.focus.request requires windowId."));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(WindowFocusResponse(requestId, windowId, accepted: false));
        }

        try
        {
            var accepted = await desktop.FocusWindowAsync(windowId, cancellationToken);
            return AgentReplies.Direct(WindowFocusResponse(requestId, windowId, accepted));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_focus_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleWindowCloseAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var windowId = request["windowId"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "window.close.request requires windowId."));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(WindowCloseResponse(requestId, windowId, accepted: false));
        }

        try
        {
            var accepted = await desktop.CloseWindowAsync(windowId, cancellationToken);
            if (!accepted)
            {
                return AgentReplies.Direct(WindowCloseResponse(requestId, windowId, accepted));
            }

            UntrackWindow(windowId);
            return new AgentReplies(
                DirectReplies: new[] { WindowCloseResponse(requestId, windowId, accepted) },
                BroadcastEvents: new[] { WindowClosedEvent(windowId) },
                StopStreamWindowId: windowId
            );
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_close_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleWindowResizeAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var windowId = request["windowId"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId)
            || !TryReadInt(request, "width", out var width)
            || !TryReadInt(request, "height", out var height)
            || !IsPlausibleResize(width, height))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_message",
                "window.resize.request requires a tracked window and a size between 320 and 8192 pixels with at most 32000000 pixels."
            ));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(WindowResizeResponse(requestId, windowId, bounds: null));
        }

        try
        {
            var bounds = await desktop.ResizeWindowAsync(
                new WindowResizeInput(windowId, width, height),
                cancellationToken
            );
            return AgentReplies.Direct(WindowResizeResponse(requestId, windowId, bounds));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_resize_failed", error.Message));
        }
    }

    private AgentReplies HandleSystemShutdown(string? requestId)
    {
        var response = new JsonObject
        {
            ["type"] = MessageTypes.SystemShutdownResponse,
            ["requestId"] = requestId
        };
        try
        {
            guestShutdown.Start();
            response["accepted"] = true;
        }
        catch (Exception error)
        {
            response["accepted"] = false;
            response["reason"] = error.Message;
        }

        return AgentReplies.Direct(response);
    }

    private async Task<AgentReplies> HandleDisplayResizeAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        if (!TryReadInt(request, "width", out var width)
            || !TryReadInt(request, "height", out var height)
            || !IsPlausibleDisplayResize(width, height))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_message",
                "display.resize.request requires a width and height between 640 and 3840 pixels with at most 8294400 pixels."
            ));
        }

        try
        {
            var result = await desktop.ResizeDisplayAsync(
                new DisplayResizeInput(width, height),
                cancellationToken
            );
            return AgentReplies.Direct(DisplayResizeResponse(requestId, result));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "display_resize_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleMouseInputAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var windowId = request["windowId"]?.GetValue<string>();
        var eventName = request["event"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId)
            || string.IsNullOrWhiteSpace(eventName)
            || !TryReadInt(request, "x", out var x)
            || !TryReadInt(request, "y", out var y))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "input.mouse requires windowId, event, x, and y."));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_not_tracked", $"No tracked window exists for id {windowId}."));
        }

        var modifiers = request["modifiers"] is JsonArray modifierArray
            ? modifierArray.Select(modifier => modifier?.GetValue<string>() ?? string.Empty).Where(modifier => modifier.Length > 0).ToArray()
            : Array.Empty<string>();

        try
        {
            var applied = await desktop.SendMouseInputAsync(
                new WindowMouseInput(
                    windowId,
                    eventName,
                    x,
                    y,
                    modifiers,
                    DeltaX: TryReadInt(request, "deltaX", out var deltaX) ? deltaX : 0,
                    DeltaY: TryReadInt(request, "deltaY", out var deltaY) ? deltaY : 0
                ),
                cancellationToken
            );
            if (!applied)
            {
                return AgentReplies.Direct(ErrorResponse(
                    requestId,
                    "input_mouse_failed",
                    $"Windows did not apply the {eventName} mouse event for window {windowId}."
                ));
            }

            var ack = OperationAck(requestId);
            if (desktop.LastInjectedPointer is { } pointer)
            {
                ack["pointer"] = new JsonObject { ["x"] = pointer.X, ["y"] = pointer.Y };
            }
            return AgentReplies.Direct(ack);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "input_mouse_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleKeyInputAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var windowId = request["windowId"]?.GetValue<string>();
        var eventName = request["event"]?.GetValue<string>();
        var key = request["key"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(windowId)
            || string.IsNullOrWhiteSpace(eventName)
            || string.IsNullOrWhiteSpace(key)
            || !TryReadInt(request, "windowsVirtualKey", out var windowsVirtualKey))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "input.key requires windowId, event, key, and windowsVirtualKey."));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_not_tracked", $"No tracked window exists for id {windowId}."));
        }

        var modifiers = request["modifiers"] is JsonArray modifierArray
            ? modifierArray.Select(modifier => modifier?.GetValue<string>() ?? string.Empty).Where(modifier => modifier.Length > 0).ToArray()
            : Array.Empty<string>();

        try
        {
            var applied = await desktop.SendKeyInputAsync(
                new WindowKeyInput(windowId, eventName, key, windowsVirtualKey, modifiers),
                cancellationToken
            );
            if (!applied)
            {
                return AgentReplies.Direct(ErrorResponse(
                    requestId,
                    "input_key_failed",
                    $"Windows did not apply the {eventName} event for key {key} on window {windowId}."
                ));
            }

            return AgentReplies.Direct(OperationAck(requestId));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "input_key_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleTextInputAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var windowId = request["windowId"]?.GetValue<string>();
        var text = request["text"]?.GetValue<string>();
        int replaceLength;
        try
        {
            replaceLength = request["replaceLength"]?.GetValue<int>() ?? 0;
        }
        catch (Exception error) when (error is FormatException or InvalidOperationException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "input.text replaceLength must be an integer."));
        }

        if (replaceLength < 0 || replaceLength > WindowsDesktop.MaxTextInputUtf16Length)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", $"input.text replaceLength must be from 0 to {WindowsDesktop.MaxTextInputUtf16Length}."));
        }

        // A composition can shrink to nothing (Backspace over its last jamo), which is a replacement with no text.
        if (string.IsNullOrWhiteSpace(windowId) || text is null || (text.Length == 0 && replaceLength == 0))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "input.text requires windowId and non-empty text."));
        }

        if (text.Length > WindowsDesktop.MaxTextInputUtf16Length)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "text_too_long", $"input.text accepts at most {WindowsDesktop.MaxTextInputUtf16Length} UTF-16 code units."));
        }

        // Enter and Tab have distinct guest semantics and belong on the input.key path; accepting them
        // here would let committed text quietly submit forms or move focus.
        if (text.Any(character => character is '\r' or '\n' or '\t'))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "input.text must not contain newlines or tabs; send those as input.key."));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_not_tracked", $"No tracked window exists for id {windowId}."));
        }

        try
        {
            var applied = await desktop.SendTextInputAsync(new WindowTextInput(windowId, text, replaceLength), cancellationToken);
            if (!applied)
            {
                return AgentReplies.Direct(ErrorResponse(
                    requestId,
                    "input_text_failed",
                    $"Windows did not post the committed text to window {windowId}."
                ));
            }

            return AgentReplies.Direct(OperationAck(requestId));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "input_text_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleClipboardTextSetAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var text = request["text"]?.GetValue<string>();
        var origin = request["origin"]?.GetValue<string>();
        if (text is null || string.IsNullOrWhiteSpace(origin))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "clipboard.text.set requires origin and text."));
        }

        if (origin != "host")
        {
            return AgentReplies.Direct();
        }

        try
        {
            await desktop.SetClipboardTextAsync(text, cancellationToken);
            // Only the host-origin write acknowledges. An echo of a guest-originated change never
            // had a request to acknowledge, and answering it would look like a reply to whatever
            // else the host has in flight.
            return AgentReplies.Direct(OperationAck(requestId));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "clipboard_text_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleClipboardImageSetAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var origin = request["origin"]?.GetValue<string>();
        if (origin == "guest")
        {
            // Same rule as text: an echo of a guest-originated image has no request to acknowledge.
            return AgentReplies.Direct();
        }

        if (origin != "host")
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "clipboard.image.set requires origin host or guest."));
        }

        var (image, rejection) = ClipboardImageMessage.Parse(request);
        if (image is null)
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                rejection?.Code ?? "invalid_message",
                rejection?.Message ?? "clipboard.image.set was rejected."
            ));
        }

        try
        {
            await desktop.SetClipboardImagePngAsync(image.Png, image.Sha256, cancellationToken);
            return AgentReplies.Direct(OperationAck(requestId));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "clipboard_image_failed", error.Message));
        }
    }

    /// <summary>
    /// Places files the host already copied into the shared folder on the clipboard. Every entry is
    /// checked before any is used, so one bad path rejects the paste instead of pasting part of it.
    /// </summary>
    private async Task<AgentReplies> HandleClipboardFilesSetAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        if (request["origin"]?.GetValue<string>() != "host")
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "clipboard.files.set only travels from the host."));
        }

        if (request["shareName"]?.GetValue<string>() != SharedFolderProbe.DefaultShareName
            || request["relativePaths"] is not JsonArray relativePaths
            || relativePaths.Count < 1
            || relativePaths.Count > ClipboardFilePaths.MaxFileCount)
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_shared_file_path",
                $"clipboard.files.set requires shareName {SharedFolderProbe.DefaultShareName} and 1 to {ClipboardFilePaths.MaxFileCount} relativePaths."
            ));
        }

        var fullPaths = new List<string>(relativePaths.Count);
        foreach (var node in relativePaths)
        {
            var relativePath = node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
            if (!ClipboardFilePaths.TryResolve(relativePath, SharedFolderProbe.DefaultGuestDirectoryPath, out var fullPath)
                || !desktop.IsRegularSharedFile(fullPath))
            {
                return AgentReplies.Direct(ErrorResponse(
                    requestId,
                    "invalid_shared_file_path",
                    $"Every clipboard file must be a regular file inside {SharedFolderProbe.DefaultGuestDirectoryPath}\\{ClipboardFilePaths.DirectoryName}."
                ));
            }

            fullPaths.Add(fullPath);
        }

        try
        {
            await desktop.SetClipboardFilesAsync(fullPaths, cancellationToken);
            return AgentReplies.Direct(OperationAck(requestId));
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "clipboard_files_failed", error.Message));
        }
    }

    private JsonObject HealthResponse(string? requestId)
    {
        var hasPackageIdentity = packageIdentityProbe.HasPackageIdentity;
        var response = new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["agentVersion"] = AgentBuild.Version,
            ["os"] = "windows-arm64",
            ["session"] = new JsonObject
            {
                ["interactive"] = Environment.UserInteractive,
                ["user"] = Environment.UserName
            },
            ["capabilities"] = new JsonObject
            {
                ["appList"] = true,
                ["appLaunch"] = true,
                ["windowTracking"] = true,
                ["windowCapture"] = true,
                ["input"] = true,
                ["clipboardText"] = true,
                // Optional on the wire: an older agent omits them and the host keeps images and files on
                // the Mac instead of sending messages this agent would reject as unknown.
                ["clipboardImage"] = true,
                ["clipboardFiles"] = true,
                // Advertises the send-only binary frame endpoint. The host only opens it when this is
                // true, so a host that cannot decode the binary format keeps receiving JSON frames.
                ["binaryFrameChannel"] = true,
                // Lets the host tell "no share yet" apart from "this agent cannot answer". Without it an
                // older agent would look like a guest whose share is missing.
                ["sharedFolder"] = true,
                // Lets the host enable the resize affordance only when this agent understands the
                // additive window.resize.request message.
                ["windowResize"] = true,
                ["displayResize"] = OperatingSystem.IsWindows(),
                // Lets the host run Windows at the Mac's backing scale (200% on Retina) with
                // display.scale.request. An older agent omits it and the host keeps one pixel per point.
                ["displayScale"] = OperatingSystem.IsWindows(),
                // Lets the host boot the next cold start on virtio-gpu alone. Read-only, like the rest
                // of health: the driver itself is installed by the setup and repair scripts.
                ["virtioGpuDisplay"] = VirtioGpuDisplay.IsDriverInstalled(),
                // Lets the host shut Windows down through the agent instead of the ACPI power button.
                ["systemShutdown"] = OperatingSystem.IsWindows(),
                // Lets the host crop windows out of the guest framebuffer from window.layout events, and
                // slow their capture with window.crop.set.
                ["windowLayout"] = OperatingSystem.IsWindows(),
                // Lets the host wait for the operation.ack reply on the fire-and-forget paths
                // (input, clipboard, frame subscribe). An older host ignores it; an older agent
                // omits it and the host keeps its fire-and-forget semantics instead of hanging.
                ["operationAcks"] = true,
                // Advertise the host-to-guest state sync messages so an older agent is never sent
                // time.sync.request or appearance.set.request.
                ["timeSync"] = true,
                ["appearanceSync"] = true,
                ["visualEffects"] = OperatingSystem.IsWindows(),
                // input.text accepts replaceLength, so the host can show an open IME composition inline
                // instead of only after it is committed.
                ["textComposition"] = OperatingSystem.IsWindows(),
                // input.ime.set: the Windows IME follows the macOS input source instead of keeping its own.
                ["imeMode"] = OperatingSystem.IsWindows(),
                // host.folder.mount.request: a Mac folder served over WebDAV, mapped as a drive letter.
                ["hostFolder"] = OperatingSystem.IsWindows(),
                ["desktopWindows"] = OperatingSystem.IsWindows(),
                ["toolsUpdate"] = OperatingSystem.IsWindows(),
                ["packageIdentity"] = hasPackageIdentity
            },
            ["notificationListener"] = notificationAccessProbe.ReadStatus(hasPackageIdentity),
            // Read-only here. Health is polled, so it must never create folders or publish shares as a
            // side effect; shared.folder.request is the message that prepares anything.
            ["sharedFolder"] = sharedFolderProbe.ReadStatus(
                SharedFolderProbe.DefaultShareName,
                SharedFolderProbe.DefaultGuestDirectoryPath
            )
        };

        var sparsePackageStatus = sparsePackageStatusProbe.ReadStatus();
        if (sparsePackageStatus is not null)
        {
            response["packageIdentityStatus"] = sparsePackageStatus;
        }

        // Diagnostic and optional: per-step capture times, so the host can see where mirrored frame time
        // goes inside the guest without reading guest logs.
        response["frameCapture"] = FrameCaptureDiagnostics.Shared.Snapshot();
        // Also diagnostic and optional: how much processor time the agent and all of Windows have used, so
        // the cost of mirroring inside the guest can be read from two health answers a few seconds apart.
        response["processor"] = ProcessorDiagnostics.Snapshot();
        return response;
    }

    /// <summary>
    /// Forces a capture method for diagnosis (screen copy or PrintWindow) or returns to automatic, and
    /// clears the recorded capture times so the next health reply describes only the new method.
    /// </summary>
    private AgentReplies HandleFrameCaptureStrategySet(JsonObject request, string? requestId)
    {
        var strategy = request["strategy"]?.GetValue<string>() ?? "";
        if (!FrameCaptureDiagnostics.Shared.SetStrategy(strategy))
        {
            return AgentReplies.Direct(
                ErrorResponse(requestId, "invalid_message", $"Unsupported capture strategy {strategy}")
            );
        }

        return AgentReplies.Direct(OperationAck(requestId));
    }

    /// <summary>
    /// Places a tracked window where the host shows it, so the guest layout matches the Mac's and
    /// overlapping mirrored windows cover each other the same way in both (<c>window.move.request</c>).
    /// </summary>
    private AgentReplies HandleWindowMove(JsonObject request, string? requestId)
    {
        var windowId = request["windowId"]?.GetValue<string>();
        int? x = request["x"] is JsonValue xValue && xValue.TryGetValue<int>(out var xInt) ? xInt : null;
        int? y = request["y"] is JsonValue yValue && yValue.TryGetValue<int>(out var yInt) ? yInt : null;
        if (string.IsNullOrWhiteSpace(windowId)
            || x is null or < -16_384 or > 16_384
            || y is null or < -16_384 or > 16_384)
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_message",
                "window.move.request requires a windowId and x and y between -16384 and 16384."
            ));
        }

        if (!TryGetTrackedWindow(windowId, out _))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "window_not_tracked", $"Window {windowId} is not tracked."));
        }

        return desktop.MoveWindow(windowId, x.Value, y.Value)
            ? AgentReplies.Direct(OperationAck(requestId))
            : AgentReplies.Direct(ErrorResponse(requestId, "window_move_failed", $"Window {windowId} could not be moved."));
    }

    private AgentReplies HandleWindowCropSet(JsonObject request, string? requestId)
    {
        if (request["windowIds"] is not JsonArray windowIds)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "window.crop.set needs windowIds."));
        }

        HashSet<string> tracked;
        lock (trackedWindowsGate)
        {
            tracked = trackedWindowsById.Keys.ToHashSet(StringComparer.Ordinal);
        }

        var hidesDesktop = request["hidesDesktop"] is JsonValue flag && flag.TryGetValue<bool>(out var value) && value;
        // Only tracked windows: the list slows their capture and must not name anything else.
        FramebufferCropRegistry.Set(
            windowIds
                .Select(node => node?.GetValue<string>())
                .OfType<string>()
                .Where(tracked.Contains),
            hidesDesktop);
        return AgentReplies.Direct(OperationAck(requestId));
    }

    private async Task<AgentReplies> HandleSharedFolderRequestAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        // The host sends the share name and folder rather than letting the guest pick, so a mismatch
        // between what the Mac tries to mount and what Windows published cannot go unnoticed. Falling
        // back to the defaults keeps an older host working.
        var shareName = request["shareName"]?.GetValue<string>() ?? SharedFolderProbe.DefaultShareName;
        var guestDirectoryPath = request["guestDirectoryPath"]?.GetValue<string>()
            ?? SharedFolderProbe.DefaultGuestDirectoryPath;

        var status = await sharedFolderProbe.EnsureAsync(shareName, guestDirectoryPath, cancellationToken);

        return AgentReplies.Direct(new JsonObject
        {
            ["type"] = MessageTypes.SharedFolderResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["sharedFolder"] = status
        });
    }

    private AgentReplies HandleTimeSyncRequest(JsonObject request, string? requestId)
    {
        return AgentReplies.Direct(new JsonObject
        {
            ["type"] = MessageTypes.TimeSyncResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["timeSync"] = timeSync.Handle(request)
        });
    }

    private AgentReplies HandleHostFolderMount(JsonObject request, string? requestId)
    {
        string? token, driveLetter, label;
        int port;
        try
        {
            token = request["token"]?.GetValue<string>();
            driveLetter = request["driveLetter"]?.GetValue<string>();
            label = request["label"]?.GetValue<string>();
            port = request["port"]?.GetValue<int>() ?? 0;
        }
        catch (Exception error) when (error is FormatException or InvalidOperationException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "host.folder.mount.request has a field of the wrong type."));
        }

        // The token and letter name a network path, so only the documented shapes are accepted.
        if (port is < 1 or > 65535
            || !HostFolderMount.IsValidToken(token)
            || !HostFolderMount.IsValidDriveLetter(driveLetter)
            || string.IsNullOrEmpty(label) || label.Length > 32)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "host.folder.mount.request needs a port, a 16-128 character token, a drive letter D-Z, and a label of up to 32 characters."));
        }

        var result = hostFolderMount.Mount(port, token!, driveLetter!, label);
        return AgentReplies.Direct(HostFolderReply(MessageTypes.HostFolderMountResponse, requestId, result.IsMounted, driveLetter!, result.UncPath, result.Message));
    }

    private AgentReplies HandleHostFolderUnmount(JsonObject request, string? requestId)
    {
        string? driveLetter;
        try
        {
            driveLetter = request["driveLetter"]?.GetValue<string>();
        }
        catch (InvalidOperationException)
        {
            driveLetter = null;
        }

        if (!HostFolderMount.IsValidDriveLetter(driveLetter))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "host.folder.unmount.request needs a drive letter D-Z."));
        }

        var result = hostFolderMount.Unmount(driveLetter!);
        return AgentReplies.Direct(HostFolderReply(MessageTypes.HostFolderUnmountResponse, requestId, result.IsMounted, driveLetter!, null, result.Message));
    }

    private static JsonObject HostFolderReply(string type, string? requestId, bool isMounted, string driveLetter, string? uncPath, string? message) => new()
    {
        ["type"] = type,
        ["requestId"] = requestId,
        ["protocolVersion"] = 1,
        ["hostFolder"] = new JsonObject
        {
            ["isMounted"] = isMounted,
            ["driveLetter"] = driveLetter,
            ["uncPath"] = uncPath,
            ["message"] = message
        }
    };

    private AgentReplies HandleImeSet(JsonObject request, string? requestId)
    {
        string? mode;
        try
        {
            mode = request["mode"]?.GetValue<string>();
        }
        catch (InvalidOperationException)
        {
            mode = null;
        }

        if (!GuestImeMode.IsValid(mode))
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "input.ime.set mode must be native, alphanumeric, or unmanaged."));
        }

        imeModeSink(mode!);
        var reply = OperationAck(requestId);
        // Diagnostics only: whether the foreground window's IME state could be read back after the change.
        var last = GuestImeMode.LastApply;
        reply["ime"] = new JsonObject
        {
            ["openBefore"] = last.OpenBefore,
            ["openAfter"] = last.OpenAfter,
            ["conversionAfter"] = last.ConversionAfter,
            ["windowClass"] = last.WindowClass,
            ["hangulToggledBefore"] = last.HangulToggledBefore,
            ["hangulToggledAfter"] = last.HangulToggledAfter
        };
        return AgentReplies.Direct(reply);
    }

    private AgentReplies HandleVisualEffectsSetRequest(JsonObject request, string? requestId)
    {
        bool reduced;
        try
        {
            if (request["reduced"] is not { } value)
            {
                throw new InvalidOperationException();
            }
            reduced = value.GetValue<bool>();
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "visual.effects.set.request reduced must be true or false."));
        }

        JsonObject status;
        try
        {
            status = visualEffects.Apply(reduced);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "visual_effects_set_failed", error.Message));
        }

        return AgentReplies.Direct(new JsonObject
        {
            ["type"] = MessageTypes.VisualEffectsSetResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["visualEffects"] = status
        });
    }

    private AgentReplies HandleAppearanceSetRequest(JsonObject request, string? requestId)
    {
        string? theme;
        try
        {
            theme = request["theme"]?.GetValue<string>();
        }
        catch (InvalidOperationException)
        {
            theme = null;
        }

        JsonObject? status;
        try
        {
            status = appearanceSync.Apply(theme);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "appearance_set_failed", error.Message));
        }

        if (status is null)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "invalid_message", "appearance.set.request theme must be light or dark."));
        }

        return AgentReplies.Direct(new JsonObject
        {
            ["type"] = MessageTypes.AppearanceSetResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["appearance"] = status
        });
    }

    private async Task<AgentReplies> HandleNotificationListenerRequestAsync(
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var hasPackageIdentity = packageIdentityProbe.HasPackageIdentity;
        var status = await notificationAccessProbe.RequestAccessAsync(hasPackageIdentity, cancellationToken);
        return AgentReplies.Direct(new JsonObject
        {
            ["type"] = MessageTypes.NotificationListenerResponse,
            ["requestId"] = requestId,
            ["protocolVersion"] = 1,
            ["accepted"] = status["canListen"]?.GetValue<bool>() == true,
            ["notificationListener"] = status
        });
    }

    private async Task<JsonObject> AppListResponseAsync(string? requestId, CancellationToken cancellationToken)
    {
        var startMenuApps = await StartMenuAppsAsync(AppListCatalogWait, cancellationToken);
        return new JsonObject
        {
            ["type"] = MessageTypes.AppListResponse,
            ["requestId"] = requestId,
            ["apps"] = new JsonArray(
                AppCatalog.Select(BuiltInAppObject)
                    .Concat(startMenuApps.Select(StartMenuAppObject))
                    .Concat(runningApps.Values.OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
                        .Select(RunningAppObject))
                    .ToArray<JsonNode?>()
            )
        };
    }

    /// <summary>
    /// The Start menu apps that are not already a built-in app.
    /// </summary>
    private async Task<IReadOnlyList<WindowsAppDescriptor>> StartMenuAppsAsync(
        TimeSpan maxWait,
        CancellationToken cancellationToken
    ) =>
        StartMenuCatalog.WithoutBuiltIns(AppCatalog, await startMenu.GetAppsAsync(maxWait, cancellationToken));

    /// <summary>
    /// A built-in app or a Start menu app. File opens stay limited to the built-in apps, which are known to
    /// take a file path as their only argument.
    /// </summary>
    private async Task<WindowsAppDescriptor?> FindLaunchableAppAsync(string? appId, CancellationToken cancellationToken)
    {
        if (AppCatalog.FirstOrDefault(candidate => candidate.Id == appId) is { } builtIn)
        {
            return builtIn;
        }

        if (appId is not null && runningApps.TryGetValue(appId, out var running))
        {
            return running;
        }

        if (appId is null || !appId.StartsWith(StartMenuCatalog.IdPrefix, StringComparison.Ordinal))
        {
            return null;
        }

        return (await StartMenuAppsAsync(AppLaunchCatalogWait, cancellationToken))
            .FirstOrDefault(candidate => candidate.Id == appId);
    }

    private static JsonObject BuiltInAppObject(WindowsAppDescriptor app) => AppObject(
        app,
        WindowsAppIconExtractor.ExtractIconPngBase64(
            app.Id,
            app.AppUserModelId,
            new[] { app.Executable }.Concat(app.AlternateExecutables ?? [])
        )
    );

    private static JsonObject StartMenuAppObject(WindowsAppDescriptor app)
    {
        var appObject = AppObject(app, StartMenuCatalog.IconPngBase64(app));
        if (app.Folder is { Length: > 0 } folder)
        {
            appObject["folder"] = folder;
        }

        return appObject;
    }

    /// <summary>
    /// An app known only from an open window. <c>running</c> tells the host it is not a Start menu entry.
    /// </summary>
    private static JsonObject RunningAppObject(WindowsAppDescriptor app)
    {
        var appObject = AppObject(app, StartMenuCatalog.IconPngBase64(app));
        appObject["running"] = true;
        return appObject;
    }

    private static JsonObject AppObject(WindowsAppDescriptor app, string? iconPngBase64) => new()
    {
        ["id"] = app.Id,
        ["name"] = app.Name,
        ["exePath"] = app.Executable,
        ["publisher"] = app.Publisher,
        ["iconId"] = app.IconId,
        ["iconPngBase64"] = iconPngBase64
    };

    private static JsonObject LaunchResponse(string? requestId, int processId) => new()
    {
        ["type"] = MessageTypes.AppLaunchResponse,
        ["requestId"] = requestId,
        ["accepted"] = true,
        ["processId"] = processId
    };

    private static JsonObject FileOpenResponse(string? requestId, bool accepted, int processId) => new()
    {
        ["type"] = MessageTypes.FileOpenResponse,
        ["requestId"] = requestId,
        ["accepted"] = accepted,
        ["processId"] = processId
    };

    private static JsonObject WindowCreatedEvent(WindowsAppDescriptor app, LaunchedWindow window)
    {
        var message = WithResizable(WindowCreatedEventFields(app, window), window);
        // Only sent for popups so ordinary window events, and their fixtures, stay as they were.
        if (window.IsPopup)
        {
            message["popup"] = true;
            if (window.OwnerWindowId is { } ownerWindowId)
            {
                message["ownerWindowId"] = ownerWindowId;
            }
        }
        return message;
    }

    private static JsonObject WindowCreatedEventFields(WindowsAppDescriptor app, LaunchedWindow window) => new()
    {
        ["type"] = MessageTypes.WindowCreated,
        ["windowId"] = window.WindowId,
        ["processId"] = window.ProcessId,
        ["appId"] = app.Id,
        ["title"] = window.Title,
        ["bounds"] = new JsonObject
        {
            ["x"] = window.Bounds.X,
            ["y"] = window.Bounds.Y,
            ["width"] = window.Bounds.Width,
            ["height"] = window.Bounds.Height
        },
        ["state"] = window.State,
        ["focused"] = window.Focused
    };

    private static JsonObject WithResizable(JsonObject message, LaunchedWindow window)
    {
        // Only sent when false, so events for ordinary windows, and their fixtures, stay as they were.
        if (!window.Resizable)
        {
            message["resizable"] = false;
        }

        return message;
    }

    private static JsonObject WindowFrameEvent(WindowFrame frame) => new()
    {
        ["type"] = MessageTypes.WindowFrame,
        ["windowId"] = frame.WindowId,
        ["frameId"] = frame.FrameId,
        ["sequence"] = frame.Sequence,
        ["format"] = frame.Format,
        ["width"] = frame.Width,
        ["height"] = frame.Height,
        ["scale"] = frame.Scale,
        ["encodedData"] = frame.EncodedData
    };

    private static JsonObject WindowClosedEvent(string windowId) => new()
    {
        ["type"] = MessageTypes.WindowClosed,
        ["windowId"] = windowId
    };

    private static JsonObject WindowFocusResponse(string? requestId, string windowId, bool accepted) => new()
    {
        ["type"] = MessageTypes.WindowFocusResponse,
        ["requestId"] = requestId,
        ["windowId"] = windowId,
        ["accepted"] = accepted
    };

    private static JsonObject WindowCloseResponse(string? requestId, string windowId, bool accepted) => new()
    {
        ["type"] = MessageTypes.WindowCloseResponse,
        ["requestId"] = requestId,
        ["windowId"] = windowId,
        ["accepted"] = accepted
    };

    private static JsonObject WindowResizeResponse(string? requestId, string windowId, WindowRect? bounds)
    {
        var response = new JsonObject
        {
            ["type"] = MessageTypes.WindowResizeResponse,
            ["requestId"] = requestId,
            ["windowId"] = windowId,
            ["accepted"] = bounds is not null
        };

        if (bounds is not null)
        {
            response["bounds"] = new JsonObject
            {
                ["x"] = bounds.X,
                ["y"] = bounds.Y,
                ["width"] = bounds.Width,
                ["height"] = bounds.Height
            };
        }

        return response;
    }

    private AgentReplies HandleDisplayScale(JsonObject request, string? requestId)
    {
        var hasPercent = TryReadInt(request, "scalePercent", out var percent);
        var restores = request["restoresUserScale"] is JsonValue restoreValue
            && restoreValue.TryGetValue<bool>(out var flag)
            && flag;
        if (hasPercent == restores || (hasPercent && !DisplayScaleSteps.IsStep(percent)))
        {
            return AgentReplies.Direct(ErrorResponse(
                requestId,
                "invalid_message",
                "display.scale.request requires either a scalePercent that is a Windows scale step or restoresUserScale: true."
            ));
        }

        var result = displayScale.Apply(new DisplayScaleInput(hasPercent ? percent : null, restores));
        var response = new JsonObject
        {
            ["type"] = MessageTypes.DisplayScaleResponse,
            ["requestId"] = requestId,
            ["accepted"] = result.Accepted
        };
        if (result.ScalePercent is { } applied)
        {
            response["scalePercent"] = applied;
        }

        if (result.Reason is { } reason)
        {
            response["reason"] = reason;
        }

        return AgentReplies.Direct(response);
    }

    private static JsonObject DisplayResizeResponse(string? requestId, DisplayResizeResult? result)
    {
        var response = new JsonObject
        {
            ["type"] = MessageTypes.DisplayResizeResponse,
            ["requestId"] = requestId,
            ["accepted"] = result is not null
        };

        if (result is not null)
        {
            response["width"] = result.Width;
            response["height"] = result.Height;
        }
        else
        {
            response["reason"] = "display_mode_not_supported";
        }

        return response;
    }

    private static JsonObject ErrorResponse(string? requestId, string code, string message) => new()
    {
        ["type"] = MessageTypes.Error,
        ["requestId"] = requestId,
        ["code"] = code,
        ["message"] = message
    };

    /// <summary>
    /// The success reply for messages the host used to send fire-and-forget. Failures keep using
    /// the <see cref="ErrorResponse"/> shape, so one host read of "one reply frame" covers both.
    /// An agent that predates acknowledgements sends nothing and the host falls back after a
    /// bounded wait, which is why this reply carries no payload beyond the echoed request id.
    /// </summary>
    private static JsonObject OperationAck(string? requestId) => new()
    {
        ["type"] = MessageTypes.OperationAck,
        ["requestId"] = requestId,
        ["accepted"] = true
    };

    private static bool IsPlausibleResize(int width, int height) =>
        width >= 320
            && width <= 8_192
            && height >= 320
            && height <= 8_192
            && (long)width * height <= 32_000_000;

    private static bool IsPlausibleDisplayResize(int width, int height) =>
        width >= 640
            && width <= 3_840
            && height >= 640
            && height <= 3_840
            && (long)width * height <= 8_294_400;

    private void TrackWindow(WindowsAppDescriptor app, LaunchedWindow window)
    {
        lock (trackedWindowsGate)
        {
            trackedWindowsById[window.WindowId] = window;
            appByWindowId[window.WindowId] = app;
        }
    }

    private void TrackWindows(WindowsAppDescriptor app, IEnumerable<LaunchedWindow> windows)
    {
        lock (trackedWindowsGate)
        {
            foreach (var window in windows)
            {
                trackedWindowsById[window.WindowId] = window;
                appByWindowId[window.WindowId] = app;
            }
        }
    }

    private bool TryGetTrackedWindow(string windowId, out LaunchedWindow window)
    {
        lock (trackedWindowsGate)
        {
            return trackedWindowsById.TryGetValue(windowId, out window!);
        }
    }

    private void UntrackWindow(string windowId)
    {
        lock (trackedWindowsGate)
        {
            trackedWindowsById.Remove(windowId);
            appByWindowId.Remove(windowId);
        }
    }

    /// <summary>
    /// Snapshot of every app with at least one tracked window, paired with the window ids already
    /// known for it -- <see cref="WindowDiscoveryStreamer"/> uses this to scan only apps that have
    /// actually been launched, and to know which windows are already reported so it doesn't
    /// re-announce them.
    /// </summary>
    /// <summary>Every tracked window id with the window that owns it, for <c>window.layout</c>.</summary>
    internal IReadOnlyDictionary<string, string?> SnapshotTrackedWindowOwners()
    {
        lock (trackedWindowsGate)
        {
            return trackedWindowsById.ToDictionary(pair => pair.Key, pair => pair.Value.OwnerWindowId);
        }
    }

    /// <summary>
    /// True while an app launch or file open is looking for its window. Desktop-wide discovery waits, so it
    /// does not announce the window the launch is about to report itself.
    /// </summary>
    internal bool IsLaunching => Volatile.Read(ref launchesInFlight) > 0;

    internal IReadOnlySet<string> SnapshotTrackedWindowIds()
    {
        lock (trackedWindowsGate)
        {
            return trackedWindowsById.Keys.ToHashSet();
        }
    }

    /// <summary>
    /// The app a window found on the desktop belongs to: a built-in or Start menu app when one matches, and
    /// otherwise an app made from the window's program and remembered for app.list and app.launch.
    /// </summary>
    internal async Task<WindowsAppDescriptor> AppForDiscoveredWindowAsync(
        DiscoveredAppWindow window,
        CancellationToken cancellationToken
    )
    {
        // Right after the agent starts the Start menu is still being read. Waiting for it keeps a Start menu
        // app's window from being reported as a running app under a different id. Once the list is known
        // this returns at once.
        var startMenuApps = await StartMenuAppsAsync(AppLaunchCatalogWait, cancellationToken);
        if (RunningAppCatalog.Match(window, AppCatalog.Concat(startMenuApps).ToArray()) is { } known)
        {
            return known;
        }

        var described = RunningAppCatalog.Describe(window, RunningAppCatalog.FileDescription);
        return runningApps.GetOrAdd(described.Id, described);
    }

    internal IReadOnlyList<(WindowsAppDescriptor App, IReadOnlySet<string> KnownWindowIds)> SnapshotTrackedAppsForDiscovery()
    {
        lock (trackedWindowsGate)
        {
            return appByWindowId
                .GroupBy(pair => pair.Value, pair => pair.Key)
                .Select(group => (group.Key, (IReadOnlySet<string>)group.ToHashSet()))
                .ToList();
        }
    }

    /// <summary>
    /// Tracks a window discovered outside the launch flow (a second window for an already-launched
    /// app) and returns its <c>window.created</c> event, or <c>null</c> if it's already tracked --
    /// guards against the discovery scan racing a launch/close that tracked or removed the same
    /// window id between the scan and this call.
    /// </summary>
    internal JsonObject? TryTrackDiscoveredWindow(WindowsAppDescriptor app, LaunchedWindow window)
    {
        lock (trackedWindowsGate)
        {
            if (trackedWindowsById.ContainsKey(window.WindowId))
            {
                return null;
            }

            trackedWindowsById[window.WindowId] = window;
            appByWindowId[window.WindowId] = app;
        }

        return WindowCreatedEvent(app, window);
    }

    /// <summary>
    /// Untracks a window the discovery scan found is no longer open (the user closed it directly on
    /// the guest rather than through <c>window.close.request</c>) and returns a <c>window.closed</c>
    /// event, or <c>null</c> if it wasn't tracked -- guards against the scan racing a concurrent
    /// <c>window.close.request</c> for the same window id.
    /// </summary>
    internal JsonObject? TryUntrackClosedWindow(string windowId)
    {
        lock (trackedWindowsGate)
        {
            if (!trackedWindowsById.Remove(windowId))
            {
                return null;
            }

            appByWindowId.Remove(windowId);
        }

        return WindowClosedEvent(windowId);
    }

    private static bool TryReadInt(JsonObject request, string key, out int value)
    {
        value = 0;
        try
        {
            var node = request[key];
            if (node is null)
            {
                return false;
            }

            value = node.GetValue<int>();
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}

public sealed record AgentReplies(
    IReadOnlyList<JsonObject> DirectReplies,
    IReadOnlyList<JsonObject> BroadcastEvents,
    LaunchedWindow? StreamWindow = null,
    int NextFrameSequence = 1,
    string? StopStreamWindowId = null
)
{
    public static AgentReplies Direct(params JsonObject[] replies) => new(replies, Array.Empty<JsonObject>());

    public IEnumerable<string> SerializeDirectReplies() => DirectReplies.Select(Serialize);

    public IEnumerable<string> SerializeBroadcastEvents() => BroadcastEvents.Select(Serialize);

    public static string SerializeFrame(WindowFrame frame)
    {
        var message = new JsonObject
        {
            ["type"] = MessageTypes.WindowFrame,
            ["windowId"] = frame.WindowId,
            ["frameId"] = frame.FrameId,
            ["sequence"] = frame.Sequence,
            ["format"] = frame.Format,
            ["width"] = frame.Width,
            ["height"] = frame.Height,
            ["scale"] = frame.Scale,
            ["encodedData"] = frame.EncodedData
        };

        return Serialize(message);
    }

    /// <summary>
    /// Proof that a frame stream is alive with nothing new to draw. Carries no image payload.
    /// </summary>
    public static string SerializeUnchangedFrame(string windowId, int sequence)
    {
        var message = new JsonObject
        {
            ["type"] = MessageTypes.WindowFrameUnchanged,
            ["windowId"] = windowId,
            ["sequence"] = sequence,
            ["capturedAt"] = DateTimeOffset.UtcNow.ToString("O")
        };

        return Serialize(message);
    }

    private static string Serialize(JsonObject message) => message.ToJsonString(ProtocolJson.Options);
}

public static class ProtocolJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };
}
