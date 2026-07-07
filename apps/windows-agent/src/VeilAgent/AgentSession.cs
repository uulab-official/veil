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
    private readonly Dictionary<string, LaunchedWindow> trackedWindowsById = new();
    private readonly Dictionary<string, WindowsAppDescriptor> appByWindowId = new();
    private readonly object trackedWindowsGate = new();

    public AgentSession(IWindowsDesktop desktop, IWindowFrameCapture capture)
    {
        this.desktop = desktop;
        this.capture = capture;
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
                MessageTypes.WindowFrameSubscribe => HandleWindowFrameSubscribeAsync(request, requestId),
                MessageTypes.WindowFrameUnsubscribe => HandleWindowFrameUnsubscribeAsync(request, requestId),
                MessageTypes.WindowFocusRequest => await HandleWindowFocusAsync(request, requestId, cancellationToken),
                MessageTypes.WindowCloseRequest => await HandleWindowCloseAsync(request, requestId, cancellationToken),
                MessageTypes.InputMouse => await HandleMouseInputAsync(request, requestId, cancellationToken),
                MessageTypes.InputKey => await HandleKeyInputAsync(request, requestId, cancellationToken),
                MessageTypes.ClipboardTextSet => await HandleClipboardTextSetAsync(request, requestId, cancellationToken),
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

        LaunchedWindow launched;
        try
        {
            launched = await desktop.LaunchAppAsync(app, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "app_launch_failed", error.Message));
        }

        TrackWindow(app, launched);
        var frame = await CaptureInitialFrameWithFallbackAsync(launched, cancellationToken);

        return new AgentReplies(
            DirectReplies: new List<JsonObject>
            {
                LaunchResponse(requestId, launched.ProcessId),
                WindowCreatedEvent(app, launched)
            },
            BroadcastEvents: new List<JsonObject>
            {
                WindowFrameEvent(frame)
            },
            StreamWindow: launched,
            NextFrameSequence: 2
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
        var frame = await CaptureInitialFrameWithFallbackAsync(launched, cancellationToken);

        return new AgentReplies(
            DirectReplies: new List<JsonObject>
            {
                FileOpenResponse(requestId, accepted: true, launched.ProcessId),
                WindowCreatedEvent(app, launched)
            },
            BroadcastEvents: new List<JsonObject>
            {
                WindowFrameEvent(frame)
            },
            StreamWindow: launched,
            NextFrameSequence: 2
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

    private async Task<WindowFrame> CaptureInitialFrameWithFallbackAsync(
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
                $"Initial frame capture failed for {launched.WindowId}; using bootstrap frame. {error.GetType().Name}: {error.Message}"
            );
            return await new BootstrapPngFrameCapture().CaptureFrameAsync(launched, sequence: 1, cancellationToken);
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
            DirectReplies: Array.Empty<JsonObject>(),
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
            DirectReplies: Array.Empty<JsonObject>(),
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
            await desktop.SendMouseInputAsync(
                new WindowMouseInput(windowId, eventName, x, y, modifiers),
                cancellationToken
            );
            return AgentReplies.Direct();
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
            await desktop.SendKeyInputAsync(
                new WindowKeyInput(windowId, eventName, key, windowsVirtualKey, modifiers),
                cancellationToken
            );
            return AgentReplies.Direct();
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "input_key_failed", error.Message));
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
            return AgentReplies.Direct();
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "clipboard_text_failed", error.Message));
        }
    }

    private static JsonObject HealthResponse(string? requestId) => new()
    {
        ["type"] = MessageTypes.AgentHealthResponse,
        ["requestId"] = requestId,
        ["protocolVersion"] = 1,
        ["agentVersion"] = "0.1.0",
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
            ["clipboardText"] = true
        }
    };

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

    private static JsonObject ErrorResponse(string? requestId, string code, string message) => new()
    {
        ["type"] = MessageTypes.Error,
        ["requestId"] = requestId,
        ["code"] = code,
        ["message"] = message
    };

    private void TrackWindow(WindowsAppDescriptor app, LaunchedWindow window)
    {
        lock (trackedWindowsGate)
        {
            trackedWindowsById[window.WindowId] = window;
            appByWindowId[window.WindowId] = app;
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

    private static string Serialize(JsonObject message) => message.ToJsonString(ProtocolJson.Options);
}

public static class ProtocolJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };
}
