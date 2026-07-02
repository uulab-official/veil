using Veil.Agent;

var endpoint = AgentEndpoint.FromEnvironment();
var desktop = new WindowsDesktop();
var capture = new BootstrapPngFrameCapture();
var session = new AgentSession(desktop, capture);
var server = new WebSocketAgentServer(endpoint, session);

Console.WriteLine($"Veil Windows Agent listening on {endpoint.WebSocketUrl}");
await server.RunAsync();
