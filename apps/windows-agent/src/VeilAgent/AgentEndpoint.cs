namespace Veil.Agent;

public sealed record AgentEndpoint(string Host, int Port)
{
    public string HttpPrefix => $"http://{Host}:{Port}/";
    public string WebSocketUrl => $"ws://{Host}:{Port}/";

    public static AgentEndpoint FromEnvironment()
    {
        var host = Environment.GetEnvironmentVariable("VEIL_AGENT_HOST") ?? "127.0.0.1";
        var portText = Environment.GetEnvironmentVariable("VEIL_AGENT_PORT") ?? "18444";
        return int.TryParse(portText, out var port)
            ? new AgentEndpoint(host, port)
            : new AgentEndpoint(host, 18444);
    }
}
