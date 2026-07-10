namespace Veil.Agent;

public static class MessageTypes
{
    public const string AgentHealthRequest = "agent.health.request";
    public const string AgentHealthResponse = "agent.health.response";
    public const string AppListRequest = "app.list.request";
    public const string AppListResponse = "app.list.response";
    public const string AppLaunchRequest = "app.launch.request";
    public const string AppLaunchResponse = "app.launch.response";
    public const string FileOpenRequest = "file.open.request";
    public const string FileOpenResponse = "file.open.response";
    public const string WindowCreated = "window.created";
    public const string WindowUpdated = "window.updated";
    public const string WindowClosed = "window.closed";
    public const string WindowFrame = "window.frame";
    public const string WindowFrameSubscribe = "window.frame.subscribe";
    public const string WindowFrameUnsubscribe = "window.frame.unsubscribe";
    public const string WindowFocusRequest = "window.focus.request";
    public const string WindowFocusResponse = "window.focus.response";
    public const string WindowCloseRequest = "window.close.request";
    public const string WindowCloseResponse = "window.close.response";
    public const string InputMouse = "input.mouse";
    public const string InputKey = "input.key";
    public const string ClipboardTextSet = "clipboard.text.set";
    public const string NotificationListenerRequest = "notification.listener.request";
    public const string NotificationListenerResponse = "notification.listener.response";
    public const string NotificationReceived = "notification.received";
    public const string Error = "error";
}
