using System.Net;

namespace Veil.Agent;

public sealed record AgentEndpoint(string Host, int Port)
{
    public string HttpPrefix => $"http://{Host}:{Port}/";
    public string WebSocketUrl => $"ws://{Host}:{Port}/";
    public IPAddress ListenAddress => Host switch
    {
        "*" => IPAddress.Any,
        "+" => IPAddress.Any,
        "0.0.0.0" => IPAddress.Any,
        "::" => IPAddress.IPv6Any,
        _ when IPAddress.TryParse(Host, out var address) => address,
        _ => IPAddress.Any
    };

    public static AgentEndpoint FromEnvironment()
    {
        var host = Environment.GetEnvironmentVariable("VEIL_AGENT_HOST") ?? "0.0.0.0";
        var portText = Environment.GetEnvironmentVariable("VEIL_AGENT_PORT") ?? "18444";
        return int.TryParse(portText, out var port)
            ? new AgentEndpoint(host, port)
            : new AgentEndpoint(host, 18444);
    }
}
