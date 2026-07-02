using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class AgentSession
{
    private readonly IWindowsDesktop desktop;
    private readonly IWindowFrameCapture capture;
    private readonly Dictionary<string, LaunchedWindow> trackedWindowsById = new();
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

        return type switch
        {
            MessageTypes.AgentHealthRequest => AgentReplies.Direct(HealthResponse(requestId)),
            MessageTypes.AppListRequest => AgentReplies.Direct(AppListResponse(requestId)),
            MessageTypes.AppLaunchRequest => await HandleAppLaunchAsync(request, requestId, cancellationToken),
            MessageTypes.WindowFrameSubscribe => HandleWindowFrameSubscribeAsync(request, requestId),
            MessageTypes.WindowFrameUnsubscribe => HandleWindowFrameUnsubscribeAsync(request, requestId),
            MessageTypes.WindowCloseRequest => await HandleWindowCloseAsync(request, requestId, cancellationToken),
            MessageTypes.InputMouse => await HandleMouseInputAsync(request, requestId, cancellationToken),
            MessageTypes.InputKey => await HandleKeyInputAsync(request, requestId, cancellationToken),
            MessageTypes.ClipboardTextSet => await HandleClipboardTextSetAsync(request, requestId, cancellationToken),
            _ => AgentReplies.Direct(ErrorResponse(requestId, "unknown_message_type", $"Unsupported message type {type}"))
        };
    }

    private async Task<AgentReplies> HandleAppLaunchAsync(
        JsonObject request,
        string? requestId,
        CancellationToken cancellationToken
    )
    {
        var appId = request["appId"]?.GetValue<string>();
        if (appId != "winapp_notepad")
        {
            return AgentReplies.Direct(ErrorResponse(requestId, "app_not_found", $"No app exists for id {appId}"));
        }

        var launched = await desktop.LaunchNotepadAsync(cancellationToken);
        TrackWindow(launched);
        var frame = await capture.CaptureFrameAsync(launched, sequence: 1, cancellationToken);

        return new AgentReplies(
            DirectReplies: new List<JsonObject>
            {
                LaunchResponse(requestId, launched.ProcessId),
                WindowCreatedEvent(launched)
            },
            BroadcastEvents: new List<JsonObject>
            {
                WindowFrameEvent(frame)
            },
            StreamWindow: launched,
            NextFrameSequence: 2
        );
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

        try
        {
            var accepted = await desktop.CloseWindowAsync(windowId, cancellationToken);
            return AgentReplies.Direct(WindowCloseResponse(requestId, windowId, accepted));
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
        ["apps"] = new JsonArray
        {
            new JsonObject
            {
                ["id"] = "winapp_notepad",
                ["name"] = "Notepad",
                ["exePath"] = @"C:\Windows\System32\notepad.exe",
                ["publisher"] = "Microsoft",
                ["iconId"] = "icon_notepad"
            }
        }
    };

    private static JsonObject LaunchResponse(string? requestId, int processId) => new()
    {
        ["type"] = MessageTypes.AppLaunchResponse,
        ["requestId"] = requestId,
        ["accepted"] = true,
        ["processId"] = processId
    };

    private static JsonObject WindowCreatedEvent(LaunchedWindow window) => new()
    {
        ["type"] = MessageTypes.WindowCreated,
        ["windowId"] = window.WindowId,
        ["processId"] = window.ProcessId,
        ["appId"] = "winapp_notepad",
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

    private void TrackWindow(LaunchedWindow window)
    {
        lock (trackedWindowsGate)
        {
            trackedWindowsById[window.WindowId] = window;
        }
    }

    private bool TryGetTrackedWindow(string windowId, out LaunchedWindow window)
    {
        lock (trackedWindowsGate)
        {
            return trackedWindowsById.TryGetValue(windowId, out window!);
        }
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
