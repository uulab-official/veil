using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public sealed class AgentSession
{
    private readonly IWindowsDesktop desktop;
    private readonly IWindowFrameCapture capture;

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
            ["input"] = false,
            ["clipboardText"] = false
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

    private static JsonObject ErrorResponse(string? requestId, string code, string message) => new()
    {
        ["type"] = MessageTypes.Error,
        ["requestId"] = requestId,
        ["code"] = code,
        ["message"] = message
    };
}

public sealed record AgentReplies(
    IReadOnlyList<JsonObject> DirectReplies,
    IReadOnlyList<JsonObject> BroadcastEvents,
    LaunchedWindow? StreamWindow = null,
    int NextFrameSequence = 1
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
