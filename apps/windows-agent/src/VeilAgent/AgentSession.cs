using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class AgentSession
{
    private static readonly TimeSpan InitialFrameCaptureTimeout = TimeSpan.FromSeconds(2);
    private const int MaxDroppedFileBytes = 50 * 1024 * 1024;
    private static readonly TimeSpan DroppedFileCleanupDelay = TimeSpan.FromMinutes(5);
    private static readonly IReadOnlyList<WindowsAppDescriptor> AppCatalog = new[]
    {
        new WindowsAppDescriptor(
            Id: "winapp_notepad",
            Name: "Notepad",
            Executable: "notepad.exe",
            Publisher: "Microsoft",
            IconId: "icon_notepad"
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
            WindowDiscoveryTimeoutOverride: TimeSpan.FromSeconds(12)
        ),
        new WindowsAppDescriptor(
            Id: "winapp_paint",
            Name: "Paint",
            Executable: "mspaint.exe",
            Publisher: "Microsoft",
            IconId: "icon_paint"
        )
    };

    private readonly IWindowsDesktop desktop;
    private readonly IWindowFrameCapture capture;
    private readonly IPackageIdentityProbe packageIdentityProbe;
    private readonly ISparsePackageStatusProbe sparsePackageStatusProbe;
    private readonly IWindowsNotificationAccessProbe notificationAccessProbe;
    private readonly IWindowsSharedFolderProbe sharedFolderProbe;
    private readonly IGuestShutdown guestShutdown;
    private readonly Dictionary<string, LaunchedWindow> trackedWindowsById = new();
    private readonly Dictionary<string, WindowsAppDescriptor> appByWindowId = new();
    private readonly ConcurrentDictionary<string, SemaphoreSlim> appLaunchGates = new();
    private readonly object trackedWindowsGate = new();

    public AgentSession(
        IWindowsDesktop desktop,
        IWindowFrameCapture capture,
        IPackageIdentityProbe? packageIdentityProbe = null,
        ISparsePackageStatusProbe? sparsePackageStatusProbe = null,
        IWindowsNotificationAccessProbe? notificationAccessProbe = null,
        IWindowsSharedFolderProbe? sharedFolderProbe = null,
        IGuestShutdown? guestShutdown = null
    )
    {
        this.desktop = desktop;
        this.capture = capture;
        this.packageIdentityProbe = packageIdentityProbe ?? new WindowsPackageIdentityProbe();
        this.sparsePackageStatusProbe = sparsePackageStatusProbe ?? new SparsePackageStatusProbe();
        this.notificationAccessProbe = notificationAccessProbe ?? new WindowsNotificationAccessProbe();
        this.sharedFolderProbe = sharedFolderProbe ?? new SharedFolderProbe();
        this.guestShutdown = guestShutdown ?? new WindowsGuestShutdown();
    }

    public async Task<AgentReplies> HandleAsync(JsonObject request, CancellationToken cancellationToken = default)
    {
        var type = request["type"]?.GetValue<string>();
        var requestId = request["requestId"]?.GetValue<string>();

        try
        {
            return type switch
            {
                MessageTypes.AgentHealthRequest => AgentReplies.Direct(HealthResponse(requestId)),
                MessageTypes.AppListRequest => AgentReplies.Direct(AppListResponse(requestId)),
                MessageTypes.AppLaunchRequest => await HandleAppLaunchAsync(request, requestId, cancellationToken),
                MessageTypes.FileOpenRequest => await HandleFileOpenAsync(request, requestId, cancellationToken),
                MessageTypes.SharedFileOpenRequest => await HandleSharedFileOpenAsync(request, requestId, cancellationToken),
                MessageTypes.WindowFrameSubscribe => HandleWindowFrameSubscribeAsync(request, requestId),
                MessageTypes.WindowFrameUnsubscribe => HandleWindowFrameUnsubscribeAsync(request, requestId),
                MessageTypes.WindowFocusRequest => await HandleWindowFocusAsync(request, requestId, cancellationToken),
                MessageTypes.WindowCloseRequest => await HandleWindowCloseAsync(request, requestId, cancellationToken),
                MessageTypes.WindowResizeRequest => await HandleWindowResizeAsync(request, requestId, cancellationToken),
                MessageTypes.DisplayResizeRequest => await HandleDisplayResizeAsync(request, requestId, cancellationToken),
                MessageTypes.SystemShutdownRequest => HandleSystemShutdown(requestId),
                MessageTypes.InputMouse => await HandleMouseInputAsync(request, requestId, cancellationToken),
                MessageTypes.InputKey => await HandleKeyInputAsync(request, requestId, cancellationToken),
                MessageTypes.InputText => await HandleTextInputAsync(request, requestId, cancellationToken),
                MessageTypes.ClipboardTextSet => await HandleClipboardTextSetAsync(request, requestId, cancellationToken),
                MessageTypes.ClipboardImageSet => await HandleClipboardImageSetAsync(request, requestId, cancellationToken),
                MessageTypes.ClipboardFilesSet => await HandleClipboardFilesSetAsync(request, requestId, cancellationToken),
                MessageTypes.NotificationListenerRequest => await HandleNotificationListenerRequestAsync(requestId, cancellationToken),
                MessageTypes.SharedFolderRequest => await HandleSharedFolderRequestAsync(request, requestId, cancellationToken),
                _ => AgentReplies.Direct(ErrorResponse(requestId, "unknown_message_type", $"Unsupported message type {type}"))
            };
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "handler_failed", error.Message));
        }
    }

    private async Task<AgentReplies> HandleAppLaunchAsync(
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

        var reuseExistingWindow = request["reuseExistingWindow"]?.GetValue<bool>() ?? false;
        var launchGate = appLaunchGates.GetOrAdd(app.Id, _ => new SemaphoreSlim(1, 1));
        LaunchedWindow launched;
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
                    launched = existingWindows.FirstOrDefault(window => window.Focused) ?? existingWindows[0];
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
            BroadcastEvents: frame is null ? Array.Empty<JsonObject>() : [WindowFrameEvent(frame)],
            StreamWindow: launched,
            NextFrameSequence: frame is null ? 1 : 2
        );
    }

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
                new WindowMouseInput(windowId, eventName, x, y, modifiers),
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

            return AgentReplies.Direct(OperationAck(requestId));
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
        if (string.IsNullOrWhiteSpace(windowId) || string.IsNullOrEmpty(text))
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
            var applied = await desktop.SendTextInputAsync(new WindowTextInput(windowId, text), cancellationToken);
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
                // Lets the host boot the next cold start on virtio-gpu alone. Read-only, like the rest
                // of health: the driver itself is installed by the setup and repair scripts.
                ["virtioGpuDisplay"] = VirtioGpuDisplay.IsDriverInstalled(),
                // Lets the host shut Windows down through the agent instead of the ACPI power button.
                ["systemShutdown"] = OperatingSystem.IsWindows(),
                // Lets the host wait for the operation.ack reply on the fire-and-forget paths
                // (input, clipboard, frame subscribe). An older host ignores it; an older agent
                // omits it and the host keeps its fire-and-forget semantics instead of hanging.
                ["operationAcks"] = true,
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

        return response;
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

    private static JsonObject AppListResponse(string? requestId) => new()
    {
        ["type"] = MessageTypes.AppListResponse,
        ["requestId"] = requestId,
        ["apps"] = new JsonArray(AppCatalog.Select(AppObject).ToArray<JsonNode?>())
    };

    private static JsonObject AppObject(WindowsAppDescriptor app) => new()
    {
        ["id"] = app.Id,
        ["name"] = app.Name,
        ["exePath"] = app.Executable,
        ["publisher"] = app.Publisher,
        ["iconId"] = app.IconId,
        ["iconPngBase64"] = WindowsAppIconExtractor.ExtractIconPngBase64(
            app.Id,
            new[] { app.Executable }.Concat(app.AlternateExecutables ?? [])
        )
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

    private static JsonObject WindowCreatedEvent(WindowsAppDescriptor app, LaunchedWindow window) => new()
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
