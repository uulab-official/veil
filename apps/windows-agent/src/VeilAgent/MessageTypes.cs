namespace Veil.Agent;

public static class MessageTypes
{
    public const string AgentHealthRequest = "agent.health.request";
    public const string AgentHealthResponse = "agent.health.response";
    public const string AppListRequest = "app.list.request";
    public const string AppListResponse = "app.list.response";
    public const string AppLaunchRequest = "app.launch.request";
    public const string AppLaunchResponse = "app.launch.response";
    public const string WindowCreated = "window.created";
    public const string WindowFrame = "window.frame";
    public const string WindowCloseRequest = "window.close.request";
    public const string WindowCloseResponse = "window.close.response";
    public const string InputMouse = "input.mouse";
    public const string Error = "error";
}
